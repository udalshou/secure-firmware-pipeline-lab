# Repository protection

How changes reach `main`, and what stops a change that skipped the checks.
SSDF PS.1 (protect all forms of code from unauthorized access and tampering)
and PO.5 (secure environments for software development).

## Branch ruleset

The ruleset on the default branch is kept as code in
[`.github/rulesets/main.json`](../.github/rulesets/main.json). It has no
bypass actors, so it binds the repository admin too.

| Rule | Effect |
|------|--------|
| `pull_request` | Every change goes through a pull request; squash merge only. Open review threads block the merge. |
| `required_status_checks` | CI jobs `api`, `ui`, `os`, `image`, `sast` and `sca` must pass on a branch that is up to date with `main`. |
| `code_scanning` | A Bandit, Semgrep OSS or Trivy alert of high or higher security severity (or error level) in the PR blocks the merge, on top of the failing `sast` / `sca` job. |
| `required_signatures` | Every commit on `main` carries a verified signature. Squash merges are signed by GitHub. |
| `required_linear_history`, `non_fast_forward`, `deletion` | No merge commits, no force pushes, `main` cannot be deleted. |

Apply or update it with the GitHub CLI (repository admin token):

```
gh api -X POST repos/{owner}/{repo}/rulesets --input .github/rulesets/main.json
gh api -X PUT repos/{owner}/{repo}/rulesets/<id> --input .github/rulesets/main.json
```

### One developer, one reviewer

A PR author cannot approve their own PR, so a required human approval would
deadlock a one-person repository. The ruleset requires zero approvals and
does not require a code owner review. [`CODEOWNERS`](../.github/CODEOWNERS)
still marks the build system and CI (`os/`, `.github/`, `tools/`, `Makefile`)
as owned by the security reviewer. The second, independent review comes from
the automated checks above and from an AI reviewer on every PR (task 09).
With a second maintainer, raise `required_approving_review_count` to 1 and
set `require_code_owner_review`.

## Signed commits

Commits are signed with an SSH key registered on GitHub as a signing key
(`gpg.format ssh`, `commit.gpgsign true` in the repository's git config).
GitHub shows them as "Verified"; the ruleset rejects unsigned ones.

## Secret scanning

Secret scanning and push protection are on: a push containing a recognised
credential is rejected before it reaches GitHub. Private keys never enter
the repository (`.gitignore` blocks `*.key` except `*public*.key`).

## CI hardening

- Every third-party action is pinned by full commit SHA, tag in a trailing
  comment; Dependabot proposes updates.
- Workflow token is `contents: read`; a job that uploads SARIF adds only
  `security-events: write`. The release `publish` job, which builds nothing,
  is the only one with `contents: write` and `id-token: write`
  ([release-signing.md](release-signing.md)). Checkouts use
  `persist-credentials: false`.
- No workflow uses `pull_request_target`, so code from a fork never runs with
  a write token or secrets.
- `step-security/harden-runner` runs in audit mode on the `supply-chain`
  workflow, the job with the most network access, and on both release jobs. It records outbound
  connections without blocking them; switching to `egress-policy: block`
  needs an allow-list built from those records.

## OpenSSF Scorecard

`.github/workflows/scorecard.yml` runs
[OpenSSF Scorecard](https://github.com/ossf/scorecard) on every push to
`main`, weekly and when branch protection changes. Results land in code
scanning and in the public Scorecard API, which backs the README badge.
