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
trap 'cd / && rm -rf "$HOUSEBROKEN_HOME"' EXIT
G="git -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false"

fail() { echo "FAIL $name: $1" >&2; exit 1; }
sha() { (sha256sum "$1" 2>/dev/null || shasum -a 256 "$1") | awk '{print $1}'; }

# a filing runs from the clone it files
clone="$HOUSEBROKEN_HOME/clone"
mkdir -p "$clone"
(cd "$clone" && $G init -q && $G commit -q --allow-empty -m base) || fail "clone setup failed"
cd "$clone" || fail "cannot enter the clone"
head=$(git rev-parse HEAD)

help=$(bash "$script" --help) || fail "--help exited non-zero"
printf '%s' "$help" | grep -q "usage: file-pr.sh" || fail "--help printed no usage line"

# gate one: no prior art on disk
out=$(bash "$script" octocat/Hello-World --title t --body ok 2>&1); rc=$?
[ "$rc" -eq 2 ] || fail "missing prior art exited $rc, expected 2"
printf '%s' "$out" | grep -q "REFUSED: no prior art" || fail "missing prior art printed no refusal"

# satisfy gate one so the later gates are what is left
mkdir -p "$HOUSEBROKEN_HOME/prior-art"
echo "## Prior art: octocat/Hello-World" > "$HOUSEBROKEN_HOME/prior-art/prior-art-octocat-Hello-World.md"

# gate two: no policy printout, then a ban, then a disclosure requirement the body ignores
policyfile="$HOUSEBROKEN_HOME/policy/policy-octocat-Hello-World.md"
out=$(bash "$script" octocat/Hello-World --title t --body ok 2>&1); rc=$?
[ "$rc" -eq 2 ] || fail "missing policy printout exited $rc, expected 2"
printf '%s' "$out" | grep -q "REFUSED: no policy printout" || fail "missing policy printout printed no refusal"
mkdir -p "$HOUSEBROKEN_HOME/policy"
policy() { printf '## AI policy: octocat/Hello-World\nbranch: main\nRESULT: %s\n' "$1" > "$policyfile"; }
policy "BAN (a policy file forbids AI-written contributions)"
out=$(bash "$script" octocat/Hello-World --title t --body ok 2>&1); rc=$?
[ "$rc" -eq 2 ] || fail "a BAN policy exited $rc, expected 2"
printf '%s' "$out" | grep -q "forbids AI-written contributions" || fail "a BAN policy printed no refusal"
policy "CLEAN (no policy file names AI)"

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

clean="$HOUSEBROKEN_HOME/clean.md"
printf 'one finding, one test\n' > "$clean"

# gate two, disclosure: a DISCLOSE policy refuses a body that says nothing about AI and accepts one that does
policy "DISCLOSE (a policy file requires AI use to be disclosed)"
out=$(bash "$script" octocat/Hello-World --title t --body-file "$clean" 2>&1); rc=$?
[ "$rc" -eq 2 ] || fail "a DISCLOSE policy with a silent body exited $rc, expected 2"
printf '%s' "$out" | grep -q "requires AI use to be disclosed" || fail "a DISCLOSE policy printed no refusal"
disclosed="$HOUSEBROKEN_HOME/disclosed.md"
printf 'one finding, one test\n\nThe patch and this description were written with Claude.\n' > "$disclosed"
out=$(bash "$script" octocat/Hello-World --title t --body-file "$disclosed" 2>&1); rc=$?
printf '%s' "$out" | grep -q "requires AI use to be disclosed" && fail "a disclosed body was refused by the DISCLOSE gate"
policy "CLEAN (no policy file names AI)"

# gate four: branch-check has not stamped this head
out=$(bash "$script" octocat/Hello-World --title t --body-file "$clean" 2>&1); rc=$?
[ "$rc" -eq 2 ] || fail "no branch stamp exited $rc, expected 2"
printf '%s' "$out" | grep -q "REFUSED: branch-check.sh has not passed head" || fail "a missing branch stamp printed no refusal"
stamp() { mkdir -p "$HOUSEBROKEN_HOME/branch-checks"; printf 'head: %s\n' "$1" > "$HOUSEBROKEN_HOME/branch-checks/$1"; }
stamp "$head"

# gate five: no adversarial review
out=$(bash "$script" octocat/Hello-World --title t --body-file "$clean" 2>&1); rc=$?
[ "$rc" -eq 2 ] || fail "no review exited $rc, expected 2"
printf '%s' "$out" | grep -q "REFUSED: no adversarial review" || fail "a missing review printed no refusal"

