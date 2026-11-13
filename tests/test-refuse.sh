#!/bin/bash
# test-refuse.sh - refuse.sh ends a refusal with its rule's name and leaves one
# line in the local log: the time, the name and the repository. A name or a
# repository that is not in its form never reaches the log, a reason handed
# back as text is split at its first pipe, the line stays on stdout for the
# caller to redirect, and a log that cannot be written changes nothing but
# one line on stderr.
# shellcheck disable=SC2015  # "a && b || fail": fail exits, so it is the if-then-else it reads as
set -u
name=test-refuse
here=$(cd "$(dirname "$0")" && pwd)
scripts="$here/../scripts"
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
export HOUSEBROKEN_HOME="$root/home"
log="$HOUSEBROKEN_HOME/refusals.tsv"
tab=$(printf '\t')

fail() { echo "FAIL $name: $1" >&2; exit 1; }
lines() { if [ -f "$log" ]; then wc -l < "$log" | tr -d ' '; else echo 0; fi; }

# through a script: the line, the stream, the exit and the log
err=$(bash "$scripts/push.sh" notarepo 2>&1 >/dev/null); rc=$?
[ "$rc" -eq 2 ] || fail "exit $rc"
[ "$err" = "REFUSED: name the upstream repository as owner/repo [push-repo-form]" ] || fail "line: $err"
[ "$(lines)" = 1 ] || fail "not exactly one line: $(lines)"
[ "$(cut -f2,3 "$log")" = "push-repo-form$tab-" ] || fail "fields: $(cat "$log")"
grep -qE "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$tab" "$log" || fail "time: $(cat "$log")"
[ "$(awk -F'\t' '{print NF}' "$log")" = 3 ] || fail "not three fields: $(cat "$log")"

# a refusal after the repository was read carries it
mkdir "$root/plain"
err=$(bash "$scripts/push.sh" apache/commons-io "$root/plain" 2>&1 >/dev/null); rc=$?
[ "$rc" -eq 2 ] || fail "exit $rc for a directory that is not a clone"
printf '%s\n' "$err" | grep -q ' is not a git clone \[push-not-a-clone\]$' || fail "line: $err"
[ "$(tail -n 1 "$log" | cut -f2,3)" = "push-not-a-clone${tab}apache/commons-io" ] || fail "repo: $(tail -n 1 "$log")"

# a command that is not refused writes nothing
n=$(lines)
bash "$scripts/push.sh" --help >/dev/null || fail "--help failed"
[ "$(lines)" = "$n" ] || fail "a command that was not refused wrote to the log"

# the earliest refusal of every script is named, so the helper is in hand before it
first() { # script name-expected args...
  local s="$1" want="$2" got; shift 2
  got=$(bash "$scripts/$s.sh" "$@" 2>&1)
  printf '%s\n' "$got" | grep -q "^REFUSED: .* \[$want\]\$" || fail "$s.sh: its first refusal is not named $want: $got"
}
first branch-check branch-check-base-no-ref . --base
first claim-check claim-check-no-file-named
first close close-repo-form notarepo
first declare declare-unknown-option --bogus
first edit-pr edit-pr-repo-form notarepo
first file-issue file-issue-repo-form notarepo
first file-pr file-pr-repo-form notarepo
first proof proof-unknown-option --bogus
first ref-check ref-check-repo-form notarepo
first reply reply-repo-form notarepo
first review review-no-report check "$root/no-such-report.md"

# shellcheck source=scripts/refuse.sh
. "$scripts/refuse.sh"

