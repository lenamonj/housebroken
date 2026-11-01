# common.sh - what several gates share. Sourced, never run.
# shellcheck shell=bash

# Git as these scripts read it, whatever the user's config says: paths as they
# are and plain output. core.quotePath quotes a non-ASCII name, color.ui=always
# hides every added line behind an escape, and an external diff driver prints
# no diff at all, and each of those reads as a branch with nothing in it.
gitq() {
  git -c core.quotePath=false -c color.ui=false -c color.diff=false \
    -c diff.noprefix=false -c diff.mnemonicPrefix=false -c diff.relative=false "$@"
}
gdiff() { gitq diff --no-ext-diff --no-textconv "$@"; }

# The added lines of a unified diff on stdin, as FILE<TAB>TEXT. The hunk length
# says which lines are added, so a line that starts with ++ is not a header.
added_lines() {
  awk '
    /^@@ /            { n = (index($3, ",") ? substr($3, index($3, ",") + 1) : 1) + 0; next }
    n > 0 && /^\+/    { print file "\t" substr($0, 2); n--; next }
    n > 0 && /^-/     { next }
    /^\+\+\+ /        { file = substr($0, 7); sub(/\t$/, "", file) }
  '
}

# A renamed file's old path, from "OLD<TAB>NEW" lines in $renames, so a diff
# limited to the new path alone does not read the whole file as added.
renamed_from() { printf '%s\n' "${renames:-}" | awk -F'\t' -v n="$1" '$2 == n {print $1; exit}'; }

# Whether a path is a test by where it lives or what it is called. A substring
# is not enough: latest.c, inspect.go and special_cases.py say test or spec too.
is_test_path() {
  printf '%s\n' "$1" | grep -qE '(^|/)(tests?|specs?|__tests__|testdata)/|(^|/)test_[^/]*$|[._-](test|spec)s?\.[^/]+$|[a-z0-9]Tests?\.[^/]+$|(^|/)conftest\.py$'
}

# Seconds since a file last changed. stat differs between GNU and BSD.
file_age() {
  local m
  m=$(stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null) || return 1
  echo $(( $(date +%s) - m ))
}

# Text a stranger wrote, on stdin, safe to print: control characters out, so an
# escape sequence cannot redraw a line, and line breaks kept.
clean_lines() { LC_ALL=C tr -d '\000-\010\013\014\016-\037\177'; }
# The same on one line, for a title, a path or a check name in the script's own
# output. Its argument, or stdin.
clean_line() {
  if [ "$#" -gt 0 ]; then printf '%s' "$1"; else cat; fi | LC_ALL=C tr '\r\n\t' '   ' | clean_lines
}

# What both filing gates read first: the prior-art and policy printouts for this
# repository, each present, under a day old and written for this repository, not
# for one whose name joins to the same file. Sets art, policy and policy_result.
read_printouts() {
  local repo="$1" home="$2" age
  art="$home/prior-art/prior-art-${repo%%/*}-${repo##*/}.md"
  if [ ! -f "$art" ]; then
    echo "REFUSED: no prior art at $art - run prior-art.sh $repo <terms> --out first" >&2
    exit 2
  fi
  age=$(file_age "$art") || { echo "REFUSED: cannot read the age of $art" >&2; exit 2; }
  if [ "$age" -gt 86400 ]; then
    echo "REFUSED: prior art $art is $(( age / 3600 ))h old - rerun prior-art.sh --out" >&2
    exit 2
  fi
  policy="$home/policy/policy-${repo%%/*}-${repo##*/}.md"
  if [ ! -f "$policy" ]; then
    echo "REFUSED: no policy printout at $policy - run check-ai-policy.sh $repo --out first" >&2
    exit 2
  fi
  age=$(file_age "$policy") || { echo "REFUSED: cannot read the age of $policy" >&2; exit 2; }
  if [ "$age" -gt 86400 ]; then
    echo "REFUSED: policy printout $policy is $(( age / 3600 ))h old - rerun check-ai-policy.sh --out" >&2
    exit 2
  fi
  local f who
  for f in "$art" "$policy"; do
    who=$(head -1 "$f" | tr -d '\r' | awk '{print $4}')
    if [ "$who" != "$repo" ]; then
      echo "REFUSED: $f is the printout of $who, not $repo - rerun it for $repo" >&2
      exit 2
    fi
  done
  policy_result=$(grep -m1 '^RESULT: ' "$policy" | awk '{print $2}')
  case "$policy_result" in
    BAN) echo "REFUSED: $repo forbids AI-written contributions ($policy); never file here" >&2; exit 2 ;;
    DISCLOSE|CLEAN) ;;
    MENTION)
      if ! grep -q '^READING: .' "$policy"; then
        echo "REFUSED: $policy names AI without a recorded reading - read its lines, then rerun check-ai-policy.sh $repo --out --reading 'what they mean for this change'" >&2
        exit 2
      fi ;;
    UNREAD) echo "REFUSED: $policy reads UNREAD - GitHub did not give every policy file; rerun check-ai-policy.sh --out" >&2; exit 2 ;;
    *) echo "REFUSED: $policy has no RESULT line - rerun check-ai-policy.sh --out" >&2; exit 2 ;;
  esac
}
