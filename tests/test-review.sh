#!/bin/bash
# test-review.sh - scripts/review.sh names a reviewer that is not the author,
# writes a brief bound to the head and the text, and its check refuses every
# report that is not a POST AS IS on exactly what is being sent. Each refusal
# sits beside the passing case it differs from by one line, so a check that
# cannot fail fails here. Nothing touches the network.
set -u
name=test-review
here=$(cd "$(dirname "$0")" && pwd)
script="$here/../scripts/review.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export HOUSEBROKEN_HOME="$tmp/home"
G="git -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false -c core.autocrlf=false"

fail() { echo "FAIL $name: $1" >&2; exit 1; }
sha() { (sha256sum "$1" 2>/dev/null || shasum -a 256 "$1") | awk '{print $1}'; }

# the reviewer: one tier down, never below sonnet, never the author
for pair in fable:opus opus:sonnet sonnet:opus haiku:sonnet claude-opus-5:sonnet claude-fable-5-1:opus "Claude Sonnet 5:opus"; do
  got=$(bash "$script" reviewer "${pair%%:*}") || fail "reviewer ${pair%%:*} exited non-zero"
  [ "$got" = "${pair##*:}" ] || fail "reviewer ${pair%%:*} gave $got, expected ${pair##*:}"
done
bash "$script" reviewer gpt-5 >/dev/null 2>&1
[ "$?" -eq 2 ] || fail "a model outside the table was given a default reviewer"

# a clone and a reply to review
clone="$tmp/clone"
mkdir -p "$clone"
(cd "$clone" && $G init -q && printf 'a\n' > a.txt && $G add -A && $G commit -q -m base) || fail "clone setup failed"
reply="$tmp/reply.md"
printf 'All 87 tests pass on the branch.\n' > "$reply"
head=$(git -C "$clone" rev-parse HEAD)
hash=$(sha "$reply")

brief=$(bash "$script" brief --author claude-opus-5 --repo octo/cat --clone "$clone" --text "$reply" 2>"$tmp/err") ||
  fail "brief exited non-zero"
for want in "reviewer-model: sonnet" "author-model: claude-opus-5" "head: $head" "text: sha256:$hash" \
  "All 87 tests" "Nothing leaves this machine" "strongest engineer in the language" "4. The form:"   "verdict: POST AS IS | POST WITH CHANGES | DO NOT POST"; do
  printf '%s\n' "$brief" | grep -qF "$want" || fail "brief is missing: $want"
done
report="$HOUSEBROKEN_HOME/reviews/review-octo-cat-${head:0:12}.md"
grep -qF "$report" "$tmp/err" || fail "brief did not name the report path $report"
[ -d "$HOUSEBROKEN_HOME/reviews" ] || fail "brief did not create the reviews directory"

# a reply with no clone is keyed by its own hash
bash "$script" brief --author fable --repo octo/cat --text "$reply" 2>"$tmp/err" >/dev/null || fail "text-only brief exited non-zero"
grep -qF "review-octo-cat-${hash:0:12}.md" "$tmp/err" || fail "text-only brief was not keyed by the text's sha256"

# an override that breaks the rule is refused; one that keeps it is not
bash "$script" brief --author opus --reviewer claude-opus-5 --repo octo/cat --clone "$clone" >/dev/null 2>&1
[ "$?" -eq 1 ] || fail "the author's own model was accepted as its reviewer"
bash "$script" brief --author opus --reviewer haiku --repo octo/cat --clone "$clone" >/dev/null 2>&1
[ "$?" -eq 1 ] || fail "haiku was accepted as a reviewer"
bash "$script" brief --author opus --reviewer fable --repo octo/cat --clone "$clone" >/dev/null 2>&1 ||
  fail "a different, stronger reviewer was refused"

# check: the report the brief asked for, then broken one line at a time
write_report() { # reviewer verdict head
  printf 'review-of: octo/cat\nhead: %s\ntext: sha256:%s reply.md\nauthor-model: claude-opus-5\nreviewer-model: %s\nverdict: %s\n\n1. NIT: nothing blocking.\n' \
    "$3" "$hash" "$1" "$2" > "$report"
}
passes() { bash "$script" check "$report" --clone "$clone" --text "$reply" >/dev/null 2>&1; }

