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
#   moved      an added comment line whose text, trimmed, is a removed comment
#              line's anywhere else in the diff, deleted files included, one for
#              one; each move is printed as a CHECK naming where it came from
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
# Rust, Java, Kotlin, Swift, C#, Scala, Dart, PHP, JavaScript, TypeScript, CSS,
# Objective-C and protobuf; # for Python, Ruby, shell, YAML, TOML, CMake, Perl,
# R, Elixir, Terraform, Makefile and Dockerfile; -- for SQL, Lua and Haskell; ;
# for assembly and Lisps. A shebang on line one is not a comment, and a leading
# * is one only when a space follows, so *out = 0; is code. Docstrings, comments
# that share a line with code, and files of any other kind are not measured.
set -u
# shellcheck source=scripts/refuse.sh
. "$(cd "$(dirname "$0")" && pwd)/refuse.sh"

usage() { awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"; }
# shellcheck source=scripts/common.sh
. "$(cd "$(dirname "$0")" && pwd)/common.sh"

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
cd "$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "comment-check.sh: $clone is not a git clone" >&2; exit 2; }
mb=$(git merge-base "$base" HEAD 2>/dev/null) || { echo "comment-check.sh: no merge base between $base and HEAD" >&2; exit 2; }

comment_re() {
  case "$1" in
    c|cc|cpp|cxx|h|hh|hpp|m|mm|go|rs|java|kt|kts|swift|cs|scala|groovy|gradle|dart|php|js|jsx|mjs|cjs|ts|tsx|mts|cts|css|scss|less|proto)
      printf '%s' '^[[:space:]]*(//|/[*]|[*]/|[*]([[:space:]]|$))' ;;
    py|pyi|rb|sh|bash|zsh|yaml|yml|toml|cmake|pl|r|ex|exs|tf) printf '%s' '^[[:space:]]*#' ;;
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

found=0
measured=0
report() {
  if [ -n "$asked" ]; then
    echo "CHECK: $* (asked for in $asked)"
  else
    refused comment-check-comment-added "$*"
    found=1
  fi
}

ext_of() {
  local name="${1##*/}"
  case "$name" in
    Makefile|GNUmakefile|Dockerfile|CMakeLists.txt) echo sh ;;
    *.*) printf '%s\n' "${name##*.}" | tr '[:upper:]' '[:lower:]' ;;
    *) return 1 ;;
  esac
}

namestat=$(gdiff --name-status -M --diff-filter=d "$mb" HEAD)
renames=$(printf '%s\n' "$namestat" | awk -F'\t' 'NF == 3 {print $2 "\t" $3}')

# Every file writes two kinds of row to $work/all, fields split by \034 so a tab
# in a comment cannot shift them: H, an added comment nothing in its hunk paid
# for, and R, a removed comment no added line in its hunk took. An R pays for
# an H of the same trimmed text once the whole diff is read: a move.
: > "$work/all"
while IFS= read -r f; do
  [ -n "$f" ] || continue
  ext=$(ext_of "$f") || continue
  re=$(comment_re "$ext") || continue
  measured=$((measured + 1))
  # Both sides of a rename, or git reads every existing comment as added.
  spec=("$f")
  old=$(renamed_from "$f")
  [ -z "$old" ] || spec=("$old" "$f")
  existed=0
  git cat-file -e "$mb:${old:-$f}" 2>/dev/null && existed=1
  header_ok=0
  if [ "$existed" -eq 0 ] && siblings_open_with_comment "$f" "$ext" "$re"; then header_ok=1; fi

  # One row per changed line: sign, hunk number, new line number, text.
  gdiff -U0 -M "$mb" HEAD -- "${spec[@]}" | awk '
    /^@@ /                 { h++; split($3, a, ","); ln = substr(a[1], 2) + 0; next }
    h == 0                 { next }
    /^\+/                  { print "+\t" h "\t" ln "\t" substr($0, 2); ln++; next }
    /^-/                   { print "-\t" h "\t0\t" substr($0, 2); next }
  ' > "$work/rows"
  [ -s "$work/rows" ] || continue

  # An added comment line is unpaid unless a removed comment line in the same
  # hunk pays for it, the one of the same text first, or it is in the leading
  # comment block of a new file whose neighbours open with one. Every added line
  # between an added /* and its */ is a comment, whatever it starts with. The
  # text is everything after the third tab, not a field: a tab-indented line
  # would split there.
  blk=0
  case "$re" in *'/[*]'*) blk=1 ;; esac
  awk -F'\t' -v re="$re" -v hdr="$header_ok" -v file="$f" -v blk="$blk" '
    function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
    function take(h, t,   i, pick) {
      pick = 0
      for (i = 1; i <= rn[h]; i++) if (!ru[h, i]) { if (rt[h, i] == t) { pick = i; break } if (!pick) pick = i }
      if (pick) ru[h, pick] = 1
      return pick
    }
    { line = $0; for (i = 0; i < 3; i++) line = substr(line, index(line, "\t") + 1) }
    $1 == "-" { if (line ~ re) { n = ++rn[$2]; rt[$2, n] = trim(line) } next }
    $1 == "+" {
      iscom = (line ~ re) && !($3 == 1 && line ~ /^#!/)
      if (blk == 1) {
        if ($3 != prev + 1) inblock = 0
        prev = $3
        if (inblock) { iscom = 1; if (line ~ /[*]\//) inblock = 0 }
        else if (line ~ /^[[:space:]]*\/[*]/ && line !~ /[*]\//) inblock = 1
      }
      if (iscom) {
        t = trim(line)
        if (take($2, t)) next
        if (hdr == 1 && !code_seen) next
        text = line; sub(/^[[:space:]]+/, "", text)
        print "H\034" t "\034" file ":" $3 "\034" file ":" $3 " adds a comment: " text
      } else if (line !~ /^[[:space:]]*$/) code_seen = 1
    }
    END { for (h in rn) for (i = 1; i <= rn[h]; i++) if (!ru[h, i]) print "R\034" rt[h, i] "\034" file }
  ' "$work/rows" >> "$work/all"
done < <(printf '%s\n' "$namestat" | awk -F'\t' 'NF == 3 {print $3} NF == 2 {print $2}')

# A file the branch deletes gives up every comment it had.
while IFS= read -r f; do
  [ -n "$f" ] || continue
  ext=$(ext_of "$f") || continue
  re=$(comment_re "$ext") || continue
  git show "$mb:$f" 2>/dev/null | awk -v re="$re" -v file="$f" '
    $0 ~ re && !(NR == 1 && /^#!/) { t = $0; sub(/^[[:space:]]+/, "", t); sub(/[[:space:]]+$/, "", t); print "R\034" t "\034" file }
  ' >> "$work/all"
done < <(gdiff --name-only --diff-filter=D "$mb" HEAD)

# Read twice: every R first, then each H takes one R of its text or is refused.
awk 'BEGIN { FS = "\034" }
  NR == FNR { if ($1 == "R") { c[$2]++; from[$2, c[$2]] = $3 } next }
  $1 == "H" { if (u[$2] < c[$2]) { u[$2]++; print "M\034" $3 " moves a comment from " from[$2, u[$2]] } else print "X\034" $4 }
' "$work/all" "$work/all" > "$work/verdicts"
while IFS= read -r row; do
  case "$row" in
    M*) echo "CHECK: ${row#M?}" ;;
    X*) report "${row#X?}" ;;
  esac
done < "$work/verdicts"

if [ "$found" -ne 0 ]; then
  echo "comment-check: refused. A comment goes into someone else's code only when its maintainer asks for it."
  exit 1
fi
echo "comment-check: $measured files measured, no comment added."
