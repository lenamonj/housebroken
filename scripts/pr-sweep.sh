#!/bin/bash
# pr-sweep.sh - every open upstream PR of ours, and which ones need us to act.
#
#   bash pr-sweep.sh            # prints only PRs where the ball is in our court
#   bash pr-sweep.sh --all      # prints every open PR with its state
#
# Ball in our court means any of: the newest comment or review is not ours
# (bots excluded), a review requests changes, CI has a failing check, or the
# PR is CONFLICTING (needs a rebase). Read-only; acting is the operator's.
set -u
ME=lenamonj
ALL=0; [ "${1:-}" = "--all" ] && ALL=1
list="$(gh search prs --author "$ME" --state open --limit 100 --json repository,number,title,updatedAt \
  --jq '.[] | "\(.repository.nameWithOwner)\t\(.number)\t\(.updatedAt)\t\(.title)"' 2>/dev/null | sort)"
[ -n "$list" ] || { echo "no open PRs found (or gh failed)"; exit 1; }
n=0; act=0
while IFS=$'\t' read -r repo num updated title; do
  [ -n "$repo" ] || continue
  n=$((n + 1))
  j="$(gh pr view "$num" --repo "$repo" --json mergeable,reviewDecision,statusCheckRollup,comments,reviews,latestReviews 2>/dev/null)" || { printf '%-40s #%-5s (gh pr view failed)\n' "$repo" "$num"; continue; }
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
