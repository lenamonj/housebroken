#!/bin/bash
# close.sh - the only way a pull request of yours is withdrawn.
#
# A close is a comment the maintainer reads and a decision they did not make,
# so it is held to what a reply is held to. The hook refuses gh pr close, and
# before this gate existed three pull requests were withdrawn by hand on one
# evening, outside every check: no tone, no spacing, the fork branches left up
# and nothing recorded.
#
# Refused: a note with no words of its own (only code, quotes or nothing); a
# note that fails a reply's tone checks (a verdict as the opening, thanks or
# an apology, an exclamation mark, bold, a closing offer, more than three
# sentences, a dash, a tool footer); a reference ref-check.sh cannot find; a
# pull request that is not yours, is not open, or could not be read; and a
# close within ten minutes of your last reply or close on the repository.
#
# Then it posts the note, logs it beside the replies the moment it is public,
# closes the pull request, records it in the repository's notes, and deletes the fork
# branch the way housebroken hygiene would: only on a fork of yours, and only
# when no open pull request still uses it.
#
# Usage:
#   bash close.sh owner/repo NUMBER --body-file FILE [--clone DIR]
#   bash close.sh --help
#
# Environment:
#   HOUSEBROKEN_HOME  work directory, default $HOME/.housebroken; a close is
#                     logged to replies/<owner>-<repo>.log for the spacing
#   HOUSEBROKEN_USER  your login, read from gh when unset
#   CLOSE_DRY         1 checks everything, prints what would be closed, and
#                     writes nothing
#
# Exits 0 when closed (or on a dry run), 2 on a refusal, a usage error or a
# close that failed, 1 when the close went through but the notes line could
# not be written or the fork branch could not be deleted.
set -u
# shellcheck source=scripts/refuse.sh
. "$(cd "$(dirname "$0")" && pwd)/refuse.sh"

usage() { awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"; }
case "${1:-}" in --help|-h) usage; exit 0 ;; esac

repo="${1:-}"; num="${2:-}"
case "$repo" in */*) ;; *) refused close-repo-form "name the repository as owner/repo" >&2; exit 2 ;; esac
case "$num" in ''|*[!0-9]*) refused close-no-number "name the pull request number" >&2; exit 2 ;; esac
shift 2
body=""; clone=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --body-file) body="${2:-}"; shift ;;
    --clone) clone="${2:-}"; shift ;;
    *) refused close-unknown-argument "unknown argument $1" >&2; exit 2 ;;
  esac
  shift
done
[ -f "$body" ] || { refused close-body-file-missing "--body-file names no file" >&2; exit 2; }
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=scripts/common.sh
. "$here/common.sh"
home="${HOUSEBROKEN_HOME:-$HOME/.housebroken}"

reasons=""
refuse() { refusal_log "$1"; reasons="$reasons
    $2 [$1]"; }
refuse_line() { refuse "${1%%|*}" "${1#*|}"; } # a "name|message" line from a shared check

# The first line of our own words: not code, not a quote, and with a letter in it.
# shellcheck disable=SC2016  # the backticks are markdown, matched literally
own=$(awk '/^(```|~~~)/ {f = !f; next} !f && !/^ *>/' "$body" | sed 's/`[^`]*`//g' | grep -m1 '[[:alpha:]]')
[ -n "$own" ] || refuse close-no-note-of-its-own "it carries no note of its own; say why it is withdrawn and where the work went"
while IFS= read -r r; do refuse_line "$r"; done < <(tone_refusals "$body" 0 "a close note is one to three")

refargs=("$repo" "$body"); [ -n "$clone" ] && refargs+=(--clone "$clone")
if ! refs=$(bash "$here/ref-check.sh" "${refargs[@]}" 2>&1); then
  refuse close-reference-not-found "it names something that does not exist: $(printf '%s\n' "$refs" | grep 'NOT FOUND' | tr -s ' ' | tr '\n' ';')"
fi

user="${HOUSEBROKEN_USER:-$(gh api user --jq .login 2>/dev/null)}"
[ -n "$user" ] || { refused close-gh-unauthenticated "gh is not authenticated, so whose pull request this is cannot be read" >&2; exit 2; }
fork_owner=""; fork=""; branch=""
if pr=$(gh pr view "$num" --repo "$repo" --json author,state,headRefName,headRepository,headRepositoryOwner 2>/dev/null); then
  author=$(printf '%s' "$pr" | jq -r '.author.login // "?"' | tr -d '\r')
  state=$(printf '%s' "$pr" | jq -r '.state // "?"' | tr -d '\r')
  fork_owner=$(printf '%s' "$pr" | jq -r '.headRepositoryOwner.login // ""' | tr -d '\r')
  fork=$(printf '%s' "$pr" | jq -r '.headRepository.name // ""' | tr -d '\r')
  branch=$(printf '%s' "$pr" | jq -r '.headRefName // ""' | tr -d '\r')
  [ "$author" = "$user" ] || refuse close-not-yours "$repo#$num is $author's, not yours"
  [ "$state" = "OPEN" ] || refuse close-not-open "$repo#$num is $state; only an open pull request is closed"
else
  refuse close-thread-unreadable "cannot read $repo#$num, so whose it is and whether it is open are unknown"
fi

log="$home/replies/${repo%%/*}-${repo##*/}.log"
if [ -f "$log" ]; then
  last=$(tail -1 "$log" | awk '{print $1}')
  since=$(( $(date -u +%s) - ${last:-0} ))
  [ "$since" -ge 600 ] || refuse close-too-soon-after-last "your last comment on $repo went out ${since}s ago; space them ten minutes apart"
fi

if [ -n "$reasons" ]; then
  refused close-not-ready "the close of $repo#$num is not ready:$reasons" >&2
  exit 2
fi
claims=$(bash "$here/claim-check.sh" "$body" 2>&1) || printf 'Posting these claims, which step 10 had you re-derive with housebroken claims first:\n%s\n' "$claims" >&2

if [ "${CLOSE_DRY:-0}" = "1" ]; then
  echo "DRY RUN, not closed: $repo#$num with $body"
  exit 0
fi
# The note goes out on its own, as the file's bytes, and is logged the moment it
# is public: gh pr close --comment posts the comment before it closes, so a close
# that failed there would leave the note up with nothing logged, and a retry
# would post it twice.
if ! gh api "repos/$repo/issues/$num/comments" -F "body=@$body" --jq .html_url; then
  echo "FAILED: the note was not posted on $repo#$num, which is still open; nothing was recorded" >&2
  exit 2
fi
mkdir -p "$home/replies"
printf '%s %s#%s\n' "$(date -u +%s)" "$repo" "$num" >> "$log"
if ! gh pr close "$num" --repo "$repo"; then
  echo "FAILED: the note is on $repo#$num but it is still open; read it before trying again" >&2
  exit 2
fi
rc=0
bash "$here/notes.sh" "$repo" add "we closed #$num: $(printf '%s' "$own" | clean_line | cut -c1-200)" || rc=1
if [ "$fork_owner" = "$user" ] && [ -n "$fork" ] && [ -n "$branch" ]; then
  if ! drop_fork_branch "$user" "$fork" "$branch" "CLOSED $repo#$num" 0; then
    echo "housebroken hygiene deletes it on its next run" >&2
    rc=1
  fi
fi
echo "closed $repo#$num"
exit "$rc"
