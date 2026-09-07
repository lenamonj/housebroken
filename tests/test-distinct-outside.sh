#!/bin/bash
# test-distinct-outside.sh - read-only check of scripts/distinct-outside.sh
# against a busy public repository.
set -u
name="distinct-outside.sh"
here=$(cd "$(dirname "$0")" && pwd)
script="$here/../scripts/distinct-outside.sh"
HOUSEBROKEN_HOME=$(mktemp -d)
export HOUSEBROKEN_HOME
trap 'rm -rf "$HOUSEBROKEN_HOME"' EXIT

fail() { echo "FAIL $name: $1" >&2; exit 1; }

help=$(bash "$script" --help) || fail "--help exited non-zero"
printf '%s' "$help" | grep -q "usage: distinct-outside.sh" || fail "--help printed no usage line"

out=$(bash "$script" cli/cli) || fail "run against cli/cli exited non-zero"
printf '%s\n' "$out" | grep -qE '^cli/cli: [0-9]+ distinct outside humans in 120d ->' ||
  fail "no count printed for the default window: $out"
n=$(printf '%s\n' "$out" | sed -E 's/^cli\/cli: ([0-9]+) .*/\1/')
[ "$n" -gt 0 ] || fail "cli/cli reported no outside contributors"

# the window is an option
out=$(bash "$script" --days 30 cli/cli) || fail "--days 30 run exited non-zero"
printf '%s\n' "$out" | grep -qE 'distinct outside humans in 30d ->' || fail "--days was not applied"

bash "$script" --days notanumber cli/cli >/dev/null 2>&1 && fail "--days notanumber was accepted"

echo "PASS $name"
