#!/bin/bash
# test-refusal-ids.sh - every refusal carries a name, and a name means one
# site. Read from the scripts themselves: no script but refuse.sh prints
# REFUSED on its own, every name is written out where it is used, begins with
# its script's name, is forty characters or fewer, and is used once. The four
# faults a later change is likeliest to make are planted and must be named.
# shellcheck disable=SC2015,SC2016  # "a && b || fail"; the planted text is shell, not expanded here
set -u
name=test-refusal-ids
here=$(cd "$(dirname "$0")" && pwd)
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT

fail() { echo "FAIL $name: $1" >&2; exit 1; }

# A site is a name written as the first word after refused or reason, after a
# script's own wrapper around them (refuse, block), or after why_id= in the
# hook. Comment lines are not read, and neither is the line that defines a
# wrapper, which passes on the name it was given. refused_reason and
# refusal_log take what a site named, so they are not sites.
sites() { # scripts-dir
  local f base
  for f in "$1"/*.sh; do
    base=$(basename "$f" .sh)
    [ "$base" != refuse ] || continue
    tr -d '\r' < "$f" | grep -vE '^[[:space:]]*#' | grep -vE '^[[:space:]]*[a-z_]+\(\)[[:space:]]*\{' \
      | grep -oE '(^|[;&|{()]|then|else|do)[[:space:]]*(refused|refuse|block|reason)[[:space:]]+[^[:space:];]+|(^|[[:space:];])why_id="?[^[:space:];"]+' \
      | sed -E 's/^.*(refused|refuse|block|reason)[[:space:]]+//; s/^.*why_id="?//' \
      | while IFS= read -r id; do printf '%s\t%s\n' "$base" "$id"; done
  done
}

census() { # scripts-dir: the first fault and 1, or "N" and 0
  local dir="$1" echoes all bad long dup
  echoes=$(grep -lE "(echo|printf) +[\"']REFUSED" "$dir"/*.sh 2>/dev/null | grep -vc '/refuse\.sh$')
  [ "$echoes" -eq 0 ] || { echo "$echoes script(s) still echo REFUSED"; return 1; }
  all=$(sites "$dir")
  [ -n "$all" ] || { echo "no site found, so nothing was checked"; return 1; }
  bad=$(printf '%s\n' "$all" | awk -F'\t' '{
    want = ($1 == "gate-hook") ? "gate" : $1
    if ($2 !~ ("^" want "-[a-z0-9]+(-[a-z0-9]+)*$")) { print $1 ".sh: " $2; exit } }')
  [ -z "$bad" ] || { echo "not a literal id of its script: $bad"; return 1; }
  long=$(printf '%s\n' "$all" | awk -F'\t' 'length($2) > 40 {print $2; exit}')
  [ -z "$long" ] || { echo "id $long is longer than 40 characters"; return 1; }
  dup=$(printf '%s\n' "$all" | cut -f2 | sort | uniq -d | head -n 1)
  [ -z "$dup" ] || { echo "id $dup names two sites"; return 1; }
  printf '%s\n' "$all" | grep -c .
}

n=$(census "$here/../scripts") || fail "$n"

# the planted faults, each in a copy of two scripts
plant() { # what-to-do-to-push.sh, as a sed program, or "append TEXT"
  rm -rf "$root/s"; mkdir "$root/s"
  cp "$here/../scripts/refuse.sh" "$here/../scripts/push.sh" "$root/s/"
  case "$1" in
    append\ *) printf '%s\n' "${1#append }" >> "$root/s/push.sh" ;;
    *) sed "$1" "$here/../scripts/push.sh" > "$root/s/push.sh" ;;
  esac
  cmp -s "$here/../scripts/push.sh" "$root/s/push.sh" && fail "nothing was planted by: $1"
  census "$root/s"
}
out=$(plant 's/refused push-unknown-option /refused push-repo-form /') && fail "a name on two sites passed: $out"
[ "$out" = "id push-repo-form names two sites" ] || fail "a shared name: $out"
out=$(plant 's/refused push-unknown-option /refused "$id" /') && fail "a variable as the name passed: $out"
[ "$out" = 'not a literal id of its script: push.sh: "$id"' ] || fail "a variable as the name: $out"
out=$(plant 's/refused push-unknown-option /refused reply-wrong-prefix /') && fail "another script's prefix passed: $out"
[ "$out" = "not a literal id of its script: push.sh: reply-wrong-prefix" ] || fail "another script's prefix: $out"
out=$(plant 'append echo "REFUSED: an old line" >&2') && fail "an old echo passed: $out"
[ "$out" = "1 script(s) still echo REFUSED" ] || fail "an old echo: $out"
out=$(plant 's/refused push-unknown-option /refused push-a-name-that-runs-well-past-forty-characters /') && fail "a long name passed: $out"
[ "$out" = "id push-a-name-that-runs-well-past-forty-characters is longer than 40 characters" ] || fail "a long name: $out"
out=$(plant 's/refused push-unknown-option /refused Push-Unknown /') && fail "a name with capitals passed: $out"
[ "$out" = "not a literal id of its script: push.sh: Push-Unknown" ] || fail "a name with capitals: $out"
out=$(census "$root/empty" 2>/dev/null) && fail "a directory with no scripts passed: $out"

echo "PASS $name ($n names)"
