#!/bin/bash
# test-verify-filed-pr.sh - the verifier runs to completion on a merged public
# PR (spf13/pflag #507) and reports the head sha and the files. Read-only.
set -u
name=test-verify-filed-pr
script="$(cd "$(dirname "$0")/../scripts" && pwd)/verify-filed-pr.sh"

bash "$script" --help | grep -q "Usage:" || { echo "FAIL $name: --help has no usage"; exit 1; }
bash "$script" 2>/dev/null && { echo "FAIL $name: missing arguments exited 0"; exit 1; }

out=$(bash "$script" spf13/pflag 507)
echo "$out"
echo "$out" | grep -q "^state  *MERGED" || { echo "FAIL $name: state not reported"; exit 1; }
echo "$out" | grep -qE "^head  *[0-9a-f]{12}" || { echo "FAIL $name: head sha not reported"; exit 1; }
echo "$out" | grep -q "files in the PR" || { echo "FAIL $name: no files section"; exit 1; }
echo "$out" | grep -qE "^   .+  \+[0-9]+/-[0-9]+" || { echo "FAIL $name: no file rows"; exit 1; }
echo "$out" | grep -q "^PR-VERIFY:" || { echo "FAIL $name: no verdict line"; exit 1; }
echo "PASS $name"
