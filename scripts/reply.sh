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
# Refused: an opening that grades the reviewer or thanks or apologises
# ("you are right", "good catch", "great point", "thanks", "sorry"); an
# exclamation mark or bold; more than three sentences unless --long; a
# closing offer ("let me know", "happy to", "feel free", "hope this
# helps"); a typographic dash, a tool footer or a session link; a reference
# ref-check.sh cannot find; and a second reply to the repository within ten
# minutes. Code spans and quoted lines are left out of the tone checks.
# With --review REPORT, the review must pass `review.sh check` for this text,
# which the skill requires for a reply that concedes, disagrees or rides on a
# code change.
#
# Usage:
#   bash reply.sh owner/repo NUMBER --body-file FILE [--review REPORT] [--long] [--clone DIR]
#   bash reply.sh --help
#
# Environment:
#   HOUSEBROKEN_HOME  work directory, default $HOME/.housebroken; replies are
#                     logged to replies/<owner>-<repo>.log for the spacing
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
body=""; report=""; long=0; clone=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --body-file) body="${2:-}"; shift ;;
    --review) report="${2:-}"; shift ;;
    --clone) clone="${2:-}"; shift ;;
    --long) long=1 ;;
    *) echo "REFUSED: unknown argument $1" >&2; exit 2 ;;
  esac
  shift
done
[ -f "$body" ] || { echo "REFUSED: --body-file names no file" >&2; exit 2; }
here=$(cd "$(dirname "$0")" && pwd)
home="${HOUSEBROKEN_HOME:-$HOME/.housebroken}"

refused=""
refuse() { refused="$refused
    $*"; }

# The prose, without code spans, fenced blocks or quoted lines.
# shellcheck disable=SC2016  # the backticks are markdown, matched literally
prose=$(awk '/^(```|~~~)/ {f = !f; next} !f && !/^ *>/' "$body" | sed 's/`[^`]*`//g')
first=$(printf '%s\n' "$prose" | grep -m1 -v '^[[:space:]]*$' | sed 's/^[[:space:]]*//')
printf '%s' "$first" | grep -qiE "^(you('| a)re (right|correct)|good (catch|point|call)|great (catch|point|question)|nice catch|thanks|thank you|apologies|sorry|i apologi[sz]e)\b" &&
  refuse "it opens with a verdict, thanks or an apology; lead with the fact: $(printf '%s' "$first" | cut -c1-60)"
printf '%s' "$prose" | grep -q '!' && refuse "it has an exclamation mark"
printf '%s' "$prose" | grep -qE '\*\*[^*]+\*\*|__[^_]+__' && refuse "it has bold"
printf '%s' "$prose" | grep -qiE "\b(let me know|happy to (help|send|open|make|change)|feel free|hope (this|that) helps)\b" &&
  refuse "it closes with an offer; stop when the content stops"
sentences=$(printf '%s\n' "$prose" | tr '\n' ' ' | grep -oE '[.?][[:space:]]+[A-Z]|[.?][[:space:]]*$' | grep -c .)
[ "$long" -eq 1 ] || [ "$sentences" -le 3 ] || refuse "it runs $sentences sentences; a reply is one to three (--long when the maintainer asked for detail)"
em=$(printf '\xe2\x80\x94'); en=$(printf '\xe2\x80\x93')
grep -qF -e "$em" -e "$en" "$body" && refuse "it has a typographic dash"
grep -qiE 'generated with|claude\.ai/code|co-authored-by:' "$body" && refuse "it carries a tool footer, a session link or a trailer"

refargs=("$repo" "$body"); [ -n "$clone" ] && refargs+=(--clone "$clone")
if ! refs=$(bash "$here/ref-check.sh" "${refargs[@]}" 2>&1); then
  refuse "it names something that does not exist: $(printf '%s\n' "$refs" | grep 'NOT FOUND' | tr -s ' ' | tr '\n' ';')"
fi
if [ -n "$report" ]; then
  checked=$(bash "$here/review.sh" check "$report" --text "$body" 2>&1) || refuse "the review does not clear this text: $checked"
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
claims=$(bash "$here/claim-check.sh" "$body" 2>&1) || printf 'Re-derive before it posts:\n%s\n' "$claims" >&2

if [ "${REPLY_DRY:-0}" = "1" ]; then
  echo "DRY RUN, not posted: reply to $repo#$num from $body"
  exit 0
fi
gh api "repos/$repo/issues/$num/comments" -F "body=@$body" --jq .html_url || exit 2
mkdir -p "$home/replies"
printf '%s %s#%s\n' "$(date -u +%s)" "$repo" "$num" >> "$log"
