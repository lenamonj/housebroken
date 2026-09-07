#!/bin/bash
# test-pr-sweep.sh - --all lists at least one open PR for the authenticated
# user and exits 0, the first run records its open set in the state file given
# by --state, and a PR that has left the open set is reported as merged or
# closed on the next run. Read-only; the real state file is never touched.
set -u
name=test-pr-sweep
script="$(cd "$(dirname "$0")/../scripts" && pwd)/pr-sweep.sh"

bash "$script" --help | grep -q "Usage:" || { echo "FAIL $name: --help has no usage"; exit 1; }
bash "$script" --nonsense 2>/dev/null && { echo "FAIL $name: bad argument exited 0"; exit 1; }
grep -q 'HOUSEBROKEN_USER' "$script" || { echo "FAIL $name: no HOUSEBROKEN_USER"; exit 1; }
grep -qi 'lenamonj' "$script" && { echo "FAIL $name: literal username still present"; exit 1; }

tmp=$(mktemp -d) || { echo "FAIL $name: mktemp failed"; exit 1; }
trap 'rm -rf "$tmp"' EXIT
state="$tmp/sweep-state.json"

out=$(bash "$script" --all --state "$state")
rc=$?
echo "$out" | head -20
[ "$rc" -eq 0 ] || { echo "FAIL $name: --all exited $rc"; exit 1; }
echo "$out" | grep -qE '^(ok|ACT) ' || { echo "FAIL $name: no PR rows"; exit 1; }
echo "$out" | grep -qx -- '--- no previous sweep recorded' ||
  { echo "FAIL $name: first run did not say there was no previous sweep"; exit 1; }
open=$(echo "$out" | sed -n 's/^open PRs: \([0-9]*\);.*/\1/p')
if [ -z "$open" ] || [ "$open" -lt 1 ]; then echo "FAIL $name: open PR count is $open"; exit 1; fi

[ -f "$state" ] || { echo "FAIL $name: no state file at $state"; exit 1; }
jq -e -r '.lastRun | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")' "$state" >/dev/null ||
  { echo "FAIL $name: lastRun is not an ISO time"; exit 1; }
jq -e '(.open | length) > 0' "$state" >/dev/null ||
  { echo "FAIL $name: open set in the state file is empty"; exit 1; }

# a PR merged long ago stands in for one that left the open set between runs
jq '.open += ["google/snappy#257"]' "$state" > "$state.new" ||
  { echo "FAIL $name: cannot edit the state file"; exit 1; }
mv "$state.new" "$state"

out=$(bash "$script" --state "$state")
rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL $name: second run exited $rc"; exit 1; }
echo "$out" | grep -qE '^--- merged or closed since [0-9]{4}-' ||
  { echo "FAIL $name: no since-last-run section"; exit 1; }
echo "$out" | grep -q '^MERGED google/snappy#257 by danilak-G at 2026-09-07' ||
  { echo "FAIL $name: merged PR not reported"; echo "$out" | head -5; exit 1; }
jq -e '.open | index("google/snappy#257") == null' "$state" >/dev/null ||
  { echo "FAIL $name: the merged PR survived in the rewritten state"; exit 1; }

rm -rf "$tmp"
trap - EXIT
echo "PASS $name"
