#!/bin/bash
# inbox.sh - what GitHub has to tell you since you last looked, bodies included.
#
# A commenter list is not a read. This prints every notification on the
# threads you are subscribed to (everything you authored) newer than a cursor,
# expands each to the full text of its latest comment or review, states the
# thread's current state (open, draft, merged, closed), and then takes a census
# of every open pull request of yours for failing, blocked or conflicting
# checks, which the notification feed does not carry for upstream pulls.
# Written 2026-09-08 after a two-bug review on apache/commons-lang #1783 sat
# unread for forty minutes because a check printed who had commented instead
# of what they said, and after cisco/libsrtp #821 sat red for two days with
# nobody reading its checks.
#
# The cursor is a timestamp, not GitHub's unread flag: reading a thread on the
# phone marks it read, and that must not hide it from the desk.
#
# Usage:
#   bash inbox.sh                   # since the stored cursor (first run: 24 h ago)
#   bash inbox.sh --since <ISO8601> # since an explicit time, cursor untouched
#   bash inbox.sh --no-ci           # skip the census of open pull requests
#   bash inbox.sh --ack             # store now as the cursor; run after acting
#   bash inbox.sh --help
#
# Environment:
#   HOUSEBROKEN_USER  your GitHub login, default the authenticated user
#   HOUSEBROKEN_HOME  workshop root, default $HOME/.housebroken; the cursor
#                     lives at $HOUSEBROKEN_HOME/inbox-cursor and every run is
#                     appended to $HOUSEBROKEN_HOME/inbox-ledger.md
#
# Assumes: gh is installed and authenticated with the notifications scope, jq
# is on PATH. Read-only apart from the cursor and the ledger. Exits non-zero
# when gh fails.
set -u

usage() { sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'; }

home="${HOUSEBROKEN_HOME:-$HOME/.housebroken}"
cursor_file="$home/inbox-cursor"
ledger="$home/inbox-ledger.md"
since=""
do_ci=1
ack=0
while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --since) shift; since="${1:-}"; [ -n "$since" ] || { echo "inbox.sh: --since needs a time" >&2; exit 2; } ;;
    --no-ci) do_ci=0 ;;
    --ack) ack=1 ;;
    *) echo "inbox.sh: unknown argument $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
if [ "$ack" -eq 1 ]; then
  mkdir -p "$home" && printf '%s\n' "$now" > "$cursor_file" && echo "inbox cursor is now $now" && exit 0
  echo "inbox.sh: could not write $cursor_file" >&2; exit 1
fi

user="${HOUSEBROKEN_USER:-$(gh api user --jq .login 2>/dev/null)}"
[ -n "$user" ] || { echo "inbox.sh: gh is not authenticated" >&2; exit 1; }
if [ -z "$since" ]; then
  if [ -s "$cursor_file" ]; then since="$(head -1 "$cursor_file")"; else since="$(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-24H +%Y-%m-%dT%H:%M:%SZ)"; fi
fi

is_bot() { case "$1" in *"[bot]"|copilot-pull-request-reviewer|codecov-commenter|coveralls|CLAassistant|meta-cla*|vercel*|coderabbitai*|copy-pr-bot*|oracle-contributor-agreement*|dependabot*|github-actions*|sonarcloud*|netlify*) return 0 ;; *) return 1 ;; esac; }

echo "== inbox for $user since $since (now $now) =="
if ! feed="$(gh api "notifications?all=true&since=$since&per_page=100" --paginate 2>/dev/null)"; then
  echo "inbox.sh: gh api notifications failed (is the notifications scope granted?)" >&2; exit 1
