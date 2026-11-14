#!/bin/bash
# test-comment-check.sh - an added comment is refused, a reworded one passes, a
# new file's licence header passes when its neighbours carry one, a test file
# counts, and --asked turns the refusal into a check. Local git only.
set -u
name=test-comment-check
script="$(cd "$(dirname "$0")/../scripts" && pwd)/comment-check.sh"

bash "$script" --help | grep -q "Usage:" || { echo "FAIL $name: --help has no usage"; exit 1; }
bash "$script" /definitely/not/a/directory --base main >/dev/null 2>&1
[ "$?" = "2" ] || { echo "FAIL $name: missing directory did not exit 2"; exit 1; }

root=$(mktemp -d) || exit 1
trap 'rm -rf "$root"' EXIT
repo="$root/repo"
G="git -c user.email=t@example.com -c user.name=t -c core.autocrlf=false"
mkdir -p "$repo/src" || exit 1
(
  cd "$repo" || exit 1
  $G init -q -b main .
  printf '// Copyright The Project Authors\n// SPDX-License-Identifier: MIT\n\npackage a\n\nfunc A() int { return 1 }\n' > src/a.go
  printf 'package b\n\n// B returns two.\nfunc B() int { return 2 }\n' > src/b.go
  printf '# notes\n' > README.md
  $G add -A && $G commit -q -m base
  $G checkout -q -b feature
) || { echo "FAIL $name: fixture failed"; exit 1; }
cd "$repo" || exit 1

run() { bash "$script" . --base main "$@" 2>&1; }
commit() { $G add -A && $G commit -q -m "$1"; }

# control: a code-only change passes
printf 'package a\n\nfunc A() int { return 1 }\n\nfunc A2() int { return 2 }\n' | { printf '// Copyright The Project Authors\n// SPDX-License-Identifier: MIT\n\n'; cat; } > src/a.go
commit "code only"
out=$(run); rc=$?
[ "$rc" = "0" ] || { echo "FAIL $name: code-only change exited $rc: $out"; exit 1; }

# 1. a comment added beside existing code is refused
printf '// Copyright The Project Authors\n// SPDX-License-Identifier: MIT\n\npackage a\n\nfunc A() int { return 1 }\n\n// A2 returns two.\nfunc A2() int { return 2 }\n' > src/a.go
commit "add a comment"
out=$(run); rc=$?
[ "$rc" = "1" ] || { echo "FAIL $name: added comment exited $rc, expected 1: $out"; exit 1; }
echo "$out" | grep -q "src/a.go:8 adds a comment: // A2 returns two." || { echo "FAIL $name: refusal did not name the line: $out"; exit 1; }

