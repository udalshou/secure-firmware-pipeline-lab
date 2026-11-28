# Single entry point for local builds and CI: CI calls these same targets.
.DEFAULT_GOAL := all
SHELL := /bin/bash
.SHELLFLAGS := -euo pipefail -c

# Never let a developer shell switch off TLS certificate checks for npm.
unexport NODE_TLS_REJECT_UNAUTHORIZED

.PHONY: all api-test ui-build os-lint docs-check sast tools-image rootfs hardening-audit mender mender-selftest sbom sca \
	release mender-sign release-sign verify-release clean

all: api-test os-lint docs-check sast rootfs mender-selftest sbom sca

# Version of everything built from this checkout: the tag on a release build,
# otherwise the short commit hash (with -dirty for uncommitted changes).
VERSION = $(shell git describe --tags --always --dirty)

# Linters for the OS build run as images pinned by digest, identical in CI and
# locally; nothing is installed on the host. Bump tag and digest together.
SHELLCHECK_IMAGE := koalaman/shellcheck:v0.11.0@sha256:61862eba1fcf09a484ebcc6feea46f1782532571a34ed51fedf90dd25f925a8d
HADOLINT_IMAGE := hadolint/hadolint:v2.14.0@sha256:27086352fd5e1907ea2b934eb1023f217c5ae087992eb59fde121dce9c9ff21e
# Link checker for the documentation, pinned by digest like the linters.
LYCHEE_IMAGE := lycheeverse/lychee:0.24.2@sha256:e2d19e57cf6ab037026f20b8e449a1f30d9d7f81eef4194763aab2eab20bd28d
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

# OS tools image (os/Dockerfile.tools): packs and compresses the rootfs and
# builds, signs and tests the Mender artifact. Built locally from the same
# pins as the rootfs.
TOOLS_IMAGE := lab-os-tools:build
# Mender OTA update artifact: rootfs.ext4 as a full-image update. Devices
# accept it only if it is signed by the key whose public half is baked into
# the image under /etc/mender (see docs/mender-signing.md).
MENDER_ARTIFACT := lab-firmware.mender
MENDER_DEVICE_TYPE := lab-device
MENDER_VERIFY_KEY := os/rootfs-overlay/etc/mender/artifact-verify-key.pem
# $(call TOOLS_RUN,<dir>[,<docker options>]) runs the tools image as the host
# user, without network, with <dir> as its working directory and the device
# public key at /verify-key.pem.
TOOLS_RUN = docker run --rm --network none $(AS_HOST_USER) \
	--volume "$(CURDIR)/$(MENDER_VERIFY_KEY):/verify-key.pem:ro" \
	--volume "$(CURDIR)/$(1):/work" --workdir /work $(2) $(TOOLS_IMAGE)

# The disk image ships xz-compressed: rootfs.ext4 is a 256 MiB file system,
# mostly empty blocks. Single-threaded xz, so the output does not depend on
# the CPU count.
ROOTFS_XZ := rootfs.ext4.xz
# Files published in a release, and the subset with a cosign signature:
# SHA256SUMS covers every file, the image can also be checked on its own.
# release-sign refuses to run if out/release holds anything else.
RELEASE_FILES := $(ROOTFS_XZ) sbom.cdx.json $(MENDER_ARTIFACT)
SIGNED_FILES := $(ROOTFS_XZ) SHA256SUMS
# A signature is valid only if this repository's release workflow made it
# while running for the tag being verified.
SIGNER_IDENTITY = https://github.com/$(GITHUB_REPO)/$(RELEASE_WORKFLOW)@refs/tags/$(TAG)
OIDC_ISSUER := https://token.actions.githubusercontent.com
# Attestations the release workflow records for the image (actions/attest):
# SLSA build provenance and the CycloneDX SBOM.
ATTESTATION_TYPES := https://slsa.dev/provenance/v1 https://cyclonedx.org/bom

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

## Docs: every relative link and #anchor in tracked Markdown resolves. Offline:
## the docs are evidence for docs/ssdf-mapping.md and docs/cra-checklist.md,
## so a renamed file or heading must not leave a dead reference; web links
## are not fetched, so the check never fails on someone else's outage
docs-check:
	$(LINT_RUN) --user "$$(id -u):$$(id -g)" $(LYCHEE_IMAGE) --offline --no-progress \
		--include-fragments $$(git ls-files '*.md')

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

## OS tools image, see TOOLS_IMAGE
tools-image:
	docker build --quiet --file os/Dockerfile.tools --tag $(TOOLS_IMAGE) os

## OS image: out/rootfs.tar and out/rootfs.ext4
rootfs: ui-build tools-image
	TOOLS_IMAGE=$(TOOLS_IMAGE) os/build-rootfs.sh

## OS hardening audit -> out/hardening: Lynis inside the rootfs, offline
## systemd-analyze security of our units, boot check under systemd in an
## unprivileged container. Fails if the image does not boot with lab-api
## answering or a unit scores above 2.0 (os/hardening-audit.sh,
## docs/hardening-review.md)
hardening-audit: rootfs
	TOOLS_IMAGE=$(TOOLS_IMAGE) os/hardening-audit.sh out/rootfs.tar out/hardening

## Mender artifact out/lab-firmware.mender from rootfs.ext4, unsigned: only
## the release workflow signs it (mender-sign)
mender: rootfs
	$(call TOOLS_RUN,out) mender-artifact write rootfs-image --no-progress \
		--compression lzma --file rootfs.ext4 --device-type $(MENDER_DEVICE_TYPE) \
		--artifact-name lab-firmware-$(VERSION) --output-path $(MENDER_ARTIFACT)

