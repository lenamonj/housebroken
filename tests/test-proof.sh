#!/bin/bash
# test-proof.sh - proof.sh stamps only an experiment that shows the fix: red
# on the base, green on the head, different code in the two arms, and the
# head restored byte for byte. Each refusal is paired with the change that
# lifts it. Local only.
# shellcheck disable=SC2015  # "a && b || fail": fail exits, so it is the if-then-else it reads as
set -u
name=test-proof
here=$(cd "$(dirname "$0")" && pwd)
script="$here/../scripts/proof.sh"
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
export HOUSEBROKEN_HOME="$root/home"
G="git -c user.email=t@example.com -c user.name=t -c core.autocrlf=false -c commit.gpgsign=false"

fail() { echo "FAIL $name: $1" >&2; exit 1; }

bash "$script" --help | grep -q "Usage:" || fail "--help printed no usage"

repo="$root/repo"
mkdir -p "$repo/src" && cd "$repo" || fail "fixture failed"
$G init -q -b main . && printf 'buggy\n' > src/lib.txt && $G add -A && $G commit -q -m base && git branch upstream-main ||
  fail "fixture failed"
# The test passes when the library says fixed; the fix is the library change.
printf '#!/bin/bash\ngrep -q fixed src/lib.txt\n' > src/lib_test.sh
printf 'fixed\n' > src/lib.txt
$G add -A && $G commit -q -m fix || fail "fixture failed"
head=$(git rev-parse HEAD)
before=$(git hash-object src/lib.txt)

out=$(bash "$script" . --base upstream-main --test 'bash src/lib_test.sh'); rc=$?
[ "$rc" -eq 0 ] || fail "a real red-green run was refused: $out"
stamp="$HOUSEBROKEN_HOME/proofs/$head"
grep -q '^proof: red-green' "$stamp" || fail "no red-green stamp"
grep -q '^base-exit: 1' "$stamp" && grep -q '^head-exit: 0' "$stamp" || fail "the stamp does not record both exits"
[ "$(git hash-object src/lib.txt)" = "$before" ] && [ -z "$(git status --porcelain)" ] || fail "the head was not restored"

# a test that passes on the base too shows nothing
rm -f "$stamp"
out=$(bash "$script" . --base upstream-main --test 'true'); rc=$?
[ "$rc" -eq 1 ] || fail "a test that always passes exited $rc"
printf '%s' "$out" | grep -q "passes without the fix" || fail "the always-green test was not named: $out"
[ ! -f "$stamp" ] || fail "an always-green test was stamped"

# a test that fails with the fix too
out=$(bash "$script" . --base upstream-main --test 'false'); rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "fails with the fix" || fail "an always-red test was not refused: $out"

# a fix kept by --keep leaves nothing to take away
out=$(bash "$script" . --base upstream-main --test 'bash src/lib_test.sh' --keep src/lib.txt 2>&1); rc=$?
[ "$rc" -eq 2 ] || fail "with every change kept, exited $rc"

# a dirty tree is refused before anything is swapped
printf 'scratch\n' > notes.txt
bash "$script" . --base upstream-main --test 'bash src/lib_test.sh' >/dev/null 2>&1
[ "$?" -eq 2 ] || fail "a dirty tree was not refused"
rm -f notes.txt

# a file the branch adds is removed in the base arm and put back after
printf 'helper\n' > src/helper.txt && $G add -A && $G commit -q -m helper
head=$(git rev-parse HEAD)
out=$(bash "$script" . --base upstream-main --test '[ -f src/helper.txt ] && bash src/lib_test.sh'); rc=$?
[ "$rc" -eq 0 ] || fail "an added file broke the run: $out"
[ -f src/helper.txt ] && [ -z "$(git status --porcelain)" ] || fail "an added file was not put back"

# --none records the reason instead
out=$(bash "$script" . --none 'documentation only'); rc=$?
[ "$rc" -eq 0 ] && grep -q '^reason: documentation only' "$HOUSEBROKEN_HOME/proofs/$head" || fail "--none did not record its reason"

echo "PASS $name"
