#!/bin/bash
# verify-filed-pr.sh - prove a filed PR actually landed as intended.
#
#   bash verify-filed-pr.sh owner/repo PR_NUMBER [expected-head-sha]
#
# Filing is not the end of the job. This re-derives, from GitHub rather than
# from local memory, that: the PR head is the commit meant to be there, the
# diff contains exactly the intended files, CI settled green, and the rendered
# body and comments are what was written. Written 2026-09-01 after console
# PR #296 went red on CI and the maintainer saw it before the author did.
set -u
repo="${1:?usage: verify-filed-pr.sh owner/repo PR [sha]}"
pr="${2:?usage: verify-filed-pr.sh owner/repo PR [sha]}"
want="${3:-}"
fail=0
note() { printf '%-26s %s\n' "$1" "$2"; }

state=$(gh pr view "$pr" --repo "$repo" --json state --jq .state)
head=$(gh pr view "$pr" --repo "$repo" --json headRefOid --jq .headRefOid)
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
gh pr view "$pr" --repo "$repo" --json files --jq '.files[] | "   " + .path + "  +" + (.additions|tostring) + "/-" + (.deletions|tostring)'

echo ""
echo "-- checks (waits until every check has settled; 2026-09-02, Valinor #838
#    was left at 'still running' and its mutation job failed unseen)"
gh pr checks "$pr" --repo "$repo" --watch --interval 20 >/dev/null 2>&1
rollup=$(gh pr view "$pr" --repo "$repo" --json statusCheckRollup \
  --jq '[.statusCheckRollup[] | (.conclusion // .status)] | group_by(.) | map({k:.[0], n:length}) | .[] | .k + "=" + (.n|tostring)')
if [ -z "$rollup" ]; then
  note "checks" "none reported"
else
  echo "$rollup" | sed 's/^/   /'
  case "$rollup" in
    *FAILURE*|*TIMED_OUT*|*CANCELLED*|*ACTION_REQUIRED*) note "CHECKS NOT GREEN" "read the logs"; fail=1 ;;
    *IN_PROGRESS*|*QUEUED*|*PENDING*) note "CHECKS DID NOT SETTLE" "watch timed out"; fail=1 ;;
  esac
fi

echo ""
echo "-- rendered body, first 15 lines"
gh pr view "$pr" --repo "$repo" --json body --jq .body | head -15 | sed 's/^/   /'

echo ""
echo "-- comments, newest last"
gh pr view "$pr" --repo "$repo" --json comments \
  --jq '.comments[] | "   " + .author.login + ": " + (.body | gsub("\n"; " ") | .[0:150])'

echo ""
[ "$fail" -eq 0 ] && echo "PR-VERIFY: OK" || echo "PR-VERIFY: PROBLEMS ABOVE"
exit "$fail"
