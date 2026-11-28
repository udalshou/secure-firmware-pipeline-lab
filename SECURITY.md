# Security policy

## Supported versions

Only the latest release receives security fixes.

| Version | Supported |
|---------|-----------|
| 0.2.x (latest) | Yes |
| < 0.2 | No |

## Reporting a vulnerability

Report privately through GitHub:
**Security -> Report a vulnerability** on this repository
([direct link](https://github.com/udalshou/secure-firmware-pipeline-lab/security/advisories/new)).
Please do not open a public issue or pull request for a vulnerability.

Useful details: affected release or commit, component (API, UI, OS image,
build pipeline, release signing), steps to reproduce, and impact.

## Response targets

| Step | Target |
|------|--------|
| Acknowledge the report | 5 business days |
| Triage: confirm, assign a CVSS v3.1 severity | 10 business days |
| Fix released, critical or high | 30 days after triage |
| Fix released, medium or low | next scheduled release, at most 90 days |

This is a one-maintainer project; the targets are best effort. A fix ships
as a new signed release; verify it with `make verify-release TAG=<tag>`.

## Coordinated disclosure

- The report stays private until a fix is released, or 90 days after the
  report, whichever comes first. The date can move by agreement.
- The fix is published with a GitHub security advisory that describes the
  issue, affected versions, impact, severity and how to update. A CVE is
  requested through GitHub when it applies.
- Reporters are credited in the advisory unless they ask not to be.
- Good-faith research on your own copy of the software is welcome. Do not
  test against systems you do not own.

## Scope

In scope: the code, build scripts, workflows and released artifacts in this
repository. Out of scope: vulnerabilities in upstream components that are
already public (Dependabot and the weekly scans track them), and findings
that need physical access to a device, which the lab does not defend against
(see [docs/threat-model.md](docs/threat-model.md)).
