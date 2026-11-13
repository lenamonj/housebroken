#!/bin/bash
# test-reply.sh - reply.sh refuses a reply that opens with a verdict, thanks
# or an apology, carries an exclamation mark, bold, a closing offer, a dash,
# a footer, more than three sentences, or a reference to nothing, and one
# sent within ten minutes of the last to the repository; code spans are not
# read for tone. Every case is a dry run through the stub gh: nothing is
# posted.
set -u
name=test-reply
here=$(cd "$(dirname "$0")" && pwd)
export PATH="$here/stubs:$PATH"
script="$here/../scripts/reply.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export HOUSEBROKEN_HOME="$tmp/home" REPLY_DRY=1 HOUSEBROKEN_USER=me THREAD_DIR="$tmp/thread" STUBS="$here/stubs"
# the thread being answered, in front of the stub gh: by default a member spoke last
mkdir -p "$tmp/thread" "$tmp/bin"
cat > "$tmp/bin/gh" <<'STUB'
#!/bin/bash
case "$*" in
  "api repos/octocat/Hello-World/issues/1 --jq .pull_request"*) cat "$THREAD_DIR/kind" ;;
  "api --paginate repos/octocat/Hello-World/issues/1/comments"*) [ -f "$THREAD_DIR/ic.fail" ] && exit 1; cat "$THREAD_DIR/ic.json" ;;
  "api --paginate repos/octocat/Hello-World/pulls/1/reviews"*) cat "$THREAD_DIR/rv.json" ;;
  "api --paginate repos/octocat/Hello-World/pulls/1/comments"*) cat "$THREAD_DIR/rc.json" ;;
  "api repos/octocat/Hello-World/pulls/comments/123456"*) cat "$THREAD_DIR/one.json" ;;
  *) exec "$STUBS/gh" "$@" ;;
esac
STUB
chmod +x "$tmp/bin/gh"
export PATH="$tmp/bin:$PATH"
voice() { # login association [when]
  jq -n --arg l "$1" --arg r "$2" --arg t "${3:-2026-11-01T10:10:00Z}" '{created_at: $t, user: {login: $l, type: "User"}, author_association: $r, body: "x"}'
}
printf '' > "$tmp/thread/kind"
voice maint MEMBER | jq -s . > "$tmp/thread/ic.json"
echo '[]' > "$tmp/thread/rv.json"; echo '[]' > "$tmp/thread/rc.json"
jq -n '{user: {login: "maint"}, author_association: "MEMBER"}' > "$tmp/thread/one.json"

fail() { echo "FAIL $name: $1" >&2; exit 1; }

bash "$script" --help | grep -q "Usage:" || fail "--help printed no usage"

reply() { # expected-exit text [extra args]
  local want="$1" text="$2"; shift 2
  printf '%s\n' "$text" > "$tmp/r.md"
  bash "$script" octocat/Hello-World 1 --body-file "$tmp/r.md" "$@" > "$tmp/out" 2>&1
  [ "$?" = "$want" ] || { cat "$tmp/out" >&2; fail "exit not $want for: $text"; }
  # every reason a refused reply lists carries the name of its rule
  if [ "$want" = 2 ] && grep -E '^    ' "$tmp/out" | grep -vqE ' \[[a-z0-9]+(-[a-z0-9]+)+\]$'; then fail "a reason with no name: $(cat "$tmp/out")"; fi
}

