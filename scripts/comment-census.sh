#!/bin/bash
# comment-census.sh - added code lines against added comment lines, per branch,
# plus a neighbourhood check on every added comment.
#
# A patch that carries a paragraph of comments into a file that has none reads
# as machine-written and gets closed. This counts, for every branch in every
# clone under a directory, the added non-comment lines and the added comment
# lines, so a pull request can be made to match the comment density of the file
# it lands in. Three maintainers asked for exactly this, in three separate
# reviews, before it became a script.
#
# A fourth asked for more. On google/benchmark #2294 the maintainer called a
# single comment above a two-line fix "unnecessary comment" in a file whose
# overall ratio was healthy: he judged the comment against the function around
# it, not against the file. So every added comment line is also checked against
# its neighbourhood - the 20 lines above and the 20 lines below it on the
# branch, excluding the added lines themselves. If none of those lines is a
# comment, the added comment is flagged whatever the file ratio says. A shebang
# or a licence header in the first 15 lines does not rescue a comment added
# further down.
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
# Neighbourhood detection picks the comment family from the file extension:
# //, /* */ for .c .cc .cpp .h .hpp .go .rs .java .kt .swift .ts .js, # for
# .py .rb .sh .toml .yaml .yml, and ; for .asm .s .lisp .el .clj. A file with
# any other extension gets no neighbourhood check.
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

paths=(. ':(exclude)*test*' ':(exclude)*Test*' ':(exclude)*_test.go' ':(exclude)Tests/*' ':(exclude)*.md' ':(exclude)*.sum')

# Comment family for an extension, as an ERE. Returns 1 for unknown extensions.
comment_re() {
  case "$1" in
    c|cc|cpp|h|hpp|go|rs|java|kt|swift|ts|js) printf '%s' '^[[:space:]]*(//|/[*]|[*]|[*]/)' ;;
    py|rb|sh|toml|yaml|yml) printf '%s' '^[[:space:]]*#' ;;
    asm|s|lisp|el|clj) printf '%s' '^[[:space:]]*;' ;;
    *) return 1 ;;
  esac
}

flagfile=$(mktemp) || exit 1
trap 'rm -f "$flagfile"' EXIT

flag_scan() {
  local d="$1" base="$2" br="$3" name="$4"
  local map content addedset cur row f ln text e re lo hi body
  local rows=()
  map=$(mktemp) || return 1
  content=$(mktemp) || { rm -f "$map"; return 1; }
  addedset=$(mktemp) || { rm -f "$map" "$content"; return 1; }

  git -C "$d" diff --unified=0 "$base..$br" -- "${paths[@]}" | awk '
    /^\+\+\+ / { file=""; if (substr($0,1,6) == "+++ b/") file=substr($0,7); next }
    /^--- /    { next }
    /^@@ /     { split($3, a, ","); ln=substr(a[1],2)+0; next }
    /^\+/      { if (file != "") { print file "\t" ln "\t" substr($0,2); ln++ } next }
    /^ /       { ln++ }
  ' > "$map"

  mapfile -t rows < "$map"
  cur=""
  for row in ${rows[@]+"${rows[@]}"}; do
    IFS=$'\t' read -r f ln text <<< "$row"
    e="${f##*.}"
    re=$(comment_re "$e") || continue
    printf '%s\n' "$text" | grep -qE "$re" || continue
    if [ "$f" != "$cur" ]; then
      cur="$f"
      git -C "$d" show "$br:$f" > "$content" 2>/dev/null || : > "$content"
      awk -F'\t' -v want="$f" '$1 == want { print $2 }' "$map" > "$addedset"
    fi
    lo=$((ln - 20))
    [ "$lo" -lt 1 ] && lo=1
    hi=$((ln + 20))
    body=0
    [ "$ln" -gt 15 ] && body=1
    if ! awk -v lo="$lo" -v hi="$hi" -v body="$body" -v self="$ln" -v re="$re" -v af="$addedset" '
      BEGIN { found=0; while ((getline a < af) > 0) added[a+0]=1 }
      NR < lo { next }
      NR > hi { exit }
      NR == self { next }
      added[NR] { next }
      body == 1 && NR <= 15 { next }
      $0 ~ re { found=1; exit }
      END { exit (found ? 0 : 1) }
    ' "$content"; then
      printf 'FLAG %s %s %s:%s %s\n' "$name" "$br" "$f" "$ln" "$text" >> "$flagfile"
    fi
  done

  rm -f "$map" "$content" "$addedset"
}

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
    added=$(git -C "$d" diff "$base..$br" -- "${paths[@]}" | grep '^+' | grep -v '^+++' || true)
    if [ -z "$added" ]; then
      code=0; cmnt=0
    else
      code=$(printf '%s\n' "$added" | grep -v -E '^\+\s*(//|/\*|\*|#|///|\*/)' | grep -c -v -E '^\+\s*$' || true)
      cmnt=$(printf '%s\n' "$added" | grep -c -E '^\+\s*(//|/\*|\*|///|\*/)' || true)
    fi
    tests=$(git -C "$d" diff "$base..$br" --numstat | awk '/[Tt]est/{s+=$1} END{print s+0}')
    printf '%-28s %-36s %5s %5s %5s\n' "$name" "$br" "$code" "$cmnt" "$tests"
    flag_scan "$d" "$base" "$br" "$name"
  done < <(git -C "$d" for-each-ref --format='%(refname:short)' refs/heads/)
done

if [ "$found" = 0 ]; then
  echo "comment-census.sh: no git clones found under $root" >&2
  exit 1
fi

if [ -s "$flagfile" ]; then
  echo
  cat "$flagfile"
fi
echo
echo "$(grep -c '^FLAG ' "$flagfile" || true) comment lines added into comment-free neighbourhoods"
