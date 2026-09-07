#!/bin/bash
# test-pr-sweep.sh - --all lists at least one open PR for the authenticated
# user and exits 0. Read-only.
set -u
name=test-pr-sweep
script="$(cd "$(dirname "$0")/../scripts" && pwd)/pr-sweep.sh"

bash "$script" --help | grep -q "Usage:" || { echo "FAIL $name: --help has no usage"; exit 1; }
bash "$script" --nonsense 2>/dev/null && { echo "FAIL $name: bad argument exited 0"; exit 1; }
grep -q 'HOUSEBROKEN_USER' "$script" || { echo "FAIL $name: no HOUSEBROKEN_USER"; exit 1; }
grep -qi 'lenamonj' "$script" && { echo "FAIL $name: literal username still present"; exit 1; }

out=$(bash "$script" --all)
rc=$?
echo "$out" | head -20
[ "$rc" -eq 0 ] || { echo "FAIL $name: --all exited $rc"; exit 1; }
echo "$out" | grep -qE '^(ok|ACT) ' || { echo "FAIL $name: no PR rows"; exit 1; }
open=$(echo "$out" | sed -n 's/^open PRs: \([0-9]*\);.*/\1/p')
if [ -z "$open" ] || [ "$open" -lt 1 ]; then echo "FAIL $name: open PR count is $open"; exit 1; fi
echo "PASS $name"
