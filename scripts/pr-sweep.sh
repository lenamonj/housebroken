#!/bin/bash
# pr-sweep.sh - every open upstream PR of ours, and which ones need us to act.
#
# Every maintainer comment gets a same-day answer; without a sweep the answer
# depends on remembering which PR was touched. Ball in our court means any of:
# the newest comment or review is not ours (bots excluded), a review requests
# changes, CI has a failing check, or the PR is CONFLICTING (needs a rebase).
# Read-only; acting is the operator's.
#
# A merge or a close drops a PR out of the open list without a word, so each
# run writes its open set to a state file and the next run reports what left
# it.
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
# the ones authored by that login. Exits non-zero when gh fails or the search
# returns nothing.
set -u

usage() {
  sed -n '2,/^set -u$/p' "$0" | sed 's/^# \{0,1\}//; /^set -u$/d'
}

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

if ! list="$(gh search prs --author "$ME" --state open --limit 100 --json repository,number,title,updatedAt \
  --jq '.[] | "\(.repository.nameWithOwner)\t\(.number)\t\(.updatedAt)\t\(.title)"' | sort)"; then
  echo "pr-sweep.sh: gh search prs failed for author $ME" >&2
  exit 1
fi
[ -n "$list" ] || { echo "pr-sweep.sh: no open PRs found for $ME" >&2; exit 1; }

open_ids="$(printf '%s\n' "$list" | tr -d '\r' | awk -F'\t' 'NF > 1 { print $1 "#" $2 }' | sort)"
if [ -f "$STATE" ]; then
  # jq on Windows writes CRLF; a stray CR would make every stored id look new
  if ! last="$(jq -r '.lastRun // "an unknown time"' "$STATE" | tr -d '\r')"; then
    echo "pr-sweep.sh: cannot read $STATE" >&2
    exit 1
  fi
  echo "--- merged or closed since $last"
  gone="$(comm -23 <(jq -r '.open[]?' "$STATE" | tr -d '\r' | sort) <(printf '%s\n' "$open_ids"))"
  while read -r id; do
    [ -n "$id" ] || continue
    gone_repo="${id%#*}"; gone_num="${id##*#}"
    if ! v="$(gh pr view "$gone_num" --repo "$gone_repo" --json state,mergedAt,closedAt,mergedBy)"; then
      echo "pr-sweep.sh: gh pr view $id failed" >&2
      continue
    fi
    case "$(printf '%s' "$v" | jq -r '.state // "-"' | tr -d '\r')" in
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
fi

if ! printf '%s\n' "$open_ids" | jq -R -s --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{lastRun: $t, open: (split("\n") | map(select(length > 0)))}' > "$STATE"; then
  echo "pr-sweep.sh: cannot write $STATE" >&2
  exit 1
fi

n=0; act=0
while IFS=$'\t' read -r repo num updated title; do
  [ -n "$repo" ] || continue
  n=$((n + 1))
  if ! j="$(gh pr view "$num" --repo "$repo" --json mergeable,reviewDecision,statusCheckRollup,comments,reviews,latestReviews)"; then
    printf '%-40s #%-5s (gh pr view failed)\n' "$repo" "$num" >&2
    continue
  fi
  last_actor="$(printf '%s' "$j" | jq -r '
    [ (.comments[]? | {a: .author.login, t: .createdAt}), (.reviews[]? | {a: .author.login, t: .submittedAt}) ]
    | map(select(.a != null and (.a | test("bot|\\[bot\\]|github-actions|codecov|dependabot|cla-|-cla|claassistant|coderabbit|devin|coveralls|vercel|asf-|apache-"; "i") | not)))
    | sort_by(.t) | last | "\(.a // "-") \(.t // "-")"')"
  la_user="${last_actor%% *}"; la_time="${last_actor#* }"
  ci="$(printf '%s' "$j" | jq -r '[.statusCheckRollup[]? | (.conclusion // .state // "PENDING")] | if length == 0 then "none" elif any(. == "FAILURE" or . == "ERROR") then "FAILING" elif any(. == "PENDING" or . == "IN_PROGRESS" or . == "QUEUED" or . == "EXPECTED") then "pending" else "green" end')"
  mergeable="$(printf '%s' "$j" | jq -r '.mergeable // "-"')"
  decision="$(printf '%s' "$j" | jq -r '.reviewDecision // "-"')"
  why=""
  [ "$la_user" != "-" ] && [ "$la_user" != "$ME" ] && why="$why last-word:$la_user@${la_time:0:10}"
  [ "$decision" = "CHANGES_REQUESTED" ] && why="$why changes-requested"
  [ "$ci" = "FAILING" ] && why="$why ci-failing"
  [ "$mergeable" = "CONFLICTING" ] && why="$why conflicting"
  if [ -n "$why" ]; then
    act=$((act + 1))
    printf 'ACT  %-38s #%-5s %s  [%s] %s\n' "$repo" "$num" "${title:0:60}" "${why# }" "https://github.com/$repo/pull/$num"
  elif [ "$ALL" = 1 ]; then
    printf 'ok   %-38s #%-5s %s  ci=%s mergeable=%s updated=%s\n' "$repo" "$num" "${title:0:60}" "$ci" "$mergeable" "${updated:0:10}"
  fi
done <<< "$list"
echo "open PRs: $n; needing action: $act"
