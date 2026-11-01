#!/bin/bash
# test-check-ai-policy.sh - scripts/check-ai-policy.sh over a stub repository: a
# CONTRIBUTING that asks contributors to refrain from AI tools reads as BAN with
# exit 4, an AGENTS.md saying AI use must be disclosed reads as DISCLOSE with
# exit 3, the policy file is found by its own tree listing, and --out writes the
# printout file-pr.sh reads.
set -u
name="check-ai-policy.sh"
here=$(cd "$(dirname "$0")" && pwd)
script="$here/../scripts/check-ai-policy.sh"
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
export HOUSEBROKEN_HOME="$root/home" STUB_DIR="$root"
mkdir -p "$root/bin" "$root/files"
cp "$here/stubs/policy-gh" "$root/bin/gh"
chmod +x "$root/bin/gh"
export PATH="$root/bin:$PATH"

fail() { echo "FAIL $name: $1" >&2; exit 1; }

help=$(bash "$script" --help) || fail "--help exited non-zero"
printf '%s' "$help" | grep -q "Usage:" || fail "--help printed no usage line"

printf 'CONTRIBUTING.md\n' > "$root/tree.txt"
printf 'Please refrain from using AI tools to write your contribution.\n' > "$root/files/CONTRIBUTING.md"
out=$(bash "$script" o/r); rc=$?
[ "$rc" -eq 4 ] || fail "a repository that bans AI tools exited $rc, expected 4"
printf '%s\n' "$out" | grep -q "refrain from using AI tools" || fail "the AI tools sentence from CONTRIBUTING was not printed"
printf '%s\n' "$out" | grep -q -- "--- CONTRIBUTING.md ---" || fail "the hit was not attributed to a file"
printf '%s\n' "$out" | grep -q "^RESULT: BAN" || fail "the reading was not BAN"

out=$(bash "$script" --branch main --out o/r); rc=$?
[ "$rc" -eq 4 ] || fail "--branch --out run exited $rc, expected 4"
printf '%s\n' "$out" | grep -q "branch: main" || fail "--branch was not reported"
saved="$HOUSEBROKEN_HOME/policy/policy-o-r.md"
[ -f "$saved" ] || fail "--out wrote no printout at $saved"
grep -q "^RESULT: BAN" "$saved" || fail "the saved printout has no BAN result"

printf 'AGENTS.md\n' > "$root/tree.txt"
printf 'AI use must be disclosed in the pull request description.\n' > "$root/files/AGENTS.md"
out=$(bash "$script" o/r); rc=$?
[ "$rc" -eq 3 ] || fail "a repository that requires disclosure exited $rc, expected 3"
printf '%s\n' "$out" | grep -q -- "--- AGENTS.md ---" || fail "AGENTS.md was not read"
printf '%s\n' "$out" | grep -q "^RESULT: DISCLOSE" || fail "the reading was not DISCLOSE"

echo "PASS $name"
