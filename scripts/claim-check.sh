#!/bin/bash
# claim-check.sh - lists every claim in outbound text that a maintainer can
# falsify, so each one gets re-derived before it is sent.
#
# On microsoft/GSL #1272 a reply draft said "The five new static_asserts fail on
# main." A reviewer falsified it in one pass. The number had come from a red arm
# that grepped only for `static assertion failed`, so it counted five matches
# and never saw the twenty-one other errors beside them; and against the commit
# a maintainer would actually revert to, only four of the five fail. The
# sentence named a basis and was still wrong about it.
#
# So this does not try to judge a claim. Text checks cannot: the bad sentence
# named its revision and read perfectly. It lists them, and the rule in step 6
# is that every listed line is re-measured, at the moment of writing, against
# the exact revision the sentence names. The gap this closes is that until now
# every gate here read code and nothing read the prose, while the prose is what
# the maintainer reads first.
#
# Usage:
#   bash claim-check.sh FILE
#   bash claim-check.sh --help
#
# Exits 1 when it finds claims to re-derive, 0 when it finds none, 2 on a usage
# error. Exit 1 is not a refusal to send; it is a refusal to send unread.
set -u

usage() { awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"; }

case "${1:-}" in
  --help|-h) usage; exit 0 ;;
  "") echo "REFUSED: name the file holding the text" >&2; exit 2 ;;
esac
file="$1"
[ -f "$file" ] || { echo "REFUSED: $file does not exist" >&2; exit 2; }

# Strip fenced code and quoted logs: a number inside pasted output is evidence,
# not a claim being made.
body=$(awk '/^```/ {fence = !fence; next} !fence && !/^ *[|>]/ {print NR": "$0}' "$file")

quantified=$(printf '%s
' "$body" | grep -nEi '[0-9]+ *(of|/) *[0-9]+|\b([0-9]+|one|two|three|four|five|six|seven|eight|nine|ten|no) +([a-z_-]+ +){0,3}(tests?|assertions?|static_asserts?|checks?|errors?|failures?|jobs?|files?|warnings?|projects?|commits?|suites?)\b' | cut -d: -f2-)

absolute=$(printf '%s\n' "$body" | grep -nEi \
  '\b(only|exactly|always|never|every|all|none|nothing|everything|guaranteed|any)\b' \
  | cut -d: -f2-)

found=0
if [ -n "$quantified" ]; then
  found=1
  echo "COUNTED: re-derive each, against the revision the sentence names, now:"
  printf '%s\n' "$quantified" | sed 's/^/    /'
fi
if [ -n "$absolute" ]; then
  found=1
  echo "ABSOLUTE: falsify each against the code, not against your memory of it:"
  printf '%s\n' "$absolute" | sed 's/^/    /'
fi

if [ "$found" -eq 0 ]; then
  echo "claim-check: no falsifiable claim found in $file"
  exit 0
fi
echo
echo "claim-check: $file makes claims a maintainer can check. Re-measure each"
echo "one before sending. A sentence that names its revision can still be wrong"
echo "about it; that is the failure this exists for."
exit 1
