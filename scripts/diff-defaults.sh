#!/bin/bash
# diff-defaults.sh - added default arguments and one-line forwarding wrappers.
#
# On google/benchmark #2294 the maintainer asked "why are there defaults here?"
# about two default arguments added so that ten existing call sites did not
# have to change. A default argument, an overload or a one-line wrapper that
# exists only to keep call sites untouched hides the change from the reader and
# leaves the old behaviour reachable. The fix is to touch the call sites. This
# script reads the added lines of a diff and reports both shapes so the author
# sees them before the maintainer does. It reports, it does not judge: the exit
# status is 0 whether or not anything was found.
#
# Usage:
#   bash diff-defaults.sh [CLONE_ROOT]
#   bash diff-defaults.sh --diff FILE
#   bash diff-defaults.sh --diff -
#   bash diff-defaults.sh --help
#
# CLONE_ROOT is any directory whose immediate subdirectories are git clones;
# every branch is diffed against its clone's default branch. With --diff, a
# unified diff is read from FILE, or from standard input when FILE is -.
#
# Environment:
#   HOUSEBROKEN_CLONES  default clone root
#   HOUSEBROKEN_HOME    workshop root, default $HOME/.housebroken
#
# Output is one line per hit, "file:line  kind  text", where kind is
# default-arg or forwarding, followed by a summary count.
#
# Languages: C, C++, Python, Kotlin, Swift, TypeScript and JavaScript, by
# extension (.c .cc .cpp .h .hpp .py .kt .swift .ts .js). Other files are
# ignored.
#
# Heuristic. Working one added line at a time, with no parser and no view of
# the surrounding function, the script calls a line a signature when it holds
# an assignment whose left side ends in an identifier and one of these is true:
#   - the assignment sits between the line's first ( and its last ), and
#     nothing after that ) opens another paren:  void Run(int n, bool v = 0);
#   - the line opens a parameter list it does not close, and the assignment is
#     after the (
#   - the line closes a parameter list it did not open, and the assignment is
#     before the )
#   - the trimmed line ends with a comma, the shape of a parameter continuation
# A forwarding wrapper is an added line that defines a name and calls that same
# name again on the same line, with a return, an =>, an = or a { between them.
#
# Known misses. False positives: a keyword or designated argument written with
# = inside a call, "foo(a, b = 5);"; a brace-initialiser or array element
# ending in a comma, though a leading . is skipped; a recursive one-line
# function, which on one line looks exactly like a forwarding wrapper. False
# negatives: a default on a signature split so that neither the identifier nor
# the = lands on an added line; a forwarding wrapper whose body is on the next
# line; a default introduced by a line the diff records as unchanged context;
# C++ default template arguments and Python keyword-only markers are not
# modelled.
set -u

usage() {
  sed -n '2,/^set -u$/p' "$0" | sed 's/^# \{0,1\}//; /^set -u$/d'
}

mode="clones"
diff_src=""
case "${1:-}" in
  --help|-h) usage; exit 0 ;;
  --diff)
    if [ $# -lt 2 ] || [ -z "$2" ]; then
      echo "diff-defaults.sh: --diff needs a file or -" >&2
      exit 2
    fi
    mode="diff"
    diff_src="$2"
    ;;
  --*)
    echo "diff-defaults.sh: unknown option: $1" >&2
    exit 2
    ;;
esac

