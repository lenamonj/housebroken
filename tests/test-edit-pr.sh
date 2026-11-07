#!/bin/bash
# test-edit-pr.sh - edit-pr.sh changes a filed pull request's body or title
# only through the prose gates a filing passes: a policy printout that is not
# BAN, no footer or dash, the project's template kept and 120 words of ours,
# a disclosure where the policy asks for one, every reference found; and
# only on an open pull request of ours, ten minutes apart. It keeps the copy
# verify-filed-pr.sh compares against. Every case is a dry run through the
# stub gh except the last, which writes only to the stub's own log.
set -u
name=test-edit-pr
here=$(cd "$(dirname "$0")" && pwd)
export PATH="$here/stubs:$PATH"
script="$here/../scripts/edit-pr.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export HOUSEBROKEN_HOME="$tmp/home" EDIT_PR_DRY=1 HOUSEBROKEN_USER=me

fail() { echo "FAIL $name: $1" >&2; exit 1; }

bash "$script" --help | grep -q "Usage:" || fail "--help printed no usage"

edit() { # expected-exit text [extra args]
  local want="$1" text="$2"; shift 2
  printf '%s\n' "$text" > "$tmp/b.md"
  bash "$script" octocat/Hello-World 9 --body-file "$tmp/b.md" "$@" > "$tmp/out" 2>&1
  [ "$?" = "$want" ] || { cat "$tmp/out" >&2; fail "exit not $want for: $text $*"; }
}

# no policy printout: the edit is held to the same reading a filing is
edit 2 "The loader checks its read before it returns."
grep -q "REFUSED: no policy printout" "$tmp/out" || fail "a missing policy printout was not named: $(cat "$tmp/out")"
mkdir -p "$HOUSEBROKEN_HOME/policy"
policy() { printf '## AI policy: octocat/Hello-World\nbranch: main\nRESULT: %s\n' "$1" > "$HOUSEBROKEN_HOME/policy/policy-octocat-Hello-World.md"; }
policy "BAN (a policy file forbids AI-written contributions)"
edit 2 "The loader checks its read before it returns."
policy "CLEAN (no policy file names AI)"
edit 0 "The loader checks its read before it returns."
grep -q "DRY RUN, not edited:" "$tmp/out" || fail "a dry run did not say so: $(cat "$tmp/out")"
grep -q "gh pr edit 9 --repo octocat/Hello-World --body-file" "$tmp/out" || fail "the dry run did not print the command: $(cat "$tmp/out")"

# the prose gates a filing passes
edit 2 "$(printf 'The loader checks its read \xe2\x80\x94 before it returns.')"
edit 2 "The loader checks its read. Generated with Claude Code"
edit 2 "The loader checks its read before it returns." --title "$(printf 'fix \xe2\x80\x93 loader')"
edit 0 "The loader checks its read before it returns." --title "fix: loader checks its read"
long=$(for _ in $(seq 1 121); do printf 'word '; done)
edit 2 "$long"
grep -q "REFUSED: the body is 121 words" "$tmp/out" || fail "121 words printed no refusal: $(cat "$tmp/out")"
template="$HOUSEBROKEN_HOME/policy/template-octocat-Hello-World.md"
printf '## Checklist\n- [ ] Read the contributing guidelines.\n' > "$template"
edit 2 "The loader checks its read before it returns."
grep -q "keeps none of octocat/Hello-World's pull request template" "$tmp/out" || fail "a dropped template was not named: $(cat "$tmp/out")"
edit 0 "$(printf '## Checklist\n- [x] Read the contributing guidelines.\n\nThe loader checks its read before it returns.')"
edit 2 "$(printf '## Checklist\n- [x] Read the contributing guidelines.\n\n%s' "$long")"
rm -f "$template"
policy "DISCLOSE (a policy file requires AI use to be disclosed)"
edit 2 "The loader checks its read before it returns."
grep -q "requires AI use to be disclosed" "$tmp/out" || fail "a silent body under DISCLOSE was not refused: $(cat "$tmp/out")"
edit 0 "The loader checks its read before it returns. Written with Claude."
policy "CLEAN (no policy file names AI)"
edit 2 "The loader checks its read, see #99999999."
grep -q "does not exist" "$tmp/out" || fail "a reference to nothing was not named: $(cat "$tmp/out")"

# only an open pull request of ours
printf 'The loader checks its read before it returns.\n' > "$tmp/b.md"
out=$(bash "$script" octocat/Hello-World 8 --body-file "$tmp/b.md" 2>&1) && fail "someone else's pull request was edited"
printf '%s' "$out" | grep -q "is other's, not yours" || fail "the wrong author was not named: $out"
out=$(bash "$script" octocat/Hello-World 7 --body-file "$tmp/b.md" 2>&1) && fail "a merged pull request was edited"
printf '%s' "$out" | grep -q "is MERGED" || fail "the closed state was not named: $out"

# ten minutes between edits to one repository
mkdir -p "$HOUSEBROKEN_HOME/edits"
printf '%s octocat/Hello-World#9\n' "$(date -u +%s)" > "$HOUSEBROKEN_HOME/edits/octocat-Hello-World.log"
edit 2 "The loader checks its read before it returns."
grep -q "ten minutes" "$tmp/out" || fail "the spacing refusal did not say why: $(cat "$tmp/out")"
printf '%s octocat/Hello-World#9\n' "$(( $(date -u +%s) - 700 ))" > "$HOUSEBROKEN_HOME/edits/octocat-Hello-World.log"
edit 0 "The loader checks its read before it returns."

# a real edit reaches gh, keeps the copy verify compares against, and keeps what it replaced
writes="$tmp/writes.log"
rm -f "$HOUSEBROKEN_HOME/edits/octocat-Hello-World.log"
kept="$HOUSEBROKEN_HOME/filed/octocat-Hello-World-7fd1a60b01f91b314f59955a4e4d4e80d8edf11d.md"
mkdir -p "$HOUSEBROKEN_HOME/filed" && printf 'the body as filed\n' > "$kept"
printf 'The loader checks its read before it returns.\n' > "$tmp/b.md"
EDIT_PR_DRY=0 STUB_WRITES="$writes" bash "$script" octocat/Hello-World 9 --body-file "$tmp/b.md" > "$tmp/out" 2>&1 || { cat "$tmp/out" >&2; fail "a real edit failed"; }
grep -q "^pr edit 9 --repo octocat/Hello-World --body-file" "$writes" || fail "no edit reached gh"
cmp -s "$kept" "$tmp/b.md" || fail "the filed copy was not replaced with the new body"
set -- "$HOUSEBROKEN_HOME/filed/"octocat-Hello-World-7fd1a60b01f91b314f59955a4e4d4e80d8edf11d.md.prev-*
[ -f "$1" ] || fail "the replaced body was not kept"
[ -s "$HOUSEBROKEN_HOME/edits/octocat-Hello-World.log" ] || fail "the edit was not logged for the spacing"

echo "PASS $name"
