# NIST SSDF mapping

How this repository implements each practice of the
[Secure Software Development Framework (SSDF), NIST SP 800-218 v1.1](https://csrc.nist.gov/pubs/sp/800/218/final).
Practice names are paraphrased. SSDF v1.2 (SP 800-218 Rev. 1) was still a
draft when this table was written (2026-11-28) and is not used here.

Status: **Met**, the practice is in place and the evidence shows it.
**Partial**, part of it is in place. **Gap**, not done. Evidence links point
at files in this repository. Every link is checked in CI (`make docs-check`).

## PO: Prepare the organization

| Practice | Control in this repository | Evidence | Status | Gap |
|----------|----------------------------|----------|--------|-----|
| PO.1 Define security requirements for development | Written policy: pinning, review, scanning gates, signing, key custody | [secure-development-policy.md](secure-development-policy.md), [security-findings.md](security-findings.md) | Met | |
| PO.2 Define roles and responsibilities | One maintainer holds every role; CODEOWNERS names the owner of build and CI | [secure-development-policy.md](secure-development-policy.md#roles), [CODEOWNERS](../.github/CODEOWNERS) | Partial | No separation of duties with one person |
| PO.3 Use supporting toolchains | Make targets wrap every tool; the same targets run in CI; tools run as digest-pinned images | [Makefile](../Makefile), [ci.yml](../.github/workflows/ci.yml) | Met | |
| PO.4 Define criteria for security checks | SARIF error level blocks a merge; fixable high or critical CVEs block; accepted findings need a statement | [security-findings.md](security-findings.md), [sarif_gate.py](../tools/sarif_gate.py), [.trivyignore.yaml](../.trivyignore.yaml) | Met | |
| PO.5 Keep development environments secure | Ephemeral GitHub-hosted runners, read-only tokens, SHA-pinned actions, harden-runner audit, no host installs | [repo-protection.md](repo-protection.md#ci-hardening) | Partial | harden-runner audits egress but does not block it; developer laptop hardening is not documented |

## PS: Protect the software

| Practice | Control in this repository | Evidence | Status | Gap |
|----------|----------------------------|----------|--------|-----|
| PS.1 Protect code from unauthorized access and tampering | Ruleset as code: PR-only, required checks, signed commits, no force push; secret scanning and push protection | [main.json](../.github/rulesets/main.json), [repo-protection.md](repo-protection.md) | Met | |
| PS.2 Provide a way to verify release integrity | Keyless cosign signatures, SHA256SUMS, SLSA provenance and SBOM attestations; signed Mender artifact | [release-signing.md](release-signing.md), [mender-signing.md](mender-signing.md), [release.yml](../.github/workflows/release.yml) | Met | `gh attestation verify` path not tested; `make verify-release` covers the same claims with cosign |
| PS.3 Archive and protect each release | Immutable GitHub Releases with the SBOM; build inputs pinned (digests, Debian snapshot, lockfiles) | [release-signing.md](release-signing.md), [README.md](../README.md#how-the-os-image-is-built) | Partial | The rootfs is reproducible on one machine but not yet across machines |

## PW: Produce well-secured software

| Practice | Control in this repository | Evidence | Status | Gap |
|----------|----------------------------|----------|--------|-----|
| PW.1 Design to meet security requirements and mitigate risks | STRIDE threat model with a control per threat | [threat-model.md](threat-model.md) | Met | Open threats T8 and T12 are listed there |
| PW.2 Review the design | Threat model reviewed on trust-boundary changes and yearly | [threat-model.md](threat-model.md) | Partial | Self-review only, no independent reviewer |
| PW.4 Reuse well-secured software | Debian stable base from a dated snapshot, FastAPI, Vue, Mender; components listed in the SBOM and scanned | [security-findings.md](security-findings.md#supply-chain-sbom-and-dependency-scanning-sca), [dependabot.yml](../.github/dependabot.yml) | Met | |
| PW.5 Follow secure coding practices | Strict linters and type checks (ruff incl. `S` rules, pyright strict, ESLint, vue-tsc, ShellCheck, hadolint) | [Makefile](../Makefile), [ci.yml](../.github/workflows/ci.yml) | Met | |
| PW.6 Configure build processes for executable security | Pinned toolchain, `apt-get upgrade` from the snapshot, setuid bits stripped, sandboxed systemd unit, kernel sysctl and module settings | [hardening-review.md](hardening-review.md), [Dockerfile.rootfs](../os/Dockerfile.rootfs) | Partial | sysctl and module settings are not verified on a running kernel |
| PW.7 Review and analyze human-readable code | Bandit and Semgrep on every PR, code scanning gate in the ruleset, maintainer self-review | [security-findings.md](security-findings.md), [sast.yml](../.github/workflows/sast.yml) | Partial | No second human reviewer; an AI reviewer is planned but not set up |
| PW.8 Test executable code | Unit tests, Mender signature negative tests, boot check with lab-api answering, Lynis and `systemd-analyze security` | [Makefile](../Makefile), [mender-selftest.sh](../os/mender-selftest.sh), [hardening-audit.sh](../os/hardening-audit.sh) | Partial | No DAST or fuzzing of the API |
| PW.9 Configure secure settings by default | No accounts with passwords, no login path, API unprivileged, only required services, updates accepted only when signed | [hardening-review.md](hardening-review.md#checklist) | Partial | The API has no authentication or TLS by default (threat T9) |

## RV: Respond to vulnerabilities

| Practice | Control in this repository | Evidence | Status | Gap |
|----------|----------------------------|----------|--------|-----|
| RV.1 Identify and confirm vulnerabilities on an ongoing basis | Weekly SAST and SCA runs on unchanged code, Dependabot alerts, private vulnerability reporting | [SECURITY.md](../SECURITY.md), [supply-chain.yml](../.github/workflows/supply-chain.yml), [sast.yml](../.github/workflows/sast.yml) | Met | Released SBOMs are not rescanned after release |
| RV.2 Assess, prioritize and remediate | Severity policy and response targets; fixes ship as a Debian snapshot bump or dependency update in a new signed release | [SECURITY.md](../SECURITY.md#response-targets), [security-findings.md](security-findings.md) | Met | |
| RV.3 Analyze root causes | Incident flow requires a root-cause note and a regression check; example: the v0.2.0 release file list bug fixed in v0.2.1 | [secure-development-policy.md](secure-development-policy.md#incidents-and-vulnerabilities), [release-signing.md](release-signing.md) | Partial | No recurring analysis across findings yet |
