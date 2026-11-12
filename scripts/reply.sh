#!/bin/bash
# reply.sh - the only way an answer on a thread gets posted.
#
# A reply is the maintainer's first impression of the person behind the
# pull request, and the rules for one are written in the skill: lead with the
# fact, never with a verdict on the reviewer; no thanks, apology, bold or
# exclamation mark; one to three sentences; no closing offer of help; no
# reference to something that does not exist; ten minutes between replies to
# one repository. This holds each rule a script can hold, then posts.
#
# Refused: an opening that grades the reviewer ("you are right", "good
# catch", "great point", "agreed", "fair point"); thanks or an apology
# anywhere; an exclamation mark or bold; more than three sentences unless
# --long; a closing offer or summary ("let me know", "happy to", "feel
# free", "hope this helps", "in summary"); a typographic dash, a tool footer
# or a session link; a reference ref-check.sh cannot find; and a second
# reply to the repository within ten minutes. Code spans, fenced blocks and
# quoted lines are evidence, not our words, and are left out of the tone
# and dash checks. With --review REPORT, the review must pass `review.sh
# check` for this text, which the skill requires for a reply that concedes,
# disagrees or rides on a code change.
#
# Whom it answers is read before it posts: the newest voice on the thread
# that is not ours and not a bot (the comment named by --in-reply-to, for an
# inline answer), with the role GitHub records for them on the repository.
# The skill answers maintainers. A voice with no role (NONE, CONTRIBUTOR,
# FIRST_TIME_CONTRIBUTOR) is refused unless --outsider carries the user's
# word to answer them, and a thread that could not be read is refused, not
# taken for empty. Two replies went to accounts with no role in a week,
# because the inbox had said "answer it" and nothing said who was asking.
#
# Usage:
#   bash reply.sh owner/repo NUMBER --body-file FILE [--review REPORT] [--long]
#                 [--clone DIR] [--in-reply-to COMMENT_ID] [--outsider]
#   bash reply.sh --help
#
# --in-reply-to answers an inline review comment in its own thread, by the
# id the inbox prints beside it; without it the reply goes to the
# conversation. --outsider answers a voice with no role in the repository,
# which only the user can decide.
#
# Environment:
#   HOUSEBROKEN_HOME  work directory, default $HOME/.housebroken; replies are
#                     logged to replies/<owner>-<repo>.log for the spacing
#   HOUSEBROKEN_USER  your login, read from gh when unset
#   REPLY_DRY         1 prints what would be posted and posts nothing
#
# Exits 0 when posted (or on a dry run), 2 on a refusal or a usage error.
set -u

usage() { awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"; }
case "${1:-}" in --help|-h) usage; exit 0 ;; esac

