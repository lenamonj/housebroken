#!/bin/bash
# test-check-ai-policy.sh - read-only check of scripts/check-ai-policy.sh: a
# repository whose CONTRIBUTING asks contributors to refrain from AI tools
# reads as BAN with exit 4, one whose AGENTS.md says AI use MUST be disclosed
# reads as DISCLOSE with exit 3, the policy file is found by its own tree
# listing, and --out writes the printout file-pr.sh reads.
set -u
name="check-ai-policy.sh"
here=$(cd "$(dirname "$0")" && pwd)
script="$here/../scripts/check-ai-policy.sh"
HOUSEBROKEN_HOME=$(mktemp -d)
export HOUSEBROKEN_HOME
trap 'rm -rf "$HOUSEBROKEN_HOME"' EXIT

fail() { echo "FAIL $name: $1" >&2; exit 1; }

help=$(bash "$script" --help) || fail "--help exited non-zero"
printf '%s' "$help" | grep -q "Usage:" || fail "--help printed no usage line"

out=$(bash "$script" apple/swift-openapi-runtime); rc=$?
[ "$rc" -eq 4 ] || fail "a repository that bans AI tools exited $rc, expected 4"
printf '%s\n' "$out" | grep -q "refrain from using AI tools" || fail "the AI tools sentence from CONTRIBUTING was not printed"
printf '%s\n' "$out" | grep -q -- "--- CONTRIBUTING.md ---" || fail "the hit was not attributed to a file"
printf '%s\n' "$out" | grep -q "^RESULT: BAN" || fail "the reading was not BAN"

out=$(bash "$script" --branch main --out apple/swift-openapi-runtime); rc=$?
[ "$rc" -eq 4 ] || fail "--branch --out run exited $rc, expected 4"
printf '%s\n' "$out" | grep -q "branch: main" || fail "--branch was not reported"
saved="$HOUSEBROKEN_HOME/policy/policy-apple-swift-openapi-runtime.md"
[ -f "$saved" ] || fail "--out wrote no printout at $saved"
grep -q "^RESULT: BAN" "$saved" || fail "the saved printout has no BAN result"

out=$(bash "$script" google/benchmark); rc=$?
[ "$rc" -eq 3 ] || fail "a repository that requires disclosure exited $rc, expected 3"
printf '%s\n' "$out" | grep -q -- "--- AGENTS.md ---" || fail "AGENTS.md was not read"
printf '%s\n' "$out" | grep -q "^RESULT: DISCLOSE" || fail "the reading was not DISCLOSE"

echo "PASS $name"
