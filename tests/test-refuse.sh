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

# shellcheck source=scripts/refuse.sh
. "$scripts/refuse.sh"

# the line is on stdout, for the caller to redirect, and refused returns 0
out=$(repo="o/r"; refused x-y "m" 2>/dev/null)
[ "$out" = "REFUSED: m [x-y]" ] || fail "refused did not print its line on stdout: $out"
[ -z "$(refused x-y "m" 2>&1 >/dev/null)" ] || fail "refused printed on stderr"
refused x-y "m" >/dev/null || fail "refused did not return 0"

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

echo "PASS $name"
