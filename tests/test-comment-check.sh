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

echo "PASS $name"
