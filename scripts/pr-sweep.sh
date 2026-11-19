#!/bin/bash
# pr-sweep.sh - every open upstream PR of ours, and which ones need us to act.
#
# Every maintainer comment gets a same-day answer; without a sweep the answer
# depends on remembering which PR was touched. Ball in our court means any of:
# the newest comment or review is not ours (bots excluded), a review requests
# changes, CI has a failing check, the PR is CONFLICTING (needs a rebase), or
# no CI job ever started on the head in a repository that runs them (GitHub made
# no run, or the run it made finished without one), or a stale bot's notice
# stands, printed with the day it closes. A new push or a close and reopen can
# start a new run, which may again wait for approval; a workflow filtered off the
# change makes none, and reads the same. A check list or a notice that could
# not be read is printed as ci-unread or stale:unread, never as clean.
# Read-only; acting is the operator's.
#
# A merge or a close drops a PR out of the open list without a word, so each
# run writes its open set to a state file and the next run reports what left
# it. A PR that left still owns a branch on our fork until someone deletes it,
# so the sweep records that branch in the state file and prints a TIDY line on
# every run until `housebroken hygiene` has removed it. A branch that has moved
# past the head its pull request held was used again for other work: hygiene
# keeps it, so the sweep prints one KEPT line and stops asking. The obligation
# is in the output, not in anyone's memory.
#
# A gate reads a pull request when it is pushed, so one filed before a review
# item existed is never read under it, however long it stays open. A run
# counts the open pull requests, outside repositories under your own login,
# whose head this machine holds no review report for, holds one written under
# an earlier brief, or holds one it cannot read; it prints the count when
# there is any, and --all prints a READ line for each. A pull request leaves
# the count once its head has a report under the current brief. It is not
# counted as an action and changes no exit status: the reports are local, so a
# head reviewed on another machine reads the same as one never reviewed.
#
# Usage:
#   bash pr-sweep.sh                  # only PRs where the ball is in our court
#   bash pr-sweep.sh --all            # every open PR with its state
#   bash pr-sweep.sh --state <path>   # a state file other than the default
#   bash pr-sweep.sh --help
#
# Environment:
#   HOUSEBROKEN_USER  GitHub login to sweep, default the authenticated user
#   HOUSEBROKEN_HOME  workshop root, default $HOME/.housebroken. The state file
#                     is $HOUSEBROKEN_HOME/sweep-state.json unless --state
#                     says otherwise.
#
# Assumes: gh is installed and authenticated, and that the PRs of interest are
# the ones authored by that login. Exits non-zero when gh fails, a pull request
# could not be read, or the search returned part of the list (SWEEP
# INCOMPLETE); no open pull requests left is a result, not a failure.
set -u
set -o pipefail

usage() {
  sed -n '2,/^set -u$/p' "$0" | sed 's/^# \{0,1\}//; /^set -u$/d'
}
# shellcheck source=scripts/common.sh
. "$(cd "$(dirname "$0")" && pwd)/common.sh"
MAX=1000

ALL=0
STATE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --all) ALL=1 ;;
    --state)
      shift
      [ $# -gt 0 ] || { echo "pr-sweep.sh: --state needs a path" >&2; exit 2; }
      STATE="$1"
      ;;
    *) echo "pr-sweep.sh: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if [ -z "$STATE" ]; then
  STATE="${HOUSEBROKEN_HOME:-$HOME/.housebroken}/sweep-state.json"
fi
if ! mkdir -p "$(dirname "$STATE")"; then
  echo "pr-sweep.sh: cannot create the directory of $STATE" >&2
  exit 1
fi

ME="${HOUSEBROKEN_USER:-$(gh api user --jq .login)}"
if [ -z "$ME" ]; then
  echo "pr-sweep.sh: cannot determine the GitHub login; set HOUSEBROKEN_USER" >&2
  exit 1
fi

if ! list="$(gh search prs --author "$ME" --state open --limit "$MAX" --json repository,number,title,updatedAt \
  --jq '.[] | [.repository.nameWithOwner, (.number | tostring), .updatedAt, .title] | @tsv' | sort)"; then
  echo "pr-sweep.sh: gh search prs failed for author $ME" >&2
  exit 1
