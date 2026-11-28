# Secure development policy

The rules every change to this repository follows. The controls that
enforce them are linked; [ssdf-mapping.md](ssdf-mapping.md) maps them to
NIST SSDF. Owner: the maintainer. Reviewed once a year and whenever a
control changes.

## Roles

One maintainer holds every role: developer, security reviewer (owner of
`os/`, `.github/`, `tools/` and `Makefile` in
[CODEOWNERS](../.github/CODEOWNERS)), release approver (required reviewer
of the `release` environment) and key custodian. Separation of duties is
not possible with one person; the automated gates below stand in for a
second reviewer. With a second maintainer, the ruleset requires one
approval and code owner review ([repo-protection.md](repo-protection.md)).

## Changes and review

- Every change reaches `main` through a pull request; squash merge only;
  commits signed. Enforced by the ruleset in
  [`.github/rulesets/main.json`](../.github/rulesets/main.json).
- A pull request merges only with green required checks (`api`, `ui`,
  `os`, `image`, `sast`, `sca`) and no high code scanning alert.
- The author reviews their own diff before merging, against the threat
  model when a trust boundary changes ([threat-model.md](threat-model.md)).

## Dependencies

- Every dependency is pinned: base images and tool images by digest,
  GitHub Actions by commit SHA, Debian packages by a dated snapshot, Python
  and npm packages by lockfile with hashes. `:latest` and floating tags are
  not allowed.
- Dependabot proposes updates weekly, after a 7-day cooldown; security
  updates skip the wait. An update merges through the same gates as code.
- Related pins move together in one pull request (for example the uv image,
  `setup-uv` and `uv_build`).
- A new dependency needs a reason in the pull request and must appear in the
  SBOM. Accepted scanner findings go in `.trivyignore.yaml` with a
  statement ([security-findings.md](security-findings.md)).

## Release and signing

- Only a commit on `main` can be released, by pushing a `v*` tag.
- Release files are signed keyless with cosign in the `publish` job, which
  builds nothing, and get SLSA provenance and SBOM attestations. Releases
  are immutable ([release-signing.md](release-signing.md)).
- The Mender artifact is signed in the `mender-sign` job, which waits for
  the release approver ([mender-signing.md](mender-signing.md)).
- Before announcing a release: `make verify-release TAG=<tag>` passes.

## Key custody

| Key | Where | Rotation |
|-----|-------|----------|
| SSH commit signing key | Maintainer laptop; public key registered on GitHub as a signing key | On suspected compromise or yearly |
| Mender artifact signing key | `~/.lab-keys/` offline copy and the `release` environment secret | On suspected compromise; procedure in [mender-signing.md](mender-signing.md#key-rotation) |
| Release signing identity | None stored: keyless, bound to `release.yml` on a tag | N/A |

Private keys never enter the repository; `.gitignore`, secret scanning and
push protection back this up.

## Incidents and vulnerabilities

1. **Intake**: private vulnerability report, scanner alert, Dependabot
   alert or own finding. Acknowledge per [SECURITY.md](../SECURITY.md).
2. **Triage**: confirm, rate with CVSS v3.1, decide if it is actively
   exploited. An actively exploited vulnerability or a severe incident
   starts the CRA Article 14 clock (24 h early warning, see
   [cra-checklist.md](cra-checklist.md#reporting-duties-article-14)).
3. **Contain**: for a leaked key, revoke and rotate it first; for a
   compromised release, mark it in the release notes and publish a fixed
   one.
4. **Fix and release** through the normal pull request and release flow;
   no bypass of the gates.
5. **Disclose**: GitHub security advisory per
   [SECURITY.md](../SECURITY.md#coordinated-disclosure).
6. **Root cause**: write down why it happened and add a check that would
   have caught it (test, scanner rule, gate). Example: v0.2.0 shipped a
   file missing from `SHA256SUMS`; v0.2.1 fixed the list and `make
   release-sign` refuses to sign unless `out/release` holds exactly the
   release files ([release-signing.md](release-signing.md)).
