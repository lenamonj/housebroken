#!/bin/bash
# test-inbox.sh - --help has usage, a bad argument exits non-zero, no literal
# username, a run with --no-ci against a fresh HOUSEBROKEN_HOME exits 0, prints
# the header and writes the ledger, and --ack writes the cursor. Read-only on
# GitHub; the real workshop is never touched.
set -u
name=test-inbox
script="$(cd "$(dirname "$0")/../scripts" && pwd)/inbox.sh"

bash "$script" --help | grep -q "Usage:" || { echo "FAIL $name: --help has no usage"; exit 1; }
bash "$script" --nonsense 2>/dev/null && { echo "FAIL $name: bad argument exited 0"; exit 1; }
grep -q 'HOUSEBROKEN_USER' "$script" || { echo "FAIL $name: no HOUSEBROKEN_USER"; exit 1; }
grep -qi 'lenamonj' "$script" && { echo "FAIL $name: literal username still present"; exit 1; }

tmp=$(mktemp -d) || { echo "FAIL $name: mktemp failed"; exit 1; }
trap 'rm -rf "$tmp"' EXIT
since="$(date -u -d '2 hours ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-2H +%Y-%m-%dT%H:%M:%SZ)"
out=$(HOUSEBROKEN_HOME="$tmp" bash "$script" --since "$since" --no-ci)
rc=$?
echo "$out" | head -12
[ "$rc" -eq 0 ] || { echo "FAIL $name: run exited $rc"; exit 1; }
echo "$out" | grep -q "^== inbox for " || { echo "FAIL $name: no header"; exit 1; }
echo "$out" | grep -qE "human item\(s\) since" || { echo "FAIL $name: no closing line"; exit 1; }
[ -s "$tmp/inbox-ledger.md" ] || { echo "FAIL $name: ledger not written"; exit 1; }
HOUSEBROKEN_HOME="$tmp" bash "$script" --ack | grep -q "inbox cursor is now" || { echo "FAIL $name: --ack"; exit 1; }
[ -s "$tmp/inbox-cursor" ] || { echo "FAIL $name: cursor not written"; exit 1; }
echo "PASS $name"
