#!/bin/bash
# test-close.sh - close.sh withdraws only an open pull request of ours, with a
# note held to a reply's tone, ten minutes after our last comment on the
# repository; it closes with the note as the comment, logs it, records it in
# notes and deletes the fork branch the way hygiene would. A refusal, a dry run
# or a failed close writes nothing. Every write goes to the stub's log.
set -u
name=test-close
here=$(cd "$(dirname "$0")" && pwd)
script="$here/../scripts/close.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export HOUSEBROKEN_USER=me STUBS="$here/stubs" STUB_DIR="$tmp/stub" STUB_WRITES="$tmp/stub/writes"
mkdir -p "$tmp/stub" "$tmp/bin"
cat > "$tmp/bin/gh" <<'STUB'
#!/bin/bash
pr() { # author state
  printf '{"author":{"login":"%s"},"state":"%s","headRefName":"fix-it","headRepository":{"name":"Hello-World"},"headRepositoryOwner":{"login":"%s"}}\n' "$1" "$2" "$(cat "$STUB_DIR/owner" 2>/dev/null || echo me)"
}
case "$*" in
  "pr view 9 --repo octocat/Hello-World --json author,state,headRefName,headRepository,headRepositoryOwner"*) pr me OPEN ;;
  "pr view 5 --repo octocat/Hello-World --json author,state,headRefName,headRepository,headRepositoryOwner"*) pr me OPEN ;;
  "pr view 4 --repo octocat/Hello-World --json author,state,headRefName,headRepository,headRepositoryOwner"*) pr me OPEN ;;
  "pr view 8 --repo octocat/Hello-World --json author,state,headRefName,headRepository,headRepositoryOwner"*) pr other OPEN ;;
  "pr view 7 --repo octocat/Hello-World --json author,state,headRefName,headRepository,headRepositoryOwner"*) pr me MERGED ;;
  "pr view 6 --repo octocat/Hello-World"*) exit 1 ;;
  "api repos/octocat/Hello-World/issues/5/comments "*) exit 1 ;;
  "api repos/octocat/Hello-World/issues/"*"/comments -F body=@"*) printf '%s\n' "$*" >> "$STUB_WRITES"; echo "https://github.com/x" ;;
  "pr close 4 "*) exit 1 ;;
  "pr close "*) printf '%s\n' "$*" >> "$STUB_WRITES" ;;
  "api graphql"*) [ -f "$STUB_DIR/graphql.fail" ] && exit 1; cat "$STUB_DIR/ref" ;;
  "api -X DELETE"*) printf '%s\n' "$*" >> "$STUB_WRITES" ;;
  *) exec "$STUBS/gh" "$@" ;;
esac
STUB
chmod +x "$tmp/bin/gh"
export PATH="$tmp/bin:$STUBS:$PATH"

fail() { echo "FAIL $name: $1" >&2; exit 1; }
fresh() { # a clean home, no writes, a fork branch nobody else uses
  rm -rf "${tmp:?}/home" "$STUB_WRITES" "$STUB_DIR/graphql.fail" "$STUB_DIR/owner"
  export HOUSEBROKEN_HOME="$tmp/home"
  printf 'true\tyes\t\n' > "$STUB_DIR/ref"
}
closepr() { # expected-exit number text
  local want="$1" num="$2"
  printf '%s\n' "$3" > "$tmp/n.md"
  bash "$script" octocat/Hello-World "$num" --body-file "$tmp/n.md" > "$tmp/out" 2>&1
  [ "$?" = "$want" ] || { cat "$tmp/out" >&2; fail "exit not $want for #$num: $3"; }
}
nothing_written() { # why
  [ ! -s "$STUB_WRITES" ] || fail "$1 wrote to GitHub: $(cat "$STUB_WRITES")"
  [ ! -f "$HOUSEBROKEN_HOME/notes/octocat-Hello-World.md" ] || fail "$1 wrote a note"
  [ ! -f "$HOUSEBROKEN_HOME/replies/octocat-Hello-World.log" ] || fail "$1 wrote the reply log"
}
note="The same fix landed upstream in #1, so this one is withdrawn."

bash "$script" --help | grep -q "Usage:" || fail "--help printed no usage"
fresh
printf '%s\n' "$note" > "$tmp/n.md"
bash "$script" octocat 9 --body-file "$tmp/n.md" >/dev/null 2>&1; [ "$?" = 2 ] || fail "a repository without an owner was taken"
bash "$script" octocat/Hello-World nine --body-file "$tmp/n.md" >/dev/null 2>&1; [ "$?" = 2 ] || fail "a number that is not one was taken"
bash "$script" octocat/Hello-World 9 --body-file "$tmp/none.md" >/dev/null 2>&1; [ "$?" = 2 ] || fail "a missing note was taken"

# a dry run checks everything and writes nothing
fresh
CLOSE_DRY=1 closepr 0 9 "$note"
grep -q "^DRY RUN, not closed" "$tmp/out" || fail "the dry run did not say so: $(cat "$tmp/out")"
nothing_written "a dry run"

