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
HOUSEBROKEN_HOME="$root/hbhome"
export HOUSEBROKEN_HOME
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
stamp="$HOUSEBROKEN_HOME/branch-checks/$(cd "$repo" && git rev-parse HEAD)"
[ -f "$stamp" ] || { echo "FAIL $name: a passing branch left no stamp at $stamp"; exit 1; }
grep -q "^head: " "$stamp" || { echo "FAIL $name: the stamp does not name the head"; exit 1; }
grep -q "^base-ref: origin/main$" "$stamp" || { echo "FAIL $name: the stamp does not name the base it measured against"; exit 1; }

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

# 2b. a mode the base already carries is not the branch's to answer for
# (Tencent/MMKV ships Core/MMKV_IO.cpp 100755 among 100644 siblings)
legacy="$root/legacy"
mkdir -p "$legacy/src" || exit 1
(
  cd "$legacy" || exit 1
  $G init -q -b main .
  printf 'export const a = 1;\n' > src/a.test.ts
  printf 'export const b = 2;\n' > src/b.test.ts
  printf 'export const x = 1;\n' > src/x.test.ts
  $G add -A && $G update-index --chmod=+x src/x.test.ts && $G commit -q -m base
  $G branch -f origin/main main
  $G checkout -q -b feature
  printf 'export const x = 2;\n' > src/x.test.ts
  $G add -A && $G update-index --chmod=+x src/x.test.ts && $G commit -q -m "edit x"
) || { echo "FAIL $name: legacy fixture failed"; exit 1; }
(cd "$legacy" && git ls-tree HEAD src/x.test.ts | grep -q '^100755' && git ls-tree origin/main src/x.test.ts | grep -q '^100755') \
  || { echo "FAIL $name: legacy fixture lost the 100755 mode"; exit 1; }
bash "$script" "$legacy" --base origin/main 2>&1 | grep -q "100755" && { echo "FAIL $name: a mode inherited from the base was refused"; exit 1; }

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

