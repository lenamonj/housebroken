#!/bin/bash
# test-check-ai-policy.sh - read-only check of scripts/check-ai-policy.sh
# against apple/swift-openapi-runtime, whose CONTRIBUTING asks contributors to
# refrain from using AI tools for parts of a pull request.
set -u
name="check-ai-policy.sh"
here=$(cd "$(dirname "$0")" && pwd)
script="$here/../scripts/check-ai-policy.sh"
HOUSEBROKEN_HOME=$(mktemp -d)
export HOUSEBROKEN_HOME
trap 'rm -rf "$HOUSEBROKEN_HOME"' EXIT

fail() { echo "FAIL $name: $1" >&2; exit 1; }

help=$(bash "$script" --help) || fail "--help exited non-zero"
printf '%s' "$help" | grep -q "usage: check-ai-policy.sh" || fail "--help printed no usage line"

out=$(bash "$script" apple/swift-openapi-runtime) || fail "run exited non-zero"
printf '%s\n' "$out" | grep -q "refrain from using AI tools" ||
  fail "the AI tools sentence from CONTRIBUTING was not printed"
printf '%s\n' "$out" | grep -q -- "--- CONTRIBUTING.md ---" || fail "the hit was not attributed to a file"

# --branch overrides the default branch; main is the default here so the
# sentence must still appear, and an unknown branch must find nothing
out=$(bash "$script" --branch main apple/swift-openapi-runtime) || fail "--branch run exited non-zero"
printf '%s\n' "$out" | grep -q "branch: main" || fail "--branch was not reported"
printf '%s\n' "$out" | grep -q "refrain from using AI tools" || fail "--branch main lost the sentence"

echo "PASS $name"