fi
rows="$(printf '%s\n' "$list" | grep -c .)"
[ "$rows" -lt "$MAX" ] || echo "SWEEP INCOMPLETE: the search stopped at $MAX open pull requests"
# GitHub search returns a short page when it is throttled, and a sweep of part
# of the list reads exactly like a clean one, so the rows are held to the count
# the API reports.
incomplete=0
claimed="$(gh api "search/issues?q=is:pr+author:$ME+is:open&per_page=1" --jq .total_count 2>/dev/null | tr -d '\r')"
case "$claimed" in
  ''|*[!0-9]*) echo "SWEEP INCOMPLETE: could not read the open pull request count, so the search may have returned part of the list"; incomplete=1 ;;
  *) if [ "$rows" -lt "$claimed" ]; then
       echo "SWEEP INCOMPLETE: the search returned $rows of $claimed open pull requests; run it again when the search rate limit recovers"
       incomplete=1
     fi ;;
esac

open_ids="$(printf '%s\n' "$list" | tr -d '\r' | awk -F'\t' 'NF > 1 { print $1 "#" $2 }' | sort)"
retry=""
unreadable=0
if [ -f "$STATE" ]; then
  # jq on Windows writes CRLF; a stray CR would make every stored id look new
  if ! last="$(jq -r '.lastRun // "an unknown time"' "$STATE" | tr -d '\r')"; then
    echo "pr-sweep.sh: cannot read $STATE" >&2
    exit 1
  fi
  echo "--- merged or closed since $last"
  tidy="$(jq -r '.tidy[]?' "$STATE" | tr -d '\r')"
  gone="$(comm -23 <(jq -r '.open[]?' "$STATE" | tr -d '\r' | sort) <(printf '%s\n' "$open_ids"))"
  # A PR filed and merged between two runs was never in the stored open set.
  if printf '%s' "$last" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T'; then
    if ! closed="$(gh search prs --author "$ME" --state closed --closed ">=$last" --limit "$MAX" --json repository,number \
      --jq '.[] | "\(.repository.nameWithOwner)#\(.number)"')"; then
      echo "pr-sweep.sh: gh search prs failed for PRs of $ME closed since $last" >&2
      exit 1
    fi
    gone="$(printf '%s\n%s\n' "$gone" "$closed" | tr -d '\r' | awk 'NF && !seen[$0]++')"
  fi
  while read -r id; do
    [ -n "$id" ] || continue
    gone_repo="${id%#*}"; gone_num="${id##*#}"
    # A pull request we could not read stays in the stored set, so the next run
    # reports it: the search below only looks forward from this run.
    if ! v="$(gh pr view "$gone_num" --repo "$gone_repo" --json state,url,mergedAt,closedAt,mergedBy,headRefName,headRefOid,headRepository,headRepositoryOwner)"; then
      echo "pr-sweep.sh: gh pr view $id failed; it is read again next run" >&2
      retry="$retry
$id"
      unreadable=$((unreadable + 1))
      continue
    fi
    head_owner="$(printf '%s' "$v" | jq -r '.headRepositoryOwner.login // "-"' | tr -d '\r')"
    head_fork="$(printf '%s' "$v" | jq -r '.headRepository.name // "-"' | tr -d '\r')"
    head_branch="$(printf '%s' "$v" | jq -r '.headRefName // "-"' | tr -d '\r')"
    head_oid="$(printf '%s' "$v" | jq -r '.headRefOid // "-"' | tr -d '\r')"
    gone_state="$(printf '%s' "$v" | jq -r '.state // "-"' | tr -d '\r')"
    if [ "$gone_state" != OPEN ] && [ "$head_owner" = "$ME" ] && [ "$gone_repo" != "$ME/$head_fork" ] && [ "$head_branch" != "-" ]; then
      tidy="$(printf '%s\n%s\n' "$tidy" "$ME/$head_fork $head_branch $id $head_oid")"
    fi
    case "$gone_state" in
      MERGED)
        printf 'MERGED %s by %s at %s\n' "$id" \
          "$(printf '%s' "$v" | jq -r '.mergedBy.login // "-"' | tr -d '\r')" \
          "$(printf '%s' "$v" | jq -r '.mergedAt // "-"' | tr -d '\r')"
        ;;
      CLOSED)
        printf 'CLOSED %s at %s\n' "$id" \
          "$(printf '%s' "$v" | jq -r '.closedAt // "-"' | tr -d '\r')"
        ;;
      OPEN)
        # Still open and not in the search: a short page, unless GitHub now
        # names it as a pull request the search did return (a renamed or
        # transferred repository). One the search missed stays in the stored
        # set, so the next run reads it again.
        now_id="$(printf '%s' "$v" | jq -r '.url // ""' | tr -d '\r' | sed -n 's|^https://github.com/\([^/]*/[^/]*\)/pull/\([0-9]*\)$|\1#\2|p')"
        if [ -z "$now_id" ] || ! printf '%s\n' "$open_ids" | grep -qxF -- "$now_id"; then
          echo "SWEEP INCOMPLETE: $id is open and the search did not return it; it is kept for the next run"
          retry="$retry
