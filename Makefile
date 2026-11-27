# Single entry point for local builds and CI: CI calls these same targets.
.DEFAULT_GOAL := all
SHELL := /bin/bash
.SHELLFLAGS := -euo pipefail -c

# Never let a developer shell switch off TLS certificate checks for npm.
unexport NODE_TLS_REJECT_UNAUTHORIZED

.PHONY: all api-test ui-build os-lint sast rootfs sbom sca release release-sign verify-release clean

all: api-test os-lint sast rootfs sbom sca

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

# Supply chain. Trivy and cyclonedx-cli are pinned by digest and run as the
# host user, so everything under out/ stays deletable without root. Trivy's
# vulnerability database is downloaded at scan time on purpose (cached in
# out/trivy-cache), so a rerun on unchanged code still sees new advisories.
TRIVY_IMAGE := aquasec/trivy:0.76.2@sha256:8f6bb947dbc528902e11f2f5be52f7b519f6a39d5d148f41166f2040499768fb
CYCLONEDX_IMAGE := cyclonedx/cyclonedx-cli:0.33.1@sha256:252c2e26f468c25fea1e63ecde1bc3198ad6e9dbb57f5ed3236bddcb2281b3a7
SBOM_DIR := out/sbom
SCA_DIR := out/sca
TRIVY_CACHE := out/trivy-cache
AS_HOST_USER := --user "$$(id -u):$$(id -g)"
TRIVY := docker run --rm $(AS_HOST_USER) --volume "$(CURDIR):/src:ro" --workdir /src \
	--volume "$(CURDIR)/$(TRIVY_CACHE):/cache" $(TRIVY_IMAGE) --cache-dir /cache --quiet
CYCLONEDX := docker run --rm --network none $(AS_HOST_USER) \
	--volume "$(CURDIR)/$(SBOM_DIR):/sbom" --workdir /sbom $(CYCLONEDX_IMAGE)
# Findings with no fixed version are not actionable for us and stay out of the
# reports; .trivyignore.yaml holds accepted findings, each with a reason.
TRIVY_POLICY := --ignore-unfixed --ignorefile .trivyignore.yaml
# Untracked or generated trees that `trivy fs` must not report on.
TRIVY_SKIP_DIRS := .git,out,tasks,api/.venv,ui/node_modules,ui/dist

# Release signing and verification. cosign is pinned by digest and runs as the
# host user; $(call COSIGN,<dir>) mounts <dir> as its working directory.
# Keyless signing reads the GitHub Actions OIDC token from the environment, so
# only the release workflow can sign; anyone can verify.
COSIGN_IMAGE := gcr.io/projectsigstore/cosign:v3.1.6@sha256:7d08ec40d6f6fd9ced81a498c367ee6d4dd90d73218f58a791f78661bdbef769
COSIGN = docker run --rm $(AS_HOST_USER) --tmpfs /tmp --env HOME=/tmp \
	--env ACTIONS_ID_TOKEN_REQUEST_URL --env ACTIONS_ID_TOKEN_REQUEST_TOKEN \
	--volume "$(CURDIR)/$(1):/work" --workdir /work $(COSIGN_IMAGE)
GITHUB_REPO := udalshou/secure-firmware-pipeline-lab
RELEASE_WORKFLOW := .github/workflows/release.yml
RELEASE_DIR := out/release
VERIFY_DIR := out/verify
# Files published in a release, and the subset with a cosign signature:
# SHA256SUMS covers every file, rootfs.ext4 can also be checked on its own.
RELEASE_FILES := rootfs.ext4 sbom.cdx.json
SIGNED_FILES := rootfs.ext4 SHA256SUMS
# A signature is valid only if this repository's release workflow made it
# while running for the tag being verified.
SIGNER_IDENTITY = https://github.com/$(GITHUB_REPO)/$(RELEASE_WORKFLOW)@refs/tags/$(TAG)
OIDC_ISSUER := https://token.actions.githubusercontent.com

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