repo="${1:-}"; num="${2:-}"
case "$repo" in */*) ;; *) echo "REFUSED: name the repository as owner/repo" >&2; exit 2 ;; esac
case "$num" in ''|*[!0-9]*) echo "REFUSED: name the pull request or issue number" >&2; exit 2 ;; esac
shift 2
body=""; report=""; long=0; clone=""; thread=""; outsider=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --body-file) body="${2:-}"; shift ;;
    --review) report="${2:-}"; shift ;;
    --clone) clone="${2:-}"; shift ;;
    --in-reply-to) thread="${2:-}"; shift ;;
    --long) long=1 ;;
    --outsider) outsider=1 ;;
    *) echo "REFUSED: unknown argument $1" >&2; exit 2 ;;
  esac
  shift
done
[ -f "$body" ] || { echo "REFUSED: --body-file names no file" >&2; exit 2; }
case "$thread" in ''|[0-9]*) ;; *) echo "REFUSED: --in-reply-to needs the comment id" >&2; exit 2 ;; esac
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=scripts/common.sh
. "$here/common.sh"
home="${HOUSEBROKEN_HOME:-$HOME/.housebroken}"

refused=""
refuse() { refused="$refused
    $*"; }

while IFS= read -r r; do refuse "$r"; done < <(tone_refusals "$body" "$long")

refargs=("$repo" "$body"); [ -n "$clone" ] && refargs+=(--clone "$clone")
if ! refs=$(bash "$here/ref-check.sh" "${refargs[@]}" 2>&1); then
  refuse "it names something that does not exist: $(printf '%s\n' "$refs" | grep 'NOT FOUND' | tr -s ' ' | tr '\n' ';')"
fi
if [ -n "$report" ]; then
  checked=$(bash "$here/review.sh" check "$report" --text "$body" 2>&1) || refuse "the review does not clear this text: $checked"
fi

# Whom this answers. One thread read, every page, into a file: a long thread
# does not fit on a command line, and a read that failed is not an empty one.
user="${HOUSEBROKEN_USER:-$(gh api user --jq .login 2>/dev/null)}"
[ -n "$user" ] || { echo "REFUSED: gh is not authenticated, so who this reply answers cannot be read" >&2; exit 2; }
work=$(mktemp -d) || { echo "REFUSED: mktemp failed" >&2; exit 2; }
trap 'rm -rf "$work"' EXIT
read_all() { # endpoint file
  gh api --paginate "$1" > "$2.raw" 2>/dev/null && jq -cs 'add // []' "$2.raw" > "$2" 2>/dev/null
}
voice=""
if [ -n "$thread" ]; then
  if one=$(gh api "repos/$repo/pulls/comments/$thread" 2>/dev/null); then
    voice=$(printf '%s' "$one" | jq -r '"\(.user.login // "?") \(.author_association // "?")"' | tr -d '\r')
  else
    refuse "cannot read comment $thread, so who it answers is unknown"
  fi
else
  ok=1
  kind=$(gh api "repos/$repo/issues/$num" --jq '.pull_request.url // ""' 2>/dev/null | tr -d '\r') || ok=0
  read_all "repos/$repo/issues/$num/comments?per_page=100" "$work/ic" || ok=0
  if [ "$ok" -eq 1 ] && [ -n "$kind" ]; then
    read_all "repos/$repo/pulls/$num/reviews?per_page=100" "$work/rv" || ok=0
    read_all "repos/$repo/pulls/$num/comments?per_page=100" "$work/rc" || ok=0
  else
    echo '[]' > "$work/rv"; echo '[]' > "$work/rc"
  fi
  if [ "$ok" -eq 1 ]; then
    # Newest first, ours and GitHub's bots left out; a bot by name is skipped below.
    voices=$(jq -r -n --slurpfile ic "$work/ic" --slurpfile rv "$work/rv" --slurpfile rc "$work/rc" --arg me "$user" '
      [ ($ic[0][] | {t: .created_at, who: .user.login, type: .user.type, r: .author_association}),
        ($rv[0][] | {t: .submitted_at, who: .user.login, type: .user.type, r: .author_association}),
        ($rc[0][] | {t: .created_at, who: .user.login, type: .user.type, r: .author_association}) ]
      | map(select(.who != null and .who != $me and (.type // "") != "Bot")) | sort_by(.t) | reverse
      | .[] | "\(.who) \(.r // "?")"' | tr -d '\r')
    while IFS= read -r v; do
      [ -n "$v" ] || continue
      is_bot "${v%% *}" && continue
      voice="$v"; break
    done <<<"$voices"
  else
    refuse "cannot read who is on $repo#$num, so who this answers is unknown"
  fi
fi
if [ -n "$voice" ] && [ "$outsider" -eq 0 ]; then
  who="${voice%% *}"; role="${voice#* }"
  has_role "$role" || refuse "$who ($role) has no role in $repo, and the skill answers maintainers; pass --outsider when the user has said to answer them"
fi

log="$home/replies/${repo%%/*}-${repo##*/}.log"
if [ -f "$log" ]; then
  last=$(tail -1 "$log" | awk '{print $1}')
  since=$(( $(date -u +%s) - ${last:-0} ))
  [ "$since" -ge 600 ] || refuse "your last reply to $repo went out ${since}s ago; space them ten minutes apart"
fi

if [ -n "$refused" ]; then
  echo "REFUSED: the reply to $repo#$num is not ready:$refused" >&2
  exit 2
fi
claims=$(bash "$here/claim-check.sh" "$body" 2>&1) || printf 'Posting these claims, which step 10 had you re-derive with housebroken claims first:\n%s\n' "$claims" >&2

endpoint="repos/$repo/issues/$num/comments"
[ -z "$thread" ] || endpoint="repos/$repo/pulls/$num/comments/$thread/replies"
if [ "${REPLY_DRY:-0}" = "1" ]; then
  echo "DRY RUN, not posted: reply to $repo#$num from $body via $endpoint"
  exit 0
fi
gh api "$endpoint" -F "body=@$body" --jq .html_url || exit 2
mkdir -p "$home/replies"
printf '%s %s#%s\n' "$(date -u +%s)" "$repo" "$num" >> "$log"
