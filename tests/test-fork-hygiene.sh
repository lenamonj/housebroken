#!/bin/bash
# test-fork-hygiene.sh - --dry-run names candidate branches and deletes nothing.
# Runs against a public account with live fork branches on closed PRs, because
# the operator's own account is already clean. Read-only: no branch is deleted,
# and a second gh call proves the first candidate still exists afterwards.
set -u
name=test-fork-hygiene
script="$(cd "$(dirname "$0")/../scripts" && pwd)/fork-hygiene.sh"
user="${TEST_FORK_USER:-AkariH}"

bash "$script" --help | grep -q "Usage:" || { echo "FAIL $name: --help has no usage"; exit 1; }
bash "$script" --nonsense 2>/dev/null && { echo "FAIL $name: bad argument exited 0"; exit 1; }
grep -qi 'lenamonj' "$script" && { echo "FAIL $name: literal username still present"; exit 1; }
grep -q '/tmp/' "$script" && { echo "FAIL $name: hardcoded temp path still present"; exit 1; }

out=$(HOUSEBROKEN_USER="$user" bash "$script" --dry-run)
echo "$out" | grep '^would delete' | head -5
echo "$out" | tail -2

echo "$out" | grep -q '^would delete ' || { echo "FAIL $name: no candidate branches printed"; exit 1; }
echo "$out" | grep -q '^deleted ' && { echo "FAIL $name: dry run reported a deletion"; exit 1; }
echo "$out" | grep -q 'forks with no PR' || { echo "FAIL $name: orphan fork section missing"; exit 1; }

first=$(echo "$out" | grep -m1 '^would delete ')
repo=$(echo "$first" | awk '{print $3}')
branch=$(echo "$first" | awk '{print $4}')
if ! gh api "repos/$repo/git/refs/heads/$branch" --jq .ref > /dev/null; then
  echo "FAIL $name: candidate branch $repo $branch is gone after the dry run"
  exit 1
fi
echo "still present after dry run: $(gh api "repos/$repo/git/refs/heads/$branch" --jq .ref) in $repo"
echo "PASS $name"