# 2. --asked turns it into a check and passes
out=$(run --asked https://example.com/pr/1#c1); rc=$?
[ "$rc" = "0" ] || { echo "FAIL $name: --asked exited $rc: $out"; exit 1; }
echo "$out" | grep -q "CHECK: src/a.go:8 .*asked for in https://example.com/pr/1#c1" || { echo "FAIL $name: --asked printed no check: $out"; exit 1; }

# 3. rewording an existing comment passes
$G reset -q --hard main
printf 'package b\n\n// B returns the number two.\nfunc B() int { return 2 }\n' > src/b.go
commit "reword"
out=$(run); rc=$?
[ "$rc" = "0" ] || { echo "FAIL $name: reworded comment exited $rc: $out"; exit 1; }

# 4. rewording one comment and adding another in the same hunk refuses the added one only
printf 'package b\n\n// B returns the number two.\n// It never fails.\nfunc B() int { return 2 }\n' > src/b.go
commit "reword and add"
out=$(run); rc=$?
[ "$rc" = "1" ] || { echo "FAIL $name: reword-plus-add exited $rc, expected 1: $out"; exit 1; }
[ "$(echo "$out" | grep -c '^REFUSED: ')" = "1" ] || { echo "FAIL $name: expected one refusal: $out"; exit 1; }
echo "$out" | grep -q "It never fails" || { echo "FAIL $name: the wrong line was refused: $out"; exit 1; }
echo "$out" | grep '^REFUSED: ' | grep -q ' \[comment-check-comment-added\]$' || { echo "FAIL $name: the refusal does not end with its name: $out"; exit 1; }
[ "$(bash "$script" . --base main 2>/dev/null | grep -c '^REFUSED: ')" = "1" ] || { echo "FAIL $name: the refusal is not on stdout, where branch-check and a reader expect it"; exit 1; }

# 5. a new file opening with the header its neighbours carry passes; a comment below it does not
$G reset -q --hard main
printf '// Copyright The Project Authors\n// SPDX-License-Identifier: MIT\n\npackage c\n\nfunc C() int { return 3 }\n' > src/c.go
commit "new file with header"
out=$(run); rc=$?
[ "$rc" = "0" ] || { echo "FAIL $name: new file with a licence header exited $rc: $out"; exit 1; }
printf '// Copyright The Project Authors\n// SPDX-License-Identifier: MIT\n\npackage c\n\n// C returns three.\nfunc C() int { return 3 }\n' > src/c.go
commit "new file with a body comment"
out=$(run); rc=$?
[ "$rc" = "1" ] || { echo "FAIL $name: body comment in a new file exited $rc, expected 1: $out"; exit 1; }
echo "$out" | grep -q "src/c.go:6 adds a comment" || { echo "FAIL $name: the body comment was not the one refused: $out"; exit 1; }

# 6. a new file where no neighbour opens with a comment gets no header allowance
$G reset -q --hard main
mkdir -p lib
printf '# helper\nx = 1\n' > lib/h.py
commit "new python file"
out=$(run); rc=$?
[ "$rc" = "1" ] || { echo "FAIL $name: header in a new file with no commented neighbour exited $rc, expected 1: $out"; exit 1; }

# 7. a test file counts
$G reset -q --hard main
printf 'package a\n\nimport "testing"\n\n// TestA checks A.\nfunc TestA(t *testing.T) { if A() != 1 { t.Fatal() } }\n' > src/a_test.go
commit "test with a comment"
out=$(run); rc=$?
[ "$rc" = "1" ] || { echo "FAIL $name: a comment in a test file exited $rc, expected 1: $out"; exit 1; }

# 8. a file with no recognised comment syntax is not measured
$G reset -q --hard main
printf '# notes\n\nMore notes here.\n' > README.md
commit "docs"
out=$(run); rc=$?
[ "$rc" = "0" ] || { echo "FAIL $name: a markdown change exited $rc: $out"; exit 1; }

# 9. a block-comment header whose inner lines carry no star passes whole; a block comment below it does not
$G reset -q --hard main
printf '/**\n# Copyright The Project Authors\n#\n#     http://example.com/licence\n**/\n\npackage d\n\nfunc D() int { return 4 }\n' > src/d.go
commit "new file with a block header"
out=$(run); rc=$?
[ "$rc" = "0" ] || { echo "FAIL $name: new file with a block-comment header exited $rc: $out"; exit 1; }
printf '/**\n# Copyright The Project Authors\n**/\n\npackage d\n\n/*\nD returns four.\n*/\nfunc D() int { return 4 }\n' > src/d.go
commit "new file with a body block comment"
out=$(run); rc=$?
[ "$rc" = "1" ] || { echo "FAIL $name: body block comment exited $rc, expected 1: $out"; exit 1; }
echo "$out" | grep -q "src/d.go:8 adds a comment: D returns four." || { echo "FAIL $name: the inner line of a body block comment was not refused: $out"; exit 1; }
echo "$out" | grep -q "src/d.go:[1-3] " && { echo "FAIL $name: the header was refused: $out"; exit 1; }

# 10. a tab-indented comment is seen: gofmt indents every comment inside a function
$G reset -q --hard main
printf 'package b\n\n// B returns two.\nfunc B() int {\n\t// two is the answer\n\treturn 2\n}\n' > src/b.go
commit "tabbed comment"
out=$(run); rc=$?
[ "$rc" = "1" ] || { echo "FAIL $name: a tab-indented comment exited $rc, expected 1: $out"; exit 1; }
echo "$out" | grep -q "src/b.go:5 adds a comment: // two is the answer" || { echo "FAIL $name: the tabbed comment was not named: $out"; exit 1; }

# 11. the same branch reads the same from a subdirectory
out=$(cd src && bash "$script" --base main 2>&1); rc=$?
[ "$rc" = "1" ] || { echo "FAIL $name: from a subdirectory exited $rc, expected 1: $out"; exit 1; }

# 12. and under a user's colour or external diff settings
for setting in "color.ui always" "diff.external true" "diff.noprefix true"; do
  # shellcheck disable=SC2086  # the setting is two words on purpose
  git config --local $setting
  out=$(run); rc=$?
  git config --local --unset "${setting%% *}"
  [ "$rc" = "1" ] || { echo "FAIL $name: under $setting exited $rc, expected 1: $out"; exit 1; }
done

# 13. a comment in a file with a non-ASCII name is measured
$G reset -q --hard main
printf 'x = 1\n# a comment\n' > "src/caf$(printf '\303\251').py"
commit "non-ascii name"
out=$(run); rc=$?
[ "$rc" = "1" ] || { echo "FAIL $name: a comment in a non-ASCII file exited $rc, expected 1: $out"; exit 1; }

# 13b. code that only looks like a comment, and a comment in a kind of file
# that had no gate
$G reset -q --hard main
printf 'void f(int *out) {\n  return;\n}\n' > src/d.c
commit "c file"
$G checkout -q main -- . 2>/dev/null
$G branch -q -f feature HEAD
printf 'void f(int *out) {\n  *out = 0;\n  return;\n}\n' > src/d.c
commit "set out"
git update-ref refs/heads/cbase "$(git rev-parse HEAD~1)"
out=$(bash "$script" . --base cbase 2>&1); rc=$?
[ "$rc" = "0" ] || { echo "FAIL $name: a dereference was read as a comment: $out"; exit 1; }
printf 'void f(int *out) {\n  /* set it\n   * to zero\n   */\n  *out = 0;\n  return;\n}\n' > src/d.c
commit "a block comment"
out=$(bash "$script" . --base cbase 2>&1); rc=$?
[ "$rc" = "1" ] || { echo "FAIL $name: a block comment exited $rc: $out"; exit 1; }
$G reset -q --hard main
mkdir -p ci
printf '#!/bin/bash\nmake test\n' > ci/run.sh
commit "a script in a new directory"
out=$(run); rc=$?
[ "$rc" = "0" ] || { echo "FAIL $name: a shebang was read as a comment: $out"; exit 1; }
for f in a.mts Makefile b.pyi; do
  $G reset -q --hard main
  case "$f" in
    a.mts) printf '// a whole-line comment\nconst x = 1;\n' > "$f" ;;
    *) printf '# a whole-line comment\nall:\n' > "$f" ;;
  esac
  commit "add $f"
  out=$(run); rc=$?
  [ "$rc" = "1" ] || { echo "FAIL $name: a comment in $f exited $rc: $out"; exit 1; }