$id"
          incomplete=1
        fi
        ;;
    esac
  done <<< "$gone"
else
  echo "--- no previous sweep recorded"
  tidy=""
fi

# every recorded fork branch is checked again; it leaves the list only once GitHub
# says it is gone, which is a 404 and not any failure. The singular ref endpoint:
# the plural one answers 200 for any branch the name is a prefix of. An entry
# carries the head its pull request held; one written before 0.21.0 carries
# none and is asked about as before. A branch whose tip is no longer that head
# was used again for other work: hygiene keeps it, so it is said once and
# leaves the list.
referr=$(mktemp) || { echo "pr-sweep.sh: mktemp failed" >&2; exit 1; }
trap 'rm -f "$referr"' EXIT
keep=""; ntidy=0
while read -r fork branch id oid; do
  [ -n "$fork" ] || continue
  entry="$fork $branch $id${oid:+ $oid}"
  if ! tip="$(gh api "repos/$fork/git/ref/heads/$(uri_path "$branch")" --jq .object.sha 2>"$referr")"; then
    if grep -q '(HTTP 404)' "$referr"; then continue; fi
    keep="$(printf '%s\n%s\n' "$keep" "$entry")"
    echo "pr-sweep.sh: cannot read $fork $branch; asked again next run" >&2
    continue
  fi
  tip="$(printf '%s' "$tip" | tr -d '\r')"
  if [ -n "$oid" ] && [ "$oid" != "-" ] && [ "$tip" != "$oid" ]; then
    printf 'KEPT   %-38s fork branch %s %s moved past the head the pull request held: other work, not a leftover\n' "$id" "$fork" "$branch"
    continue
  fi
  ntidy=$((ntidy + 1))
  keep="$(printf '%s\n%s\n' "$keep" "$entry")"
  printf 'TIDY   %-38s fork branch %s %s still exists: run housebroken hygiene\n' "$id" "$fork" "$branch"
done <<< "$(printf '%s\n' "$tidy" | awk '(NF == 3 || NF == 4) && !seen[$0]++')"

if ! jq -n --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg open "$(printf '%s\n%s\n' "$open_ids" "$retry")" --arg tidy "$(printf '%s\n' "$keep")" \
  '{lastRun: $t, open: ($open | split("\n") | map(select(length > 0))), tidy: ($tidy | split("\n") | map(select(length > 0)))}' > "$STATE"; then
  echo "pr-sweep.sh: cannot write $STATE" >&2
  exit 1
fi

home="${HOUSEBROKEN_HOME:-$HOME/.housebroken}"
n=0; act=0; nread=0; reads=""
while IFS=$'\t' read -r repo num updated title; do
  [ -n "$repo" ] || continue
  n=$((n + 1))
  title="$(printf '%s' "$title" | clean_line)"
  if ! j="$(gh pr view "$num" --repo "$repo" --json mergeable,reviewDecision,statusCheckRollup,headRefOid,labels,commits,comments,reviews,latestReviews)"; then
    printf '%-40s #%-5s (gh pr view failed)\n' "$repo" "$num" >&2
    unreadable=$((unreadable + 1))
    continue
  fi
  last_actor="$(printf '%s' "$j" | jq -r "$bot_login_jq"'
    [ (.comments[]? | {a: .author.login, t: .createdAt, r: .authorAssociation}), (.reviews[]? | {a: .author.login, t: .submittedAt, r: .authorAssociation}) ]
    | map(select(.a != null and (.a | is_bot_login | not)))
    | sort_by(.t) | last | "\(.a // "-") \(.t // "-") \(.r // "-")"')"
  read -r la_user la_time la_role <<<"$last_actor"
  ci="$(printf '%s' "$j" | jq -r "$ci_jq"'[.statusCheckRollup[]?] | if length == 0 then "none" elif any(.[]; ci == "red" and check_state != "ACTION_REQUIRED") then "FAILING" elif any(.[]; check_state == "ACTION_REQUIRED") then "needs-approval" elif any(.[]; ci == "running") then "pending" else "green" end')"
  head_oid="$(printf '%s' "$j" | jq -r '.headRefOid // ""' | tr -d '\r')"
  # An empty check list is a quiet repository or a head GitHub made no run for.
  if [ "$ci" = "none" ]; then
    ci="$(empty_rollup_reading "$repo" "$head_oid")"
    [ "$ci" = "needs-run-approval" ] && ci="needs-approval"
  fi
  # A gate reads a pull request when it is pushed, so one filed before a review
  # item existed is never read under it. The reports are this machine's, and a
  # pull request in a repository of our own never went through the door.
  if [ "${repo%%/*}" != "$ME" ]; then
    mark=""
    if [ -z "$head_oid" ]; then
      mark="head-unread"
    else
      under="$(reviewed_under "$repo" "$head_oid" "$home")"
      if [ -z "$under" ]; then mark="no-review-of-head"
      elif [ "$under" = unreadable ]; then mark="review-report-unreadable"
      elif [ "$under" -eq 0 ]; then mark="reviewed-under-an-unnumbered-brief"
      elif [ "$under" -lt "$review_brief_items" ]; then mark="reviewed-under-brief-$under-of-$review_brief_items"
      fi
      [ -z "$mark" ] || mark="$mark ${head_oid:0:12}"
    fi
    if [ -n "$mark" ]; then
      nread=$((nread + 1))
      reads="$reads$(printf 'READ %-38s #%-5s %s  [%s] %s' "$repo" "$num" "${title:0:60}" "$mark" "https://github.com/$repo/pull/$num")