reply 0 "Every loader checks its read, so a truncated file fails on main; the description is corrected."
# shellcheck disable=SC2016  # the backticks are markdown
reply 0 'The `you are right` branch is gone, as #1 shows. Fine to close.'
reply 0 "Thanksgiving week is fine for the release."
reply 2 "You are right, the loader checks its read."
reply 2 "Good catch. Fixed in the second commit."
reply 2 "Thanks, fixed in the second commit."
grep -qx 'REFUSED: the reply to octocat/Hello-World#1 is not ready: \[reply-not-ready\]' "$tmp/out" || fail "the summary line does not end with its name: $(cat "$tmp/out")"
grep -qx '    it thanks or apologises; state the fact and what changed \[common-tone-thanks\]' "$tmp/out" || fail "the tone reason does not end with its name: $(cat "$tmp/out")"
[ "$(tail -n 2 "$HOUSEBROKEN_HOME/refusals.tsv" | cut -f2,3 | tr '\t\n' '  ')" = "common-tone-thanks octocat/Hello-World reply-not-ready octocat/Hello-World " ] || fail "the log does not hold the reason and the refusal: $(tail -n 2 "$HOUSEBROKEN_HOME/refusals.tsv")"
# a shared check that hands back a reason with no name: the reason is listed as it came, under no made-up name
mkdir "$tmp/s" || fail "fixture failed"
cp "$here"/../scripts/*.sh "$tmp/s/" || fail "fixture failed"
sed 's/reason common-tone-thanks "/echo "/' "$here/../scripts/common.sh" > "$tmp/s/common.sh"
cmp -s "$here/../scripts/common.sh" "$tmp/s/common.sh" && fail "nothing was planted in common.sh"
printf '%s\n' "Thanks, fixed in the second commit." > "$tmp/r.md"
bash "$tmp/s/reply.sh" octocat/Hello-World 1 --body-file "$tmp/r.md" > "$tmp/out" 2>&1
[ "$?" = 2 ] || fail "a reason with no name did not refuse: $(cat "$tmp/out")"
grep -qx '    it thanks or apologises; state the fact and what changed' "$tmp/out" || fail "a reason with no name was given one: $(cat "$tmp/out")"
reply 2 "Fixed in the second commit!"
reply 2 "Fixed in **the second commit**."
reply 2 "Fixed. Let me know if anything else is needed."
reply 2 "One. Two. Three. Four."
reply 0 "One. Two. Three. Four." --long
reply 2 "Fixed, see #99999999."
reply 2 "$(printf 'Fixed \xe2\x80\x94 see the commit.')"
reply 2 "Fixed. Generated with Claude Code"
reply 2 "Agreed, the loader checks its read; fixed in the second commit."
reply 2 "Yes, you are right, the loader checks its read."
reply 2 "The loader checks its read; fixed in the second commit. Thanks for the review."
reply 2 "The loader checks its read. In summary, the fix is complete."
reply 0 "Yes, the comparer is the caller's own; the lookup reuses it."
reply 0 $'1. Check out the branch.\n2. Run the test.\n3. Compare the output with main.'
reply 0 "$(printf '> fixed \xe2\x80\x94 thanks\n\nThe test now runs on main and fails before the fix.')"
reply 2 "You're absolutely right, the loader checks its read."
reply 2 "$(printf 'You\xe2\x80\x99re right, the loader checks its read.')"
# shellcheck disable=SC2016  # the backticks are markdown
reply 2 '`foo` fails. `bar` passes. `baz` hangs. `qux` crashes. `quux` leaks.'
reply 2 "The first run fails. 3 tests cover it. 2 more run on CI. 1 is skipped."
reply 2 "Fixed &mdash; see the commit."
reply 2 "Fixed &#8212; see the commit."
reply 2 $'```\nThanks, you are right! Fixed.'
reply 2 "Fixed. Generated by Claude Code"
reply 0 "The thread is answered in place." --in-reply-to 123456
grep -q "pulls/1/comments/123456/replies" "$tmp/out" || fail "--in-reply-to did not post to the review thread"
reply 2 "The thread is answered in place." --in-reply-to abc

# whom it answers: the newest voice on the thread that is not ours and not a
# bot must have a role in the repository, or the user must have said --outsider
voice stranger NONE | jq -s . > "$tmp/thread/ic.json"
reply 2 "The parser checks its read on main."
grep -q "stranger (NONE) has no role in octocat/Hello-World" "$tmp/out" || fail "an outsider's thread was not refused for that: $(cat "$tmp/out")"
reply 0 "The parser checks its read on main." --outsider
voice fan CONTRIBUTOR | jq -s . > "$tmp/thread/ic.json"
reply 2 "The parser checks its read on main."
# our own later comment does not make the outsider's the maintainer's; a bot's does not count as a voice
{ voice stranger NONE; voice me OWNER 2026-11-01T11:00:00Z; } | jq -s . > "$tmp/thread/ic.json"
reply 2 "The parser checks its read on main."
{ voice maint MEMBER; voice "codecov[bot]" NONE 2026-11-01T11:00:00Z; } | jq -s . > "$tmp/thread/ic.json"
reply 0 "The parser checks its read on main."
# on a pull request, a review or an inline comment is a voice too
printf 'https://api.github.com/repos/octocat/Hello-World/pulls/1\n' > "$tmp/thread/kind"
voice maint MEMBER | jq -s . > "$tmp/thread/ic.json"
jq -n '[{submitted_at: "2026-11-01T12:00:00Z", user: {login: "stranger", type: "User"}, author_association: "NONE", state: "COMMENTED", body: "x"}]' > "$tmp/thread/rv.json"
reply 2 "The parser checks its read on main."
echo '[]' > "$tmp/thread/rv.json"
voice stranger NONE 2026-11-01T12:00:00Z | jq -s . > "$tmp/thread/rc.json"
reply 2 "The parser checks its read on main."
echo '[]' > "$tmp/thread/rc.json"
reply 0 "The parser checks its read on main."
printf '' > "$tmp/thread/kind"
# an empty thread answers nobody in particular
echo '[]' > "$tmp/thread/ic.json"
reply 0 "The parser checks its read on main."
# a read that failed is not an empty thread
touch "$tmp/thread/ic.fail"
reply 2 "The parser checks its read on main."
grep -q "cannot read" "$tmp/out" || fail "a failed read of the thread was not named: $(cat "$tmp/out")"
rm -f "$tmp/thread/ic.fail"
voice maint MEMBER | jq -s . > "$tmp/thread/ic.json"
# an inline answer reads the comment it answers
jq -n '{user: {login: "stranger"}, author_association: "NONE"}' > "$tmp/thread/one.json"
reply 2 "The thread is answered in place." --in-reply-to 123456
reply 0 "The thread is answered in place." --in-reply-to 123456 --outsider
jq -n '{user: {login: "maint"}, author_association: "COLLABORATOR"}' > "$tmp/thread/one.json"
reply 0 "The thread is answered in place." --in-reply-to 123456

# a reply that rides on a review is held to it: a report that does not clear this
# text stops the reply
printf 'review-of: octocat/Hello-World\ntext: sha256:0000 r.md\nauthor-model: opus\nreviewer-model: sonnet\nskipped: none\nverdict: POST AS IS\n\n1. NIT: fine.\n' > "$tmp/report.md"
reply 2 "The parser checks its read on main." --review "$tmp/report.md"
grep -q "review does not clear this text" "$tmp/out" || fail "the failed review was not named"
sha() { (sha256sum "$1" 2>/dev/null || shasum -a 256 "$1") | awk '{print $1}'; }
printf 'The parser checks its read on main.\n' > "$tmp/r.md"
sed -i.bak "s/sha256:0000/sha256:$(sha "$tmp/r.md")/" "$tmp/report.md" && rm -f "$tmp/report.md.bak"
reply 0 "The parser checks its read on main." --review "$tmp/report.md"

# ten minutes between replies to one repository
mkdir -p "$HOUSEBROKEN_HOME/replies"
printf '%s octocat/Hello-World#1\n' "$(date -u +%s)" > "$HOUSEBROKEN_HOME/replies/octocat-Hello-World.log"
reply 2 "The parser checks its read on main."
grep -q "ten minutes" "$tmp/out" || fail "the spacing refusal did not say why"
printf '%s octocat/Hello-World#1\n' "$(( $(date -u +%s) - 700 ))" > "$HOUSEBROKEN_HOME/replies/octocat-Hello-World.log"
reply 0 "The parser checks its read on main."

# a real reply reaches gh and starts the ten minutes; the stub writes only to this log
writes="$tmp/writes.log"
rm -f "$HOUSEBROKEN_HOME/replies/octocat-Hello-World.log"
printf 'The parser checks its read on main.\n' > "$tmp/r.md"
REPLY_DRY=0 STUB_WRITES="$writes" bash "$script" octocat/Hello-World 1 --body-file "$tmp/r.md" > "$tmp/out" 2>&1 || { cat "$tmp/out" >&2; fail "a real reply failed"; }
grep -q "^api repos/octocat/Hello-World/issues/1/comments" "$writes" || fail "no post reached gh"
[ -s "$HOUSEBROKEN_HOME/replies/octocat-Hello-World.log" ] || fail "the reply was not logged for the spacing"

echo "PASS $name"