analyzer=$(cat <<'AWK'
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
function ext(f,   n, a) { n = split(f, a, "."); return (n > 1) ? a[n] : "" }
function supported(e) {
  return (e=="c" || e=="cc" || e=="cpp" || e=="h" || e=="hpp" || e=="py" ||
          e=="kt" || e=="swift" || e=="ts" || e=="js")
}
function countch(s, c,   i, n, k) { n=length(s); k=0; for (i=1;i<=n;i++) if (substr(s,i,1)==c) k++; return k }
function lastidx(s, c,   i, n, k) { n=length(s); k=0; for (i=1;i<=n;i++) if (substr(s,i,1)==c) k=i; return k }
# position of the first plain assignment =, skipping ==, !=, +=, and friends
function eqpos(s,   i, n, p) {
  n = length(s)
  for (i = 1; i <= n; i++) {
    if (substr(s,i,1) != "=") continue
    if (substr(s,i+1,1) == "=") continue
    p = (i > 1) ? substr(s,i-1,1) : ""
    if (p ~ /[=!<>+*\/%&|^~-]/) continue
    return i
  }
  return 0
}
function is_default(t,   s, eq, pre, oc, cc, fo, lc, tail) {
  s = trim(t)
  if (substr(s,1,1) == ".") return 0
  eq = eqpos(s)
  if (eq == 0) return 0
  pre = trim(substr(s, 1, eq - 1))
  if (pre !~ /[A-Za-z0-9_]$/) return 0
  if (trim(substr(s, eq + 1)) == "") return 0
  oc = countch(s, "("); cc = countch(s, ")")
  fo = index(s, "("); lc = lastidx(s, ")")
  if (fo > 0 && lc > fo && eq > fo && eq < lc) {
    tail = substr(s, lc + 1)
    if (index(tail, "(") == 0) return 1
  }
  if (oc > cc && fo > 0 && eq > fo) return 1
  if (cc > oc && lc > 0 && eq < lc) return 1
  if (substr(s, length(s), 1) == ",") return 1
  return 0
}
function defname(s,   fo, j, e) {
  fo = index(s, "(")
  if (fo == 0) return ""
  j = fo - 1
  while (j > 0 && (substr(s,j,1) == " " || substr(s,j,1) == "\t")) j--
  e = j
  while (j > 0 && substr(s,j,1) ~ /[A-Za-z0-9_]/) j--
  return substr(s, j + 1, e - j)
}
function ncalls(s, name,   i, n, L, p, j, k) {
  n = length(s); L = length(name); k = 0
  if (L == 0) return 0
  for (i = 1; i <= n - L + 1; i++) {
    if (substr(s,i,L) != name) continue
    p = (i > 1) ? substr(s,i-1,1) : ""
    if (p ~ /[A-Za-z0-9_]/) continue
    j = i + L
    while (substr(s,j,1) == " " || substr(s,j,1) == "\t") j++
    if (substr(s,j,1) == "(") k++
  }
  return k
}
function is_forward(t,   s, name) {
  s = trim(t)
  name = defname(s)
  if (name == "") return 0
  if (name ~ /^(if|for|while|switch|return|catch|def|fun|func|function|new|sizeof)$/) return 0
  if (ncalls(s, name) < 2) return 0
  if (s ~ /return/ || index(s, "=>") > 0 || index(s, "=") > 0 || index(s, "{") > 0) return 1
  return 0
}
/^\+\+\+ / { file = ""; if (substr($0,1,6) == "+++ b/") file = substr($0,7); next }
/^--- /    { next }
/^@@ /     { split($3, a, ","); ln = substr(a[1],2) + 0; next }
/^\\/      { next }
/^\+/ {
  if (file != "") {
    t = substr($0, 2)
    if (supported(ext(file))) {
      if (is_forward(t))      print file ":" ln "  forwarding  " t
      else if (is_default(t)) print file ":" ln "  default-arg  " t
    }
    ln++
  }
  next
}
/^-/ { next }
/^ / { ln++ }
AWK
)

hits=$(mktemp) || exit 1
trap 'rm -f "$hits"' EXIT

if [ "$mode" = diff ]; then
  if [ "$diff_src" = "-" ]; then
    awk "$analyzer" >> "$hits"
  else
    if [ ! -f "$diff_src" ]; then
      echo "diff-defaults.sh: not a file: $diff_src" >&2
      exit 2
    fi
    awk "$analyzer" "$diff_src" >> "$hits"
  fi
else
  HOUSEBROKEN_HOME="${HOUSEBROKEN_HOME:-$HOME/.housebroken}"
  root="${1:-${HOUSEBROKEN_CLONES:-$HOUSEBROKEN_HOME/clones}}"
  if [ ! -d "$root" ]; then
    echo "diff-defaults.sh: not a directory: $root" >&2
    echo "give a clone root as an argument or set HOUSEBROKEN_CLONES" >&2
    exit 2
  fi
  found=0
  for d in "$root"/*/; do
    [ -d "$d/.git" ] || continue
    found=1
    base=$(git -C "$d" symbolic-ref -q --short refs/remotes/origin/HEAD || true)
    if [ -z "$base" ]; then
      if git -C "$d" rev-parse --verify -q origin/main >/dev/null; then
        base=origin/main
      elif git -C "$d" rev-parse --verify -q origin/master >/dev/null; then
        base=origin/master
      else
        echo "diff-defaults.sh: no default branch in $d, skipped" >&2
        continue
      fi
    fi
    default_branch="${base#origin/}"
    while read -r br; do
      [ -n "$br" ] || continue
      [ "$br" = "$default_branch" ] && continue
      [ "$(git -C "$d" rev-list --count "$base..$br")" = "0" ] && continue
      git -C "$d" diff --unified=0 "$base..$br" | awk "$analyzer" >> "$hits"
    done < <(git -C "$d" for-each-ref --format='%(refname:short)' refs/heads/)
  done
  if [ "$found" = 0 ]; then
    echo "diff-defaults.sh: no git clones found under $root" >&2
    exit 2
  fi
fi

cat "$hits"
echo "$(grep -c . "$hits" || true) default arguments or forwarding wrappers added"
