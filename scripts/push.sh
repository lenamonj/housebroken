#!/bin/bash
# push.sh - the only way a rework reaches a filed pull request's branch.
#
# A push to a filed branch is a new head in front of the maintainer, and it
# is held to what the first filing was: a branch-check stamp and a POST AS IS
# review of that exact head. Two pushes in one sitting read as indecision,
# and a force push rewrites what the maintainer may already have reviewed,
# so a second push to the branch within thirty minutes is refused, and a
# push that is not a fast-forward goes only with --rework naming why. The
# branch must already be on the remote: a first push is a plain git push,
# and a remote that cannot be read is a refusal, not a plain push.
#
# Usage:
#   bash push.sh owner/repo [CLONE] [--remote NAME] [--rework 'REASON']
#   bash push.sh --help
#
# CLONE defaults to the current directory and NAME to origin, the fork the
# pull request's branch lives on. The branch is the clone's current branch.
#
# Environment:
#   HOUSEBROKEN_HOME  work directory, default $HOME/.housebroken; pushes are
#                     logged to pushes/<owner>-<repo>-<branch>.log
#   PUSH_DRY          1 prints the push command and pushes nothing
#
# Exits 0 when pushed (or on a dry run), 2 on a refusal or a usage error.
set -u

usage() { awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"; }
case "${1:-}" in --help|-h) usage; exit 0 ;; esac

repo="${1:-}"
case "$repo" in */*) ;; *) echo "REFUSED: name the upstream repository as owner/repo" >&2; exit 2 ;; esac
shift
clone="."; remote="origin"; rework=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --remote) remote="${2:-}"; shift ;;
    --rework) rework="${2:-}"; [ -n "$rework" ] || { echo "REFUSED: --rework needs the reason" >&2; exit 2; }; shift ;;
    -*) echo "REFUSED: unknown option $1" >&2; exit 2 ;;
    *) clone="$1" ;;
  esac
  shift
done
here=$(cd "$(dirname "$0")" && pwd)
if ! cd "$clone" 2>/dev/null || ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "REFUSED: $clone is not a git clone" >&2
  exit 2
fi
home="${HOUSEBROKEN_HOME:-$HOME/.housebroken}"
head=$(git rev-parse HEAD)
branch=$(git rev-parse --abbrev-ref HEAD)
[ "$branch" != "HEAD" ] || { echo "REFUSED: the clone is on no branch" >&2; exit 2; }

[ -f "$home/branch-checks/$head" ] || { echo "REFUSED: branch-check.sh has not passed head ${head:0:12}" >&2; exit 2; }
review="$home/reviews/review-${repo%%/*}-${repo##*/}-${head:0:12}.md"
[ -f "$review" ] || { echo "REFUSED: no review of head ${head:0:12} at $review" >&2; exit 2; }
bash "$here/review.sh" check "$review" --clone . >/dev/null || exit 2

log="$home/pushes/${repo%%/*}-${repo##*/}-${branch//\//-}.log"
if [ -f "$log" ]; then
  last=$(tail -1 "$log" | awk '{print $1}')
  since=$(( $(date -u +%s) - ${last:-0} ))
  if [ "$since" -lt 1800 ]; then
    echo "REFUSED: the last push to $branch was ${since}s ago; settle every refusal and push once, in $(( (1800 - since) / 60 + 1 )) min" >&2
    exit 2
  fi
fi

if ! git fetch -q "$remote" "$branch" 2>/dev/null; then
  echo "REFUSED: cannot read $branch on $remote: a rework goes to the remote the pull request's branch is on (--remote NAME); a first push is a plain git push" >&2
  exit 2
fi
theirs=$(git rev-parse FETCH_HEAD)
[ "$theirs" != "$head" ] || { echo "REFUSED: $remote $branch is already at ${head:0:12}; nothing to push" >&2; exit 2; }
force=()
if ! git merge-base --is-ancestor "$theirs" HEAD; then
  if [ -z "$rework" ]; then
    echo "REFUSED: this push rewrites $branch on $remote, which the maintainer may have reviewed; pass --rework 'why' if it must" >&2
    exit 2
  fi
  force=(--force-with-lease="$branch:$theirs")
fi

if [ "${PUSH_DRY:-0}" = "1" ]; then
  echo "DRY RUN, not pushed: git push ${force[*]} $remote HEAD:refs/heads/$branch"
  exit 0
fi
git push "${force[@]}" "$remote" "HEAD:refs/heads/$branch" || exit 2
mkdir -p "$home/pushes"
printf '%s %s %s\n' "$(date -u +%s)" "$head" "${rework:-fast-forward}" >> "$log"
