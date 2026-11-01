#!/bin/bash
# test-prior-art.sh - scripts/prior-art.sh over a stub gh: the type comes from
# the API, a closed item's ruling is quoted, an open pull request that changes
# a file is listed though no title names it, a pull request past 100 files is
# read in full, --out saves where file-pr.sh looks, and a term matching more
# than a page is partial.
set -u
name="prior-art.sh"
here=$(cd "$(dirname "$0")" && pwd)
script="$here/../scripts/prior-art.sh"
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
export HOUSEBROKEN_HOME="$root/home" STUB_DIR="$root"
mkdir -p "$root/bin"

fail() { echo "FAIL $name: $1" >&2; exit 1; }

cat > "$root/bin/gh" <<'STUB'
#!/bin/bash
args="$*"
case "$args" in
  *"search/issues"*"is:pr is:open"*) echo 2 ;;
  *"search/issues"*"type:issue"*)
    case "$args" in
      *completion*) printf 'TOTAL\t50\t10\tfalse\n' ;;
      *"relative URL"*) printf 'TOTAL\t1\t1\tfalse\nissue\t98\tclosed\t2026-01-01\treporter\tRelative URLs\n' ;;
      *timedout*) printf 'TOTAL\t0\t0\ttrue\n' ;;
      *) printf 'TOTAL\t0\t0\tfalse\n' ;;
    esac ;;
  *"search/issues"*"type:pr"*)
    case "$args" in
      *"utils docs"*) printf 'TOTAL\t1\t1\tfalse\nPR\t1881\topen\t2026-08-01\tsomeone\tUtils docs\n' ;;
      *) printf 'TOTAL\t0\t0\tfalse\n' ;;
    esac ;;
  *"issues/98/comments"*)
    [ -f "$STUB_DIR/comments.fail" ] && exit 1
    cat "$STUB_DIR/comments.json" ;;
  *commits*)
    echo "$*" >> "$STUB_DIR/commit-calls"
    [ -f "$STUB_DIR/commits.fail" ] && exit 1
    cat "$STUB_DIR/commits.tsv" 2>/dev/null; true ;;
  "pr list -R o/r --state open"*)
    printf '1881\t2026-08-01\tsomeone\tUtils docs\ttyper/cli.py\n4103\t2026-08-02\tother\tBig move\tMORE\n' ;;
  *"pulls/4103/files"*)
    [ -f "$STUB_DIR/files.fail" ] && exit 1
    printf 'a.rb\nlib/prefix_tree.rb\n' ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$root/bin/gh"
export PATH="$root/bin:$PATH"

echo '[{"user":{"login":"maint","type":"User"},"body":"This is intended behaviour. We will not change it."}]' > "$root/comments.json"

help=$(bash "$script" --help) || fail "--help exited non-zero"
printf '%s' "$help" | grep -q "usage: prior-art.sh" || fail "--help printed no usage line"

# an open pull request read as an issue once got a duplicate filed
out=$(bash "$script" o/r "utils docs") || fail "run failed"
printf '%s\n' "$out" | grep -qE '^\| PR \| #1881 \|' || fail "#1881 not listed as a PR: $out"
printf '%s\n' "$out" | grep -qE '^\| issue \| #1881 \|' && fail "#1881 listed as an issue"

# a closed issue's ruling is quoted
out=$(bash "$script" o/r "relative URL") || fail "run failed"
line=$(printf '%s\n' "$out" | grep -E '^\| issue \| #98 \| closed \|' | head -1)
[ -n "$line" ] || fail "#98 not listed as a closed issue: $out"
printf '%s' "$line" | grep -q "This is intended behaviour" || fail "#98's ruling is empty: $line"

# an open pull request that changes the file is listed though no title names it
out=$(bash "$script" o/r typer/cli.py) || fail "path run failed"
printf '%s\n' "$out" | grep -qE '^\| PR \| #1881 \| open, changes this file \|' || fail "#1881 changes typer/cli.py and was not listed: $out"
# a pull request changing more than 100 files is read in full
out=$(bash "$script" o/r prefix_tree.rb) || fail "name run failed"
printf '%s\n' "$out" | grep -qE '^\| PR \| #4103 \| open, changes this file \|' || fail "#4103 was not read past its 100th file: $out"