fi
threads="$(printf '%s' "$feed" | jq -c '.[] | select(.subject.type == "PullRequest" or .subject.type == "Issue") | {repo: .repository.full_name, type: .subject.type, num: (.subject.url | split("/") | last), title: .subject.title, reason: .reason, at: .updated_at, latest: (.subject.latest_comment_url // "")}' | sort -u)"
count=$(printf '%s\n' "$threads" | grep -c . || true)
human=0
echo "$count thread(s) with activity"
while IFS= read -r t; do
  [ -n "$t" ] || continue
  repo=$(jq -r .repo <<<"$t"); num=$(jq -r .num <<<"$t"); type=$(jq -r .type <<<"$t"); reason=$(jq -r .reason <<<"$t"); at=$(jq -r .at <<<"$t"); latest=$(jq -r .latest <<<"$t"); title=$(jq -r .title <<<"$t")
  if [ "$type" = "PullRequest" ]; then
    state=$(gh pr view "$num" --repo "$repo" --json state,isDraft,mergedBy --jq 'if .state == "MERGED" then "MERGED by " + (.mergedBy.login // "?") elif .isDraft then "OPEN, DRAFT" else .state end' 2>/dev/null || echo "?")
  else
    state=$(gh issue view "$num" --repo "$repo" --json state --jq .state 2>/dev/null || echo "?")
  fi
  echo
  echo "--- $repo#$num [$reason, $at] $state"
  echo "    $title"
  if [ -n "$latest" ]; then
    if c="$(gh api "$latest" 2>/dev/null)"; then
      who=$(jq -r '.user.login // "?"' <<<"$c"); when=$(jq -r '.created_at // .submitted_at // ""' <<<"$c"); where=$(jq -r 'if .path then " on " + .path + ":" + ((.line // .original_line // 0)|tostring) else "" end' <<<"$c"); rstate=$(jq -r '.state // ""' <<<"$c")
      if [ "$who" = "$user" ]; then
        echo "    latest: yours, $when"
      elif is_bot "$who"; then
        echo "    latest: $who (bot), $when$where"
      else
        human=$((human + 1))
        echo "    latest: $who, $when$where${rstate:+ [$rstate]}"
        jq -r '.body // ""' <<<"$c" | sed 's/^/    | /'
      fi
    else
      echo "    latest comment could not be fetched: $latest"
    fi
  else
    echo "    (no comment attached: a review, a merge, a close, a mention or a review request; see the state above)"
    if [ "$type" = "PullRequest" ]; then
      gh api "repos/$repo/pulls/$num/reviews?per_page=100" --jq --arg since "$since" --arg me "$user" '.[] | select(.submitted_at > $since and .user.login != $me) | "    review " + .state + " by " + .user.login + ", " + .submitted_at + (if (.body // "") != "" then "\n    | " + (.body | gsub("\r\n"; "\n    | ")) else "" end)' 2>/dev/null
    fi
  fi
done <<<"$threads"

if [ "$do_ci" -eq 1 ]; then
  echo
  echo "== census of open pull requests: failing, blocked, conflicting, changes requested, draft =="
  prs="$(gh search prs --author "$user" --state open --limit 100 --json repository,number,isDraft --jq '.[] | "\(.repository.nameWithOwner) \(.number) \(.isDraft)"' 2>/dev/null)"
  total=$(printf '%s\n' "$prs" | grep -c . || true)
  flagged=0
  while read -r repo num draft; do
    [ -n "$repo" ] || continue
    j="$(gh pr view "$num" --repo "$repo" --json mergeable,reviewDecision,statusCheckRollup 2>/dev/null)" || continue
    why="$(jq -r --arg draft "$draft" '
      [ ( [.statusCheckRollup[]? | (.conclusion // .state // "")] | if any(. == "FAILURE" or . == "ERROR") then "FAILING" elif any(. == "ACTION_REQUIRED") then "needs-run-approval" else empty end ),
        ( if .mergeable == "CONFLICTING" then "CONFLICTING" else empty end ),
        ( if .reviewDecision == "CHANGES_REQUESTED" then "changes-requested" else empty end ),
        ( if $draft == "true" then "draft" else empty end ) ] | join(" ")' <<<"$j")"
    if [ -n "$why" ]; then
      flagged=$((flagged + 1))
      fails="$(jq -r '[.statusCheckRollup[]? | select((.conclusion // .state // "") == "FAILURE" or (.conclusion // .state // "") == "ERROR") | (.name // .context)] | unique | join(", ")' <<<"$j")"
      echo "$repo#$num: $why${fails:+  [$fails]}"
    fi
  done <<<"$prs"
  echo "$flagged of $total open pull requests flagged"
fi

echo
echo "$human human item(s) since $since. Act on each, then: housebroken inbox --ack"
mkdir -p "$home" 2>/dev/null && { echo "## $now (since $since): $count thread(s), $human human"; } >> "$ledger"
exit 0
