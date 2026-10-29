#!/bin/bash
# test-reply.sh - reply.sh refuses a reply that opens with a verdict, thanks
# or an apology, carries an exclamation mark, bold, a closing offer, a dash,
# a footer, more than three sentences, or a reference to nothing, and one
# sent within ten minutes of the last to the repository; code spans are not
# read for tone. Every case is a dry run against octocat/Hello-World, whose
# history stands still: nothing is posted.
set -u
name=test-reply
here=$(cd "$(dirname "$0")" && pwd)
script="$here/../scripts/reply.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export HOUSEBROKEN_HOME="$tmp/home" REPLY_DRY=1

fail() { echo "FAIL $name: $1" >&2; exit 1; }

bash "$script" --help | grep -q "Usage:" || fail "--help printed no usage"

reply() { # expected-exit text [extra args]
  local want="$1" text="$2"; shift 2
  printf '%s\n' "$text" > "$tmp/r.md"
  bash "$script" octocat/Hello-World 1 --body-file "$tmp/r.md" "$@" > "$tmp/out" 2>&1
  [ "$?" = "$want" ] || { cat "$tmp/out" >&2; fail "exit not $want for: $text"; }
}

reply 0 "Every loader checks its read, so a truncated file fails on main; the description is corrected."
# shellcheck disable=SC2016  # the backticks are markdown
reply 0 'The `you are right` branch is gone, as #1 shows. Fine to close.'
reply 0 "Thanksgiving week is fine for the release."
reply 2 "You are right, the loader checks its read."
reply 2 "Good catch. Fixed in the second commit."
reply 2 "Thanks, fixed in the second commit."
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
reply 0 "The thread is answered in place." --in-reply-to 123456
grep -q "pulls/1/comments/123456/replies" "$tmp/out" || fail "--in-reply-to did not post to the review thread"
reply 2 "The thread is answered in place." --in-reply-to abc

# ten minutes between replies to one repository
mkdir -p "$HOUSEBROKEN_HOME/replies"
printf '%s octocat/Hello-World#1\n' "$(date -u +%s)" > "$HOUSEBROKEN_HOME/replies/octocat-Hello-World.log"
reply 2 "The parser checks its read on main."
grep -q "ten minutes" "$tmp/out" || fail "the spacing refusal did not say why"
printf '%s octocat/Hello-World#1\n' "$(( $(date -u +%s) - 700 ))" > "$HOUSEBROKEN_HOME/replies/octocat-Hello-World.log"
reply 0 "The parser checks its read on main."

echo "PASS $name"
