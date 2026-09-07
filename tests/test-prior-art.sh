#!/bin/bash
# test-prior-art.sh - read-only checks of scripts/prior-art.sh against two
# public repositories whose closed items produced the rules it enforces.
set -u
name="prior-art.sh"
here=$(cd "$(dirname "$0")" && pwd)
script="$here/../scripts/prior-art.sh"
HOUSEBROKEN_HOME=$(mktemp -d)
export HOUSEBROKEN_HOME
trap 'rm -rf "$HOUSEBROKEN_HOME"' EXIT

fail() { echo "FAIL $name: $1" >&2; exit 1; }

# --help exits 0 and prints the usage block
help=$(bash "$script" --help) || fail "--help exited non-zero"
printf '%s' "$help" | grep -q "usage: prior-art.sh" || fail "--help printed no usage line"

# typer #1881 is an open PR; it was once read as an issue and a duplicate got filed
out=$(bash "$script" fastapi/typer "utils docs") || fail "run against fastapi/typer failed"
printf '%s\n' "$out" | grep -qE '^\| PR \| #1881 \|' || fail "typer #1881 not listed as a PR"
printf '%s\n' "$out" | grep -qE '^\| issue \| #1881 \|' && fail "typer #1881 listed as an issue"

# swift-http-types #98 is a closed issue and its ruling must be quoted
out=$(bash "$script" apple/swift-http-types "relative URL") || fail "run against apple/swift-http-types failed"
line=$(printf '%s\n' "$out" | grep -E '^\| issue \| #98 \| closed \|' | head -1)
[ -n "$line" ] || fail "swift-http-types #98 not listed as a closed issue"
ruling=$(printf '%s' "$line" | awk -F'|' '{print $8}' | tr -d ' ')
[ -n "$ruling" ] || fail "swift-http-types #98 has an empty ruling"

# --out writes the printout where file-pr.sh looks for it
bash "$script" apple/swift-http-types "relative URL" --out >/dev/null || fail "--out run failed"
[ -f "$HOUSEBROKEN_HOME/prior-art/prior-art-apple-swift-http-types.md" ] ||
  fail "--out did not write under HOUSEBROKEN_HOME/prior-art"

echo "PASS $name"