report="$HOUSEBROKEN_HOME/reviews/review-octocat-Hello-World-${head:0:12}.md"
mkdir -p "$HOUSEBROKEN_HOME/reviews"
review() { # reviewer verdict
  printf 'review-of: octocat/Hello-World\nhead: %s\ntext: sha256:%s clean.md\nauthor-model: opus\nreviewer-model: %s\nverdict: %s\n' \
    "$head" "$(sha "$clean")" "$1" "$2" > "$report"
}

review sonnet "DO NOT POST"
bash "$script" octocat/Hello-World --title t --body-file "$clean" >/dev/null 2>&1
[ "$?" -eq 2 ] || fail "a DO NOT POST review did not stop the filing"
review opus "POST AS IS"
bash "$script" octocat/Hello-World --title t --body-file "$clean" >/dev/null 2>&1
[ "$?" -eq 2 ] || fail "the author reviewing its own work did not stop the filing"

# a clean body, reviewed by a different model on this head, stops at the dry run
review sonnet "POST AS IS"
out=$(bash "$script" octocat/Hello-World --title t --body-file "$clean" 2>&1); rc=$?
[ "$rc" -eq 0 ] || fail "a reviewed clean dry run exited $rc, expected 0: $out"
printf '%s' "$out" | grep -q "DRY RUN, not filed" || fail "clean dry run did not print the command"

# the body file may be named either way gh reads it
bash "$script" octocat/Hello-World --title t -F "$clean" >/dev/null 2>&1 || fail "-F FILE was refused"
bash "$script" octocat/Hello-World --title t "--body-file=$clean" >/dev/null 2>&1 || fail "--body-file=FILE was refused"

# every other route to a body, a branch or a repository is refused
evil="$HOUSEBROKEN_HOME/evil.md"
printf 'unreviewed %s body\n' "$(printf '\xe2\x80\x94')" > "$evil"
for extra in "-F$evil" "-F=$evil" "-dF $evil" "-bunreviewed" "--fill" "--head other" "-R victim/repo" "--repo=victim/repo" "--template $evil" "--web"; do
  # shellcheck disable=SC2086
  bash "$script" octocat/Hello-World --title t --body-file "$clean" $extra >/dev/null 2>&1
  [ "$?" -eq 2 ] || fail "file-pr.sh let $extra through to gh pr create"
done

# gate two reads GitHub's own spelling of the trailer, and the title
lc="$HOUSEBROKEN_HOME/lc.md"
printf 'one finding\n\nCo-authored-by: Claude <noreply@anthropic.com>\n' > "$lc"
out=$(bash "$script" octocat/Hello-World --title t --body-file "$lc" 2>&1)
printf '%s' "$out" | grep -qi "contains 'co-authored-by" || fail "a body with Co-authored-by passed the prose gate: $out"
out=$(bash "$script" octocat/Hello-World --title "fix $(printf '\xe2\x80\x94') parser" --body-file "$clean" 2>&1); rc=$?
[ "$rc" -eq 2 ] || fail "a title with an em dash exited $rc, expected 2"

# an inline body cannot be bound to the review
out=$(bash "$script" octocat/Hello-World --title t --body "one finding, one test" 2>&1); rc=$?
[ "$rc" -eq 2 ] || fail "an inline body exited $rc, expected 2"
printf '%s' "$out" | grep -q "body-file" || fail "an inline body printed no reason"

# the body changes after the review
printf 'one finding, two tests\n' > "$clean"
bash "$script" octocat/Hello-World --title t --body-file "$clean" >/dev/null 2>&1
[ "$?" -eq 2 ] || fail "a body edited after the review did not stop the filing"

# the branch moves after the branch check and the review
printf 'one finding, one test\n' > "$clean"
$G commit -q --allow-empty -m "after the review" || fail "second commit failed"
out=$(bash "$script" octocat/Hello-World --title t --body-file "$clean" 2>&1); rc=$?
[ "$rc" -eq 2 ] || fail "a commit made after the review exited $rc, expected 2"
printf '%s' "$out" | grep -q "REFUSED: branch-check.sh has not passed head" || fail "a moved branch printed no branch refusal"
stamp "$(git rev-parse HEAD)"
out=$(bash "$script" octocat/Hello-World --title t --body-file "$clean" 2>&1); rc=$?
[ "$rc" -eq 2 ] || fail "a commit made after the review, stamped, exited $rc, expected 2"
printf '%s' "$out" | grep -q "REFUSED: no adversarial review" || fail "a moved branch printed no review refusal"

echo "PASS $name"
