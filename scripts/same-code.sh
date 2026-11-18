#!/bin/bash
# same-code.sh - every other place the base holds an expression the branch
# replaces, or makes a call the branch replaces.
#
# On mholt/PapaParse #1133 the patch replaced a per-chunk toString in the
# stream reader that had been reported, and left the same call in the piped
# reader ninety lines below, a path the README also documents. It went
# unnoticed for 114 days, until our own review of a rework found it. A fix
# belongs at every site with the same code, and the day to look is the day of
# filing. This script reads the lines the branch removes, works out what each
# one lost, and lists the other lines of the base that still hold it. It
# reports, it does not judge: the exit status is 0 whether or not anything was
# found.
#
# Usage:
#   bash same-code.sh [CLONE] --base REF
#   bash same-code.sh --help
#
# Output is one block per replaced expression: the line it was replaced on,
# then each other site as "  file:line  text". Then one block per replaced
# call, "file:line replaces a call to name(, also made at:" and its other
# callers. An expression or a call on more than ten other lines is an idiom,
# not a fault: those are named together on one line and their sites are not
# listed. A summary count of the listed sites ends it. Exits 2 on a usage
# error, or when git cannot diff the branch or search the base: a listing is
# never printed short.
#
# How an expression is found. Within a hunk the removed lines pair with the
# added lines in order. A pair is cut down to what the removed line does not
# share with its partner at the start and at the end, grown out to whole
# words and to the parenthesis that closes one it opens; a removed line with
# no partner is taken whole. What is left is searched for as fixed text across
# the tracked files of the merge base. A call is a name, dotted or not, with
# its opening parenthesis, where the name lies in what the line lost, a name
# the new line only lengthens included (encodeURI( replaced by
# encodeURIComponent(); it is searched for the same way, so the same call with
# other arguments is found.
# The lines the branch itself removes are never listed, and a removed line
# that the branch adds back word for word anywhere has moved, not been
# replaced.
#
# Known misses. It matches text, so the same fault through another variable
# or split over two lines is not listed: grep for the method or operator
# yourself. An expression under 12 characters, or with no three-letter word in
# it, is skipped as too common to mean anything, and so is a call whose name is
# under 5 characters with no dot in it, a control keyword, a removed comment
# line and every line of a deleted file. A call is not seen when it is generic
# (Name<T>( or name::<T>(), has a space before its parenthesis or no
# parenthesis at all (Ruby, shell), and one written through $ counts by the
# name after it only. Every replaced expression and call is one search of the
# base, with no limit, so a change of hundreds of lines in a large tree takes
# minutes. A site on a line over 500 characters
# is taken for minified or generated code and left out. A rewrite that shares
# nothing with the line it replaces is searched for whole and finds only exact
# copies.
set -u
# shellcheck source=scripts/common.sh
. "$(cd "$(dirname "$0")" && pwd)/common.sh"

usage() { awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"; }
bad_usage() { echo "same-code.sh: $1" >&2; exit 2; }

clone="." base=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --base) base="${2:-}"; shift ;;
    --base=*) base="${1#--base=}" ;;
    -*) bad_usage "unknown argument: $1" ;;
    *) clone="$1" ;;
  esac
  shift
done
[ -n "$base" ] || bad_usage "name the branch the pull request is filed against with --base REF"
cd "$clone" 2>/dev/null || bad_usage "$clone is not a directory"
top=$(git rev-parse --show-toplevel 2>/dev/null) || bad_usage "$clone is not a git clone"
cd "$top" || exit 2
mb=$(git merge-base "$base" HEAD 2>/dev/null) || bad_usage "no merge base between $base and HEAD"

work=$(mktemp -d) || exit 2
trap 'rm -rf "$work"' EXIT
sep=$(printf '\037')
: > "$work/own"
: > "$work/listed"

