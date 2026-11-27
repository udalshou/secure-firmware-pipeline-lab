# Release signing and verification

How a release is built, signed and published, and how anyone can check that a
release file came from this repository's CI and was not changed. SSDF PS.2
(provide a mechanism to verify software release integrity) and PS.3 (archive
and protect each software release).

## What a release contains

Pushing a tag `v*` runs [`.github/workflows/release.yml`](../.github/workflows/release.yml).
The GitHub Release for that tag holds:

| File | What it is |
|------|------------|
| `rootfs.ext4` | The root filesystem image |
| `sbom.cdx.json` | CycloneDX SBOM of what ships in it (`make sbom`) |
| `SHA256SUMS` | SHA-256 of `rootfs.ext4` and `sbom.cdx.json` |
| `rootfs.ext4.sigstore.json` | cosign signature bundle for `rootfs.ext4` |
| `SHA256SUMS.sigstore.json` | cosign signature bundle for `SHA256SUMS`, so it covers every file |

GitHub also stores two attestations for the release, signed the same way:
SLSA build provenance for every file in `SHA256SUMS`, and the SBOM as a
signed statement about `rootfs.ext4`.

## How the workflow produces it

1. `build` job, read-only token: checks that the tagged commit is on `main`
   (so it went through a reviewed pull request with green checks), then runs
   `make release`. That builds the image and SBOM, runs the SCA gate (a
   fixable high or critical vulnerability stops the release) and writes
   `out/release/`.
2. `publish` job: downloads those files and never builds or installs
   anything. `make release-sign` signs them with cosign, `actions/attest`
   records the attestations, and `gh release create` publishes the release.

Only `publish` has `contents: write` and `id-token: write`. Build steps run
npm, Docker builds and package managers; none of them can mint a signing
identity or change the repository.

## Keyless signing

cosign uses [Sigstore](https://www.sigstore.dev) keyless signing. The job's
GitHub OIDC token proves which workflow is running; Sigstore's Fulcio CA
issues a short-lived certificate (about ten minutes) for that identity,
cosign signs with an ephemeral key, and the signature is recorded in the
public Rekor transparency log. The bundle (`*.sigstore.json`) holds
signature, certificate and log inclusion proof, so verification does not
need to query Rekor.

The certificate identity names the workflow and the tag it ran for:

```
https://github.com/udalshou/secure-firmware-pipeline-lab/.github/workflows/release.yml@refs/tags/v0.1.0
```

There is no private key to store, rotate or leak. A signature is only as
trustworthy as the workflow that can produce it, which is why the tag must
point to a commit on protected `main`.

## Verify a release

Requirements: Docker, curl and python3. No GitHub account or login.

```
make verify-release TAG=v0.1.0
```

It downloads the release into `out/verify/` and fails unless every step
passes:

1. `sha256sum --check` against `SHA256SUMS`.
2. `cosign verify-blob` for `rootfs.ext4` and `SHA256SUMS`, accepting only a
   certificate issued to this repository's release workflow at that tag.
3. `cosign verify-blob-attestation` for the SLSA build provenance and the
   CycloneDX SBOM attestation of `rootfs.ext4`, with the same signer
   identity. [`tools/attestation_bundle.py`](../tools/attestation_bundle.py)
   fetches each bundle from GitHub's public attestations API; cosign checks
   it against the image's digest (the image is over cosign's 128 MiB blob
   limit, so the digest is passed instead of the file).

Every release file also carries GitHub's own release attestation (immutable
releases, signed by GitHub's private Sigstore instance). `gh attestation
verify` 2.55 stops at that one with `no matching CertificateIdentity` and
never reaches the workflow attestations; selecting by predicate type avoids
this.

The signature and attestation checks by hand, with cosign and the GitHub CLI
(the `gh attestation` lines need a gh release newer than 2.55 that skips the
release attestation; not tested here):

```
cosign verify-blob rootfs.ext4 --bundle rootfs.ext4.sigstore.json \
  --certificate-identity https://github.com/udalshou/secure-firmware-pipeline-lab/.github/workflows/release.yml@refs/tags/v0.1.0 \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
gh attestation verify rootfs.ext4 --repo udalshou/secure-firmware-pipeline-lab
gh attestation verify rootfs.ext4 --repo udalshou/secure-firmware-pipeline-lab \
  --predicate-type https://cyclonedx.org/bom
```

## Protecting published releases

The repository has GitHub immutable releases on: once a release is
published, its assets cannot be replaced or deleted and its tag cannot be
moved. A fix ships as a new version. A swapped file would fail verification
anyway; the setting stops the swap from happening.

## Keyless or keyed

Keyless signing suits these release files: they are built in public CI and
verified by people with network access. A device in the field is different.
It verifies an update offline, against a public key baked into the image,
and cannot check Fulcio certificates against a current trust root. For that
case a keyed signature fits:

- `cosign generate-key-pair`, or a KMS key (`--key awskms://...`,
  `gcpkms://...`, `hashivault://...`). The public key is committed; the
  private key sits in a GitHub environment secret with required reviewers,
  or better in a KMS, so CI gets a signing operation and never the key.
- Cost: key storage, rotation, revocation and a compromise plan become the
  project's job, and there is no transparency log unless the signer uploads
  to Rekor as well.

The over-the-air update artifact is that device-side case and is planned to
use a keyed signature.
