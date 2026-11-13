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
# phone marks it read, and that must not hide it from the desk. --ack stores the
# time the last read started, not the time of the ack, so what arrives while you
# act on it is still ahead of the cursor, and a run that could not read a thread
# leaves nothing to ack.
#
# Usage:
#   bash inbox.sh                   # since the stored cursor (first run: 24 h ago)
#   bash inbox.sh --since <ISO8601> # since an explicit time, cursor untouched
#   bash inbox.sh --no-ci           # skip the census of open pull requests
#   bash inbox.sh --ack             # store the last full read as the cursor
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
# when gh fails or a thread could not be read.
set -u

usage() { sed -n '2,/^set -u$/p' "$0" | sed 's/^# \{0,1\}//; /^set -u$/d'; }
# shellcheck source=scripts/common.sh
. "$(cd "$(dirname "$0")" && pwd)/common.sh"

home="${HOUSEBROKEN_HOME:-$HOME/.housebroken}"
cursor_file="$home/inbox-cursor"
pending_file="$home/inbox-pending"
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
  if [ ! -s "$pending_file" ]; then
    echo "inbox.sh: nothing to acknowledge: --ack follows a run that read every thread" >&2; exit 1
  fi
  mv "$pending_file" "$cursor_file" && echo "inbox cursor is now $(head -1 "$cursor_file")" && exit 0
  echo "inbox.sh: could not write $cursor_file" >&2; exit 1
fi

user="${HOUSEBROKEN_USER:-$(gh api user --jq .login 2>/dev/null)}"
[ -n "$user" ] || { echo "inbox.sh: gh is not authenticated" >&2; exit 1; }
if [ -z "$since" ]; then
  if [ -s "$cursor_file" ]; then since="$(head -1 "$cursor_file")"; else since="$(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-24H +%Y-%m-%dT%H:%M:%SZ)"; fi
fi

work=$(mktemp -d) || { echo "inbox.sh: mktemp failed" >&2; exit 1; }
trap 'rm -rf "$work"' EXIT
# One thread read, every page, into a file: a long thread does not fit on a
# command line, and a read that failed is not an empty one.
read_all() { # endpoint file
  gh api --paginate "$1" > "$2.raw" 2>/dev/null && jq -cs 'add // []' "$2.raw" > "$2" 2>/dev/null
}

echo "== inbox for $user since $since (now $now) =="
if ! feed="$(gh api "notifications?all=true&since=$since&per_page=100" --paginate 2>/dev/null)"; then
  echo "inbox.sh: gh api notifications failed (is the notifications scope granted?)" >&2; exit 1