# Every removed line as "path:line" in $work/own, and on stdout each replaced
# expression (S) and each replaced call (C) once, with the path and line it was
# replaced on. The hunk header's counts say which lines are the hunk's, so a
# removed line that starts with -- is not a header.
gdiff -U0 -M --inter-hunk-context=0 --src-prefix=a/ --dst-prefix=b/ "$mb" HEAD > "$work/diff" || bad_usage "git could not diff $mb against HEAD"
awk -v own="$work/own" -v sep="$sep" '
  BEGIN {
    words = split("if for while switch catch function return typeof sizeof foreach using synchronized", listed, " ")
    for (i = 1; i <= words; i++) keyword[listed[i]] = 1
  }
  function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
  function word(c) { return c ~ /[A-Za-z0-9_]/ }
  function opens(s,    t) { t = s; return gsub(/\(/, "", s) - gsub(/\)/, "", t) }
  # Sets P and S, the lengths old shares with new at its start and its end.
  function cut(old, new,    lo, ln) {
    lo = length(old); ln = length(new); P = 0; S = 0
    while (P < lo && P < ln && substr(old, P + 1, 1) == substr(new, P + 1, 1)) P++
    while (S < lo - P && S < ln - P && substr(old, lo - S, 1) == substr(new, ln - S, 1)) S++
    while (P > 0 && word(substr(old, P, 1)) && (word(substr(old, P + 1, 1)) || word(substr(new, P + 1, 1)))) P--
    while (S > 0 && word(substr(old, lo - S + 1, 1)) && (word(substr(old, lo - S, 1)) || word(substr(new, ln - S, 1)))) S--
    while (S > 0 && opens(substr(old, P + 1, lo - P - S)) > 0 && substr(old, lo - S + 1, 1) == ")") S--
  }
  # A hunk is kept until the whole diff is read: a removed line that some added
  # line repeats, in any hunk, moved.
  function flush(    i) {
    for (i = 1; i <= nr; i++) {
      print path ":" (first + i - 1) > own
      kept++
      at[kept] = path sep (first + i - 1); was[kept] = trim(rm[i]); skipped[kept] = gone
      paired[kept] = i <= na; now[kept] = trim(ad[i])
    }
    for (i = 1; i <= na; i++) added[trim(ad[i])] = 1
    nr = 0; na = 0
  }
  function report(k,    line, lo, span, rest, off, from, name) {
    line = was[k]; lo = length(line)
    if (skipped[k] || line in added || line ~ /^(\/\/|\/\*|\*( |$)|#[ !]|-- |<!--)/) return
    P = 0; S = 0
    if (paired[k]) cut(line, now[k])
    span = trim(substr(line, P + 1, lo - P - S))
    if (length(span) >= 12 && span ~ /[A-Za-z_][A-Za-z_][A-Za-z_]/ && !(span in seen)) {
      seen[span] = 1
      print "S" sep at[k] sep span
    }
    rest = line; off = 0
    while (lo - S > P && match(rest, /[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*\(/)) {
      from = off + RSTART
      name = substr(rest, RSTART, RLENGTH - 1)
      if (from <= lo - S && from + RLENGTH - 2 > P && (length(name) >= 5 || name ~ /\./) &&
          !(name in keyword) && !(name in called)) {
        called[name] = 1
        print "C" sep at[k] sep name "("
      }
      off += RSTART + RLENGTH - 1
      rest = substr(rest, RSTART + RLENGTH)
    }
  }
  END { for (k = 1; k <= kept; k++) report(k) }
  { sub(/\r$/, "") }
  old > 0 && /^-/ { rm[++nr] = substr($0, 2); if (--old == 0 && new == 0) flush(); next }
  old == 0 && new > 0 && /^\+/ { ad[++na] = substr($0, 2); if (--new == 0) flush(); next }
  /^\\/ { next }
  /^--- / { path = substr($0, 5); sub(/^a\//, "", path); sub(/\t$/, "", path); gone = 0; next }
  /^\+\+\+ / { gone = ($0 == "+++ /dev/null"); next }
  /^@@ / {
    split($2, o, ","); split($3, n, ",")
    first = substr(o[1], 2) + 0
    old = (2 in o) ? o[2] + 0 : 1
    new = (2 in n) ? n[2] + 0 : 1
    if (old == 0 && new == 0) flush()
  }
' "$work/diff" > "$work/found" || bad_usage "the diff could not be read, so nothing is known about this branch"

# The base's other lines that hold the text, into $work/sites as
# "  file:line  text": not the branch's own removed lines, and not a line an
# earlier block listed.
other_sites() { # text
  gitq grep -n -I -F --no-column -e "$1" "$mb" -- . > "$work/grep" 2> "$work/grep-err"
  # No match exits 1. A file it could not read can exit 0 with the rest
  # searched, so what it said on stderr counts as well as how it ended.
  if [ "$?" -gt 1 ] || [ -s "$work/grep-err" ]; then
    bad_usage "git could not search the base: $(head -n 1 "$work/grep-err" | clean_line)"
  fi
  tr -d '\r' < "$work/grep" | awk -v own="$work/own" -v listed="$work/listed" -v mb="$mb" '
    BEGIN {
      while ((getline l < own) > 0) skip[l] = 1
      while ((getline l < listed) > 0) skip[l] = 1
    }
    {
      $0 = substr($0, length(mb) + 2)
      if (!match($0, /:[0-9]+:/)) next
      at = substr($0, 1, RSTART + RLENGTH - 2)
      text = substr($0, RSTART + RLENGTH)
      sub(/^[ \t]+/, "", text)
      if (!(at in skip) && length(text) <= 500) print "  " at "  " substr(text, 1, 160)
    }' > "$work/sites" || bad_usage "the base could not be searched for: $1"
  n=$(grep -c . "$work/sites")
}
remember() { sed 's/^  //; s/  .*//' "$work/sites" >> "$work/listed"; }

total=0 idioms=""
while IFS="$sep" read -r kind path line text; do
  [ "$kind" = S ] || continue
  other_sites "$text"
  [ "$n" -gt 0 ] || continue
  remember
  if [ "$n" -gt 10 ]; then
    idioms="$idioms${idioms:+; }$text"
    continue
  fi
  total=$((total + n))
  printf '%s:%s replaces: %s\n' "$path" "$line" "$(printf '%s' "$text" | cut -c1-160)" | clean_lines
  clean_lines < "$work/sites"
done < "$work/found"
while IFS="$sep" read -r kind path line text; do
  [ "$kind" = C ] || continue
  other_sites "$text"
  [ "$n" -gt 0 ] || continue
  if [ "$n" -gt 10 ]; then
    idioms="$idioms${idioms:+; }$text"
    continue
  fi
  total=$((total + n))
  printf '%s:%s replaces a call to %s, also made at:\n' "$path" "$line" "$text" | clean_lines
  clean_lines < "$work/sites"
  remember
done < "$work/found"

[ -z "$idioms" ] || printf 'on more than ten other lines each, not listed: %s\n' "$idioms" | cut -c1-400 | clean_lines

if [ -n "$idioms" ]; then
  noun="other sites"; [ "$total" -eq 1 ] && noun="other site"
  echo "$total $noun listed; the code on the line above is on more than ten other lines each and is not counted"
elif [ "$total" -eq 1 ]; then
  echo "1 other site holds code this branch replaces"
else
  echo "$total other sites hold code this branch replaces"
fi