# the close itself: the note as the comment, the log, the note, the branch
fresh
closepr 0 9 "$note"
# the note goes out as the file's own bytes, then the pull request is closed
grep -qxF "api repos/octocat/Hello-World/issues/9/comments -F body=@$tmp/n.md --jq .html_url" "$STUB_WRITES" || fail "the note was not posted from its file: $(cat "$STUB_WRITES")"
sed -n 2p "$STUB_WRITES" | grep -qx "pr close 9 --repo octocat/Hello-World" || fail "the close did not follow the note: $(cat "$STUB_WRITES")"
grep -q "api -X DELETE repos/me/Hello-World/git/refs/heads/fix-it" "$STUB_WRITES" || fail "the fork branch was not deleted"
[ "$(grep -c . "$STUB_WRITES")" = 3 ] || fail "not exactly one note, one close and one delete: $(cat "$STUB_WRITES")"
grep -q "we closed #9: The same fix landed upstream" "$HOUSEBROKEN_HOME/notes/octocat-Hello-World.md" || fail "the close was not recorded in notes"
grep -q " octocat/Hello-World#9$" "$HOUSEBROKEN_HOME/replies/octocat-Hello-World.log" || fail "the close was not logged for the spacing"
tail -n 1 "$tmp/out" | grep -q "^closed octocat/Hello-World#9$" || fail "the last line is not the close: $(tail -n 1 "$tmp/out")"

# only an open pull request of ours, and a read that failed is not one
fresh
closepr 2 8 "$note"; grep -q "is other's, not yours" "$tmp/out" || fail "another author's pull request was not named: $(cat "$tmp/out")"
nothing_written "another author's pull request"
closepr 2 7 "$note"; grep -q "is MERGED" "$tmp/out" || fail "a merged pull request was not named: $(cat "$tmp/out")"
closepr 2 6 "$note"; grep -q "cannot read" "$tmp/out" || fail "a failed read was not named: $(cat "$tmp/out")"
nothing_written "a refused close"

# the note is held to a reply's tone
for bad in "Thanks, closing this." "Closing this in favour of #1!" "Closing. Let me know if it is wanted." \
  "One. Two. Three. Four." "$(printf 'Closing \xe2\x80\x94 the fix landed.')" "Closing. Generated with Claude Code" \
  "Superseded by #99999999."; do
  closepr 2 9 "$bad"
done
closepr 2 9 "One. Two. Three. Four."
grep -q "it runs 4 sentences; a close note is one to three$" "$tmp/out" || fail "the sentence limit did not name a close note: $(cat "$tmp/out")"
nothing_written "a refused note"

# a note of our own words is required
closepr 2 9 $'```\nlog line\n```'
grep -q "carries no note of its own" "$tmp/out" || fail "a note that is only a code block was taken: $(cat "$tmp/out")"
closepr 2 9 ""
grep -q "carries no note of its own" "$tmp/out" || fail "an empty note was taken"
# a quoted line is the maintainer's words, not ours
CLOSE_DRY=1 closepr 0 9 $'> thanks!\n\nThe fix landed upstream in #1.'

# ten minutes after our last comment on the repository, a reply or a close
mkdir -p "$HOUSEBROKEN_HOME/replies"
printf '%s octocat/Hello-World#1\n' "$(( $(date -u +%s) - 60 ))" > "$HOUSEBROKEN_HOME/replies/octocat-Hello-World.log"
closepr 2 9 "$note"; grep -q "ten minutes" "$tmp/out" || fail "the spacing refusal did not say why"
[ ! -s "$STUB_WRITES" ] || fail "a close inside ten minutes wrote to GitHub"

# a branch already gone, or not on a fork, is left without a failure
fresh
printf 'true\tno\t\n' > "$STUB_DIR/ref"
closepr 0 9 "$note"
grep -q "DELETE" "$STUB_WRITES" && fail "a branch that is gone was deleted"
fresh
printf 'false\tyes\t\n' > "$STUB_DIR/ref"
closepr 0 9 "$note"
grep -q "DELETE" "$STUB_WRITES" && fail "a branch of a repository that is not a fork was deleted"
# a head on someone else's repository is never ours to delete
fresh
echo maint > "$STUB_DIR/owner"
closepr 0 9 "$note"
grep -q "DELETE" "$STUB_WRITES" && fail "a branch on someone else's repository was deleted"

# a branch that could not be read: the close stands and the exit says the rest did not
fresh
touch "$STUB_DIR/graphql.fail"
closepr 1 9 "$note"
grep -q "pr close 9" "$STUB_WRITES" || fail "the close did not go through before the branch read"
grep -q "housebroken hygiene deletes it on its next run" "$tmp/out" || fail "the failed branch read was not followed by what to do: $(cat "$tmp/out")"
[ -f "$HOUSEBROKEN_HOME/replies/octocat-Hello-World.log" ] || fail "a close that went through was not logged"

# a note that could not be posted records nothing
fresh
closepr 2 5 "$note"
grep -q "^FAILED: the note was not posted on octocat/Hello-World#5, which is still open; nothing was recorded" "$tmp/out" || fail "a failed note was not named: $(cat "$tmp/out")"
nothing_written "a failed note"

# a close that fails after the note went out: the note is public, so the
# spacing holds and the message says so
fresh
closepr 2 4 "$note"
grep -q "^FAILED: the note is on octocat/Hello-World#4 but it is still open; read it before trying again" "$tmp/out" || fail "a close that failed after the note was not named: $(cat "$tmp/out")"
grep -q " octocat/Hello-World#4$" "$HOUSEBROKEN_HOME/replies/octocat-Hello-World.log" || fail "the posted note was not logged for the spacing"
[ ! -f "$HOUSEBROKEN_HOME/notes/octocat-Hello-World.md" ] || fail "a close that failed was recorded in notes"
grep -q "DELETE" "$STUB_WRITES" && fail "the branch of a pull request still open was deleted"
closepr 2 4 "$note"; grep -q "ten minutes" "$tmp/out" || fail "a retry right after a posted note was not refused"

echo "PASS $name"