## SBOM of what ships, out/sbom/sbom.cdx.json (CycloneDX): Debian and Python
## packages found in rootfs.tar, plus the npm packages bundled into the UI
## (production dependencies from package-lock.json; the bundle hides them)
sbom: rootfs
	rm -rf $(SBOM_DIR)
	mkdir -p $(SBOM_DIR)/rootfs-tree $(TRIVY_CACHE)
	tar -xf out/rootfs.tar -C $(SBOM_DIR)/rootfs-tree --no-same-owner --no-same-permissions
	$(TRIVY) rootfs --format cyclonedx $(SBOM_DIR)/rootfs-tree > $(SBOM_DIR)/sbom-rootfs.cdx.json
	rm -rf $(SBOM_DIR)/rootfs-tree
	$(TRIVY) fs --format cyclonedx ui/package-lock.json > $(SBOM_DIR)/sbom-ui.cdx.json
	$(CYCLONEDX) merge --input-files sbom-rootfs.cdx.json sbom-ui.cdx.json \
		--name lab-appliance --version "$$(git describe --tags --always --dirty)" \
		--output-file sbom.cdx.json
	$(CYCLONEDX) validate --input-file sbom.cdx.json --fail-on-errors

## SCA: Trivy scans the repository (lockfiles, secrets, Dockerfile
## misconfigurations) and the shipped SBOM, writes SARIF to out/sca, then the
## gate fails on error-level (HIGH/CRITICAL) findings that have a fix
sca: sbom
	mkdir -p $(SCA_DIR)
	$(TRIVY) fs $(TRIVY_POLICY) --scanners vuln,secret,misconfig --skip-dirs $(TRIVY_SKIP_DIRS) \
		--format sarif . > $(SCA_DIR)/trivy-repo.sarif
	$(TRIVY) sbom $(TRIVY_POLICY) --format sarif $(SBOM_DIR)/sbom.cdx.json > $(SCA_DIR)/trivy-sbom.sarif
	python3 tools/sarif_gate.py $(SCA_DIR)/trivy-repo.sarif $(SCA_DIR)/trivy-sbom.sarif

## Release files in out/release: rootfs.ext4, its SBOM and SHA256SUMS over
## both; built only when the SCA gate passes
release: sca
	rm -rf $(RELEASE_DIR)
	mkdir -p $(RELEASE_DIR)
	cp out/rootfs.ext4 $(SBOM_DIR)/sbom.cdx.json $(RELEASE_DIR)/
	cd $(RELEASE_DIR) && sha256sum $(RELEASE_FILES) > SHA256SUMS

## Keyless cosign signatures (Sigstore bundles <file>.sigstore.json) for the
## files in out/release. Release workflow only: needs its OIDC token, and does
## not rebuild, so it signs exactly the files the build job produced
release-sign:
	test -n "$${ACTIONS_ID_TOKEN_REQUEST_URL:-}" || \
		{ echo "release-sign needs the GitHub Actions OIDC token (release.yml)" >&2; exit 1; }
	for f in $(SIGNED_FILES); do \
		$(call COSIGN,$(RELEASE_DIR)) sign-blob --yes --bundle "$$f.sigstore.json" "$$f"; \
	done

## Download release TAG and verify it as a consumer would: checksums, cosign
## signatures from this repository's release workflow at TAG, and GitHub's
## build provenance and SBOM attestations. Needs gh, logged in
verify-release:
	test -n "$(TAG)" || { echo "usage: make verify-release TAG=v0.1.0" >&2; exit 2; }
	rm -rf $(VERIFY_DIR)
	mkdir -p $(VERIFY_DIR)
	gh release download "$(TAG)" --repo $(GITHUB_REPO) --dir $(VERIFY_DIR)
	cd $(VERIFY_DIR) && sha256sum --check --strict SHA256SUMS
	for f in $(SIGNED_FILES); do \
		$(call COSIGN,$(VERIFY_DIR)) verify-blob --bundle "$$f.sigstore.json" \
			--certificate-identity "$(SIGNER_IDENTITY)" \
			--certificate-oidc-issuer $(OIDC_ISSUER) "$$f"; \
	done
	gh attestation verify $(VERIFY_DIR)/rootfs.ext4 --repo $(GITHUB_REPO) \
		--cert-identity "$(SIGNER_IDENTITY)"
	gh attestation verify $(VERIFY_DIR)/rootfs.ext4 --repo $(GITHUB_REPO) \
		--cert-identity "$(SIGNER_IDENTITY)" --predicate-type https://cyclonedx.org/bom

clean:
	rm -rf out ui/dist