fi
threads="$(printf '%s' "$feed" | jq -c '.[] | select(.subject.type == "PullRequest" or .subject.type == "Issue") | {repo: .repository.full_name, type: .subject.type, num: (.subject.url | split("/") | last), title: .subject.title, reason: .reason, at: .updated_at, latest: (.subject.latest_comment_url // "")}' | sort -u)"
count=$(printf '%s\n' "$threads" | grep -c . || true)
human=0
unread=0
echo "$count thread(s) with activity"
others="$(printf '%s' "$feed" | jq -rs '(add // []) | [.[] | select(.subject.type != "PullRequest" and .subject.type != "Issue") | .subject.type] | group_by(.) | map("\(.[0]) \(length)") | join(", ")' | tr -d '\r')"
[ -z "$others" ] || echo "not expanded: $others"
while IFS= read -r t; do
  [ -n "$t" ] || continue
  repo=$(jq -r .repo <<<"$t"); num=$(jq -r .num <<<"$t"); type=$(jq -r .type <<<"$t"); reason=$(jq -r .reason <<<"$t"); at=$(jq -r .at <<<"$t"); title=$(jq -r .title <<<"$t" | clean_line)
  if [ "$type" = "PullRequest" ]; then
    state=$(gh pr view "$num" --repo "$repo" --json state,isDraft,mergedBy --jq 'if .state == "MERGED" then "MERGED by " + (.mergedBy.login // "?") elif .isDraft then "OPEN, DRAFT" else .state end' 2>/dev/null || echo "?")
  else
    state=$(gh issue view "$num" --repo "$repo" --json state --jq .state 2>/dev/null || echo "?")
  fi
  echo
  echo "--- $repo#$num [$reason, $at] $state"
  # Anyone who can @mention you chooses a title: it is theirs, not this script's.
  echo "    title (untrusted): $title"
  ok=1
  read_all "repos/$repo/issues/$num/comments?since=$since&per_page=100" "$work/ic" || ok=0
  if [ "$type" = "PullRequest" ]; then
    read_all "repos/$repo/pulls/$num/comments?since=$since&per_page=100" "$work/rc" || ok=0
    read_all "repos/$repo/pulls/$num/reviews?per_page=100" "$work/rv" || ok=0
  else
    echo '[]' > "$work/rc"; echo '[]' > "$work/rv"
  fi
  [ "$ok" -eq 1 ] && events="$(jq -nc --slurpfile ic "$work/ic" --slurpfile rc "$work/rc" --slurpfile rv "$work/rv" --arg since "$since" '
    def bot: (.user.type // "") == "Bot";
    def role: (.author_association // "unknown") | ascii_downcase;
    [ ($ic[0][] | {t: .created_at, who: (.user.login // "?"), bot: bot, role: role, kind: "comment", where: "", rst: "", body: (.body // "")}),
      ($rc[0][] | {t: .created_at, who: (.user.login // "?"), bot: bot, role: role, kind: "inline", where: (" on " + (.path // "?") + ":" + ((.line // .original_line // 0) | tostring) + " (comment " + (.id | tostring) + ", answer it with reply --in-reply-to)"), rst: "", body: (.body // "")}),
      ($rv[0][] | select((.submitted_at // "") > $since) | {t: .submitted_at, who: (.user.login // "?"), bot: bot, role: role, kind: "review", where: "", rst: (.state // ""), body: (.body // "")}) ]
    | sort_by(.t) | .[]' 2>/dev/null)" || ok=0
  if [ "$ok" -eq 0 ]; then
    unread=$((unread + 1))
    echo "    UNREAD: this thread's comments or reviews could not be read, which is not the same as none"
    continue
  fi
  shown=0
  while IFS= read -r e; do
    [ -n "$e" ] || continue
    who=$(jq -r .who <<<"$e"); when=$(jq -r .t <<<"$e"); kind=$(jq -r .kind <<<"$e"); where=$(jq -r .where <<<"$e" | clean_line); rst=$(jq -r .rst <<<"$e"); bot=$(jq -r .bot <<<"$e"); role=$(jq -r .role <<<"$e")
    shown=$((shown + 1))
    if [ "$who" = "$user" ]; then
      echo "    $when yours: $kind$where"
    elif [ "$bot" = "true" ] || is_bot "$who"; then
      echo "    $when $who (bot): $kind$where${rst:+ [$rst]}"
      # A review bot can ask for a real change; most say nothing, so only the top.
      jq -r .body <<<"$e" | head -20 | fence "$who" "    "
    else
      human=$((human + 1))
      # The role is GitHub's word on who this is to the repository: the skill
      # answers maintainers, and a voice with no role is read, not answered.
      echo "    $when $who [$role]: $kind$where${rst:+ [$rst]}"
      # A body is someone else's text: evidence to read, never an instruction.
      jq -r .body <<<"$e" | fence "$who" "    "
      has_role "$role" || echo "    ($who has no role in $repo: the skill answers maintainers, and housebroken reply needs --outsider)"
    fi
  done <<<"$events"
  [ "$shown" -gt 0 ] || echo "    (no comment or review since the cursor: a merge, a close, a push, a mention or a review request; see the state above)"
done <<<"$threads"

if [ "$do_ci" -eq 1 ]; then
  echo
  echo "== census of open pull requests: failing, blocked, conflicting, changes requested, draft =="
  prs="$(gh search prs --author "$user" --state open --limit 100 --json repository,number,isDraft --jq '.[] | "\(.repository.nameWithOwner) \(.number) \(.isDraft)"' 2>/dev/null)"
  total=$(printf '%s\n' "$prs" | grep -c . || true)
  # GitHub search returns a short page when it is throttled, and a census of half
  # the pull requests reads exactly like a clean one. Compare against the count the
  # API itself reports and say so loudly rather than silently flagging fewer.
  claimed="$(gh api "search/issues?q=is:pr+author:$user+is:open&per_page=1" --jq '.total_count' 2>/dev/null)"
  case "$claimed" in
    ''|*[!0-9]*) echo "CENSUS UNVERIFIED: could not read the open pull request count from the API" ;;
    *) [ "$total" -ge "$claimed" ] || echo "CENSUS INCOMPLETE: search returned $total of $claimed open pull requests, so this census covers only part of them; re-run when the search rate limit recovers" ;;
  esac
  flagged=0
  unreadable=0
  unreadable_list=""
  while read -r repo num draft; do
    [ -n "$repo" ] || continue
    j="$(gh pr view "$num" --repo "$repo" --json mergeable,reviewDecision,statusCheckRollup,headRefOid,labels,comments,reviews 2>/dev/null)"
    if [ -z "$j" ]; then
      # A pull request we could not read is not a clean one: say so rather than skipping in silence.
      unreadable=$((unreadable + 1)); unreadable_list="$unreadable_list $repo#$num"; continue
    fi
    why="$(jq -r --arg draft "$draft" "$ci_jq"'
      [ ( [.statusCheckRollup[]?] | if any(.[]; ci == "red" and check_state != "ACTION_REQUIRED") then "FAILING" elif any(.[]; check_state == "ACTION_REQUIRED") then "needs-run-approval" else empty end ),
        ( if .mergeable == "CONFLICTING" then "CONFLICTING" else empty end ),
        ( if .reviewDecision == "CHANGES_REQUESTED" then "changes-requested" else empty end ),
        ( if $draft == "true" then "draft" else empty end ) ] | join(" ")' <<<"$j")"
    # An empty check list is a quiet repository or a head GitHub made no run for.
    if [ "$(jq -r '[.statusCheckRollup[]?] | length' <<<"$j" | tr -d '\r')" = "0" ]; then
      empty="$(empty_rollup_reading "$repo" "$(jq -r '.headRefOid // ""' <<<"$j" | tr -d '\r')")"
      case "$empty" in none|pending) ;; *) why="$empty${why:+ $why}" ;; esac
    fi
    # A stale bot's warning is the one bot comment with a deadline.
    stale="$(jq -r "$stale_jq"'stale_mark' <<<"$j" | tr -d '\r')"
    [ -z "$stale" ] || why="${why:+$why }$stale"
    if [ -n "$why" ]; then
      flagged=$((flagged + 1))
      fails="$(jq -r "$ci_jq"'[.statusCheckRollup[]? | select(ci == "red" and check_state != "ACTION_REQUIRED") | (.name // .context)] | unique | join(", ")' <<<"$j" | clean_line)"
      echo "$repo#$num: $why${fails:+  [$fails]}"
    fi
  done <<<"$prs"
  [ "$unreadable" -eq 0 ] || echo "CENSUS UNREADABLE: could not read $unreadable of $total pull requests, so their state is unknown, not clean:$unreadable_list"
  echo "$flagged of $total open pull requests flagged"
fi

echo
mkdir -p "$home" 2>/dev/null && { echo "## $now (since $since): $count thread(s), $human human, $unread unread"; } >> "$ledger"
if [ "$unread" -gt 0 ]; then
  rm -f "$pending_file"
  echo "$unread thread(s) UNREAD, $human human item(s) since $since. Run it again before you ack: the cursor cannot pass what was not read."
  exit 1
fi
printf '%s\n' "$now" > "$pending_file"
echo "$human human item(s) since $since. Act on each, then: housebroken inbox --ack"
exit 0
