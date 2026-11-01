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
      *) printf 'TOTAL\t0\t0\tfalse\n' ;;
    esac ;;
  *"search/issues"*"type:pr"*)
    case "$args" in
      *"utils docs"*) printf 'TOTAL\t1\t1\tfalse\nPR\t1881\topen\t2026-08-01\tsomeone\tUtils docs\n' ;;
      *) printf 'TOTAL\t0\t0\tfalse\n' ;;
    esac ;;
  *"issues/98/comments"*)
    echo '[{"user":{"login":"maint"},"body":"This is intended behaviour. We will not change it."}]' ;;
  *commits*) ;;
  "pr list -R o/r --state open"*)
    printf '1881\t2026-08-01\tsomeone\tUtils docs\ttyper/cli.py\n4103\t2026-08-02\tother\tBig move\tMORE\n' ;;
  *"pulls/4103/files"*) printf 'a.rb\nlib/prefix_tree.rb\n' ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$root/bin/gh"
export PATH="$root/bin:$PATH"

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

echo "PASS $name"
