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
# every run until `housebroken hygiene` has removed it. The obligation is in
# the output, not in anyone's memory.
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
# the ones authored by that login. Exits non-zero when gh fails or a pull request
# could not be read; no open pull requests left is a result, not a failure.
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
[ "$(printf '%s\n' "$list" | grep -c .)" -lt "$MAX" ] || echo "SWEEP INCOMPLETE: the search stopped at $MAX open pull requests"

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
    if ! v="$(gh pr view "$gone_num" --repo "$gone_repo" --json state,mergedAt,closedAt,mergedBy,headRefName,headRepository,headRepositoryOwner)"; then
      echo "pr-sweep.sh: gh pr view $id failed; it is read again next run" >&2
      retry="$retry
$id"
      unreadable=$((unreadable + 1))
      continue
    fi
    head_owner="$(printf '%s' "$v" | jq -r '.headRepositoryOwner.login // "-"' | tr -d '\r')"
    head_fork="$(printf '%s' "$v" | jq -r '.headRepository.name // "-"' | tr -d '\r')"
    head_branch="$(printf '%s' "$v" | jq -r '.headRefName // "-"' | tr -d '\r')"
    gone_state="$(printf '%s' "$v" | jq -r '.state // "-"' | tr -d '\r')"
    if [ "$gone_state" != OPEN ] && [ "$head_owner" = "$ME" ] && [ "$gone_repo" != "$ME/$head_fork" ] && [ "$head_branch" != "-" ]; then
      tidy="$(printf '%s\n%s\n' "$tidy" "$ME/$head_fork $head_branch $id")"
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
    esac
  done <<< "$gone"
else
  echo "--- no previous sweep recorded"
  tidy=""
fi

# every recorded fork branch is checked again; it leaves the list only once GitHub
# says it is gone, which is a 404 and not any failure. The singular ref endpoint:
# the plural one answers 200 for any branch the name is a prefix of.
keep=""; ntidy=0
while read -r fork branch id; do
  [ -n "$fork" ] || continue
  if ! err="$(gh api "repos/$fork/git/ref/heads/$(uri_path "$branch")" 2>&1 >/dev/null)"; then
    case "$err" in *"(HTTP 404)"*) continue ;; esac
    keep="$(printf '%s\n%s\n' "$keep" "$fork $branch $id")"
    echo "pr-sweep.sh: cannot read $fork $branch; asked again next run" >&2
    continue
  fi
  ntidy=$((ntidy + 1))
  keep="$(printf '%s\n%s\n' "$keep" "$fork $branch $id")"
  printf 'TIDY   %-38s fork branch %s %s still exists: run housebroken hygiene\n' "$id" "$fork" "$branch"
done <<< "$(printf '%s\n' "$tidy" | awk 'NF == 3 && !seen[$0]++')"

if ! jq -n --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg open "$(printf '%s\n%s\n' "$open_ids" "$retry")" --arg tidy "$(printf '%s\n' "$keep")" \
  '{lastRun: $t, open: ($open | split("\n") | map(select(length > 0))), tidy: ($tidy | split("\n") | map(select(length > 0)))}' > "$STATE"; then
  echo "pr-sweep.sh: cannot write $STATE" >&2
  exit 1
fi

n=0; act=0
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
  # An empty check list is a quiet repository or a head GitHub made no run for.
  if [ "$ci" = "none" ]; then
    ci="$(empty_rollup_reading "$repo" "$(printf '%s' "$j" | jq -r '.headRefOid // ""' | tr -d '\r')")"
    [ "$ci" = "needs-run-approval" ] && ci="needs-approval"
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
echo "open PRs: $n; needing action: $act"
[ "$ntidy" -gt 0 ] && echo "fork branches to tidy: $ntidy (housebroken hygiene)"
if [ "$unreadable" -gt 0 ]; then
  echo "SWEEP UNREADABLE: $unreadable pull request(s) could not be read, so their state is unknown, not clean" >&2
  exit 1
fi
exit 0
