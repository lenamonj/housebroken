#!/bin/bash
# test-claim-check.sh - the historical sentence flags, claim-free text does not,
# and pasted evidence inside a fence is not mistaken for a claim. Each case is
# paired with its sabotage so none of them rests on another's condition.
set -u
name=test-claim-check
script="$(cd "$(dirname "$0")/../scripts" && pwd)/claim-check.sh"
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT

bash "$script" --help | grep -q "Usage:" || { echo "FAIL $name: --help has no usage"; exit 1; }
bash "$script" >/dev/null 2>&1; [ "$?" = "2" ] || { echo "FAIL $name: no argument did not exit 2"; exit 1; }
bash "$script" "$tmp/nope.md" >/dev/null 2>&1; [ "$?" = "2" ] || { echo "FAIL $name: missing file did not exit 2"; exit 1; }

# The sentence this script exists for. It reads perfectly and names a revision.
printf 'The five new static_asserts fail on main.\n' > "$tmp/history.md"
out=$(bash "$script" "$tmp/history.md"); rc=$?
[ "$rc" = "1" ] || { echo "FAIL $name: the historical sentence did not flag"; echo "$out"; exit 1; }
printf '%s\n' "$out" | grep -q "COUNTED" || { echo "FAIL $name: not reported as a counted claim"; exit 1; }

# Sabotage: drop the count and the same sentence must go quiet.
printf 'The new static_asserts fail on main.\n' > "$tmp/nocount.md"
out=$(bash "$script" "$tmp/nocount.md"); rc=$?
[ "$rc" = "0" ] || { echo "FAIL $name: flagged a sentence with no count or absolute"; echo "$out"; exit 1; }

# Digits with words in between, which is how the historical one slipped a first draft.
for s in "15 of 15 tests passed" "4 tests failed" "two remaining checks are red" "no tests failed"; do
  printf '%s\n' "$s" > "$tmp/q.md"
  bash "$script" "$tmp/q.md" >/dev/null 2>&1
  [ "$?" = "1" ] || { echo "FAIL $name: missed a counted claim: $s"; exit 1; }
done

# Absolutes.
printf 'It removes only the files it generated.\n' > "$tmp/abs.md"
out=$(bash "$script" "$tmp/abs.md"); rc=$?
[ "$rc" = "1" ] || { echo "FAIL $name: absolute claim did not flag"; exit 1; }
printf '%s\n' "$out" | grep -q "ABSOLUTE" || { echo "FAIL $name: not reported as an absolute"; exit 1; }

# Pasted evidence is not a claim: inside a fence it is quiet, outside it is not.
printf 'Result below.\n\n```\n15 of 15 tests passed\n```\n' > "$tmp/fenced.md"
bash "$script" "$tmp/fenced.md" >/dev/null 2>&1
[ "$?" = "0" ] || { echo "FAIL $name: counted a number inside a code fence"; exit 1; }
printf 'Result below.\n\n15 of 15 tests passed\n' > "$tmp/unfenced.md"
bash "$script" "$tmp/unfenced.md" >/dev/null 2>&1
[ "$?" = "1" ] || { echo "FAIL $name: fence exemption is not resting on the fence"; exit 1; }

echo "PASS $name"
