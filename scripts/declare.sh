#!/bin/bash
# declare.sh - the author says what was not tested and what was assumed.
#
# A review attacks what it is shown. The gaps an author knows about and does
# not mention are the ones a maintainer finds: the mode that was never run,
# the comparer that was assumed to be the default, the caller that was
# assumed not to exist. The declaration names them before the review, so
# the reviewer can attack each one and a gap left out becomes a statement
# that was false, not an oversight.
#
# The first run writes a declaration for the clone's head and prints its
# path; fill it in. Later runs check it:
#   not-tested:   what this change was not run against, at least one line;
#                 "none" is refused, because something always was not
#   assumptions:  one line each, "- <assumption> | if wrong: <what breaks,
#                 for whom> | checked by: <the command and its result, or
#                 unchecked>"
#
# Pass the declaration to the review as a --text, so the reviewer attacks it
# and the review is bound to it. file-pr.sh requires a passing declaration
# for the head, and that the review read it.
#
# Usage:
#   bash declare.sh [CLONE]
#   bash declare.sh --help
#
# Writes or reads $HOUSEBROKEN_HOME/declarations/<head>.md. Exits 0 when the
# declaration passes, 1 when it was just written or does not pass, 2 on a
# usage error.
set -u

usage() { awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"; }

case "${1:-}" in
  --help|-h) usage; exit 0 ;;
  -*) echo "REFUSED: unknown option $1" >&2; exit 2 ;;
esac
clone="${1:-.}"
head=$(git -C "$clone" rev-parse HEAD 2>/dev/null) || { echo "REFUSED: $clone is not a git clone" >&2; exit 2; }
home="${HOUSEBROKEN_HOME:-$HOME/.housebroken}"
decl="$home/declarations/$head.md"

if [ ! -f "$decl" ]; then
  mkdir -p "$home/declarations"
  cat > "$decl" <<EOF
head: $head

not-tested:
-

assumptions:
- <assumption> | if wrong: <what breaks, for whom> | checked by: <command and result, or unchecked>
EOF
  echo "declare: fill in $decl, then run this again"
  exit 1
fi

bad=""
grep -q "^head: $head\$" "$decl" || bad="$bad
    the head line is not $head"
section() { awk -v s="$1:" '$0 == s {on = 1; next} /^[a-z-]+:/ {on = 0} on && /^- */ {sub(/^- */, ""); print}' "$decl" | sed 's/[[:space:]]*$//' | grep -v '^$'; }
nt=$(section not-tested)
if [ -z "$nt" ]; then
  bad="$bad
    not-tested: names nothing"
elif printf '%s\n' "$nt" | grep -qixE 'none\.?|n/a|nothing\.?'; then
  bad="$bad
    not-tested: says none; something always was not tested"
fi
as=$(section assumptions)
[ -n "$as" ] || bad="$bad
    assumptions: lists none"
while IFS= read -r a; do
  [ -n "$a" ] || continue
  case "$a" in
    *"<assumption>"*|*"<what breaks"*|*"<command and result"*) bad="$bad
    an assumption is still the template line" ;;
    *"| if wrong: "*"| checked by: "*) ;;
    *) bad="$bad
    an assumption lacks '| if wrong: ... | checked by: ...': $a" ;;
  esac
done <<EOF
$as
EOF

if [ -n "$bad" ]; then
  echo "REFUSED: $decl does not pass:$bad"
  exit 1
fi
echo "declare: $decl passes ($(printf '%s\n' "$nt" | grep -c .) not tested, $(printf '%s\n' "$as" | grep -c .) assumptions)"
