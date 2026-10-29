#!/bin/bash
# test-declare.sh - declare.sh writes a declaration for the head on its first
# run and refuses it until it names something untested and every assumption
# carries what breaks if it is wrong and how it was checked. Local only.
# shellcheck disable=SC2015  # "a && b || fail": fail exits, so it is the if-then-else it reads as
set -u
name=test-declare
here=$(cd "$(dirname "$0")" && pwd)
script="$here/../scripts/declare.sh"
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
export HOUSEBROKEN_HOME="$root/home"
G="git -c user.email=t@example.com -c user.name=t -c commit.gpgsign=false"

fail() { echo "FAIL $name: $1" >&2; exit 1; }

bash "$script" --help | grep -q "Usage:" || fail "--help printed no usage"
mkdir -p "$root/repo" && (cd "$root/repo" && $G init -q && $G commit -q --allow-empty -m base) || fail "fixture failed"
head=$(git -C "$root/repo" rev-parse HEAD)
decl="$HOUSEBROKEN_HOME/declarations/$head.md"

out=$(bash "$script" "$root/repo"); rc=$?
[ "$rc" -eq 1 ] && [ -f "$decl" ] || fail "the first run did not write a declaration and exit 1: $out"
bash "$script" "$root/repo" >/dev/null && fail "the unfilled template passed"

write() { printf 'head: %s\n\nnot-tested:\n%s\n\nassumptions:\n%s\n' "$head" "$1" "$2" > "$decl"; }
good_nt='- the AOT publish leg; no Windows runner here'
good_as='- callers pass the dictionary own comparer | if wrong: a found key reads as missing | checked by: grep -rn Comparer src, 3 call sites, all pass it'

write "$good_nt" "$good_as"
out=$(bash "$script" "$root/repo") || fail "a filled declaration was refused: $out"
write "- none" "$good_as"
bash "$script" "$root/repo" >/dev/null && fail "not-tested: none passed"
write "" "$good_as"
bash "$script" "$root/repo" >/dev/null && fail "an empty not-tested passed"
write "$good_nt" "- callers pass their comparer"
out=$(bash "$script" "$root/repo") && fail "an assumption without if wrong and checked by passed"
printf '%s' "$out" | grep -q "lacks '| if wrong" || fail "the bare assumption was not named: $out"
write "$good_nt" ""
bash "$script" "$root/repo" >/dev/null && fail "a declaration with no assumptions passed"
printf 'head: 0000\n\nnot-tested:\n%s\n\nassumptions:\n%s\n' "$good_nt" "$good_as" > "$decl"
bash "$script" "$root/repo" >/dev/null && fail "a declaration for another head passed"

printf 'head: %s\r\n\r\nnot-tested:\r\n%s\r\n\r\nassumptions:\r\n%s\r\n' "$head" "$good_nt" "$good_as" > "$decl"
bash "$script" "$root/repo" >/dev/null || fail "a declaration saved with CRLF endings was refused"

echo "PASS $name"
