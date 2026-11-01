#!/bin/bash
# test-fork-hygiene.sh - scripts/fork-hygiene.sh over a stub gh: --dry-run names
# a candidate and deletes nothing, a branch an open pull request uses anywhere is
# kept, one nobody uses is deleted, a repository of our own or a ref that cannot
# be read is left alone, and a branch name is never mistaken for another.
set -u
name=test-fork-hygiene
script="$(cd "$(dirname "$0")/../scripts" && pwd)/fork-hygiene.sh"

fail() { echo "FAIL $name: $1"; exit 1; }

bash "$script" --help | grep -q "Usage:" || fail "--help has no usage"
bash "$script" --nonsense 2>/dev/null && fail "bad argument exited 0"
grep -qi 'lenamonj' "$script" && fail "literal username still present"
grep -q '/tmp/' "$script" && fail "hardcoded temp path still present"

stub=$(mktemp -d) || exit 1
trap 'rm -rf "$stub"' EXIT
export STUB_DIR="$stub"
cat > "$stub/gh" <<'STUB'
#!/bin/bash
case "$*" in
  "search prs --author u --state closed"*) echo "o/r 1" ;;
  "pr view 1 --repo o/r"*) cat "$STUB_DIR/info" ;;
  "api graphql"*)
    [ -f "$STUB_DIR/graphql.fail" ] && exit 1
    cat "$STUB_DIR/ref" ;;
  "api -X DELETE"*) echo "$*" >> "$STUB_DIR/deleted" ;;
  "repo list"*) [ -f "$STUB_DIR/list.fail" ] && exit 1; printf 'o/r\nq/s\n' ;;
  "search prs --author u --json"*) printf 'o/r\n' ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$stub/gh"
hyg() { PATH="$stub:$PATH" HOUSEBROKEN_USER=u bash "$script" "$@"; }
printf 'u\tr\tfix-it\tCLOSED\n' > "$stub/info"
ref() { printf '%s\t%s\t%s\n' "$1" "$2" "${3:-}" > "$stub/ref"; }

ref true yes
out=$(hyg --dry-run)
echo "$out" | grep -q '^would delete u/r fix-it (CLOSED o/r#1)' || fail "no candidate branch printed: $out"
[ ! -f "$stub/deleted" ] || fail "a dry run deleted a branch"
echo "$out" | grep -q 'forks with no PR' || fail "orphan fork section missing"
echo "$out" | tail -1 | grep -q '^q/s $' || fail "the orphan fork was not listed: $out"

# an open pull request on any repository in the network keeps the branch
ref true yes "downstream/r#9"
out=$(hyg)
echo "$out" | grep -q "^kept u/r fix-it: open pull request downstream/r#9 still uses it" || fail "a branch an open pull request uses was not kept: $out"
[ ! -f "$stub/deleted" ] || fail "a branch an open pull request uses was deleted"

# a repository of our own is never touched, nor a ref that is gone or unreadable
ref false yes
hyg >/dev/null; [ ! -f "$stub/deleted" ] || fail "a branch of a repository that is not a fork was deleted"
ref true no
hyg >/dev/null; [ ! -f "$stub/deleted" ] || fail "a ref that does not exist was deleted"
touch "$stub/graphql.fail"
ref true yes
out=$(hyg 2>&1)
rm -f "$stub/graphql.fail"
[ ! -f "$stub/deleted" ] || fail "a ref that could not be read was deleted"
echo "$out" | grep -q "cannot read u/r fix-it; kept" || fail "an unreadable ref was not named: $out"

ref true yes
out=$(hyg)
echo "$out" | grep -q "^deleted u/r fix-it" || fail "a branch no open pull request uses was not deleted: $out"
grep -q "repos/u/r/git/refs/heads/fix-it" "$stub/deleted" || fail "the wrong ref was deleted: $(cat "$stub/deleted")"
rm -f "$stub/deleted"

# a # would end the URL, and | is not a separator
printf 'u\tr\tfeature/wip|fix#123\tCLOSED\n' > "$stub/info"
out=$(hyg)
echo "$out" | grep -q "^deleted u/r feature/wip|fix#123" || fail "an odd branch name was not read whole: $out"
grep -q "heads/feature/wip%7Cfix%23123" "$stub/deleted" || fail "the branch name was not encoded: $(cat "$stub/deleted")"
printf 'u\tr\tfix-it\tCLOSED\n' > "$stub/info"

# a failed listing is not every fork an orphan
touch "$stub/list.fail"
out=$(hyg 2>&1); rc=$?
rm -f "$stub/list.fail"
[ "$rc" -eq 1 ] || fail "a failed fork listing exited $rc: $out"

echo "PASS $name"
