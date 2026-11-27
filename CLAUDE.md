# secure-firmware-pipeline-lab

Before committing, check whether this file, `README.md`, `docs/` and inline
comments still describe current behavior — update them if not.

Git branching: only branch off `main` when explicitly asked. Default —
commit straight to whatever branch is checked out (usually `main`). Once
task 05 lands, `main` is protected: work goes through PRs.

Commit messages and PR descriptions: describe only what was implemented — no
AI attribution / `Co-Authored-By` trailers.

`tasks/` (gitignored) is the personal task tracker — `tasks/README.md` is its
index. Check it for planned work (`todo/`) and completed work (`done/`)
before starting anything new.

## PUBLIC REPO — current hard rule

This repo is public (portfolio). Never commit, in files, commit messages,
PR text or CI logs:

- client, employer or project names, ticket IDs, NDA or internal details
- secrets of any kind: API keys, tokens, passwords, private signing keys
  (cosign, Mender, GPG/SSH). Private keys live outside the repo or in GitHub
  environment secrets; only public keys may be committed
- personal data

`.gitignore` covers `tasks/`, `out/`, Python caches and `*.key` except
`*public*.key`. Push protection and secret scanning stay on.

Commits use the GitHub noreply address
(`167848153+udalshou@users.noreply.github.com`, repo-local `git config`);
the global git email has an employer domain and must not reach this repo.

## Project

A small, reproducible secure SDLC pipeline for an embedded Linux appliance:
Python API + Vue UI + OS image build scripts + signed OTA update artifact,
mapped to NIST SP 800-218 (SSDF) and the EU Cyber Resilience Act. The app
code stays tiny; the pipeline and its evidence are the point. Plan: tasks
01-11 in `tasks/todo/`.

Repo: https://github.com/udalshou/secure-firmware-pipeline-lab (public).

Status (2026-11-27): task 01 done (API, UI, rootless rootfs build,
`make all` green on a clean clone). Next: task 02 (CI baseline).

## Conventions

- OS base: Debian trixie (`debian:trixie-slim` by digest), apt pinned to a
  dated snapshot.debian.org archive (`DEBIAN_SNAPSHOT` in `os/Dockerfile.*`).
  Bump digest and snapshot together.
- Security tools not on the host (ShellCheck, hadolint, Trivy, Semgrep,
  cosign, mender-artifact) run as Docker images pinned by digest, the same
  in CI and locally. No system installs.
- Root-needing image steps (ownership, `mkfs.ext4`) run inside the tools
  container (`os/Dockerfile.tools`), never with host root.
- Images from ghcr.io fail to pull on the dev machine (token 403); prefer
  Docker Hub mirrors (e.g. `astral/uv`) or test CI-only.
- Never disable TLS checks for package managers; the Makefile unexports
  `NODE_TLS_REJECT_UNAUTHORIZED`.

## Project structure

```
secure-firmware-pipeline-lab/
├── api/        ← FastAPI app (uv, pyproject.toml + uv.lock)
├── ui/         ← Vue 3 + TypeScript (Vite, npm + package-lock.json)
├── os/         ← Dockerfiles + bash scripts: rootfs.tar, rootfs.ext4 (.mender: task 07)
├── .github/    ← CI, SAST, SBOM, release + signing workflows (task 02+)
├── docs/       ← SSDF mapping, CRA checklist, hardening review, signing docs (later tasks)
├── out/        ← gitignored build output
└── tasks/      ← gitignored personal task tracker (README.md, todo/, done/)
```

Build locally with `make all`; CI must run the same Makefile targets.

---

# Software design principles

This repo follows John Ousterhout's *A Philosophy of Software Design* for
all code it owns — scripts, configuration, workflows, and test suites:
favor deep modules with simple interfaces, invest continuously in readability
over speed of writing, keep general and special-case code clearly separated,
and make wrong states unreachable rather than just handled (e.g. pinning every
dependency, action and container version by digest/SHA and rejecting
`:latest` in tests). Before merging, self-review against Ousterhout's
red-flag list (shallow modules, information leakage, temporal decomposition,
repetition, vague names, comments that repeat the code).