done

# 14. a pure rename adds no comment, and a comment added in the same commit is still seen
$G reset -q --hard main
$G mv src/b.go src/b2.go
commit "rename only"
out=$(run); rc=$?
[ "$rc" = "0" ] || { echo "FAIL $name: a pure rename exited $rc, expected 0: $out"; exit 1; }
printf 'package b\n\n// B returns two.\n// A new line of comment.\nfunc B() int { return 2 }\n' > src/b2.go
commit "comment in the renamed file"
out=$(run); rc=$?
[ "$rc" = "1" ] || { echo "FAIL $name: a comment in a renamed file exited $rc, expected 1: $out"; exit 1; }

# 15. a comment that moves to another file with its code is not added (#29,
# uber/h3 #1236), and the pairing is printed for the reader to check
$G reset -q --hard main
printf 'package b\n' > src/b.go
printf '// Copyright The Project Authors\n// SPDX-License-Identifier: MIT\n\npackage a\n\nfunc A() int { return 1 }\n\n// B returns two.\nfunc B() int { return 2 }\n' > src/a.go
commit "move B"
out=$(run); rc=$?
[ "$rc" = "0" ] || { echo "FAIL $name: a moved comment exited $rc, expected 0: $out"; exit 1; }
echo "$out" | grep -q "^CHECK: src/a.go:8 moves a comment from src/b.go$" || { echo "FAIL $name: the move was not printed: $out"; exit 1; }

