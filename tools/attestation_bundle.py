"""Fetch a GitHub artifact attestation as a Sigstore bundle, for cosign.

Usage: python3 tools/attestation_bundle.py OWNER/REPO SHA256 PREDICATE_TYPE OUT.json

Reads the repository's public attestations API (no login needed) for the
artifact with that SHA-256 digest and writes the first attestation whose
in-toto predicate type matches, e.g. https://slsa.dev/provenance/v1 or
https://cyclonedx.org/bom. Nothing here is trusted: the caller verifies the
bundle with `cosign verify-blob-attestation`, which checks the signature, the
signer identity and that the statement names this digest.

An artifact can carry several attestations; GitHub adds its own release
attestation to immutable releases. Selecting by predicate type keeps those
apart.

Exit status: 0 bundle written, 1 no attestation of that type, 2 bad usage or
API error.
"""

import base64
import json
import re
import sys
import urllib.request
from pathlib import Path
from typing import Any

API = "https://api.github.com"
REPO_PATTERN = re.compile(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+")
DIGEST_PATTERN = re.compile(r"[0-9a-f]{64}")


def predicate_type(bundle: dict[str, Any]) -> str:
    """Return the in-toto predicate type of a bundle's DSSE payload."""
    payload = base64.b64decode(bundle["dsseEnvelope"]["payload"])
    return str(json.loads(payload)["predicateType"])


def attestation_bundles(repo: str, digest: str) -> list[dict[str, Any]]:
    """Return every attestation bundle the repository holds for the digest."""
    request = urllib.request.Request(
        f"{API}/repos/{repo}/attestations/sha256:{digest}",
        headers={"Accept": "application/vnd.github+json"},
    )
    with urllib.request.urlopen(request, timeout=30) as response:  # noqa: S310 - fixed https host
        body: dict[str, Any] = json.load(response)
    return [entry["bundle"] for entry in body.get("attestations", [])]


def main(argv: list[str]) -> int:
    if len(argv) != 5:
        print(__doc__, file=sys.stderr)
        return 2
    repo, digest, wanted_type, out = argv[1:]
    if not REPO_PATTERN.fullmatch(repo) or not DIGEST_PATTERN.fullmatch(digest):
        print("attestation-bundle: expected OWNER/REPO and a hex SHA-256", file=sys.stderr)
        return 2
    try:
        bundles = attestation_bundles(repo, digest)
    except OSError as error:
        print(f"attestation-bundle: {error}", file=sys.stderr)
        return 2
    matching = [b for b in bundles if predicate_type(b) == wanted_type]
    if not matching:
        print(f"attestation-bundle: no {wanted_type} attestation for {digest}", file=sys.stderr)
        return 1
    Path(out).write_text(json.dumps(matching[0]), encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
