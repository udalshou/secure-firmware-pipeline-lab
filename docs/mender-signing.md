# Mender update artifact signing

How the over-the-air (OTA) update artifact is built and signed, how a device
decides to trust it, and the tests that show a wrong or modified artifact is
rejected. SSDF PS.2 (provide a mechanism to verify software release
integrity) and PO.5 (secure environments: the signing key is isolated in one
CI job); EU Cyber Resilience Act Annex I, Part I: security updates, and
integrity of software against unauthorised modification.

## What is built

`make mender` wraps `out/rootfs.ext4` into `out/lab-firmware.mender`, a
[Mender](https://mender.io) full-image (`rootfs-image`) update:

| Field | Value |
|-------|-------|
| Device type | `lab-device` (a device accepts only artifacts for its type) |
| Artifact name | `lab-firmware-<version>`, version from `git describe` (the tag on a release) |
| Payload | `rootfs.ext4`; its checksum in the artifact is the image's SHA-256 |
| Tool | `mender-artifact` 3.9.0 from the pinned Debian snapshot, in `os/Dockerfile.tools` |

Because the payload checksum equals the SHA-256 of `rootfs.ext4`, the
artifact carries exactly the image that the release's cosign signature and
build provenance describe.

## Two signatures, two audiences

| Signature | Checked by | Trust anchor |
|-----------|-----------|--------------|
| Mender signature inside `lab-firmware.mender` | the device, offline, before installing | public key baked into the running image |
| cosign keyless over `SHA256SUMS` (covers the `.mender` file) | people and pipelines downloading the release | GitHub OIDC identity of the release workflow, see [release-signing.md](release-signing.md) |

A device cannot check Fulcio certificates against a current Sigstore trust
root, so the update itself carries a keyed signature.

## Keys

ECDSA P-256. Generated once, outside the repository:

```
umask 077; mkdir -p ~/.lab-keys
openssl ecparam -genkey -name prime256v1 -noout -out ~/.lab-keys/mender-artifact.key
openssl ec -in ~/.lab-keys/mender-artifact.key -pubout \
  -out os/rootfs-overlay/etc/mender/artifact-verify-key.pem
```

Only the public key is committed, at
`os/rootfs-overlay/etc/mender/artifact-verify-key.pem`, so it ships in every
image under `/etc/mender/`. The same file is what CI and `make
verify-release` check signatures against.

Findings with `mender-artifact` 3.9.0:

- It reads only traditional PEM private keys (`BEGIN EC PRIVATE KEY`,
  `BEGIN RSA PRIVATE KEY`). PKCS#8 keys, which `openssl genpkey` writes,
  fail with `x509: failed to parse private key (use ParsePKCS8PrivateKey
  instead for this key format)`; convert with `openssl pkey -traditional`.
- RSA 3072 and ECDSA P-256 both sign and verify. P-256 was chosen for its
  small keys and signatures.
- Ed25519 is not supported, and verification with an Ed25519 public key
  **fails open**: `mender-artifact validate -k ed25519.pub unsigned.mender`
  prints `unsupported public key type` and exits 0. The self-test below
  therefore checks that an unsigned artifact is rejected with the real
  device key, so a wrong key type in the image fails CI.

The private key lives in two places: `~/.lab-keys/` on the developer machine
and the `MENDER_SIGNING_KEY` secret of the GitHub `release` environment. In
production it belongs in an HSM or KMS, so CI gets a signing operation and
never the key: `mender-artifact sign` supports `--key-pkcs11` and
`--gcp-kms-key` for that.

## How a release signs it

[`.github/workflows/release.yml`](../.github/workflows/release.yml):

1. `build` (read-only token) runs `make release`, which builds the unsigned
   `lab-firmware.mender` next to `rootfs.ext4` and the SBOM.
2. `mender-sign` runs in the `release` environment, the only place
   `MENDER_SIGNING_KEY` is available. It builds the tools image first, then
   writes the key to a mode 600 file in `$RUNNER_TEMP` and runs `make
   mender-sign`. That signs the artifact (`mender-artifact sign` refuses an
   already signed artifact) and validates it against the committed public
   key, so a release cannot ship a signature that devices would reject. The
   key file is deleted when the step ends. This job has no write token and
   no OIDC token.
3. `publish` (no key) writes `SHA256SUMS` over the final files, including
   the signed `.mender`, signs it with cosign and publishes the release.

The `release` environment is configured once, by the repository admin. It
requires a reviewer, accepts deployments only from `v*` tags, and holds the
key:

```
gh api -X PUT repos/{owner}/{repo}/environments/release --input - <<'EOF'
{"reviewers": [{"type": "User", "id": <user id>}],
 "prevent_self_review": false,
 "deployment_branch_policy": {"protected_branches": false, "custom_branch_policies": true}}
EOF
gh api -X POST repos/{owner}/{repo}/environments/release/deployment-branch-policies \
  -f name='v*' -f type=tag
gh secret set MENDER_SIGNING_KEY --env release < ~/.lab-keys/mender-artifact.key
```

Self-review is allowed because this is a one-person repository. The approval
still makes signing a deliberate step, separate from pushing a tag.

## Verify an artifact

`make verify-release TAG=<tag>` checks the `.mender` file with the rest of the
release (checksum, cosign, attestations) and then validates its Mender
signature against the public key in the checkout. By hand, with the tools
image (`make tools-image`):

```
docker run --rm --network none -v "$PWD:/w" -w /w lab-os-tools:build \
  mender-artifact validate -k os/rootfs-overlay/etc/mender/artifact-verify-key.pem lab-firmware.mender
docker run --rm --network none -v "$PWD:/w" -w /w lab-os-tools:build \
  mender-artifact read -k os/rootfs-overlay/etc/mender/artifact-verify-key.pem lab-firmware.mender
```

`read` shows `Signature: signed and verified correctly`.

## Tests

`make mender-selftest` ([`os/mender-selftest.sh`](../os/mender-selftest.sh))
runs in the CI `image` job on every pull request. It signs the freshly built
artifact with a throwaway key A and checks that verification accepts and
rejects the right cases. Output of a local run:

```
PASS  signed with A, verified with A: accepted
      mender-artifact: Artifact file '/tmp/tmp.oJxZRpHbDw/signed.mender' validated successfully
PASS  signed with A, verified with B: rejected
      mender-artifact: signer: verification failed
PASS  unsigned, verified with A: rejected
      mender-artifact: missing signature
PASS  signed with A, one byte flipped: rejected
      mender-artifact: Payload: can not install Payload: rootfs.ext4: invalid checksum; expected: [cb02107…]; actual: [d0231fa…]
PASS  unsigned, verified with the device key: rejected
      mender-artifact: missing signature
```

With an Ed25519 public key in place of the device key, the last check
reports `FAIL  unsigned, verified with the device key: accepted, expected
reject` and the target fails. A one-off manual run also flipped a byte near
the start of a signed artifact (in the tar headers, not the payload); that
was rejected too.

`make mender-sign` with the real lab key, run locally on a copy of the
artifact:

| Case | Result |
|------|--------|
| No `MENDER_KEY` | exit 2, `usage: make mender-sign MENDER_KEY=<private key file>` |
| Sign, then validate with the committed public key | `validated successfully`; `read` shows `signed and verified correctly` |
| Sign the signed artifact again | exit 1, `Artifact already signed, refusing to re-sign` |

## On the device

`os/rootfs-overlay/etc/mender/mender.conf` points the Mender client at the
baked-in key:

```json
{
  "ArtifactVerifyKey": "/etc/mender/artifact-verify-key.pem"
}
```

With `ArtifactVerifyKey` set, the client refuses unsigned artifacts and
artifacts signed by any other key. The Mender client in Debian trixie
(`mender-client` 3.4.0) knows only this single-key setting. Newer clients
also document a list form, `ArtifactVerifyKeys`, which this lab does not
use or test.

The image ships the key and the configuration but not the client. Installing
updates needs a Mender-integrated device: A/B root partitions, a persistent
data partition and bootloader support for rollback. That integration, and a
device install test in QEMU, are out of scope here.

## Key rotation

A device trusts exactly the key in its running image, so a new key has to
arrive in an update signed with the old one:

1. Generate the new key pair. Commit the new public key to
   `artifact-verify-key.pem` and release version N, still signed with the
   old private key (`MENDER_SIGNING_KEY` unchanged). Devices accept N and,
   once N runs, trust only the new key.
2. Replace `MENDER_SIGNING_KEY` with the new private key. Release N+1 and
   later are signed with it.
3. Destroy the old private key once every device runs N or later.

Release N is the one release whose Mender signature does not match the
public key in its own checkout, so `make mender-sign` and `make
verify-release` reject it as they stand. For that release, pass the old
public key: `make mender-sign MENDER_VERIFY_KEY=<old public key>` (in
`release.yml` as well).

A device that skips N cannot install N+1, so N stays available until the
fleet has moved. With a client that supports `ArtifactVerifyKeys`, N can
trust both keys and the switch needs no ordering. If the key leaks, the same
procedure applies, but an attacker with the old key can still sign updates
for devices that have not reached N. That is the case an HSM prevents.

## Limits

- The `.mender` file is not bit-for-bit reproducible: `mender-artifact`
  records the current time and the build user in the artifact's tar
  headers. Its payload, `rootfs.ext4`, is reproducible on one machine, not
  yet across machines.
- The image has no `/etc/mender/artifact_info`, so a device could not report
  which artifact it runs. A Mender-integrated build would write it.