# the line is on stdout, for the caller to redirect, and refused returns 0
out=$(repo="o/r"; refused x-y "m" 2>/dev/null)
[ "$out" = "REFUSED: m [x-y]" ] || fail "refused did not print its line on stdout: $out"
[ -z "$(refused x-y "m" 2>&1 >/dev/null)" ] || fail "refused printed on stderr"
refused x-y "m" >/dev/null || fail "refused did not return 0"
# a message of several lines: the name ends the line that says REFUSED, and the rest follows as it was
out=$(refused x-y "the reply is not ready:
    one [a-b]
    two" 2>/dev/null)
[ "$out" = "REFUSED: the reply is not ready: [x-y]
    one [a-b]
    two" ] || fail "a message of several lines: $out"

# a repository that is not owner/name reaches the log as -
for odd in "a/b${tab}c" "a/b/c" "$(printf 'a/b\nc/d')" "nothing" "o/r x" ""; do
  repo="$odd"
  refused x-y "m" >/dev/null
  [ "$(tail -n 1 "$log" | cut -f2,3)" = "x-y$tab-" ] || fail "an odd repository reached the log: $(tail -n 1 "$log")"
done
unset repo
refused x-y "m" >/dev/null
[ "$(tail -n 1 "$log" | cut -f3)" = "-" ] || fail "no repository at all did not read as -"
[ "$(awk -F'\t' 'NF != 3' "$log" | wc -l | tr -d ' ')" = 0 ] || fail "a line does not have three fields"
repo="o/r"

# a name that is not in the form never reaches the log
n=$(lines)
err=$( { refusal_log 'Not A Slug'; refusal_log "a-b${tab}c"; refusal_log ""; refusal_log single; refusal_log "a-b|c"; } 2>&1 )
[ "$(lines)" = "$n" ] || fail "a name outside the form reached the log"
[ "$(printf '%s\n' "$err" | grep -c 'was not logged')" = 5 ] || fail "an unnamed refusal was not said each time: $err"

# a reason handed back as text is split at its first pipe only
[ "$(reason common-tone-bold "it has bold | and a pipe")" = "common-tone-bold|it has bold | and a pipe" ] || fail "reason did not print name, pipe, message"
out=$(refused_reason "common-tone-bold|it has bold | and a pipe" 2>/dev/null)
[ "$out" = "REFUSED: it has bold | and a pipe [common-tone-bold]" ] || fail "split past the first pipe: $out"
[ "$(tail -n 1 "$log" | cut -f2,3)" = "common-tone-bold${tab}o/r" ] || fail "the reason's name is not in the log: $(tail -n 1 "$log")"
# a line that carries no name is printed as it came and said, never logged under a guess
n=$(lines)
out=$(refused_reason "it has bold" 2>"$root/err")
[ "$out" = "REFUSED: it has bold" ] || fail "a reason with no name: $out"
[ "$(lines)" = "$n" ] || fail "a reason with no name was logged"
grep -q 'was not logged' "$root/err" || fail "a reason with no name was not said"

# a log that cannot be written: the line, the stream and the exit are what they were
printf 'x\n' > "$root/afile"
err=$(HOUSEBROKEN_HOME="$root/afile" bash "$scripts/push.sh" notarepo 2>&1 >/dev/null); rc=$?
[ "$rc" -eq 2 ] || fail "an unwritable log changed the exit: $rc"
printf '%s\n' "$err" | grep -qxF 'REFUSED: name the upstream repository as owner/repo [push-repo-form]' || fail "an unwritable log changed the line: $err"
[ "$(printf '%s\n' "$err" | grep -c 'could not be written')" = 1 ] || fail "the unwritable log was not said: $err"
[ "$(cat "$root/afile")" = "x" ] || fail "the file in the log's place was changed"
out=$(HOUSEBROKEN_HOME="$root/afile" bash "$scripts/push.sh" notarepo 2>/dev/null)
[ -z "$out" ] || fail "an unwritable log put text on stdout: $out"
# and a script that refuses twice says it once
err=$( HOUSEBROKEN_HOME="$root/afile"; { refused x-y "one"; refused x-y "two"; } 2>&1 >/dev/null )
[ "$(printf '%s\n' "$err" | grep -c 'could not be written')" = 1 ] || fail "the unwritable log was said more than once: $err"

# with no home at all the refusal is what it was, and the log is said unwritable
err=$(env -u HOME -u HOUSEBROKEN_HOME bash "$scripts/push.sh" notarepo 2>&1 >/dev/null); rc=$?
[ "$rc" -eq 2 ] || fail "no home changed the exit: $rc: $err"
printf '%s\n' "$err" | grep -qxF 'REFUSED: name the upstream repository as owner/repo [push-repo-form]' || fail "no home changed the line: $err"
[ "$(printf '%s\n' "$err" | grep -c 'could not be written')" = 1 ] || fail "no home was not said: $err"

# the time is UTC whatever the machine's zone is
before=$(date -u +%Y-%m-%dT%H)
TZ=JST-9 bash "$scripts/push.sh" notarepo >/dev/null 2>&1
after=$(date -u +%Y-%m-%dT%H)
got=$(tail -n 1 "$log" | cut -c1-13)
[ "$got" = "$before" ] || [ "$got" = "$after" ] || fail "the time is not UTC: $got, not $before"

# a script that sources common.sh alone can still refuse through it
printf '%s 1\n' "$(date -u +%s)" > "$root/filing.log"
out=$(bash -c 'set -u; . "$1/common.sh"; filing_log() { echo "$2"; }; spacing_gate o/r "$2"' _ "$scripts" "$root/filing.log" 2>&1); rc=$?
[ "$rc" -eq 2 ] || fail "common.sh alone: exit $rc: $out"
printf '%s\n' "$out" | grep -qE '^REFUSED: your last filing on o/r .* \[common-filing-too-soon-after-last\]$' || fail "common.sh alone did not refuse by name: $out"

echo "PASS $name"