# --out writes the printout where file-pr.sh looks for it
bash "$script" o/r "relative URL" --out >/dev/null || fail "--out run failed"
[ -f "$HOUSEBROKEN_HOME/prior-art/prior-art-o-r.md" ] || fail "--out did not write under HOUSEBROKEN_HOME/prior-art"
rm -f "$HOUSEBROKEN_HOME/prior-art/prior-art-o-r.md"

# a term matching more than one page is partial: --out refuses to save it,
# --partial saves it marked as such
saved="$HOUSEBROKEN_HOME/prior-art/prior-art-o-r.md"
out=$(bash "$script" o/r completion --out 2>&1); rc=$?
[ "$rc" -eq 1 ] || fail "a partial printout saved with --out exited $rc, expected 1"
printf '%s' "$out" | grep -q "showing 10 of 50 issues for 'completion'" || fail "the truncation was not printed: $out"
[ ! -f "$saved" ] || fail "a partial printout was saved without --partial"
bash "$script" o/r completion --out --partial >/dev/null 2>&1 || fail "--partial did not save"
grep -q "saved with --partial" "$saved" || fail "the saved partial printout is not marked"

# a read that failed is a printout that has not read everything, whatever it found
partial() { # what it is for, then the arguments
  local what="$1"; shift
  rm -f "$saved"
  out=$(bash "$script" o/r "$@" --out 2>&1); rc=$?
  [ "$rc" -eq 1 ] || fail "$what saved a printout: exit $rc: $out"
  printf '%s' "$out" | grep -q "^PARTIAL: " || fail "$what was not marked partial: $out"
  [ ! -f "$saved" ] || fail "$what was saved"
}
partial "a search GitHub gave up on, with no results" timedout
touch "$root/commits.fail"; partial "a failed history read" src/parser.py; rm -f "$root/commits.fail"
touch "$root/files.fail"; partial "a failed file list of a large open pull request" src/parser.py; rm -f "$root/files.fail"
touch "$root/comments.fail"; partial "a failed read of a closed item's comments" "relative URL"; rm -f "$root/comments.fail"

# the history is read in full, with the path as a field so a + survives
rm -f "$root/commit-calls"
bash "$script" o/r libstdc++-v3/ChangeLog >/dev/null || fail "a path with a plus failed"
grep -q -- "--paginate" "$root/commit-calls" || fail "the history is not paginated: $(cat "$root/commit-calls")"
grep -q -- "-f path=libstdc++-v3/ChangeLog" "$root/commit-calls" || fail "the path was not sent as a field: $(cat "$root/commit-calls")"

# a merged pull request is the number the merge wrote, not an issue the subject names
printf 'Fix #12 in the parser (#34)\t2026-10-01\tmaint\nMerge pull request #56 from a/b\t2026-10-02\tmaint\nFix #78 by hand\t2026-10-03\tmaint\n' > "$root/commits.tsv"
out=$(bash "$script" o/r src/parser.py) || fail "the history run failed"
printf '%s\n' "$out" | grep -q '^| PR | #34 | merged' || fail "the merged pull request was not listed: $out"
printf '%s\n' "$out" | grep -q '^| PR | #56 | merged' || fail "a merge commit's pull request was not listed: $out"
printf '%s\n' "$out" | grep -qE '^\| PR \| #(12|78) ' && fail "an issue named in a subject was listed as a merged pull request: $out"
rm -f "$root/commits.tsv"

# a lock bot's boilerplate is not the ruling, and a stranger's escapes do not print
esc=$(printf '\033')
jq -n --arg b "$(printf 'We will not change this. %s[2J' "$esc")" '[{user: {login: "maint", type: "User"}, body: $b}, {user: {login: "lock", type: "Bot"}, body: "This issue has been automatically locked."}, {user: {login: "stale[bot]"}, body: "Closing."}]' > "$root/comments.json"
out=$(bash "$script" o/r "relative URL") || fail "the ruling run failed"
printf '%s\n' "$out" | grep -q 'We will not change this' || fail "the ruling was replaced by a bot: $out"
case "$out" in *"$esc"*) fail "an escape sequence reached the printout" ;; esac
printf '%s\n' "$out" | sed -n 2p | grep -q "strangers' text" || fail "the printout does not mark what is untrusted: $out"

echo "PASS $name"
