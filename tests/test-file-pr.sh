#!/bin/bash
# test-file-pr.sh - checks that scripts/file-pr.sh refuses. Every case here runs
# with FILE_PR_DRY=1 and every case exits before gh pr create, so nothing is
# ever filed.
set -u
name="file-pr.sh"
here=$(cd "$(dirname "$0")" && pwd)
script="$here/../scripts/file-pr.sh"
HOUSEBROKEN_HOME=$(mktemp -d)
export HOUSEBROKEN_HOME FILE_PR_DRY=1
trap 'rm -rf "$HOUSEBROKEN_HOME"' EXIT

fail() { echo "FAIL $name: $1" >&2; exit 1; }

help=$(bash "$script" --help) || fail "--help exited non-zero"
printf '%s' "$help" | grep -q "usage: file-pr.sh" || fail "--help printed no usage line"

# gate one: no prior art on disk
out=$(bash "$script" octocat/Hello-World --title t --body ok 2>&1); rc=$?
[ "$rc" -eq 2 ] || fail "missing prior art exited $rc, expected 2"
printf '%s' "$out" | grep -q "REFUSED: no prior art" || fail "missing prior art printed no refusal"

# satisfy gate one so gate two is the only thing left
mkdir -p "$HOUSEBROKEN_HOME/prior-art"
echo "## Prior art: octocat/Hello-World" > "$HOUSEBROKEN_HOME/prior-art/prior-art-octocat-Hello-World.md"

# gate two: an em dash in the body
body="fixes the parser $(printf '\xe2\x80\x94') one line"
out=$(bash "$script" octocat/Hello-World --title t --body "$body" 2>&1); rc=$?
[ "$rc" -eq 2 ] || fail "em dash body exited $rc, expected 2"
printf '%s' "$out" | grep -q "REFUSED" || fail "em dash body printed no refusal"

# gate two: an em dash in a body file
bodyfile="$HOUSEBROKEN_HOME/body.md"
printf 'fixes the parser \xe2\x80\x94 one line\n' > "$bodyfile"
out=$(bash "$script" octocat/Hello-World --title t --body-file "$bodyfile" 2>&1); rc=$?
[ "$rc" -eq 2 ] || fail "em dash body file exited $rc, expected 2"
printf '%s' "$out" | grep -q "REFUSED" || fail "em dash body file printed no refusal"

# a clean body passes both gates and stops at the dry run
out=$(bash "$script" octocat/Hello-World --title t --body "one finding, one test" 2>&1); rc=$?
[ "$rc" -eq 0 ] || fail "clean dry run exited $rc, expected 0"
printf '%s' "$out" | grep -q "DRY RUN, not filed" || fail "clean dry run did not print the command"

echo "PASS $name"
