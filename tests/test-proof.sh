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

# a detected rename: the base arm gets the old path back, so a test that reads either path runs the base code
git checkout -q -b rename upstream-main
seq 1 30 | sed 's/^15$/buggy/' > src/big.txt && $G add -A && $G commit -q -m big && git branch -f rename-base
git mv src/big.txt src/big2.txt && seq 1 30 | sed 's/^15$/fixed/' > src/big2.txt
printf '#!/bin/bash\ngrep -q fixed src/big*.txt\n' > src/big_test.sh && $G add -A && $G commit -q -m fix
git diff --name-status rename-base HEAD | grep -q '^R' || fail "fixture: the rename was not detected"
head=$(git rev-parse HEAD)
out=$(bash "$script" . --base rename-base --test 'bash src/big_test.sh'); rc=$?
[ "$rc" -eq 0 ] || fail "a renamed fix was refused: $out"
grep -q '^base-file: [0-9a-f]* src/big.txt' "$HOUSEBROKEN_HOME/proofs/$head" || fail "the base arm did not get the old path back"
git checkout -q -b rename2 rename-base
git mv src/big.txt src/big2.txt && seq 1 30 | sed 's/^15$/buggy/; s/^20$/twenty/' > src/big2.txt
printf '#!/bin/bash\ngrep -q 1 src/big*.txt\n' > src/big_test.sh && $G add -A && $G commit -q -m "rename, no fix"
out=$(bash "$script" . --base rename-base --test 'bash src/big_test.sh'); rc=$?
[ "$rc" -eq 1 ] || fail "a rename with no fix exited $rc, expected 1: $out"

# a clone checked out with core.autocrlf=true comes back with its CRLF endings and a clean status
git checkout -q -b crlf upstream-main
printf 'fixed\n' > src/lib.txt && printf '#!/bin/bash\ngrep -q fixed src/lib.txt\n' > src/lib_test.sh && $G add -A && $G commit -q -m fix
git config core.autocrlf true && rm src/lib.txt && git checkout -q -- src/lib.txt
git ls-files --eol src/lib.txt | grep -q 'w/crlf' || fail "fixture: the worktree is not CRLF"
out=$(bash "$script" . --base upstream-main --test 'bash src/lib_test.sh'); rc=$?
[ "$rc" -eq 0 ] && [ -z "$(git status --porcelain)" ] || fail "an autocrlf clone was refused or left dirty: $out $(git status --porcelain)"
git ls-files --eol src/lib.txt | grep -q 'w/crlf' || fail "the restore changed the line endings"
git config core.autocrlf false && rm src/lib.txt && git checkout -q -- src/lib.txt

# an untracked file the command leaves is a note; a tracked file it rewrites is refused by name
git checkout -q -b leftover upstream-main
printf 'lock\n' > lock.txt && $G add -A && $G commit -q -m lock && git branch -f lock-base
printf 'fixed\n' > src/lib.txt && printf '#!/bin/bash\necho x > scratch.txt; grep -q fixed src/lib.txt\n' > src/lib_test.sh && $G add -A && $G commit -q -m fix
out=$(bash "$script" . --base lock-base --test 'bash src/lib_test.sh'); rc=$?
[ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q "note: the test command left untracked files.*scratch.txt" || fail "an untracked leftover was not a note: $out"
rm -f scratch.txt
printf '#!/bin/bash\necho y >> lock.txt; grep -q fixed src/lib.txt\n' > src/lib_test.sh && $G add -A && $G commit -q -m rewrite
out=$(bash "$script" . --base lock-base --test 'bash src/lib_test.sh' 2>&1); rc=$?
[ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q "changed tracked files" && printf '%s' "$out" | grep -q "lock.txt" || fail "a rewritten tracked file was not named: $out"
git checkout -q -- lock.txt

# a command whose script the base arm takes away did not run; that is not red
git checkout -q -b repro upstream-main
printf '#!/bin/bash\ngrep -q fixed src/lib.txt\n' > src/repro.sh && printf 'fixed\n' > src/lib.txt && $G add -A && $G commit -q -m repro
out=$(bash "$script" . --base upstream-main --test 'bash src/repro.sh'); rc=$?
[ "$rc" -eq 1 ] && printf '%s' "$out" | grep -q "did not run" || fail "a missing script read as red: $out"
# --keep, --fix and --base-file name files the branch changes, as git prints them
out=$(bash "$script" . --base upstream-main --test 'bash src/repro.sh' --keep ./src/repro.sh 2>&1); rc=$?
[ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q "not a file this branch changes" || fail "an unknown --keep passed: $out"

# --fix takes away a file whose path says test
git checkout -q -b testing upstream-main
mkdir -p src/testing && printf 'fixed\n' > src/testing/util.txt && printf '#!/bin/bash\ngrep -q fixed src/testing/util.txt\n' > src/lib_test.sh && $G add -A && $G commit -q -m util
out=$(bash "$script" . --base upstream-main --test 'bash src/lib_test.sh' 2>&1); rc=$?
[ "$rc" -eq 2 ] && printf '%s' "$out" | grep -q "every changed file is a test or kept" || fail "a fix under testing/ was taken away: $out"
out=$(bash "$script" . --base upstream-main --test 'bash src/lib_test.sh' --fix src/testing/util.txt); rc=$?
[ "$rc" -eq 0 ] || fail "--fix was refused: $out"

# one file carrying the test and the fix: --base-file gives the base arm the base plus the test
git checkout -q -b inline upstream-main
printf 'fixed\n# test: grep -q ^fixed src/lib.txt\n' > src/lib.txt && $G add -A && $G commit -q -m inline
printf 'buggy\n# test: grep -q ^fixed src/lib.txt\n' > "$root/base-plus-test.txt"
# shellcheck disable=SC2016  # the command is evaluated later, in the arm
inline_cmd='bash -c "$(sed -n "s/^# test: //p" src/lib.txt)"'
out=$(bash "$script" . --base upstream-main --test "$inline_cmd"); rc=$?
[ "$rc" -eq 1 ] || fail "without --base-file the inline test exited $rc, expected 1: $out"
out=$(bash "$script" . --base upstream-main --test "$inline_cmd" --base-file "src/lib.txt=$root/base-plus-test.txt"); rc=$?
[ "$rc" -eq 0 ] && grep -q '^base-from: src/lib.txt=' "$HOUSEBROKEN_HOME/proofs/$(git rev-parse HEAD)" || fail "--base-file was refused: $out"

# no --base and no stamp: the clone's upstream or origin main
git update-ref refs/remotes/origin/main upstream-main
out=$(bash "$script" . --test "$inline_cmd" --base-file "src/lib.txt=$root/base-plus-test.txt"); rc=$?
[ "$rc" -eq 0 ] || fail "the origin/main fallback failed: $out"

echo "PASS $name"
