# Security findings: scanners and severity policy

Every scanner writes its full report as SARIF and uploads it to GitHub code
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

## Severity policy

The SARIF level is the common scale across tools:

| SARIF level | Bandit | Semgrep | Action |
|-------------|--------|---------|--------|
| `error` | HIGH severity | ERROR | Blocks the merge: `make sast` fails (`tools/sarif_gate.py`). Fix before merging. |
| `warning` | MEDIUM | WARNING | Fix within the current iteration; tracked as an open alert. |
| `note` | LOW | INFO | Triage: fix, or dismiss in code scanning with a reason. |

## False positives

A suppression must name the rule and say why it is safe, so a reviewer can
challenge it in the pull request:

```python
subprocess.run(["systemctl", "restart", unit])  # nosec B603 - fixed argv, unit from an allowlist
```

Semgrep: `# nosemgrep: <rule-id>` with the same kind of reason. An alert
that only applies to code scanning (for example, a test fixture) may be
dismissed there as "false positive" or "used in tests", with a comment.
