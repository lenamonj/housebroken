#!/bin/bash
# test-ref-check.sh - every reference in a body is looked up on GitHub and, with
# a clone, in the clone: what exists is found, what does not is NOT FOUND with
# exit 1, and fenced or quoted evidence is not read as a reference, all through
# the stub gh.
set -u
name=test-ref-check
here=$(cd "$(dirname "$0")" && pwd)
export PATH="$here/stubs:$PATH"
script="$here/../scripts/ref-check.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
G="git -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false"

fail() { echo "FAIL $name: $1" >&2; exit 1; }

bash "$script" --help | grep -q "Usage:" || fail "--help printed no usage"
bash "$script" octocat/Hello-World "$tmp/none.md" >/dev/null 2>&1
[ "$?" -eq 2 ] || fail "a missing file did not exit 2"

clone="$tmp/clone"
mkdir -p "$clone/src" || fail "clone setup failed"
(cd "$clone" && $G init -q && printf 'func TestParseRow(t *testing.T) {}\n' > src/row_test.go &&
  $G add -A && $G commit -q -m base) || fail "clone setup failed"
sha=$(git -C "$clone" rev-parse --short=12 HEAD)

body="$tmp/body.md"
# shellcheck disable=SC2016  # the backticks are markdown, written literally
printf 'Fixes #1, see https://github.com/octocat/Hello-World/blob/master/README. `TestParseRow` in `src/row_test.go` at `%s` covers it.\n```\n#99999999 in a pasted log\n```\n> quoted #99999998\n' "$sha" > "$body"
out=$(bash "$script" octocat/Hello-World "$body" --clone "$clone"); rc=$?
[ "$rc" -eq 0 ] || fail "every real reference exited $rc: $out"
for want in "#1 (pull request closed" "blob/master/README" "test TestParseRow" "file src/row_test.go" "commit $sha"; do
  printf '%s' "$out" | grep '^  found' | grep -qF "$want" || fail "not found: $want: $out"
done
printf '%s' "$out" | grep -q "99999999\|99999998" && fail "fenced or quoted evidence was read as a reference: $out"

# shellcheck disable=SC2016  # the backticks are markdown, written literally
for bad in 'Fixes #99999999.' 'See octocat/Hello-World#99999999.' 'See https://github.com/octocat/Hello-World/blob/master/NOPE.' \
           'Covered by `TestNoSuchThing`.' 'In `src/nope_test.go`.' 'At `0123456789ab`.'; do
  printf '%s\n' "$bad" > "$body"
  out=$(bash "$script" octocat/Hello-World "$body" --clone "$clone"); rc=$?
  [ "$rc" -eq 1 ] || fail "a reference to nothing exited $rc: $bad"
  printf '%s' "$out" | grep -q "NOT FOUND" || fail "a reference to nothing was not named: $bad"
done

printf 'The parser drops the last field.\n' > "$body"
out=$(bash "$script" octocat/Hello-World "$body"); rc=$?
[ "$rc" -eq 0 ] || fail "a body with no references exited $rc"

# identifiers and versions with a dot are not files; tilde fences and indented
# code are evidence; a github.com page outside a repository is not looked up
# shellcheck disable=SC2016  # the backticks are markdown, written literally
printf 'Use `os.path` and `t.Run` since `v1.2.3`. See https://github.com/features/actions.\n\n    error at #99999997\n\n~~~\n#99999996\n~~~\n' > "$body"
out=$(bash "$script" octocat/Hello-World "$body" --clone "$clone"); rc=$?
[ "$rc" -eq 0 ] || fail "identifiers, code blocks or a features page were refused: $out"

# what reads like a reference and is not one
(cd "$clone" && printf 'gone\n' > src/old.py && $G add -A && $G commit -q -m "add old" && $G rm -q src/old.py && $G commit -q -m "remove old") || fail "fixture failed"
# shellcheck disable=SC2016  # the backticks are markdown, written literally
for fine in 'Removes the dead `src/old.py`.' 'The `net/http.Client` timeout is ignored.' 'A buffer of `1048576` bytes overflows.' \
            'The value `2147483647` wraps.' 'It reads `/etc/app/config.yml` at startup.' 'Sends `application/vnd.api` as the type.'; do
  printf '%s\n' "$fine" > "$body"
  out=$(bash "$script" octocat/Hello-World "$body" --clone "$clone"); rc=$?
  [ "$rc" -eq 0 ] || fail "not a reference, exited $rc: $fine: $out"
done
# shellcheck disable=SC2016  # the backticks are markdown, written literally
printf 'See the `lib/nope.go` file.\n' > "$body"
out=$(bash "$script" octocat/Hello-World "$body" --clone "$clone")
printf '%s' "$out" | grep -q "CHECK      lib/nope.go is not in the clone" || fail "an unknown first directory was not noted: $out"

# a branch with a slash in its name, and a comparison, are looked up as what they are
stubbed="$tmp/bin"
mkdir -p "$stubbed"
cat > "$stubbed/gh" <<'STUB'
#!/bin/bash
case "$*" in
  "api repos/me/fork/contents/?ref=fix/parser "*|"api repos/me/fork/contents/a.c?ref=fix/parser "*) echo ok ;;
  "api repos/o/r/compare/main...me:real "*) echo ahead ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$stubbed/gh"
refs() { printf '%s\n' "$1" > "$body"; PATH="$stubbed:$PATH" bash "$script" o/r "$body"; }
refs 'See https://github.com/me/fork/tree/fix/parser for it.' >/dev/null || fail "a branch with a slash was refused"
refs 'See https://github.com/me/fork/blob/fix/parser/a.c#L3 for it.' >/dev/null || fail "a file on a branch with a slash was refused"
refs 'See https://github.com/me/fork/tree/fix/nosuch for it.' >/dev/null && fail "a branch that does not exist was found"
refs 'See https://github.com/o/r/compare/main...me:real for it.' >/dev/null || fail "a comparison was refused"
refs 'See https://github.com/o/r/compare/main...me:nosuch for it.' >/dev/null && fail "a comparison of nothing was found"

echo "PASS $name"
