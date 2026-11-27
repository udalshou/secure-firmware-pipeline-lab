# Single entry point for local builds and CI: CI calls these same targets.
.DEFAULT_GOAL := all
SHELL := /bin/bash
.SHELLFLAGS := -euo pipefail -c

# Never let a developer shell switch off TLS certificate checks for npm.
unexport NODE_TLS_REJECT_UNAUTHORIZED

.PHONY: all api-test ui-build os-lint sast rootfs clean

all: api-test os-lint sast rootfs

# Linters for the OS build run as images pinned by digest, identical in CI and
# locally; nothing is installed on the host. Bump tag and digest together.
SHELLCHECK_IMAGE := koalaman/shellcheck:v0.11.0@sha256:61862eba1fcf09a484ebcc6feea46f1782532571a34ed51fedf90dd25f925a8d
HADOLINT_IMAGE := hadolint/hadolint:v2.14.0@sha256:27086352fd5e1907ea2b934eb1023f217c5ae087992eb59fde121dce9c9ff21e
LINT_RUN := docker run --rm --network none --volume "$(CURDIR):/src:ro" --workdir /src

# SAST. The Semgrep engine is pinned by digest; its registry rulesets are
# fetched at scan time on purpose, so new detection rules apply without a bump
# (like a vulnerability database). Semgrep scans only files tracked by git.
SEMGREP_IMAGE := semgrep/semgrep:1.187.0-nonroot@sha256:36cd451db16459c30711510295052467d333ad4dd4a6b69bc8d7d7e9e3e9dae7
SEMGREP_CONFIGS := p/python p/typescript r/bash p/github-actions
SAST_DIR := out/sast

## API: lint, format check, type check, tests (locked dependencies only)
api-test:
	cd api && uv sync --locked
	cd api && uv run ruff check
	cd api && uv run ruff format --check
	cd api && uv run pyright
	cd api && uv run pytest -q

## UI: clean install from package-lock.json, lint, type check, build
ui-build:
	cd ui && npm ci
	cd ui && npm run lint
	cd ui && npm run build

## OS build: ShellCheck and hadolint; any finding, down to style/info, fails
os-lint:
	$(LINT_RUN) $(SHELLCHECK_IMAGE) --external-sources os/*.sh
	$(LINT_RUN) $(HADOLINT_IMAGE) hadolint os/Dockerfile.*

## SAST: Bandit and Semgrep write SARIF to out/sast (all findings, for code
## scanning); then the gate fails on error-level (high) findings only
sast:
	mkdir -p $(SAST_DIR)
	uv run --project api --locked bandit --quiet --exit-zero --recursive api/src \
		--format sarif --output $(SAST_DIR)/bandit.sarif
	docker run --rm --volume "$(CURDIR):/src:ro" --workdir /src $(SEMGREP_IMAGE) \
		semgrep scan --metrics=off --disable-version-check \
		$(addprefix --config ,$(SEMGREP_CONFIGS)) --sarif > $(SAST_DIR)/semgrep.sarif
	python3 tools/sarif_gate.py $(SAST_DIR)/bandit.sarif $(SAST_DIR)/semgrep.sarif

## OS image: out/rootfs.tar and out/rootfs.ext4
rootfs: ui-build
	os/build-rootfs.sh

clean:
	rm -rf out ui/dist
