#!/bin/bash
# comment-check.sh - refuse a comment added to somebody else's code.
#
# The rule: a branch adds no comment to a repository it does not own. A
# comment that is already there may be reworded, a new file may open with the
# licence header its neighbours carry, and a maintainer who asks for
# documentation is answered; everything else is a refusal. Test files count.
#
# What passes:
#   reworded   an added comment line that replaces a removed comment line in
#              the same hunk, one for one
#   header     the comment block a new file opens with, before its first line
#              of code, when the files with its extension beside it at the
#              base open with a comment too
#   asked      --asked URL, the maintainer's request for documentation; every
#              refusal is then printed as a CHECK naming that URL, and the
#              branch passes
#
# Usage:
#   bash comment-check.sh [CLONE] --base REF [--asked URL]
#   bash comment-check.sh --help
#
# Exits 0 when nothing is refused, 1 on a refusal, 2 on a usage error.
# Comment syntax is recognised by extension: // /* * for the C family, Go,
# Rust, Java, Kotlin, Swift, C#, Scala, Dart, PHP, JavaScript and TypeScript;
# # for Python, Ruby, shell, YAML, TOML, CMake, Perl, R and Elixir; -- for SQL,
# Lua and Haskell; ; for assembly and Lisps. Docstrings and comments that share
# a line with code are not measured, and files with any other extension are
# not measured.
set -u

usage() { awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"; }

clone="."
base=""
asked=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --base)
      shift
      base="${1:-}"
      [ -n "$base" ] || { echo "comment-check.sh: --base needs a ref" >&2; exit 2; }
      ;;
    --base=*) base="${1#--base=}" ;;
    --asked)
      shift
      asked="${1:-}"
      [ -n "$asked" ] || { echo "comment-check.sh: --asked needs the URL of the maintainer's ask" >&2; exit 2; }
      ;;
    --asked=*) asked="${1#--asked=}" ;;
    -*) echo "comment-check.sh: unknown option $1" >&2; exit 2 ;;
    *) clone="$1" ;;
  esac
  shift
done
[ -n "$base" ] || { echo "comment-check.sh: --base REF is required" >&2; exit 2; }
cd "$clone" 2>/dev/null || { echo "comment-check.sh: $clone is not a directory" >&2; exit 2; }
mb=$(git merge-base "$base" HEAD 2>/dev/null) || { echo "comment-check.sh: no merge base between $base and HEAD" >&2; exit 2; }

comment_re() {
  case "$1" in
    c|cc|cpp|cxx|h|hh|hpp|go|rs|java|kt|kts|swift|cs|scala|groovy|gradle|dart|php|js|jsx|mjs|cjs|ts|tsx)
      printf '%s' '^[[:space:]]*(//|/[*]|[*]|[*]/)' ;;
    py|rb|sh|bash|zsh|yaml|yml|toml|cmake|pl|r|ex|exs|tf) printf '%s' '^[[:space:]]*#' ;;
    sql|lua|hs) printf '%s' '^[[:space:]]*--' ;;
    asm|s|lisp|el|clj) printf '%s' '^[[:space:]]*;' ;;
    *) return 1 ;;
  esac
}

# Do the files with this extension beside PATH at the base open with a comment?
siblings_open_with_comment() {
  local f="$1" ext="$2" re="$3" dir s
  dir="${f%/*}"; [ "$dir" = "$f" ] && dir=""
  while IFS= read -r s; do
    case "${s##*/}" in
      *."$ext") [ "$s" != "$f" ] || continue
        if git show "$mb:$s" 2>/dev/null | head -15 | grep -Eq "$re"; then return 0; fi ;;
    esac
  done < <(if [ -n "$dir" ]; then git ls-tree --name-only "$mb" -- "$dir/"; else git ls-tree --name-only "$mb"; fi)
  return 1
}

work=$(mktemp -d) || exit 2
trap 'rm -rf "$work"' EXIT

refused=0
measured=0
report() {
  if [ -n "$asked" ]; then
    echo "CHECK: $* (asked for in $asked)"
  else
    echo "REFUSED: $*"
    refused=1
  fi
}

while IFS= read -r f; do
  [ -n "$f" ] || continue
  name="${f##*/}"
  case "$name" in *.*) ext=$(printf '%s' "${name##*.}" | tr '[:upper:]' '[:lower:]') ;; *) continue ;; esac
  re=$(comment_re "$ext") || continue
  measured=$((measured + 1))
  existed=0
  git cat-file -e "$mb:$f" 2>/dev/null && existed=1
  header_ok=0
  if [ "$existed" -eq 0 ] && siblings_open_with_comment "$f" "$ext" "$re"; then header_ok=1; fi

  # One row per changed line: sign, hunk number, new line number, text.
  git diff -U0 "$mb" HEAD -- "$f" | awk '
    /^@@ /                 { h++; split($3, a, ","); ln = substr(a[1], 2) + 0; next }
    h == 0                 { next }
    /^\+/                  { print "+\t" h "\t" ln "\t" substr($0, 2); ln++; next }
    /^-/                   { print "-\t" h "\t0\t" substr($0, 2); next }
  ' > "$work/rows"
  [ -s "$work/rows" ] || continue

  # An added comment line is refused unless a removed comment line in the same
  # hunk pays for it, or it is in the leading comment block of a new file whose
  # neighbours open with one.
  awk -F'\t' -v re="$re" -v hdr="$header_ok" -v file="$f" '
    $1 == "-" { if ($4 ~ re) rem[$2]++; next }
    $1 == "+" {
      if ($4 ~ re) {
        if (rem[$2] > 0) { rem[$2]--; next }
        if (hdr == 1 && !code_seen) next
        text = $4; sub(/^[[:space:]]+/, "", text)
        print file ":" $3 " adds a comment: " text
      } else if ($4 !~ /^[[:space:]]*$/) code_seen = 1
    }
  ' "$work/rows" > "$work/hits"
  while IFS= read -r hit; do
    [ -n "$hit" ] && report "$hit"
  done < "$work/hits"
done < <(git diff --name-only --diff-filter=d "$mb" HEAD)

if [ "$refused" -ne 0 ]; then
  echo "comment-check: refused. A comment goes into someone else's code only when its maintainer asks for it."
  exit 1
fi
echo "comment-check: $measured files measured, no comment added."
