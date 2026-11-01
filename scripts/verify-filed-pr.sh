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
# Assumes: gh is installed and authenticated with read access to the repo. The
# intended head is the sha passed in, else one branch-check stamped: a head
# neither names was not meant by anyone. Exits non-zero when the head does not
# match, when a read fails, when checks are not green, or when they do not settle
# before the watch gives up.
# Exits 3, and says NOT SETTLED, when nothing is wrong but CI has not run: a
# workflow on the head waits for a maintainer's approval, no check has started,
# or the runs could not be read.
set -u

usage() {
  sed -n '2,/^set -u$/p' "$0" | sed 's/^# \{0,1\}//; /^set -u$/d'
}
# shellcheck source=scripts/common.sh
. "$(cd "$(dirname "$0")" && pwd)/common.sh"

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
unsettled=0
note() { printf '%-26s %s\n' "$1" "$2"; }

# Fails with the read: every $(view ...) below tests that, because an exit inside
# a command substitution only ends the substitution.
view() {
  local field="$1" jqexpr="$2"
  if ! gh pr view "$pr" --repo "$repo" --json "$field" --jq "$jqexpr"; then
    echo "verify-filed-pr.sh: gh pr view $repo#$pr ($field) failed" >&2
    return 1
  fi
}

state=$(view state .state) || exit 1
head=$(view headRefOid .headRefOid) || exit 1
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
view files '.files[] | "   " + .path + "  +" + (.additions|tostring) + "/-" + (.deletions|tostring)' || exit 1

# The intended files are the branch-check stamp's, and the intended body is the
# copy file-pr.sh kept; GitHub's versions are compared to both.
home="${HOUSEBROKEN_HOME:-$HOME/.housebroken}"
stamp="$home/branch-checks/$head"
intended=""
[ -f "$stamp" ] && intended=$(sed -n 's/^file: //p' "$stamp" | tr -d '\r' | sort)
if [ -n "$intended" ]; then
  filed=$(view files '.files[].path') || exit 1
  filed=$(printf '%s\n' "$filed" | sort)
  if [ "$intended" = "$filed" ]; then
    note "files match the stamp" "yes"
  else
    note "FILES DIFFER FROM STAMP" "$(diff <(printf '%s\n' "$intended") <(printf '%s\n' "$filed") | grep '^[<>]' | tr '\n' ' ')"
    fail=1
  fi
elif [ -n "$want" ]; then
  note "files" "no branch-check stamp listing files for ${head:0:12}; not compared"
else
  note "HEAD NOT INTENDED" "no branch-check stamp for ${head:0:12} and no sha passed, so nothing says this head was meant"
  fail=1
fi
body=$(view body .body) || exit 1
kept="$home/filed/${repo%%/*}-${repo##*/}-$head.md"
if [ -f "$kept" ]; then
  norm() { tr -d '\r' | sed -e 's/[[:space:]]*$//' | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}'; }
  if [ "$(printf '%s\n' "$body" | norm)" = "$(norm < "$kept")" ]; then
    note "body matches what was filed" "yes"
  else
    note "BODY DIFFERS" "from $kept; read the diff, a maintainer may have edited it"
    diff <(norm < "$kept") <(printf '%s\n' "$body" | norm) | head -20 | clean_lines | sed 's/^/    /'
  fi
else
  note "body" "no filed copy for ${head:0:12}; not compared"
fi

echo ""
echo "-- checks (waits until every check has settled)"
gh pr checks "$pr" --repo "$repo" --watch --interval 20 >/dev/null 2>&1 || true
rollup=$(view statusCheckRollup "$ci_jq"'[.statusCheckRollup[] | check_state] | group_by(.) | map({k:.[0], n:length}) | .[] | .k + "=" + (.n|tostring)') || exit 1
ci=$(view statusCheckRollup "$ci_jq"'[.statusCheckRollup[] | ci] | if any(. == "red") then "red" elif any(. == "running") then "running" else "green" end') || exit 1
if [ -z "$rollup" ]; then
  # Straight after filing a fork's checks may not exist yet, and that is not green.
  if [ "$(gh api "repos/$repo/actions/workflows" --jq .total_count 2>/dev/null)" = "0" ]; then
    note "checks" "none, and the repository has no workflows"
  else
    note "CHECKS NOT STARTED" "nothing has reported on this head yet"
    unsettled=1
  fi
else
  echo "$rollup" | awk '{print "   " $0}'
  case "$ci" in
    red) note "CHECKS NOT GREEN" "read the logs"; fail=1 ;;
    running) note "CHECKS DID NOT SETTLE" "watch timed out"; fail=1 ;;
  esac
fi
# A fork's workflow that waits for a maintainer's approval has run nothing and
# is absent from the rollup above.
if ! waiting=$(gh run list --repo "$repo" --commit "$head" --json conclusion --jq '[.[] | select(.conclusion == "action_required")] | length' 2>/dev/null); then
  note "WORKFLOW RUNS UNREAD" "whether any waits for approval is unknown"
  waiting=0
  unsettled=1
fi
if [ "${waiting:-0}" -gt 0 ]; then
  note "WORKFLOWS AWAIT APPROVAL" "$waiting run(s) on this head have not started"
  unsettled=1
fi

echo ""
echo "-- rendered body, first 15 lines"
printf '%s\n' "$body" | head -15 | fence "the body on GitHub" "   "

echo ""
echo "-- comments, newest last"
comments=$(view comments '.comments[] | .author.login + ": " + (.body | gsub("\n"; " ") | .[0:150])') || exit 1
[ -z "$comments" ] || printf '%s\n' "$comments" | fence "these commenters" "   "

echo ""
if [ "$fail" -ne 0 ]; then echo "PR-VERIFY: PROBLEMS ABOVE"
elif [ "${waiting:-0}" -gt 0 ]; then echo "PR-VERIFY: NOT SETTLED ($waiting workflow run(s) wait for a maintainer to approve them; nothing settles until one does, so move on)"
elif [ "$unsettled" -ne 0 ]; then echo "PR-VERIFY: NOT SETTLED (CI has not run on this head, or its runs could not be read)"
else echo "PR-VERIFY: OK"; fi
[ "$fail" -eq 0 ] && [ "$unsettled" -ne 0 ] && exit 3
exit "$fail"
