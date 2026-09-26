#!/bin/bash
# test-file-issue.sh - checks that scripts/file-issue.sh refuses. Every case
# here runs with FILE_ISSUE_DRY=1 and every case exits before gh issue create,
# so nothing is ever filed.
set -u
name="file-issue.sh"
here=$(cd "$(dirname "$0")" && pwd)
script="$here/../scripts/file-issue.sh"
HOUSEBROKEN_HOME=$(mktemp -d)
export HOUSEBROKEN_HOME FILE_ISSUE_DRY=1
trap 'rm -rf "$HOUSEBROKEN_HOME"' EXIT

fail() { echo "FAIL $name: $1" >&2; exit 1; }

help=$(bash "$script" --help) || fail "--help exited non-zero"
printf '%s' "$help" | grep -q "usage: file-issue.sh" || fail "--help printed no usage line"

bodyfile="$HOUSEBROKEN_HOME/body.md"
printf 'The parser drops the last field of a quoted row.\n' > "$bodyfile"
run() { bash "$script" octocat/Hello-World "$@" 2>&1; }

# gate one: no prior art on disk
out=$(run --title t --body-file "$bodyfile"); rc=$?
[ "$rc" -eq 2 ] || fail "missing prior art exited $rc, expected 2"
printf '%s' "$out" | grep -q "REFUSED: no prior art" || fail "missing prior art printed no refusal"
mkdir -p "$HOUSEBROKEN_HOME/prior-art"
echo "## Prior art: octocat/Hello-World" > "$HOUSEBROKEN_HOME/prior-art/prior-art-octocat-Hello-World.md"

# gate two: no policy printout, then a ban, then a disclosure the body ignores
policyfile="$HOUSEBROKEN_HOME/policy/policy-octocat-Hello-World.md"
out=$(run --title t --body-file "$bodyfile"); rc=$?
[ "$rc" -eq 2 ] || fail "missing policy printout exited $rc, expected 2"
printf '%s' "$out" | grep -q "REFUSED: no policy printout" || fail "missing policy printout printed no refusal"
mkdir -p "$HOUSEBROKEN_HOME/policy"
policy() { printf '## AI policy: octocat/Hello-World\nbranch: main\nRESULT: %s\n' "$1" > "$policyfile"; }
policy "BAN (a policy file forbids AI-written contributions)"
out=$(run --title t --body-file "$bodyfile"); rc=$?
[ "$rc" -eq 2 ] || fail "a BAN policy exited $rc, expected 2"
printf '%s' "$out" | grep -q "forbids AI-written contributions" || fail "a BAN policy printed no refusal"
policy "DISCLOSE (a policy file asks for disclosure)"
out=$(run --title t --body-file "$bodyfile"); rc=$?
[ "$rc" -eq 2 ] || fail "an undisclosed body under DISCLOSE exited $rc, expected 2"
printf '%s' "$out" | grep -q "requires AI use to be disclosed" || fail "an undisclosed body under DISCLOSE printed no refusal"
policy "CLEAN (no policy file names AI)"

# gate three: an em dash, a session link and a co-author trailer in the body; a dash in the title
for bad in 'the parser \xe2\x80\x94 one line' 'see https://claude.ai/code/session_abc' 'Co-Authored-By: x'; do
  printf "$bad\n" > "$HOUSEBROKEN_HOME/bad.md"
  out=$(run --title t --body-file "$HOUSEBROKEN_HOME/bad.md"); rc=$?
  [ "$rc" -eq 2 ] || fail "body '$bad' exited $rc, expected 2"
  printf '%s' "$out" | grep -q "REFUSED" || fail "body '$bad' printed no refusal"
done
out=$(run --title "$(printf 'a \xe2\x80\x93 b')" --body-file "$bodyfile"); rc=$?
[ "$rc" -eq 2 ] || fail "en dash title exited $rc, expected 2"

# only --body-file carries the body; --body, --web and --template are refused
for extra in "--body x" "--web" "--template t"; do
  # shellcheck disable=SC2086
  run --title t --body-file "$bodyfile" $extra >/dev/null 2>&1
  [ "$?" -eq 2 ] || fail "file-issue.sh let $extra through to gh issue create"
done
out=$(run --body-file "$bodyfile"); rc=$?
[ "$rc" -eq 2 ] || fail "a missing --title exited $rc, expected 2"
out=$(run --title t); rc=$?
[ "$rc" -eq 2 ] || fail "a missing --body-file exited $rc, expected 2"

# gate four: a fix offered with no branch link is refused; the same body with a link passes
printf 'The parser drops the last field. I have a fix; say the word and I will send it as a PR.\n' > "$bodyfile"
out=$(run --title t --body-file "$bodyfile"); rc=$?
[ "$rc" -eq 2 ] || fail "a fix offered without a link exited $rc, expected 2"
printf '%s' "$out" | grep -q "links no branch or commit" || fail "a fix offered without a link printed no refusal"
for word in patch "pull request" fixes; do
  printf 'The parser drops the last field. A %s is ready.\n' "$word" > "$bodyfile"
  run --title t --body-file "$bodyfile" >/dev/null 2>&1
  [ "$?" -eq 2 ] || fail "'$word' offered without a link was not refused"
done
printf 'The parser drops the last field. The fix is at https://github.com/octocat/Hello-World/tree/parser-last-field for review.\n' > "$bodyfile"
out=$(run --title t --body-file "$bodyfile"); rc=$?
[ "$rc" -eq 0 ] || fail "a fix with a branch link exited $rc, expected 0: $out"
printf '%s' "$out" | grep -q "DRY RUN" || fail "a passing body did not reach the dry run"
printf '%s' "$out" | grep -q -- "gh issue create -R octocat/Hello-World" || fail "the dry run names the wrong command"
printf 'The parser drops the last field. Commit https://github.com/octocat/Hello-World/commit/0123abcd shows it.\n' > "$bodyfile"
run --title t --body-file "$bodyfile" >/dev/null 2>&1 || fail "a commit link was not accepted"

# a body that offers nothing needs no link
printf 'The parser drops the last field of a quoted row.\n' > "$bodyfile"
out=$(run --title t --body-file "$bodyfile"); rc=$?
[ "$rc" -eq 0 ] || fail "a plain report exited $rc, expected 0: $out"

echo "PASS $name"