# 7. a tool trailer nobody asked for, and its sabotage
(cd "$repo" && printf 'export const d = 4;\n' > src/d.test.ts && $G add -A && $G commit -q -m "add d

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_abc123")
fires "tool trailer or a session link" || { echo "FAIL $name: tool trailer not refused"; exit 1; }
(cd "$repo" && $G commit -q --amend -m "add d")
fires "tool trailer or a session link" && { echo "FAIL $name: trailer refusal survived rewriting the message"; exit 1; }

# 8. a DCO sign-off naming a username, and its sabotage
(cd "$repo" && $G commit -q --amend -m "add d

Signed-off-by: lenamonj <someone@example.com>")
fires "asks for a real name" || { echo "FAIL $name: username sign-off not refused"; exit 1; }
(cd "$repo" && $G commit -q --amend -m "add d

Signed-off-by: Jeff Lenamon <someone@example.com>")
fires "asks for a real name" && { echo "FAIL $name: sign-off refusal survived using a real name"; exit 1; }

# 9. GitHub's spelling of another tool's trailer, a session link alone, a tool as author, and prose that only names the trailer
(cd "$repo" && $G commit -q --amend -m "add d

Co-authored-by: Codex <codex@openai.com>")
fires "tool trailer or a session link" || { echo "FAIL $name: a Co-authored-by trailer from another tool not refused"; exit 1; }
(cd "$repo" && $G commit -q --amend -m "add d

Claude-Session: https://claude.ai/code/session_abc123")
fires "tool trailer or a session link" || { echo "FAIL $name: a session link alone not refused"; exit 1; }
(cd "$repo" && $G commit -q --amend --author="Claude <noreply@anthropic.com>" -m "add d")
fires "tool trailer or a session link" || { echo "FAIL $name: a commit authored by a tool not refused"; exit 1; }
(cd "$repo" && $G commit -q --amend --reset-author -m "docs: explain the Co-Authored-By: Claude trailer

The parser now reads Co-Authored-By: Claude lines.")
fires "tool trailer or a session link" && { echo "FAIL $name: prose that names the trailer was refused"; exit 1; }

# 10. a username sign-off with a capital or a dot
for who in Lenamonj jeff.lenamon; do
  (cd "$repo" && $G commit -q --amend -m "add d

Signed-off-by: $who <someone@example.com>")
  fires "asks for a real name" || { echo "FAIL $name: sign-off $who not refused"; exit 1; }
done
(cd "$repo" && $G commit -q --amend -m "add d")

# 11. a comment added to code is refused, leaves no stamp, and --asked turns it into a check
(cd "$repo" && printf '// e is four\nexport const e = 4;\n' > src/e.test.ts && $G add -A && $G commit -q -m "add e with a comment")
fires "adds comments to code that nobody asked for" || { echo "FAIL $name: added comment not refused"; exit 1; }
[ -f "$HOUSEBROKEN_HOME/branch-checks/$(cd "$repo" && git rev-parse HEAD)" ] && { echo "FAIL $name: a refused branch left a stamp"; exit 1; }
out=$(bash "$script" "$repo" --base origin/main --asked https://example.com/pr/9 2>&1)
echo "$out" | grep -q "adds comments to code that nobody asked for" && { echo "FAIL $name: --asked did not lift the comment refusal: $out"; exit 1; }
echo "$out" | grep -q "CHECK: src/e.test.ts:1 .*asked for in https://example.com/pr/9" || { echo "FAIL $name: --asked printed no check: $out"; exit 1; }
(cd "$repo" && printf 'export const e = 4;\n' > src/e.test.ts && $G add -A && $G commit -q --amend -m "add e")
fires "adds comments" && { echo "FAIL $name: comment refusal survived removing the comment"; exit 1; }

# 12. the go-nvml shape: a file the project already tracks under an ignored name is not build output
(cd "$repo" && printf 'dl\n' >> .gitignore && mkdir -p pkg/dl && printf 'package dl\n' > pkg/dl/dl.go &&
  $G add .gitignore && $G add -f pkg/dl/dl.go && $G commit -q -m "tracked under an ignored name" && $G branch -f origin/main HEAD &&
  printf 'package dl // edited\n' > pkg/dl/dl.go && $G add -f pkg/dl/dl.go && $G commit -q -m "edit it")
fires "gitignore excludes it" && { echo "FAIL $name: a tracked file under an ignored name was refused"; exit 1; }

# 13. a warning suppression the branch adds is refused until a build log shows the warning firing
# (shouldly #1335 suppressed IL2075, which never fired, and the reflection it covered broke under AOT)
(cd "$repo" && printf 'class S {\n    [UnconditionalSuppressMessage("Trimming", "IL2075", Justification = "x")]\n    void M() { }\n}\n' > src/S.cs &&
  $G add -A && $G commit -q -m "add a suppression")
fires "adds a warning suppression" || { echo "FAIL $name: an added suppression not refused"; exit 1; }
printf 'Build succeeded.\n    0 Warning(s)\n' > "$root/quiet.log"
bash "$script" "$repo" --base origin/main --warning-log "$root/quiet.log" 2>&1 | grep -q "adds a warning suppression" \
  || { echo "FAIL $name: a log without IL2075 lifted the suppression refusal"; exit 1; }
printf 'S.cs(3,9): warning IL2075: GetProperty on an unannotated type\n' > "$root/fires.log"
bash "$script" "$repo" --base origin/main --warning-log "$root/fires.log" 2>&1 | grep -q "adds a warning suppression" \
  && { echo "FAIL $name: a log showing IL2075 did not lift the suppression refusal"; exit 1; }
(cd "$repo" && printf 'class S {\n    void M() { }\n}\n' > src/S.cs && $G add -A && $G commit -q --amend -m "add S")
fires "adds a warning suppression" && { echo "FAIL $name: suppression refusal survived removing the suppression"; exit 1; }
(cd "$repo" && printf 'class S {\n#pragma warning disable CS8602\n    void M() { }\n}\n' > src/S.cs && $G add -A && $G commit -q --amend -m "add S")
fires "adds a warning suppression" || { echo "FAIL $name: a #pragma warning disable not refused"; exit 1; }
(cd "$repo" && printf 'class S {\n    void M() { }\n}\n' > src/S.cs && $G add -A && $G commit -q --amend -m "add S")

# 14. reflection added to a project that declares itself AOT compatible is refused until an AOT publish log is given
(cd "$repo" && printf 'class R {\n    object K(object o) => o.GetType().GetProperty("Key")?.GetValue(o);\n}\n' > src/R.cs &&
  $G add -A && $G commit -q -m "add reflection")
fires "adds reflection" && { echo "FAIL $name: reflection refused in a project that declares no AOT support"; exit 1; }
# shellcheck disable=SC2016  # $(...) is MSBuild syntax, written literally
(cd "$repo" && printf '<Project>\n  <PropertyGroup>\n    <IsAotCompatible Condition="$([MSBuild]::IsTargetFrameworkCompatible('"'"'$(TargetFramework)'"'"', '"'"'net8.0'"'"'))">true</IsAotCompatible>\n  </PropertyGroup>\n</Project>\n' > src/Lib.csproj &&
  $G add -A && $G commit -q -m "declare AOT")
fires "adds reflection to a project that declares AOT" || { echo "FAIL $name: reflection in an AOT-compatible project not refused"; exit 1; }
bash "$script" "$repo" --base origin/main --aot-log "$root/quiet.log" 2>&1 | grep -q "adds reflection" \
  || { echo "FAIL $name: a log that is not an AOT publish lifted the reflection refusal"; exit 1; }
printf 'Generating native code\n  R -> /tmp/publish/R\n' > "$root/aot.log"
bash "$script" "$repo" --base origin/main --aot-log "$root/aot.log" 2>&1 | grep -q "adds reflection" \
  && { echo "FAIL $name: an AOT publish log did not lift the reflection refusal"; exit 1; }

echo "PASS $name"
