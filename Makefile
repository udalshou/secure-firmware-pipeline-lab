# Single entry point for local builds and CI: CI calls these same targets.
.DEFAULT_GOAL := all
SHELL := /bin/bash
.SHELLFLAGS := -euo pipefail -c

# Never let a developer shell switch off TLS certificate checks for npm.
unexport NODE_TLS_REJECT_UNAUTHORIZED

.PHONY: all api-test ui-build os-lint rootfs clean

all: api-test os-lint rootfs

# Linters for the OS build run as images pinned by digest, identical in CI and
# locally; nothing is installed on the host. Bump tag and digest together.
SHELLCHECK_IMAGE := koalaman/shellcheck:v0.11.0@sha256:61862eba1fcf09a484ebcc6feea46f1782532571a34ed51fedf90dd25f925a8d
HADOLINT_IMAGE := hadolint/hadolint:v2.14.0@sha256:27086352fd5e1907ea2b934eb1023f217c5ae087992eb59fde121dce9c9ff21e
LINT_RUN := docker run --rm --network none --volume "$(CURDIR):/src:ro" --workdir /src

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

## OS image: out/rootfs.tar and out/rootfs.ext4
rootfs: ui-build
	os/build-rootfs.sh

clean:
	rm -rf out ui/dist
