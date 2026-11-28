# Threat model

What can go wrong with the appliance and its pipeline, and which control in
this repository answers it. SSDF PW.1 (design software to meet security
requirements and mitigate risks); CRA Annex I Part I (1) (security level
based on a risk assessment). Reviewed on every change to the trust
boundaries below, at the latest once a year.

## System and trust boundaries

```
 developer laptop          GitHub                          device
 ┌──────────────┐  signed  ┌───────────────────────────┐   ┌──────────────────────┐
 │ git + SSH    │  commit  │ main (ruleset)            │   │ Mender client        │
 │ signing key  ├─────────►│ CI: test, SAST, SCA, SBOM │   │  verifies artifact   │
 │ Mender key   │   PR     │ release.yml               │   │  signature (P-256)   │
 │ (~/.lab-keys)│          │  build -> mender-sign     │   │ lab-api :8080        │
 └──────────────┘          │  (env `release`) ->       │   │  /health /status, UI │
                           │  publish (cosign, OIDC)   │   │ journald, timesyncd  │
                           └────────────┬──────────────┘   └──────────▲───────────┘
                                        │ GitHub Release              │ OTA update
                                        └──────── operator ───────────┘
 B1: laptop -> GitHub     B2: CI job -> secrets/OIDC     B3: release -> device
 B4: management network -> lab-api
```

Assets: the source and build definitions, the Mender signing key, the
release signing identity (the `release.yml` workflow on a `v*` tag), the
released image, and the device's integrity and availability. The lab API
holds no user data or credentials.

## Threats and controls (STRIDE)

| # | Boundary | Threat | Control | Status |
|---|----------|--------|---------|--------|
| T1 | B1 | Spoofing: a commit pushed as the maintainer with stolen GitHub credentials | Signed commits required on `main`, PR-only changes, no bypass actors ([repo-protection.md](repo-protection.md)) | Mitigated; a stolen SSH signing key defeats it |
| T2 | B1 | Tampering: malicious code or a backdoored dependency reaches `main` | Required CI, SAST and SCA gates, lockfiles with hashes, Dependabot cooldown of 7 days ([security-findings.md](security-findings.md)) | Partly mitigated: no second human reviewer (see PW.7 in [ssdf-mapping.md](ssdf-mapping.md)) |
| T3 | B2 | Tampering: a compromised third-party action or tool image changes the build | Actions pinned by SHA, tool images by digest, `contents: read` tokens, harden-runner audit on release and supply-chain jobs | Mitigated for drift; egress is audited, not blocked |
| T4 | B2 | Information disclosure: the Mender signing key leaks from CI | Key only in the `release` environment, which needs a reviewer and a `v*` tag; only the `mender-sign` job sees it ([mender-signing.md](mender-signing.md)) | Mitigated; no HSM, the key is a file secret |
| T5 | B2 | Elevation: fork PR code runs with secrets or a write token | No `pull_request_target`; fork workflows get no secrets | Mitigated |
| T6 | B3 | Tampering: a modified image or update is installed on a device | Mender artifact signature checked on the device against the baked-in public key; negative tests in `make mender-selftest` | Mitigated for OTA; no verified boot for physical access |
| T7 | B3 | Spoofing: an attacker publishes a release that looks official | Keyless cosign signatures bound to `release.yml@refs/tags/<tag>`, SLSA provenance, immutable releases, `make verify-release` ([release-signing.md](release-signing.md)) | Mitigated |
| T8 | B3 | Tampering: rollback to an older, vulnerable signed image | None in the lab: Mender accepts any validly signed artifact | Gap: needs a version check or anti-rollback counter |
| T9 | B4 | Spoofing / information disclosure: anyone on the network reads `/status` or the UI | The API exposes only version and uptime; no credentials, no writes | Accepted for the lab; a real device needs authentication and TLS |
| T10 | B4 | Denial of service: request flood on lab-api | systemd restarts lab-api if it crashes (`Restart=on-failure`); journald size capped | Partly mitigated: no rate limit, no firewall |
| T11 | device | Elevation: a bug in lab-api leads to root | `DynamicUser`, no capabilities, `ProtectSystem=strict`, syscall filter, no setuid binaries, no login path ([hardening-review.md](hardening-review.md)) | Mitigated |
| T12 | device | Tampering with physical access: rootfs changed offline | None in the lab | Gap: verified boot and dm-verity (out of scope, see hardening review) |
| T13 | all | Repudiation: who changed or released what | Signed commits, PR history, Actions logs, provenance attestations, environment deployment log | Mitigated |

## Gaps carried forward

T8, T12 and the missing authentication and TLS for T9 are product gaps,
listed in [cra-checklist.md](cra-checklist.md). T2 (no second human
reviewer) is a process gap, listed in [ssdf-mapping.md](ssdf-mapping.md).