"
    fi
  fi
  mergeable="$(printf '%s' "$j" | jq -r '.mergeable // "-"')"
  decision="$(printf '%s' "$j" | jq -r '.reviewDecision // "-"')"
  why=""
  # The role is GitHub's word on who spoke last: a maintainer is answered, an
  # outsider is read, and the desk should know which before it drafts.
  [ "$la_user" != "-" ] && [ "$la_user" != "$ME" ] && why="$why last-word:$la_user@${la_time:0:10} role:$(printf '%s' "$la_role" | tr '[:upper:]' '[:lower:]')"
  [ "$decision" = "CHANGES_REQUESTED" ] && why="$why changes-requested"
  [ "$ci" = "FAILING" ] && why="$why ci-failing"
  [ "$ci" = "no-ci-on-head" ] && why="$why no-ci-on-head"
  [ "$ci" = "ci-never-started" ] && why="$why ci-never-started"
  [ "$ci" = "ci-unread" ] && why="$why ci-unread"
  [ "$mergeable" = "CONFLICTING" ] && why="$why conflicting"
  # A stale bot's notice is the one bot comment with a deadline. A notice that
  # could not be read is said, not passed over.
  if ! stale="$(printf '%s' "$j" | jq -r "$stale_jq"'stale_mark' 2>/dev/null)"; then stale="stale:unread"; fi
  stale="$(printf '%s' "$stale" | tr -d '\r')"
  [ -n "$stale" ] && why="$why $stale"
  if [ -n "$why" ]; then
    act=$((act + 1))
    printf 'ACT  %-38s #%-5s %s  [%s] %s\n' "$repo" "$num" "${title:0:60}" "${why# }" "https://github.com/$repo/pull/$num"
    # Any comment resets the bot's timer, so what is checked first is whether
    # the pull request still says what is true.
    case "$stale" in
      stale:closes-*|stale:warned-*|stale:label)
        echo "     before any bump: re-derive the body's claims on the default branch, read ci on the head, and check whether upstream changed the touched files" ;;
    esac
  elif [ "$ALL" = 1 ]; then
    printf 'ok   %-38s #%-5s %s  ci=%s mergeable=%s updated=%s\n' "$repo" "$num" "${title:0:60}" "$ci" "$mergeable" "${updated:0:10}"
  fi
done <<< "$list"
if [ "$nread" -gt 0 ] && [ "$ALL" = 1 ]; then
  echo "--- no review of the head under the current brief ($review_brief_items items) on this machine"
  printf '%s' "$reads"
fi
echo "open PRs: $n; needing action: $act"
[ "$nread" -gt 0 ] && echo "not read under the current review brief: $nread of $n (housebroken sweep --all names them)"
[ "$ntidy" -gt 0 ] && echo "fork branches to tidy: $ntidy (housebroken hygiene)"
if [ "$unreadable" -gt 0 ]; then
  echo "SWEEP UNREADABLE: $unreadable pull request(s) could not be read, so their state is unknown, not clean" >&2
  exit 1
fi
[ "$incomplete" -eq 0 ] || exit 1
exit 0
