#!/usr/bin/env bash
# Proves that Mender artifact verification rejects what it must, using the
# same mender-artifact build that signs releases. Runs in the tools container
# (see Dockerfile.tools) on every CI run; no real signing key is involved.
#
# Usage: mender-selftest <unsigned.mender> <device-public-key.pem>
#
# Checks, with throwaway ECDSA P-256 keys A and B:
#   1. an artifact signed with A validates with A
#   2. it does not validate with B (wrong signer)
#   3. the unsigned artifact does not validate with A (no signature)
#   4. the signed artifact with one flipped byte does not validate
#   5. the unsigned artifact does not validate with the device public key.
#      mender-artifact 3.9 exits 0 when given a key type it cannot use
#      (e.g. Ed25519), so this guards the baked-in key against failing open.
set -euo pipefail

unsigned=$1
device_key=$2

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failures=0

# mender-artifact 3.9 reads only traditional PEM keys (SEC1 "EC PRIVATE KEY").
for name in a b; do
    openssl ecparam -genkey -name prime256v1 -noout -out "$work/$name.key"
    openssl ec -in "$work/$name.key" -pubout -out "$work/$name.pem" 2>/dev/null
done

cp "$unsigned" "$work/signed.mender"
mender-artifact sign -k "$work/a.key" "$work/signed.mender"

# Flip the lowest bit of the byte in the middle of the file (payload data).
cp "$work/signed.mender" "$work/flipped.mender"
offset=$(($(stat --format=%s "$work/flipped.mender") / 2))
byte=$(od --address-radix=n --format=u1 --skip-bytes="$offset" --read-bytes=1 "$work/flipped.mender")
printf '%b' "\\0$(printf '%03o' $((byte ^ 1)))" |
    dd of="$work/flipped.mender" bs=1 seek="$offset" conv=notrunc status=none

# expect <accept|reject> <description> <public key> <artifact>
expect() {
    local want=$1 description=$2 key=$3 artifact=$4 output got
    if output=$(mender-artifact validate -k "$key" "$artifact" 2>&1); then
        got=accept
    else
        got=reject
    fi
    if [[ $got == "$want" ]]; then
        echo "PASS  $description: ${want}ed"
    else
        echo "FAIL  $description: ${got}ed, expected ${want}"
        failures=$((failures + 1))
    fi
    echo "      mender-artifact: $(tail -n 1 <<<"$output")"
}

expect accept "signed with A, verified with A" "$work/a.pem" "$work/signed.mender"
expect reject "signed with A, verified with B" "$work/b.pem" "$work/signed.mender"
expect reject "unsigned, verified with A" "$work/a.pem" "$unsigned"
expect reject "signed with A, one byte flipped" "$work/a.pem" "$work/flipped.mender"
expect reject "unsigned, verified with the device key" "$device_key" "$unsigned"

if ((failures > 0)); then
    echo "$failures Mender verification check(s) failed" >&2
    exit 1
fi
