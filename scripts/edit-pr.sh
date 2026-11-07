#!/bin/bash
# edit-pr.sh - the only way a filed pull request's body or title is changed.
#
# A body with a wrong example in it sat on a stale pull request for sixty
# days: the hook refuses `gh pr edit` outside a gate, and there was no gate,
# so the correction could only be made by hand in the browser, where no
# check reads it. This is that gate. The new text passes what a filing
# passes: the policy printout is read and is not BAN or UNREAD, the prose
# carries no footer, trailer or typographic dash, the project's template is
# kept and the body holds to 120 words of its own, the policy's disclosure is
# in it, and every reference it names exists. The pull request is open and
# yours, edits to one repository are ten minutes apart, and the copy
# verify-filed-pr.sh compares GitHub's body against is replaced, with the
# text it replaced kept beside it.
#
# Usage:
#   bash edit-pr.sh owner/repo NUMBER --body-file FILE [--title TEXT] [--clone DIR]
#   bash edit-pr.sh --help
#
# --clone names the clone whose files and commits the body may refer to.
#
# Environment:
#   HOUSEBROKEN_HOME  work directory, default $HOME/.housebroken; the policy
#                     printout and template are read from it, the filed copy
#                     is kept under filed/, edits are logged to
#                     edits/<owner>-<repo>.log for the spacing
#   HOUSEBROKEN_USER  your login, read from gh when unset
#   EDIT_PR_DRY       1 prints the gh command and edits nothing
#
# Exits 0 when edited (or on a dry run), 2 on a refusal or a usage error.
set -u

usage() { awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"; }
case "${1:-}" in --help|-h) usage; exit 0 ;; esac

repo="${1:-}"; num="${2:-}"
case "$repo" in */*) ;; *) echo "REFUSED: name the repository as owner/repo" >&2; exit 2 ;; esac
case "$num" in ''|*[!0-9]*) echo "REFUSED: name the pull request number" >&2; exit 2 ;; esac
shift 2
bodyfile=""; title=""; clone=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --body-file) bodyfile="${2:-}"; shift ;;
    --title) title="${2:-}"; shift ;;
    --clone) clone="${2:-}"; shift ;;
    *) echo "REFUSED: unknown argument $1" >&2; exit 2 ;;
  esac
  shift
done
[ -f "$bodyfile" ] || { echo "REFUSED: --body-file names no file" >&2; exit 2; }
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=scripts/common.sh
. "$here/common.sh"
home="${HOUSEBROKEN_HOME:-$HOME/.housebroken}"

# The policy is read as a filing reads it, whatever its age: a ban did not lift
# because the pull request is already open.
policy="$home/policy/policy-${repo%%/*}-${repo##*/}.md"
[ -f "$policy" ] || { echo "REFUSED: no policy printout at $policy - run check-ai-policy.sh $repo --out first" >&2; exit 2; }
policy_result=$(grep -m1 '^RESULT: ' "$policy" | awk '{print $2}')
case "$policy_result" in
  BAN) echo "REFUSED: $repo forbids AI-written contributions ($policy); nothing of ours belongs there" >&2; exit 2 ;;
  DISCLOSE|CLEAN|MENTION) ;;
  UNREAD) echo "REFUSED: $policy reads UNREAD - rerun check-ai-policy.sh $repo --out" >&2; exit 2 ;;
  *) echo "REFUSED: $policy has no RESULT line - rerun check-ai-policy.sh $repo --out" >&2; exit 2 ;;
esac

check_text "body file $bodyfile" "$(cat "$bodyfile")"
check_text "--title" "$title"
prose_gate "$repo" "$bodyfile" "$home"
if [ "$policy_result" = "DISCLOSE" ] && ! discloses "$bodyfile" "$template"; then
  echo "REFUSED: $repo requires AI use to be disclosed ($policy) and the body does not name it" >&2
  exit 2
fi
refargs=("$repo" "$bodyfile"); [ -n "$clone" ] && refargs+=(--clone "$clone")
if ! refs=$(bash "$here/ref-check.sh" "${refargs[@]}" 2>&1); then
  echo "REFUSED: the body names something that does not exist:" >&2
  printf '%s\n' "$refs" | grep -E 'NOT FOUND|REFUSED' >&2
  exit 2
fi

user="${HOUSEBROKEN_USER:-$(gh api user --jq .login 2>/dev/null)}"
[ -n "$user" ] || { echo "REFUSED: gh is not authenticated" >&2; exit 2; }
pr=$(gh pr view "$num" --repo "$repo" --json author,state,headRefOid 2>/dev/null) || { echo "REFUSED: cannot read $repo#$num" >&2; exit 2; }
author=$(printf '%s' "$pr" | jq -r '.author.login // "?"' | tr -d '\r')
state=$(printf '%s' "$pr" | jq -r '.state // "?"' | tr -d '\r')
head=$(printf '%s' "$pr" | jq -r '.headRefOid // ""' | tr -d '\r')
[ "$author" = "$user" ] || { echo "REFUSED: $repo#$num is $author's, not yours" >&2; exit 2; }
[ "$state" = "OPEN" ] || { echo "REFUSED: $repo#$num is $state; only an open pull request is edited" >&2; exit 2; }

log="$home/edits/${repo%%/*}-${repo##*/}.log"
if [ -f "$log" ]; then
  last=$(tail -1 "$log" | awk '{print $1}')
  since=$(( $(date -u +%s) - ${last:-0} ))
  [ "$since" -ge 600 ] || { echo "REFUSED: your last edit on $repo went out ${since}s ago; space them ten minutes apart" >&2; exit 2; }
fi
claims=$(bash "$here/claim-check.sh" "$bodyfile" 2>&1) || printf 'Filing these claims, which step 6 had you re-derive with housebroken claims first:\n%s\n' "$claims" >&2

args=(--body-file "$bodyfile"); [ -n "$title" ] && args+=(--title "$title")
if [ "${EDIT_PR_DRY:-0}" = "1" ]; then
  printf 'DRY RUN, not edited:\ngh pr edit %s --repo %s' "$num" "$repo"
  for arg in "${args[@]}"; do printf ' %q' "$arg"; done
  printf '\n'
  exit 0
fi
# The copy verify-filed-pr.sh compares against is now this text; what it
# replaced stays beside it, so the change can be read back.
mkdir -p "$home/filed" "$home/edits"
kept="$home/filed/${repo%%/*}-${repo##*/}-$head.md"
[ ! -f "$kept" ] || mv "$kept" "$kept.prev-$(date -u +%s)"
cp "$bodyfile" "$kept"
gh pr edit "$num" --repo "$repo" "${args[@]}" || exit 2
printf '%s %s#%s\n' "$(date -u +%s)" "$repo" "$num" >> "$log"
