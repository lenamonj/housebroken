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