## Mender verification self-test with throwaway keys: a correct signature is
## accepted; wrong key, no signature and a flipped byte are rejected; the
## device key does not fail open (os/mender-selftest.sh)
mender-selftest: mender
	$(call TOOLS_RUN,out) mender-selftest $(MENDER_ARTIFACT) /verify-key.pem

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
		--name lab-appliance --version "$(VERSION)" \
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

## Release files in out/release: the xz-compressed rootfs.ext4, its SBOM and
## the unsigned Mender artifact; built only when the SCA gate passes
release: sca mender
	rm -rf $(RELEASE_DIR)
	mkdir -p $(RELEASE_DIR)
	$(call TOOLS_RUN,out) xz -9 --threads=1 --stdout rootfs.ext4 > $(RELEASE_DIR)/$(ROOTFS_XZ)
	cp $(SBOM_DIR)/sbom.cdx.json out/$(MENDER_ARTIFACT) $(RELEASE_DIR)/

## Sign the Mender artifact in out/release with the private key file
## MENDER_KEY, then check it against the device public key. In CI the key
## comes from the `release` environment and exists only in the mender-sign job
mender-sign: tools-image
	test -f "$(MENDER_KEY)" || \
		{ echo "usage: make mender-sign MENDER_KEY=<private key file>" >&2; exit 2; }
	$(call TOOLS_RUN,$(RELEASE_DIR),--volume "$(abspath $(MENDER_KEY)):/signing.key:ro") \
		mender-artifact sign --key /signing.key $(MENDER_ARTIFACT)
	$(call TOOLS_RUN,$(RELEASE_DIR)) mender-artifact validate --key /verify-key.pem $(MENDER_ARTIFACT)

## SHA256SUMS over the final release files, then keyless cosign signatures
## (Sigstore bundles <file>.sigstore.json). Release workflow only: needs its
## OIDC token, and does not rebuild, so it signs exactly the files the build
## and mender-sign jobs produced
release-sign:
	test -n "$${ACTIONS_ID_TOKEN_REQUEST_URL:-}" || \
		{ echo "release-sign needs the GitHub Actions OIDC token (release.yml)" >&2; exit 1; }
	cd $(RELEASE_DIR) && test "$$(ls | sort)" = "$$(printf '%s\n' $(RELEASE_FILES) | sort)" || \
		{ echo "$(RELEASE_DIR) must hold exactly: $(RELEASE_FILES); it has: $$(ls | xargs)" >&2; exit 1; }
	cd $(RELEASE_DIR) && sha256sum $(RELEASE_FILES) > SHA256SUMS
	for f in $(SIGNED_FILES); do \
		$(call COSIGN,$(RELEASE_DIR)) sign-blob --yes --bundle "$$f.sigstore.json" "$$f"; \
	done

## Download release TAG and verify it as a consumer would, with no GitHub
## login: checksums, the cosign signatures, GitHub's build provenance and
## SBOM attestations for the image (each of these must come from this
## repository's release workflow running for TAG), the Mender artifact
## signature against the device public key, and that the Mender payload is
## the same image. Needs Docker, curl, python3
verify-release: tools-image
	test -n "$(TAG)" || { echo "usage: make verify-release TAG=v0.2.1" >&2; exit 2; }
	rm -rf $(VERIFY_DIR)
	mkdir -p $(VERIFY_DIR)
	for f in $(RELEASE_FILES) SHA256SUMS $(SIGNED_FILES:=.sigstore.json); do \
		curl --fail --silent --show-error --location --output "$(VERIFY_DIR)/$$f" \
			"https://github.com/$(GITHUB_REPO)/releases/download/$(TAG)/$$f"; \
	done
	cd $(VERIFY_DIR) && sha256sum --check --strict SHA256SUMS
	for f in $(SIGNED_FILES); do \
		$(call COSIGN,$(VERIFY_DIR)) verify-blob --bundle "$$f.sigstore.json" \
			--certificate-identity "$(SIGNER_IDENTITY)" \
			--certificate-oidc-issuer $(OIDC_ISSUER) "$$f"; \
	done
	digest="$$(sha256sum $(VERIFY_DIR)/$(ROOTFS_XZ) | cut -d' ' -f1)"; \
	for type in $(ATTESTATION_TYPES); do \
		python3 tools/attestation_bundle.py $(GITHUB_REPO) "$$digest" "$$type" \
			$(VERIFY_DIR)/attestation.json; \
		$(call COSIGN,$(VERIFY_DIR)) verify-blob-attestation --bundle attestation.json \
			--type "$$type" --digest "$$digest" --digestAlg sha256 \
			--certificate-identity "$(SIGNER_IDENTITY)" \
			--certificate-oidc-issuer $(OIDC_ISSUER); \
	done
	$(call TOOLS_RUN,$(VERIFY_DIR)) mender-artifact validate --key /verify-key.pem $(MENDER_ARTIFACT)
	$(call TOOLS_RUN,$(VERIFY_DIR)) bash -c 'set -euo pipefail; \
		image=$$(xz --decompress --stdout $(ROOTFS_XZ) | sha256sum | cut -d" " -f1); \
		payload=$$(mender-artifact read --no-progress $(MENDER_ARTIFACT) | \
			sed -n "s/^[[:space:]]*rootfs-image.checksum: //p"); \
		echo "rootfs.ext4 $$image, Mender payload $$payload"; \
		test "$$image" = "$$payload"'

clean:
	rm -rf out ui/dist
