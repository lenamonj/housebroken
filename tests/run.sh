#!/bin/bash
# run.sh - every test, one at a time, in a throwaway HOME, behind a gh that
# refuses whatever it was not scripted for. Prints one line per test and the
# totals, the output of each failure, and exits non-zero on any failure, so a
# skip is counted and never reads as a pass.
#
# Usage:
#   bash tests/run.sh               # every test
#   bash tests/run.sh proof reply   # the tests with those words in their names
set -u

here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d) || exit 1
trap 'rm -rf "$work"' EXIT
pass=0; fail=0; skip=0; failed=""

for t in "$here"/test-*.sh; do
  n=$(basename "$t" .sh)
  if [ "$#" -gt 0 ]; then
    hit=0
    for want in "$@"; do case "$n" in *"$want"*) hit=1 ;; esac; done
    [ "$hit" -eq 1 ] || continue
  fi
  mkdir -p "$work/$n"
  start=$(date +%s)
  out=$(HOME="$work/$n" HOUSEBROKEN_HOME="$work/$n/.housebroken" PATH="$here/stubs:$PATH" bash "$t" 2>&1); rc=$?
  took=$(( $(date +%s) - start ))
  if [ "$rc" -ne 0 ]; then
    fail=$((fail + 1)); failed="$failed $n"
    printf 'FAIL %-28s %3ss\n' "$n" "$took"
    printf '%s\n' "$out" | tail -15 | sed 's/^/     /'
  elif printf '%s\n' "$out" | grep -q '^SKIP '; then
    skip=$((skip + 1))
    printf 'SKIP %-28s %3ss  %s\n' "$n" "$took" "$(printf '%s\n' "$out" | grep -m1 '^SKIP ' | cut -c1-70)"
  else
    pass=$((pass + 1))
    printf 'PASS %-28s %3ss\n' "$n" "$took"
  fi
done

echo
echo "$pass passed, $fail failed, $skip skipped"
[ "$fail" -eq 0 ] && [ "$pass" -gt 0 ]
