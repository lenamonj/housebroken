#!/bin/bash
# test-notes.sh - notes.sh reports an empty repository, appends dated lines in
# order, lists the repositories that have notes, and is reachable as
# `housebroken notes`. HOUSEBROKEN_HOME is a temporary directory, so the real
# notes are never touched. No network.
set -u
name=test-notes
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/.." && pwd)
script="$repo/scripts/notes.sh"
hb="$repo/bin/housebroken"

fail() { echo "FAIL $name: $1" >&2; exit 1; }

tmp=$(mktemp -d) || fail "mktemp failed"
trap 'rm -rf "$tmp"' EXIT
export HOUSEBROKEN_HOME="$tmp/home"

bash "$script" --help | grep -q "Usage:" || fail "--help has no usage"
bash "$script" --nonsense >/dev/null 2>&1 && fail "bad argument exited 0"

out=$(bash "$script" google/benchmark) || fail "printing an empty repository exited non-zero"
printf '%s\n' "$out" | grep -q "no notes for google/benchmark" || fail "empty repository not reported: $out"

bash "$script" google/benchmark add "no comment in a function that has none" >/dev/null ||
  fail "first add exited non-zero"
bash "$script" google/benchmark add "no default arguments to spare call sites" >/dev/null ||
  fail "second add exited non-zero"

file="$HOUSEBROKEN_HOME/notes/google-benchmark.md"
[ -f "$file" ] || fail "notes file not created at $file"
out=$(bash "$script" google/benchmark) || fail "printing exited non-zero"
printf '%s\n' "$out" | grep -q "^# notes: google/benchmark$" || fail "header missing: $out"
today=$(date -u +%Y-%m-%d)
first=$(printf '%s\n' "$out" | sed -n '2p')
second=$(printf '%s\n' "$out" | sed -n '3p')
[ "$first" = "- $today: no comment in a function that has none" ] || fail "first line wrong: $first"
[ "$second" = "- $today: no default arguments to spare call sites" ] || fail "second line wrong: $second"

out=$(bash "$script" --list) || fail "--list exited non-zero"
printf '%s\n' "$out" | grep -qx "google/benchmark" || fail "--list did not name the repository: $out"

out=$(bash "$hb" notes google/benchmark) || fail "housebroken notes exited non-zero"
printf '%s\n' "$out" | grep -q "no comment in a function that has none" ||
  fail "housebroken notes did not print the notes: $out"

rm -rf "$tmp"
trap - EXIT
echo "PASS $name"
