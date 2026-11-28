# EU Cyber Resilience Act checklist

Status of the appliance against the essential requirements of the
[Cyber Resilience Act, Regulation (EU) 2024/2847](https://eur-lex.europa.eu/eli/reg/2024/2847/oj).
Requirement texts are paraphrased; the regulation is the reference. This is
an engineering self-check for a lab product, not a conformity assessment.

Key dates: reporting duties under Article 14 apply from 2026-09-11; the
other obligations, including Annex I, apply from 2027-12-11.

Classification: a general-purpose appliance with a web UI falls in the
default category and can use internal control (Module A, self-assessment).
If the product were a router, firewall or similar network device, it would
be an important product (Annex III) and need a harmonised standard or
third-party assessment.

Status: **Met**, **Partial**, **Gap**, or **N/A** for the lab.

## Annex I Part I: product security requirements

| Item | Requirement (paraphrased) | Status | Evidence or gap |
|------|---------------------------|--------|-----------------|
| 1 | Security level appropriate to the risks | Partial | Risk assessment in [threat-model.md](threat-model.md); open threats T8, T9, T12 |
| 2(a) | No known exploitable vulnerabilities at release | Met | Release build runs `make sca`; fixable high or critical CVEs fail it ([security-findings.md](security-findings.md)) |
| 2(b) | Secure by default configuration, with a reset to the original state | Partial | Hardened defaults ([hardening-review.md](hardening-review.md)); no factory reset |
| 2(c) | Vulnerabilities fixable through security updates, automatic by default with opt-out | Partial | Signed Mender full-image updates; no update server or automatic install in the lab |
| 2(d) | Protection from unauthorised access: authentication, access control | Gap | The API has no authentication (threat T9); no login path exists on the device |
| 2(e) | Confidentiality of stored and transmitted data | Gap | No TLS on the API; the device stores no user data |
| 2(f) | Integrity of data, programs and configuration; report corruption | Partial | Signed updates (threat T6); no verified boot or dm-verity (threat T12) |
| 2(g) | Data minimisation | Met | The API processes only version and uptime |
| 2(h) | Availability of essential functions, resilience against denial of service | Partial | systemd restarts lab-api if it crashes; no rate limit or firewall (threat T10) |
| 2(i) | Minimal negative impact on other devices and networks | Met | One listener, no outbound traffic except time sync |
| 2(j) | Limited attack surface, including external interfaces | Met | Only lab-api and timesyncd run; no sshd, no gettys, no setuid programs |
| 2(k) | Exploitation mitigation to reduce incident impact | Met | systemd sandbox, exposure score 1.2, kernel sysctl and module settings ([hardening-review.md](hardening-review.md)) |
| 2(l) | Recording and monitoring of security-relevant activity, with opt-out | Partial | Persistent journald; no audit log and no log shipping |
| 2(m) | Secure, easy removal of all data and settings | Gap | No factory reset or data wipe function |

## Annex I Part II: vulnerability handling requirements

| Item | Requirement (paraphrased) | Status | Evidence or gap |
|------|---------------------------|--------|-----------------|
| 1 | Identify and document components; SBOM in a machine-readable format | Met | CycloneDX SBOM of what ships, attached to each release and attested ([security-findings.md](security-findings.md)) |
| 2 | Remediate without delay; separate security updates where feasible | Partial | Response targets in [SECURITY.md](../SECURITY.md#response-targets); every update is a full image, so security and feature changes are not separated |
| 3 | Regular security tests and reviews | Met | SAST and SCA on every PR and weekly; hardening audit ([ssdf-mapping.md](ssdf-mapping.md)) |
| 4 | Disclose fixed vulnerabilities publicly with description, impact, severity, remedy | Partial | GitHub security advisories per [SECURITY.md](../SECURITY.md); none published yet |
| 5 | Coordinated vulnerability disclosure policy | Met | [SECURITY.md](../SECURITY.md#coordinated-disclosure) |
| 6 | Contact address for reporting vulnerabilities | Met | Private vulnerability reporting on GitHub ([SECURITY.md](../SECURITY.md)) |
| 7 | Secure distribution of updates | Met | Signed Mender artifact, keyless cosign signatures, provenance ([release-signing.md](release-signing.md)) |
| 8 | Security updates free of charge, without delay, with advisory messages | Partial | Releases are public and free; advisory messages not yet issued |

## Reporting duties (Article 14)

Not exercised in the lab; this is the process a manufacturer would follow.
Reports go through the ENISA single reporting platform to the CSIRT
designated as coordinator and to ENISA.

| Event | Early warning | Notification | Final report |
|-------|---------------|--------------|--------------|
| Actively exploited vulnerability | 24 h after becoming aware | 72 h | 14 days after a corrective measure is available |
| Severe incident affecting the product's security | 24 h | 72 h | 1 month after the notification |

Users are informed about the vulnerability or incident and the mitigation
as well. The internal steps are in
[secure-development-policy.md](secure-development-policy.md#incidents-and-vulnerabilities).

## Other manufacturer obligations

| Obligation | Status | Note |
|------------|--------|------|
| Support period, at least 5 years unless the product's expected use is shorter (Art. 13) | Gap | Lab: only the latest 0.2.x release is supported ([SECURITY.md](../SECURITY.md#supported-versions)) |
| User information and instructions (Annex II) | Partial | README covers build, verification and update; no end-user manual |
| Technical documentation (Annex VII) | Partial | This directory: threat model, SSDF mapping, hardening review, signing docs, SBOM |
| EU declaration of conformity, CE marking | N/A | Not a product placed on the market |
