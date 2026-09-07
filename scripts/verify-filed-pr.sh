#!/bin/bash
# verify-filed-pr.sh - prove a filed PR actually landed as intended.
#
# Filing is not the end of the job. This re-derives, from GitHub rather than
# from local memory, that: the PR head is the commit meant to be there, the
# diff contains exactly the intended files, CI settled green, and the rendered
# body and comments are what was written. Written 2026-09-01 after console
# PR #296 went red on CI and the maintainer saw it before the author did.
# The check wait was added 2026-09-02, when Valinor #838 was left at "still
# running" and its mutation job failed unseen.
#
# Usage:
#   bash verify-filed-pr.sh owner/repo PR_NUMBER [expected-head-sha]
#   bash verify-filed-pr.sh --help
#
# Environment:
#   none
#
# Assumes: gh is installed and authenticated with read access to the repo, and
# that the caller knows which head sha and which files were intended. Exits
# non-zero when the head does not match, when checks are red, or when they do
# not settle before the watch gives up.
set -u

usage() {
  sed -n '2,/^set -u$/p' "$0" | sed 's/^# \{0,1\}//; /^set -u$/d'
}

case "${1:-}" in
  --help|-h) usage; exit 0 ;;
esac

if [ "$#" -lt 2 ]; then
  echo "usage: verify-filed-pr.sh owner/repo PR [sha]" >&2
  exit 2
fi
repo="$1"
pr="$2"
want="${3:-}"
fail=0
note() { printf '%-26s %s\n' "$1" "$2"; }

view() {
  local field="$1" jqexpr="$2"
  if ! gh pr view "$pr" --repo "$repo" --json "$field" --jq "$jqexpr"; then
    echo "verify-filed-pr.sh: gh pr view $repo#$pr ($field) failed" >&2
    exit 1
  fi
}

state=$(view state .state)
head=$(view headRefOid .headRefOid)
note "state" "$state"
note "head" "${head:0:12}"
if [ -n "$want" ]; then
  case "$head" in
    "$want"*) note "head matches expected" "yes" ;;
    *) note "HEAD MISMATCH" "expected $want"; fail=1 ;;
  esac
fi

echo ""
echo "-- files in the PR (what a reviewer sees)"
view files '.files[] | "   " + .path + "  +" + (.additions|tostring) + "/-" + (.deletions|tostring)'

echo ""
echo "-- checks (waits until every check has settled)"
gh pr checks "$pr" --repo "$repo" --watch --interval 20 >/dev/null 2>&1 || true
rollup=$(view statusCheckRollup '[.statusCheckRollup[] | (.conclusion // .status)] | group_by(.) | map({k:.[0], n:length}) | .[] | .k + "=" + (.n|tostring)')
if [ -z "$rollup" ]; then
  note "checks" "none reported"
else
  echo "$rollup" | awk '{print "   " $0}'
  case "$rollup" in
    *FAILURE*|*TIMED_OUT*|*CANCELLED*|*ACTION_REQUIRED*) note "CHECKS NOT GREEN" "read the logs"; fail=1 ;;
    *IN_PROGRESS*|*QUEUED*|*PENDING*) note "CHECKS DID NOT SETTLE" "watch timed out"; fail=1 ;;
  esac
fi

echo ""
echo "-- rendered body, first 15 lines"
view body .body | head -15 | sed 's/^/   /'

echo ""
echo "-- comments, newest last"
view comments '.comments[] | "   " + .author.login + ": " + (.body | gsub("\n"; " ") | .[0:150])'

echo ""
if [ "$fail" -eq 0 ]; then echo "PR-VERIFY: OK"; else echo "PR-VERIFY: PROBLEMS ABOVE"; fi
exit "$fail"
