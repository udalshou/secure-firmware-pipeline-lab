# secure-firmware-pipeline-lab

A small, reproducible secure software development pipeline for an embedded
Linux appliance: a Python API, a Vue web UI, a Debian-based root filesystem
image and (later) a signed over-the-air update artifact. The controls are
mapped to NIST SP 800-218 (SSDF) and the EU Cyber Resilience Act.

The application code is deliberately tiny. The pipeline, its controls and the
evidence they produce are the point.

## Layout

```
api/    FastAPI service (/health, /status), managed with uv (uv.lock)
ui/     Vue 3 + TypeScript web UI (Vite), npm with package-lock.json
os/     OS image build: Dockerfiles + bash scripts -> rootfs.tar, rootfs.ext4
docs/   security documentation (added with the security controls)
out/    build output (gitignored)
```

On the device, `lab-api` runs as a sandboxed systemd service
(`os/rootfs-overlay/etc/systemd/system/lab-api.service`) and also serves the
built UI.

## Build locally

Requirements: GNU Make, Docker, [uv](https://docs.astral.sh/uv/), Node.js
with npm, git. Root on the host is not needed.

```
make all        # api-test + os-lint + ui-build + rootfs
make api-test   # ruff, pyright (strict), pytest
make ui-build   # npm ci, ESLint, vue-tsc, vite build
make os-lint    # ShellCheck + hadolint (pinned images) on os/
make rootfs     # out/rootfs.tar and out/rootfs.ext4
```

CI (`.github/workflows/ci.yml`) runs the same Makefile targets: `api`, `ui`
and `os` jobs in parallel, then `image`, which builds the rootfs and uploads
`rootfs.ext4` as a workflow artifact. Actions are pinned by commit SHA and the
workflow token is read-only.

## How the OS image is built

1. `os/Dockerfile.rootfs` assembles the root filesystem: Debian trixie,
   systemd, Python, the API in a virtualenv at `/opt/lab-api` and the UI in
   `/usr/share/lab-ui`.
2. `os/build-rootfs.sh` exports that image with `docker export`.
3. `os/pack-rootfs.sh` runs as root inside a pinned tools container
   (`os/Dockerfile.tools`), so file owners and setuid bits are kept without
   root on the host. It writes a deterministic `rootfs.tar` and populates
   `rootfs.ext4` with `mkfs.ext4 -d`.

Pinning: base images by digest, Debian packages through a dated
[snapshot.debian.org](https://snapshot.debian.org) archive, Python packages
through the hash-checked `api/uv.lock`, npm packages through
`ui/package-lock.json`. Timestamps, filesystem UUID and hash seed are fixed
(`SOURCE_DATE_EPOCH` defaults to the last commit time).