write_report sonnet "POST AS IS" "$head"
passes || fail "a POST AS IS on the exact head and text was refused"
write_report sonnet "POST WITH CHANGES" "$head"
passes && fail "POST WITH CHANGES cleared the gate"
write_report sonnet "DO NOT POST" "$head"
passes && fail "DO NOT POST cleared the gate"
write_report claude-opus-5 "POST AS IS" "$head"
passes && fail "the author's own model cleared the gate as its reviewer"
write_report haiku "POST AS IS" "$head"
passes && fail "a reviewer below the floor cleared the gate"
write_report sonnet "POST AS IS | POST WITH CHANGES | DO NOT POST" "$head"
passes && fail "an unfilled verdict cleared the gate"

# the branch moves after the review, then the new head is reviewed
write_report sonnet "POST AS IS" "$head"
(cd "$clone" && printf 'b\n' >> a.txt && $G commit -q -am "after the review") || fail "second commit failed"
passes && fail "a commit made after the review cleared the gate"
write_report sonnet "POST AS IS" "$(git -C "$clone" rev-parse HEAD)"
passes || fail "a review of the new head was refused"

# the text changes after the review
printf 'All 88 tests pass on the branch.\n' > "$reply"
passes && fail "text edited after the review cleared the gate"

# only the header counts, the lines above the first blank line
now=$(git -C "$clone" rev-parse HEAD)
printf 'All 87 tests pass on the branch.\n' > "$reply"
write_report sonnet "POST AS IS" "$now"
passes || fail "the control for the cases below was refused"
write_report sonnet "DO NOT POST" "$now"
{ printf 'Quoting round one:\nverdict: POST AS IS\n\n'; cat "$report"; } > "$tmp/quoted" && mv "$tmp/quoted" "$report"
passes && fail "a verdict above the header cleared the gate"
other="$tmp/other.md"
printf 'A second reply.\n' > "$other"
write_report sonnet "POST AS IS" "$now"
printf '\nreview-of: octo/cat\nhead: %s\ntext: sha256:%s other.md\nauthor-model: claude-opus-5\nreviewer-model: sonnet\nverdict: DO NOT POST\n' "$now" "$(sha "$other")" >> "$report"
bash "$script" check "$report" --clone "$clone" --text "$other" >/dev/null 2>&1 && fail "a second round appended below the header cleared the gate"

# the floor is Sonnet, not a list of one name
write_report gpt-4o-mini "POST AS IS" "$now"
passes && fail "a model the table cannot place cleared the gate"
write_report "claude-haiku-4-5 (sonnet floor)" "POST AS IS" "$now"
passes && fail "a name that mentions haiku and sonnet cleared the gate"
write_report "" "POST AS IS" "$now"
passes && fail "a report naming no reviewer cleared the gate"

# a head too short to bind anything, and a report saved with CRLF
write_report sonnet "POST AS IS" "${now:0:7}"
passes && fail "a 7-character head cleared the gate"
write_report sonnet "POST AS IS" "$now"
awk '{printf "%s\r\n", $0}' "$report" > "$tmp/crlf" && mv "$tmp/crlf" "$report"
passes || fail "a report saved with CRLF was refused"

# a brief for a dirty clone, and a brief given Windows paths
printf 'dirty\n' >> "$clone/a.txt"
bash "$script" brief --author opus --repo octo/cat --clone "$clone" >/dev/null 2>&1 && fail "a brief was written for a dirty clone"
git -C "$clone" checkout -q -- a.txt
if command -v cygpath >/dev/null 2>&1; then
  bash "$script" brief --author claude-opus-5 --repo octo/cat --clone "$(cygpath -w "$clone")" --text "$(cygpath -w "$reply")" 2>/dev/null |
    grep -qF "text: sha256:$hash " || fail "a brief given a Windows path asked for a text line that check cannot match"
fi

# no report at all
rm -f "$report"
bash "$script" check "$report" --clone "$clone" >/dev/null 2>&1
[ "$?" -eq 1 ] || fail "a missing report was not refused"

echo "PASS $name"
