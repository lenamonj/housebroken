#!/bin/bash
# test-branch-check.sh - every refusal fires on its own cause and stops firing
# when only that cause is removed, so no refusal is resting on another's
# condition. Local git only, no network.
set -u
name=test-branch-check
script="$(cd "$(dirname "$0")/../scripts" && pwd)/branch-check.sh"

bash "$script" --help | grep -q "Usage:" || { echo "FAIL $name: --help has no usage"; exit 1; }
bash "$script" /definitely/not/a/directory >/dev/null 2>&1
[ "$?" = "2" ] || { echo "FAIL $name: missing directory did not exit 2"; exit 1; }

root=$(mktemp -d) || exit 1
trap 'rm -rf "$root"' EXIT
repo="$root/repo"
G="git -c user.email=t@example.com -c user.name=t -c core.filemode=true -c core.autocrlf=false"

mkdir -p "$repo/src" || exit 1
(
  cd "$repo" || exit 1
  $G init -q -b main .
  printf 'dist/\n' > .gitignore
  printf 'export const a = 1;\n' > src/a.test.ts
  printf 'export const b = 2;\n' > src/b.test.ts
  printf '# readme\n' > README.md
  $G add -A && $G commit -q -m base
  $G branch -f origin/main main
  $G checkout -q -b feature
  printf 'export const c = 3;\n' > src/c.test.ts
  $G add -A && $G commit -q -m "add c"
) || { echo "FAIL $name: fixture failed"; exit 1; }

run() { bash "$script" "$repo" --base origin/main 2>&1; }
fires() { run | grep -q "$1"; }

# The clean branch is the control: if this does not pass, nothing below means anything.
out=$(run); rc=$?
[ "$rc" = "0" ] || { echo "FAIL $name: clean branch exited $rc"; echo "$out"; exit 1; }
echo "$out" | grep -q "nothing mechanical blocks" || { echo "FAIL $name: clean branch not reported clean"; echo "$out"; exit 1; }

# 1. dirty tree
printf 'export const a = 99;\n' > "$repo/src/a.test.ts"
fires "working tree is dirty" || { echo "FAIL $name: dirty tree not refused"; exit 1; }
run >/dev/null 2>&1 && { echo "FAIL $name: dirty tree exited 0"; exit 1; }
(cd "$repo" && $G checkout -q -- src/a.test.ts)
fires "working tree is dirty" && { echo "FAIL $name: dirty refusal survived cleaning the tree"; exit 1; }

# 2. executable bit that disagrees with the file's siblings
(cd "$repo" && $G update-index --chmod=+x src/c.test.ts && $G commit -q -m "mode")
fires "100755" || { echo "FAIL $name: exec mode not refused"; exit 1; }
(cd "$repo" && $G update-index --chmod=-x src/c.test.ts && $G commit -q -m "mode back")
fires "100755" && { echo "FAIL $name: mode refusal survived chmod 644"; exit 1; }

# 3. a committed file the repository's own .gitignore excludes
mkdir -p "$repo/dist"
printf 'built\n' > "$repo/dist/out.js"
(cd "$repo" && $G add -f dist/out.js && $G commit -q -m "ignored file")
fires "gitignore excludes it" || { echo "FAIL $name: ignored file not refused"; exit 1; }
(cd "$repo" && $G rm -q --cached dist/out.js && $G commit -q -m "drop ignored" && rm -f dist/out.js)
fires "gitignore excludes it" && { echo "FAIL $name: ignore refusal survived removing the file"; exit 1; }

# 4. a working artifact
printf 'plan\n' > "$repo/PLAN.md"
(cd "$repo" && $G add PLAN.md && $G commit -q -m "plan")
fires "working artifact" || { echo "FAIL $name: artifact not refused"; exit 1; }
(cd "$repo" && $G rm -q PLAN.md && $G commit -q -m "drop plan")
fires "working artifact" && { echo "FAIL $name: artifact refusal survived removing it"; exit 1; }

# 5. absolute claims in added prose warn without blocking
printf '\nThis removes only the files it generated.\n' >> "$repo/README.md"
(cd "$repo" && $G add README.md && $G commit -q -m "docs")
fires "absolute claims" || { echo "FAIL $name: absolute claim not reported"; exit 1; }
run >/dev/null 2>&1 || { echo "FAIL $name: an absolute claim must warn, not block"; exit 1; }

# 6. a branch that is not on top of its base
(cd "$repo" && $G checkout -q main && printf 'moved\n' >> README.md && $G add -A && $G commit -q -m "base moves" && $G branch -f origin/main main && $G checkout -q feature)
fires "not on top of" || { echo "FAIL $name: stale base not refused"; exit 1; }

echo "PASS $name"