# 16. one removed line pays for one added line: a second copy is refused
printf '// Copyright The Project Authors\n// SPDX-License-Identifier: MIT\n\npackage a\n\n// B returns two.\nfunc A() int { return 1 }\n\n// B returns two.\nfunc B() int { return 2 }\n' > src/a.go
commit "move B and copy its comment"
out=$(run); rc=$?
[ "$rc" = "1" ] || { echo "FAIL $name: a moved comment plus a copy exited $rc, expected 1: $out"; exit 1; }
[ "$(echo "$out" | grep -c '^REFUSED: ')" = "1" ] || { echo "FAIL $name: expected one refusal for the copy: $out"; exit 1; }

# 17. across files only identical text pays: a moved comment reworded is added
$G reset -q --hard main
printf 'package b\n' > src/b.go
printf '// Copyright The Project Authors\n// SPDX-License-Identifier: MIT\n\npackage a\n\nfunc A() int { return 1 }\n\n// B returns the number two.\nfunc B() int { return 2 }\n' > src/a.go
commit "move B and reword"
out=$(run); rc=$?
[ "$rc" = "1" ] || { echo "FAIL $name: a moved and reworded comment exited $rc, expected 1: $out"; exit 1; }

# 18. a comment whose file the branch deletes can move too
$G reset -q --hard main
$G rm -q src/b.go
printf '// Copyright The Project Authors\n// SPDX-License-Identifier: MIT\n\npackage a\n\nfunc A() int { return 1 }\n\n// B returns two.\nfunc B() int { return 2 }\n' > src/a.go
commit "fold b into a"
out=$(run); rc=$?
[ "$rc" = "0" ] || { echo "FAIL $name: a comment moved out of a deleted file exited $rc, expected 0: $out"; exit 1; }
echo "$out" | grep -q "^CHECK: src/a.go:8 moves a comment from src/b.go$" || { echo "FAIL $name: the move out of a deleted file was not printed: $out"; exit 1; }

# 19. a renamed file gives up no comments, whatever diff.renames says: a copy
# of one of its comments is added, not moved
$G reset -q --hard main
$G mv src/b.go src/b3.go
printf '// Copyright The Project Authors\n// SPDX-License-Identifier: MIT\n\npackage a\n\nfunc A() int { return 1 }\n\n// B returns two.\nfunc A3() int { return 2 }\n' > src/a.go
commit "rename b and copy its comment"
git config diff.renames false
out=$(run); rc=$?
git config --unset diff.renames
[ "$rc" = "1" ] || { echo "FAIL $name: a comment copied from a renamed file exited $rc under diff.renames=false, expected 1: $out"; exit 1; }

# 20. a block comment moves whole, its unstarred inner lines included
$G checkout -q main
printf 'int e(void) {\n  return 1;\n}\n/*\n   b returns two, always.\n*/\nint b(void) { return 2; }\n' > src/e.c
commit "e and b"
$G checkout -q feature
$G reset -q --hard main
printf 'int e(void) {\n  return 1;\n}\n' > src/e.c
printf 'int c(void) { return 3; }\n/*\n   b returns two, always.\n*/\nint b(void) { return 2; }\n' > src/c2.c
commit "move b to c2"
out=$(run); rc=$?
[ "$rc" = "0" ] || { echo "FAIL $name: a moved block comment exited $rc, expected 0: $out"; exit 1; }
[ "$(echo "$out" | grep -c "moves a comment from src/e.c")" = "3" ] || { echo "FAIL $name: the block's three lines were not each printed as a move: $out"; exit 1; }

# 21. the same block moves whole out of a file the branch deletes
$G reset -q --hard main
$G rm -q src/e.c
# Enough other code that git reads a delete and an add, not a rename.
printf 'int c(void) { return 3; }\nint c1(void) { return 31; }\nint c2(void) { return 32; }\nint c3(void) { return 33; }\nint c4(void) { return 34; }\nint c5(void) { return 35; }\n/*\n   b returns two, always.\n*/\nint b(void) { return 2; }\n' > src/c2.c
commit "fold e into c2"
git diff --name-status -M main HEAD | grep -qx $'D\tsrc/e.c' || { echo "FAIL $name: the fixture is not a deleted file: $(git diff --name-status -M main HEAD)"; exit 1; }
out=$(run); rc=$?
[ "$rc" = "0" ] || { echo "FAIL $name: a block moved out of a deleted file exited $rc, expected 0: $out"; exit 1; }

echo "PASS $name"
