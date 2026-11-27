"""Fail the build if any SARIF report holds a blocking (error-level) finding.

Usage: python3 tools/sarif_gate.py REPORT.sarif [REPORT.sarif ...]

Scanners keep every finding in their SARIF reports, which go to GitHub code
scanning for triage. This gate applies the merge policy in
docs/security-findings.md: SARIF level "error" (Bandit HIGH severity, Semgrep
ERROR) blocks; "warning" and "note" are triaged in code scanning instead.

A result's level is resolved as SARIF 2.1.0 defines it: the result's own
level, else its rule's defaultConfiguration.level, else "warning". Semgrep
only sets the level on the rule, Bandit on each result.

Exit status: 0 no blocking findings, 1 blocking findings, 2 unreadable report.
"""

import json
import sys
from pathlib import Path
from typing import Any

BLOCKING_LEVEL = "error"
DEFAULT_LEVEL = "warning"


def blocking_findings(report: Path) -> list[str]:
    """Return one "tool: path:line: rule: message" line per blocking result."""
    sarif: dict[str, Any] = json.loads(report.read_text(encoding="utf-8"))
    findings: list[str] = []
    for run in sarif["runs"]:
        driver = run["tool"]["driver"]
        rule_levels = {
            rule["id"]: rule.get("defaultConfiguration", {}).get("level", DEFAULT_LEVEL)
            for rule in driver.get("rules", [])
        }
        for result in run.get("results", []):
            rule_id = result.get("ruleId", "?")
            level = result.get("level") or rule_levels.get(rule_id, DEFAULT_LEVEL)
            if level != BLOCKING_LEVEL:
                continue
            location = result["locations"][0]["physicalLocation"]
            path = location["artifactLocation"]["uri"]
            line = location.get("region", {}).get("startLine", 0)
            message = result["message"]["text"].splitlines()[0]
            findings.append(f"{driver['name']}: {path}:{line}: {rule_id}: {message}")
    return findings


def main(reports: list[str]) -> int:
    if not reports:
        print(__doc__, file=sys.stderr)
        return 2
    findings: list[str] = []
    for report in reports:
        try:
            findings += blocking_findings(Path(report))
        except (OSError, ValueError, KeyError, IndexError) as error:
            print(f"sarif-gate: cannot read {report}: {error!r}", file=sys.stderr)
            return 2
    for finding in findings:
        print(finding)
    print(f"sarif-gate: {len(findings)} blocking finding(s) in {len(reports)} report(s)")
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
