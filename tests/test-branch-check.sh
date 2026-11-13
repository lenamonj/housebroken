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

# The base is a real remote-tracking ref, moved by pushing to a bare upstream
# beside the clone and fetching, so the live-base check has a remote to ask.
setbase() {
  local up; up="$(pwd).up.git"
  [ -d "$up" ] || git init -q --bare "$up"
  git remote get-url origin >/dev/null 2>&1 || git remote add origin "$up"
  git push -q -f origin "$1:refs/heads/main" && git fetch -q origin
}

mkdir -p "$repo/src" || exit 1
(
  cd "$repo" || exit 1
  $G init -q -b main .
  printf 'dist/\n' > .gitignore
  printf 'export const a = 1;\n' > src/a.test.ts
  printf 'export const b = 2;\n' > src/b.test.ts
  printf '# readme\n' > README.md
  $G add -A && $G commit -q -m base
  setbase main
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
  setbase main
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
(cd "$repo" && $G reset -q --hard HEAD~1)
fires "working artifact" && { echo "FAIL $name: artifact refusal survived removing it"; exit 1; }

# 5. absolute claims in added prose warn without blocking
printf '\nThis removes only the files it generated.\n' >> "$repo/README.md"
(cd "$repo" && $G add README.md && $G commit -q -m "docs")
fires "absolute claims" || { echo "FAIL $name: absolute claim not reported"; exit 1; }
run >/dev/null 2>&1 || { echo "FAIL $name: an absolute claim must warn, not block"; exit 1; }

# 6. a branch that is not on top of its base
(cd "$repo" && $G checkout -q main && printf 'moved\n' >> README.md && $G add -A && $G commit -q -m "base moves" && setbase main && $G checkout -q feature)
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
# the refusal is on stdout under its own name, and the line it relays keeps the name of the check that made it
out=$(bash "$script" "$repo" --base origin/main 2>/dev/null)
echo "$out" | grep -qx 'REFUSED: the branch adds comments to code that nobody asked for \[branch-check-comments-added\]' || { echo "FAIL $name: the comment refusal is not on stdout under its name: $out"; exit 1; }
echo "$out" | grep -q '^    src/e.test.ts:1 adds a comment: .* \[comment-check-comment-added\]$' || { echo "FAIL $name: the relayed line lost the name of its check: $out"; exit 1; }
[ "$(tail -n 2 "$HOUSEBROKEN_HOME/refusals.tsv" | cut -f2 | tr '\n' ' ')" = "comment-check-comment-added branch-check-comments-added " ] || { echo "FAIL $name: the log does not hold both names: $(tail -n 2 "$HOUSEBROKEN_HOME/refusals.tsv")"; exit 1; }
[ -f "$HOUSEBROKEN_HOME/branch-checks/$(cd "$repo" && git rev-parse HEAD)" ] && { echo "FAIL $name: a refused branch left a stamp"; exit 1; }
out=$(bash "$script" "$repo" --base origin/main --asked https://example.com/pr/9 2>&1)
echo "$out" | grep -q "adds comments to code that nobody asked for" && { echo "FAIL $name: --asked did not lift the comment refusal: $out"; exit 1; }
echo "$out" | grep -q "CHECK: src/e.test.ts:1 .*asked for in https://example.com/pr/9" || { echo "FAIL $name: --asked printed no check: $out"; exit 1; }
(cd "$repo" && printf 'export const e = 4;\n' > src/e.test.ts && $G add -A && $G commit -q --amend -m "add e")
fires "adds comments" && { echo "FAIL $name: comment refusal survived removing the comment"; exit 1; }

# 12. the go-nvml shape: a file the project already tracks under an ignored name is not build output
(cd "$repo" && printf 'dl\n' >> .gitignore && mkdir -p pkg/dl && printf 'package dl\n' > pkg/dl/dl.go &&
  $G add .gitignore && $G add -f pkg/dl/dl.go && $G commit -q -m "tracked under an ignored name" && setbase HEAD &&
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
# A suppression that names no warning hides all of them, whatever log is given;
# one that names its rule is lifted by a log showing that rule; config-file and
# MSVC forms are suppressions too.
printf 'x.go:3: Error return value is not checked (errcheck)\nIL2075 C4996 CS8602\n' > "$root/lint.log"
supp() { # file content expect(refused|lifted)
  (cd "$repo" && mkdir -p "$(dirname "$1")" && printf '%s\n' "$2" > "$1" && $G add -A && $G commit -q --amend -m "add S") || exit 1
  if bash "$script" "$repo" --base origin/main --warning-log "$root/lint.log" 2>&1 | grep -q "adds a warning suppression"; then got=refused; else got=lifted; fi
  [ "$got" = "$3" ] || { echo "FAIL $name: $2 was $got, expected $3"; exit 1; }
  (cd "$repo" && git rm -q "$1" && $G commit -q --amend -m "add S") || exit 1
}
supp src/x.go 'f() //nolint' refused
supp src/x.go 'f() //nolint:errcheck' lifted
supp src/x.go 'f() //nolint:gosec' refused
supp src/a.ts '// @ts-ignore' refused
# shellcheck disable=SC2016  # $(NoWarn) is MSBuild syntax, written literally
supp src/N.csproj '<PropertyGroup><NoWarn>$(NoWarn);IL2026</NoWarn></PropertyGroup>' refused
# shellcheck disable=SC2016
supp src/N.csproj '<PropertyGroup><NoWarn>$(NoWarn);IL2075</NoWarn></PropertyGroup>' lifted
supp src/m.cpp '#pragma warning(disable : 4996)' lifted
supp src/m.cpp '#pragma warning(disable : 4244)' refused
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
printf 'Generating native code\n  Other -> /tmp/publish/Other\n' > "$root/other.log"
bash "$script" "$repo" --base origin/main --aot-log "$root/other.log" 2>&1 | grep -q "adds reflection" \
  || { echo "FAIL $name: an AOT publish of another project lifted the reflection refusal"; exit 1; }
printf 'Generating native code\n  Lib -> /tmp/publish/Lib\n' > "$root/aot.log"
bash "$script" "$repo" --base origin/main --aot-log "$root/aot.log" 2>&1 | grep -q "adds reflection" \
  && { echo "FAIL $name: an AOT publish log did not lift the reflection refusal"; exit 1; }

# 15. The upstream moved and the clone never fetched: the local base is stale.
fires "the base moved" && { echo "FAIL $name: a current base was called stale"; exit 1; }
basesha=$(cd "$repo" && git rev-parse origin/main)
# From another clone: it is the upstream moving, and this clone must not hear of it.
git clone -q -b main "$(cd "$repo" && git remote get-url origin)" "$root/elsewhere" || { echo "FAIL $name: could not clone the upstream"; exit 1; }
(cd "$root/elsewhere" && $G commit -q --allow-empty -m "upstream moves" && git push -q origin HEAD:refs/heads/main) || { echo "FAIL $name: could not move the upstream"; exit 1; }
fires "the base moved" || { echo "FAIL $name: a base the upstream moved past was not refused"; run; exit 1; }
(cd "$root/elsewhere" && git push -q -f origin "$basesha:refs/heads/main")
fires "the base moved" && { echo "FAIL $name: restoring the upstream did not lift the stale-base refusal"; exit 1; }
# A local branch or a SHA cannot be checked against anything, so it is refused.
(cd "$repo" && git branch -q -f localbase origin/main)
bash "$script" "$repo" --base localbase 2>&1 | grep -q "is not a remote-tracking ref" \
  || { echo "FAIL $name: a local-branch base was not refused"; exit 1; }

# 16. What embarrasses a contributor first: a personal path, a token, a
# lockfile, a binary, an agent's file, a whole file rewritten for its endings.
hygiene_re="personal path|lockfile|is binary|agent's working file|working artifact|beyond whitespace"
hyg() { # setup expected-refusal ("" for none) [extra branch-check args...]
  local setup="$1" want="$2"; shift 2
  (cd "$repo" && eval "$setup" && $G add -A && $G commit -q -m hyg) || { echo "FAIL $name: setup failed: $setup"; exit 1; }
  out=$(bash "$script" "$repo" --base origin/main "$@" 2>&1)
  if [ -n "$want" ]; then
    printf '%s' "$out" | grep -q "$want" || { echo "FAIL $name: not refused ($want): $setup"; echo "$out"; exit 1; }
  else
    printf '%s' "$out" | grep -qE "$hygiene_re" && { echo "FAIL $name: refused: $setup"; echo "$out"; exit 1; }
  fi
  (cd "$repo" && $G reset -q --hard HEAD~1)
}
hyg "printf 'export const h = 16;\n' > src/h16.test.ts" ""
hyg "printf 'const p = \"C:/Users/$(basename "$HOME")/work/x\";\n' > src/p.ts" "personal path"
hyg "printf 'const p = \"/home/$(basename "$HOME")/src/x\";\n' > src/p.ts" "personal path"
hyg "printf 'const p = \"/home/alice/src/x\";\n' > src/p.ts" ""
hyg "printf 'const t = \"ghp_%s\";\n' abcdefghijklmnopqrstuvwxyz0123 > src/t.ts" "credential"
hyg "printf 'image: risk-management-service-configuration\n' > src/a.yml" ""
hyg "printf 'key: sk-abcdefghijklmnopqrstuvwxyz\n' > src/a.yml" "credential"
hyg "printf '{}\n' > package-lock.json" "lockfile"
hyg "printf '{}\n' > package-lock.json" "" --allow package-lock.json
hyg "printf '\000\001\002' > src/blob.bin" "is binary"
hyg "printf '# notes\n' > CLAUDE.md" "agent's working file"
hyg "mkdir -p .claude && printf '{}\n' > .claude/settings.json" "agent's working file"
# the base carries a 40-line LF file and a .claude/ file the project tracks; the
# branch rewrites the first with CRLF, re-indents it under a new block, or edits the second
(cd "$repo" && for i in $(seq 1 40); do printf 'line %s\n' "$i"; done > src/long.txt &&
  mkdir -p .claude/commands && printf 'run the tests\n' > .claude/commands/t.md &&
  $G add -A && $G commit -q -m "long file" && setbase HEAD) || { echo "FAIL $name: CRLF fixture failed"; exit 1; }
hyg "perl -pi -e 's/\$/\r/; s/^line 7\r\$/line seven\r/' src/long.txt" "beyond whitespace"
hyg "perl -pi -e 's/^line 7\$/line seven/' src/long.txt" ""
hyg "perl -pi -e 's/^line (\d)/    line \$1/; print qq(if (x) {\n) if \$. == 1' src/long.txt && printf '}\n' >> src/long.txt" ""
hyg "printf 'run every test\n' > .claude/commands/t.md" ""
# a suppression that explains itself, and an id with a lowercase prefix
printf 'errcheck xUnit1004\n' > "$root/lint2.log"
# shellcheck disable=SC2016  # $(NoWarn) is MSBuild syntax, written literally
(cd "$repo" && printf 'f() //nolint:errcheck // the callee logs it\n' > src/e.go &&
  printf '<PropertyGroup><NoWarn>$(NoWarn);xUnit1004</NoWarn></PropertyGroup>\n' > src/X.csproj &&
  $G add -A && $G commit -q -m "explained suppressions") || exit 1
bash "$script" "$repo" --base origin/main --warning-log "$root/lint2.log" 2>&1 | grep -q "adds a warning suppression" \
  && { echo "FAIL $name: an explained nolint or a lowercase-prefixed id was refused with a log showing it"; exit 1; }
(cd "$repo" && $G reset -q --hard HEAD~1)

# 16b. A base whose remote cannot be read, and a branch with nothing on it.
url=$(cd "$repo" && git remote get-url origin)
(cd "$repo" && git remote set-url origin "$root/nowhere.git")
fires "cannot read main from origin" || { echo "FAIL $name: an unreadable remote base was not refused"; exit 1; }
(cd "$repo" && git remote set-url origin "$url")
(cd "$repo" && $G checkout -q -b nothing-here origin/main)
fires "there is nothing to file" || { echo "FAIL $name: a branch with no changes was not refused"; exit 1; }
(cd "$repo" && $G checkout -q feature && $G branch -q -D nothing-here)

# 17. What a blind scan looked like: the same credential, refused from
# everywhere. A subdirectory, a colour setting and a non-ASCII name each once
# made the scan read nothing, exit 0 and stamp.
tok="ghp_abcdefghijklmnopqrstuvwxyz0123"
(cd "$repo" && printf 'const t = "%s";\n' "$tok" > src/t.ts && $G add -A && $G commit -q -m token) || exit 1
out=$(cd "$repo/src" && bash "$script" --base origin/main 2>&1); rc=$?
[ "$rc" = "1" ] || { echo "FAIL $name: from a subdirectory exited $rc: $out"; exit 1; }
printf '%s' "$out" | grep -q "credential" || { echo "FAIL $name: the credential was not seen from a subdirectory: $out"; exit 1; }
for setting in "color.ui always" "diff.external true"; do
  # shellcheck disable=SC2086  # the setting is two words on purpose
  (cd "$repo" && git config --local $setting)
  out=$(run); rc=$?
  (cd "$repo" && git config --local --unset "${setting%% *}")
  [ "$rc" = "1" ] || { echo "FAIL $name: under $setting exited $rc: $out"; exit 1; }
  printf '%s' "$out" | grep -q "credential" || { echo "FAIL $name: the credential was not seen under $setting: $out"; exit 1; }
done
(cd "$repo" && printf 'y = 1\n' > "a-$(printf '\303\251').py" && $G add -A && $G commit -q -m "non-ascii name") || exit 1
out=$(run); rc=$?
printf '%s' "$out" | grep -q "syntax error" && { echo "FAIL $name: a non-ASCII name broke the scan: $out"; exit 1; }
printf '%s' "$out" | grep -q "credential" || { echo "FAIL $name: the credential was not seen past a non-ASCII name: $out"; exit 1; }
(cd "$repo" && $G reset -q --hard HEAD~2)
(cd "$repo" && printf 'y = 1\n' > "a-$(printf '\303\251').py" && $G add -A && $G commit -q -m "non-ascii name") || exit 1
out=$(run); rc=$?
[ "$rc" = "0" ] || { echo "FAIL $name: a clean non-ASCII name exited $rc: $out"; exit 1; }
grep -qx "file: a-$(printf '\303\251').py" "$HOUSEBROKEN_HOME/branch-checks/$(cd "$repo" && git rev-parse HEAD)" ||
  { echo "FAIL $name: the stamp does not hold the real name"; exit 1; }
(cd "$repo" && $G reset -q --hard HEAD~1)

# 18. The commits go up, not the net diff: a later commit that removes a secret
# or an artifact leaves it in the history.
(cd "$repo" && printf 'const t = "%s";\n' "$tok" > src/t.ts && printf '# plan\n' > PLAN.md && $G add -A && $G commit -q -m wip &&
  $G rm -q src/t.ts PLAN.md && $G commit -q -m "clean up") || exit 1
out=$(run); rc=$?
[ "$rc" = "1" ] || { echo "FAIL $name: a secret removed by a later commit exited $rc: $out"; exit 1; }
printf '%s' "$out" | grep -q "history carries a personal path or a credential: $tok" || { echo "FAIL $name: the secret in the history was not named: $out"; exit 1; }
printf '%s' "$out" | grep -q "PLAN.md is in this branch's history" || { echo "FAIL $name: the artifact in the history was not named: $out"; exit 1; }
(cd "$repo" && $G reset -q --hard HEAD~2)
# --allow still lifts it, and one commit is not reported twice
(cd "$repo" && printf 'const t = "%s";\n' "$tok" > src/t.ts && $G add -A && $G commit -q -m one) || exit 1
out=$(run)
[ "$(printf '%s' "$out" | grep -c "credential")" = "1" ] || { echo "FAIL $name: one secret in one commit was reported twice: $out"; exit 1; }
(cd "$repo" && $G reset -q --hard HEAD~1)

# 19. A rename is one file with its own history: the stamp names both sides, and
# what the old path already carried is not read as added.
(cd "$repo" && printf 'const home = "/home/%s/x";\n' "$(basename "$HOME")" > src/keep.ts && $G add -A && $G commit -q -m base2 && setbase HEAD) || exit 1
(cd "$repo" && $G mv src/keep.ts src/moved.ts && $G commit -q -m rename) || exit 1
out=$(run); rc=$?
[ "$rc" = "0" ] || { echo "FAIL $name: a pure rename exited $rc: $out"; exit 1; }
stamp="$HOUSEBROKEN_HOME/branch-checks/$(cd "$repo" && git rev-parse HEAD)"
if ! grep -qx 'file: src/moved.ts' "$stamp" || ! grep -qx 'from: src/keep.ts' "$stamp"; then
  echo "FAIL $name: the stamp does not name both sides of a rename"; cat "$stamp"; exit 1
fi
(cd "$repo" && $G reset -q --hard HEAD~1)

# 20. A suppression the edited line already carried is the maintainer's, not the
# branch's (Jebel-Quant/rhiza-claude: a name added to an import that keeps its
# "# noqa: E402"); one removed line answers for one added line, so a second is new.
(cd "$repo" && printf 'from m import a  # noqa: E402\n' > src/k.py && $G add -A && $G commit -q -m k && setbase HEAD) || exit 1
(cd "$repo" && printf 'from m import a, b  # noqa: E402\n' > src/k.py && $G add -A && $G commit -q -m "edit k") || exit 1
fires "adds a warning suppression" && { echo "FAIL $name: an edited line keeping its own suppression was refused"; exit 1; }
(cd "$repo" && printf 'from m import a, b  # noqa: E402\nfrom n import c  # noqa: E402\n' > src/k.py && $G add -A && $G commit -q --amend -m "edit k") || exit 1
fires "adds a warning suppression" || { echo "FAIL $name: a second suppression beside a kept one was not refused"; exit 1; }
(cd "$repo" && $G reset -q --hard HEAD~1)

echo "PASS $name"
