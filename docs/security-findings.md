# Security findings: scanners and severity policy

Every scanner writes its report as SARIF and uploads it to GitHub code
scanning (Security -> Code scanning), so findings are tracked as alerts with
an owner and a history, not lost in job logs. A separate gate decides what
blocks a merge.

## Static analysis (SAST)

`make sast` runs locally and in `.github/workflows/sast.yml` (pull requests,
pushes to `main`, weekly):

| Tool | Scope | Version pin | Code scanning category |
|------|-------|-------------|------------------------|
| [Bandit](https://bandit.readthedocs.io) | `api/src` (Python) | `api/uv.lock` | `bandit` |
| [Semgrep](https://semgrep.dev) CE | tracked files: Python, TypeScript, bash, workflows | image digest in `Makefile` | `semgrep` |

Semgrep rulesets: `p/python`, `p/typescript`, `r/bash`, `p/github-actions`.
They come from the public Semgrep registry at scan time (no account, metrics
off). The engine is pinned; the rules deliberately are not, so the weekly
run applies new detections to unchanged code. Semgrep does not parse `.vue`
single-file components; the TypeScript in `ui/src/*.ts` is covered.

Ruff's `S` rules (a Bandit port) also run in `make api-test` and catch the
same Python issues earlier, in the editor.

## Supply chain: SBOM and dependency scanning (SCA)

`make sbom` writes `out/sbom/sbom.cdx.json` (CycloneDX) for what ships:

- Debian and Python packages, found by Trivy in the exact `rootfs.tar`
  that the build produced (`sbom-rootfs.cdx.json`);
- npm packages bundled into the UI: the production dependencies from
  `ui/package-lock.json` (`sbom-ui.cdx.json`), because the minified bundle
  no longer shows them;
- merged and schema-validated with cyclonedx-cli.

`make sca` builds that SBOM, then runs Trivy twice:

| Scan | Finds | Code scanning category |
|------|-------|------------------------|
| `trivy fs` on the repository | known vulnerabilities in `api/uv.lock` and `ui/package-lock.json`, committed secrets, Dockerfile misconfigurations | `trivy-repo` |
| `trivy sbom` on `sbom.cdx.json` | known vulnerabilities in everything that ships, scanned from the SBOM alone, the way an operator can monitor a released image | `trivy-sbom` |

`.github/workflows/supply-chain.yml` runs it on pull requests, pushes to
`main` and weekly, uploads both SARIF reports and keeps the SBOM as a
workflow artifact. Trivy and cyclonedx-cli images are pinned by digest; the
vulnerability database is downloaded on each run, so the weekly run catches
new advisories against unchanged code.

Vulnerabilities without a fixed version are left out (`--ignore-unfixed`):
there is nothing to upgrade to, and the Debian base alone carries hundreds
of them. Accepted findings live in `.trivyignore.yaml`, each with a
statement saying why it is safe.

### Keeping dependencies current

| What | Pinned by | Updated by |
|------|-----------|------------|
| Python packages | `api/uv.lock` (hashes) | Dependabot (`uv`), weekly, grouped minor/patch |
| npm packages | `ui/package-lock.json` (integrity) | Dependabot (`npm`) |
| GitHub Actions | commit SHA | Dependabot (`github-actions`) |
| Base images | digest in `os/Dockerfile.*` | Dependabot (`docker`) |
| Debian packages | `DEBIAN_SNAPSHOT` in `os/Dockerfile.*` | by hand, when `trivy-sbom` reports a fixed vulnerability |
| Tool images (ShellCheck, hadolint, Semgrep, Trivy, cyclonedx-cli) | digest in `Makefile` | by hand |

Dependabot waits 7 days after a release before proposing it (cooldown), so
a compromised release has time to be caught and pulled; security updates
skip the wait. `apt-get upgrade` in the image build makes the snapshot
decide every Debian package version, including packages already in the
base image.

## Severity policy

The SARIF level is the common scale across tools:

| SARIF level | Bandit | Semgrep | Trivy | Action |
|-------------|--------|---------|-------|--------|
| `error` | HIGH severity | ERROR | CRITICAL, HIGH | Blocks the merge: `make sast` / `make sca` fail (`tools/sarif_gate.py`). Fix before merging. |
| `warning` | MEDIUM | WARNING | MEDIUM | Fix within the current iteration; tracked as an open alert. |
| `note` | LOW | INFO | LOW, UNKNOWN | Triage: fix, or dismiss in code scanning with a reason. |

## False positives

A suppression must name the rule and say why it is safe, so a reviewer can
challenge it in the pull request:

```python
subprocess.run(["systemctl", "restart", unit])  # nosec B603 - fixed argv, unit from an allowlist
```

Semgrep: `# nosemgrep: <rule-id>` with the same kind of reason. Trivy: an
entry in `.trivyignore.yaml` with the finding ID, the paths it applies to
and a `statement`. An alert
that only applies to code scanning (for example, a test fixture) may be
dismissed there as "false positive" or "used in tests", with a comment.
