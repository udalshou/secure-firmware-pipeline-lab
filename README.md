# secure-firmware-pipeline-lab

[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/udalshou/secure-firmware-pipeline-lab/badge)](https://scorecard.dev/viewer/?uri=github.com/udalshou/secure-firmware-pipeline-lab)

A small, reproducible secure software development pipeline for an embedded
Linux appliance: a Python API, a Vue web UI, a Debian-based root filesystem
image and a signed over-the-air (Mender) update artifact. The controls are
mapped to NIST SP 800-218 (SSDF) and the EU Cyber Resilience Act.

The application code is deliberately tiny. The pipeline, its controls and the
evidence they produce are the point.

## Layout

```
api/    FastAPI service (/health, /status), managed with uv (uv.lock)
ui/     Vue 3 + TypeScript web UI (Vite), npm with package-lock.json
os/     OS image build: Dockerfiles + bash scripts -> rootfs.tar, rootfs.ext4,
        lab-firmware.mender (Mender OTA artifact)
tools/  pipeline helpers (SARIF gate, attestation fetch for release checks)
docs/   security documentation: security-findings.md, repo-protection.md,
        release-signing.md, mender-signing.md, hardening-review.md
out/    build output (gitignored)
```

On the device, `lab-api` runs as a sandboxed systemd service
(`os/rootfs-overlay/etc/systemd/system/lab-api.service`) and also serves the
built UI.

## Build locally

Requirements: GNU Make, Docker, [uv](https://docs.astral.sh/uv/), Node.js
with npm, git. Root on the host is not needed.

```
make all        # api-test + os-lint + sast + ui-build + rootfs + mender-selftest + sbom + sca
make api-test   # ruff, pyright (strict), pytest
make ui-build   # npm ci, ESLint, vue-tsc, vite build
make os-lint    # ShellCheck + hadolint (pinned images) on os/
make sast       # Bandit + Semgrep -> out/sast/*.sarif, fails on high findings
make rootfs     # out/rootfs.tar and out/rootfs.ext4
make hardening-audit  # rootfs + Lynis, unit sandbox scores, boot check -> out/hardening/
make mender     # rootfs + unsigned Mender artifact out/lab-firmware.mender
make mender-selftest  # mender + signature checks with throwaway keys (must reject bad artifacts)
make sbom       # rootfs + CycloneDX SBOM of what ships -> out/sbom/sbom.cdx.json
make sca        # sbom + Trivy on repo and SBOM -> out/sca/*.sarif, fails on fixable high
make release    # sca + mender + release files -> out/release/ (rootfs.ext4.xz, SBOM, .mender)
make mender-sign MENDER_KEY=<private key>  # sign out/release/lab-firmware.mender
make verify-release TAG=v0.2.1   # download a GitHub Release and verify it
```

CI (`.github/workflows/ci.yml`) runs the same Makefile targets: `api`, `ui`
and `os` jobs in parallel, then `image`, which builds the rootfs and the
Mender artifact, runs the Mender signature self-test and uploads
`rootfs.ext4` as a workflow artifact. Actions are pinned by commit SHA and the
workflow token is read-only.

`.github/workflows/sast.yml` runs `make sast` and uploads both SARIF reports
to GitHub code scanning, also when the gate fails. Tools, rulesets and the
severity policy (high blocks the merge) are in
[docs/security-findings.md](docs/security-findings.md).

`.github/workflows/supply-chain.yml` runs `make sca` on pull requests,
pushes and weekly: it uploads the Trivy SARIF reports to code scanning and
keeps the SBOM as a workflow artifact. Dependabot (`.github/dependabot.yml`)
proposes weekly updates for Python, npm, GitHub Actions and base images.

## Repository protection

`main` accepts changes only through squash-merged pull requests with green
CI, no high code scanning alerts and signed commits; force pushes and
deletion are blocked. The ruleset is kept as code in
`.github/rulesets/main.json`, `CODEOWNERS` assigns the build system and CI to
the security reviewer, and `.github/workflows/scorecard.yml` publishes an
OpenSSF Scorecard result. Details:
[docs/repo-protection.md](docs/repo-protection.md).

## Signed releases

Pushing a tag `v*` runs `.github/workflows/release.yml`: it builds
the image (`rootfs.ext4.xz`), its SBOM and the Mender update artifact, signs the Mender
artifact with the device key (a GitHub environment secret behind a required
reviewer), signs the release files with Sigstore keyless signing (cosign,
GitHub OIDC), adds GitHub build provenance and SBOM attestations and
publishes an immutable GitHub Release. Only a commit on `main` can be
released. Verify any release with Docker, curl and python3, no login:

```
make verify-release TAG=v0.2.1
```

What it checks, the equivalent manual commands, and keyless versus keyed
signing: [docs/release-signing.md](docs/release-signing.md). The Mender
artifact, its keys, the device configuration and key rotation:
[docs/mender-signing.md](docs/mender-signing.md).

## How the OS image is built

1. `os/Dockerfile.rootfs` assembles the root filesystem: Debian trixie,
   systemd, Python, the API in a virtualenv at `/opt/lab-api` and the UI in
   `/usr/share/lab-ui`.
2. `os/build-rootfs.sh` exports that image with `docker export`.
3. `os/pack-rootfs.sh` runs as root inside a pinned tools container
   (`os/Dockerfile.tools`), so file owners and setuid bits are kept without
   root on the host. It writes a deterministic `rootfs.tar` and populates
   `rootfs.ext4` with `mkfs.ext4 -d`.
4. `make mender` wraps `rootfs.ext4` into a Mender full-image update with
   `mender-artifact` from the same tools container. The image ships the
   public key that devices verify updates against
   (`os/rootfs-overlay/etc/mender/`).
5. `make hardening-audit` checks the result: Lynis inside the rootfs,
   `systemd-analyze security` of the API unit (fails above 2.0) and a boot
   check under systemd. The image runs only the API and time sync, has no
   login path and no setuid programs:
   [docs/hardening-review.md](docs/hardening-review.md).

Pinning: base images by digest, Debian packages through a dated
[snapshot.debian.org](https://snapshot.debian.org) archive, Python packages
through the hash-checked `api/uv.lock`, npm packages through
`ui/package-lock.json`. The image build runs `apt-get upgrade`, so the
snapshot date alone decides every Debian package version. Timestamps,
filesystem UUID and hash seed are fixed (`SOURCE_DATE_EPOCH` defaults to the
last commit time).
