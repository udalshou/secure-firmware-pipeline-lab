# secure-firmware-pipeline-lab

Before committing, check whether this file, `README.md`, `docs/` and inline
comments still describe current behavior — update them if not.

Git branching: only branch off `main` when explicitly asked. Default —
`main` is protected by a ruleset (`.github/rulesets/main.json`): work goes
through a branch and a squash-merged PR with green checks; commits are
SSH-signed (repo-local `commit.gpgsign`).

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
01-12 in `tasks/`.

Repo: https://github.com/udalshou/secure-firmware-pipeline-lab (public).

Status (2026-11-27): tasks 01-05 done (API, UI, rootless rootfs build;
GitHub Actions CI running the Makefile targets; SAST with Bandit + Semgrep
SARIF in code scanning, high findings block; CycloneDX SBOM of the rootfs +
UI, Trivy SCA on repo and SBOM, Dependabot; `main` ruleset, signed commits,
CODEOWNERS, OpenSSF Scorecard). The rootfs is deterministic per machine but
not yet across machines (task 12). Next: task 06 (release signing).

## Conventions

- OS base: Debian trixie (`debian:trixie-slim` by digest), apt pinned to a
  dated snapshot.debian.org archive (`DEBIAN_SNAPSHOT` in `os/Dockerfile.*`).
  Bump digest and snapshot together. The rootfs build runs `apt-get
  upgrade`, so a snapshot bump is how Debian security fixes land. Image
  references go in `FROM` lines directly, not via `ARG`, so Dependabot can
  update them.
- Supply chain: `make sbom` / `make sca` (Trivy + cyclonedx-cli images);
  accepted Trivy findings in `.trivyignore.yaml`, each with a statement.
  Containers that write into `out/` run as the host user (`--user`).
- Security tools not on the host (ShellCheck, hadolint, Trivy, Semgrep,
  cosign, mender-artifact) run as Docker images pinned by digest, the same
  in CI and locally. No system installs.
- GitHub Actions are pinned by commit SHA with the tag in a trailing
  comment; workflow token `contents: read` unless a job needs more.
- Root-needing image steps (ownership, `mkfs.ext4`) run inside the tools
  container (`os/Dockerfile.tools`), never with host root.
- Images from ghcr.io fail to pull on the dev machine (token 403); prefer
  Docker Hub mirrors (e.g. `astral/uv`) or test CI-only.
- Scanners write SARIF to `out/<kind>/`, upload it to code scanning even on
  failure, and gate merges with `tools/sarif_gate.py` (SARIF `error` blocks).
  Policy: `docs/security-findings.md`.
- Never disable TLS checks for package managers; the Makefile unexports
  `NODE_TLS_REJECT_UNAUTHORIZED`.

## Project structure

```
secure-firmware-pipeline-lab/
├── api/        ← FastAPI app (uv, pyproject.toml + uv.lock)
├── ui/         ← Vue 3 + TypeScript (Vite, npm + package-lock.json)
├── os/         ← Dockerfiles + bash scripts: rootfs.tar, rootfs.ext4 (.mender: task 07)
├── tools/      ← pipeline helpers (sarif_gate.py: fail on error-level SARIF)
├── .github/    ← CI, SAST, SBOM, release + signing workflows (task 02+)
├── docs/       ← security-findings.md (scanners, severity policy), repo-protection.md; SSDF/CRA docs later
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
