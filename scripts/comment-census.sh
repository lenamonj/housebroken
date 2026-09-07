#!/bin/bash
# comment-census.sh - added code lines against added comment lines, per branch.
#
# A patch that carries a paragraph of comments into a file that has none reads
# as machine-written and gets closed. This counts, for every branch in every
# clone under a directory, the added non-comment lines and the added comment
# lines, so a pull request can be made to match the comment density of the file
# it lands in. Three maintainers asked for exactly this, in three separate
# reviews, before it became a script.
#
# Usage:
#   bash comment-census.sh [CLONE_ROOT]
#   bash comment-census.sh --help
#
# CLONE_ROOT is any directory whose immediate subdirectories are git clones.
# Defaults to $HOUSEBROKEN_CLONES, then to $HOUSEBROKEN_HOME/clones.
#
# Environment:
#   HOUSEBROKEN_CLONES  default clone root
#   HOUSEBROKEN_HOME    workshop root, default $HOME/.housebroken
#
# Assumes: each clone has an origin remote whose default branch is discoverable
# (origin/HEAD, else origin/main, else origin/master); every other local branch
# is a candidate patch. Tests, markdown and lock files are excluded from the
# code and comment counts. Comment detection covers //, /* */, * and #.
set -u

usage() {
  sed -n '2,/^set -u$/p' "$0" | sed 's/^# \{0,1\}//; /^set -u$/d'
}

case "${1:-}" in
  --help|-h) usage; exit 0 ;;
esac

HOUSEBROKEN_HOME="${HOUSEBROKEN_HOME:-$HOME/.housebroken}"
root="${1:-${HOUSEBROKEN_CLONES:-$HOUSEBROKEN_HOME/clones}}"

if [ ! -d "$root" ]; then
  echo "comment-census.sh: not a directory: $root" >&2
  echo "give a clone root as an argument or set HOUSEBROKEN_CLONES" >&2
  exit 1
fi

printf '%-28s %-36s %5s %5s %5s\n' repo branch code cmnt tests

found=0
for d in "$root"/*/; do
  [ -d "$d/.git" ] || continue
  found=1
  name=$(basename "$d")
  base=$(git -C "$d" symbolic-ref -q --short refs/remotes/origin/HEAD || true)
  if [ -z "$base" ]; then
    if git -C "$d" rev-parse --verify -q origin/main >/dev/null; then
      base=origin/main
    elif git -C "$d" rev-parse --verify -q origin/master >/dev/null; then
      base=origin/master
    else
      echo "comment-census.sh: no default branch in $d, skipped" >&2
      continue
    fi
  fi
  default_branch="${base#origin/}"
  while read -r br; do
    [ -n "$br" ] || continue
    [ "$br" = "$default_branch" ] && continue
    [ "$(git -C "$d" rev-list --count "$base..$br")" = "0" ] && continue
    added=$(git -C "$d" diff "$base..$br" -- . ':(exclude)*test*' ':(exclude)*Test*' ':(exclude)*_test.go' ':(exclude)Tests/*' ':(exclude)*.md' ':(exclude)*.sum' | grep '^+' | grep -v '^+++' || true)
    if [ -z "$added" ]; then
      code=0; cmnt=0
    else
      code=$(printf '%s\n' "$added" | grep -v -E '^\+\s*(//|/\*|\*|#|///|\*/)' | grep -c -v -E '^\+\s*$' || true)
      cmnt=$(printf '%s\n' "$added" | grep -c -E '^\+\s*(//|/\*|\*|///|\*/)' || true)
    fi
    tests=$(git -C "$d" diff "$base..$br" --numstat | awk '/[Tt]est/{s+=$1} END{print s+0}')
    printf '%-28s %-36s %5s %5s %5s\n' "$name" "$br" "$code" "$cmnt" "$tests"
  done < <(git -C "$d" for-each-ref --format='%(refname:short)' refs/heads/)
done

if [ "$found" = 0 ]; then
  echo "comment-census.sh: no git clones found under $root" >&2
  exit 1
fi
