#!/bin/bash
# test-fork-hygiene.sh - scripts/fork-hygiene.sh over a stub gh: --dry-run names
# a candidate branch and deletes nothing, a branch an open pull request still
# uses is kept, and one nobody uses is deleted.
set -u
name=test-fork-hygiene
script="$(cd "$(dirname "$0")/../scripts" && pwd)/fork-hygiene.sh"

bash "$script" --help | grep -q "Usage:" || { echo "FAIL $name: --help has no usage"; exit 1; }
bash "$script" --nonsense 2>/dev/null && { echo "FAIL $name: bad argument exited 0"; exit 1; }
grep -qi 'lenamonj' "$script" && { echo "FAIL $name: literal username still present"; exit 1; }
grep -q '/tmp/' "$script" && { echo "FAIL $name: hardcoded temp path still present"; exit 1; }

stub=$(mktemp -d) || exit 1
trap 'rm -rf "$stub"' EXIT
cat > "$stub/gh" <<'STUB'
#!/bin/bash
case "$*" in
  "search prs --author u --state closed"*) echo "o/r 1" ;;
  "pr view 1 --repo o/r"*) echo "u|r|fix-it|CLOSED" ;;
  "api repos/u/r/git/refs/heads/fix-it"*) echo '{}' ;;
  "pr list --repo o/r --head fix-it"*) cat "$STUB_DIR/open" ;;
  "api -X DELETE"*) echo "DELETED $*" >> "$STUB_DIR/deleted" ;;
  "repo list"*|"search prs --author u --json"*) ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$stub/gh"
hyg() { STUB_DIR="$stub" PATH="$stub:$PATH" HOUSEBROKEN_USER=u bash "$script" "$@"; }

: > "$stub/open"
out=$(hyg --dry-run)
echo "$out" | grep -q '^would delete u/r fix-it (CLOSED o/r#1)' || { echo "FAIL $name: no candidate branch printed: $out"; exit 1; }
[ ! -f "$stub/deleted" ] || { echo "FAIL $name: a dry run deleted a branch"; exit 1; }
echo "$out" | grep -q 'forks with no PR' || { echo "FAIL $name: orphan fork section missing"; exit 1; }

printf '2\n' > "$stub/open"
out=$(hyg)
echo "$out" | grep -q "^kept u/r fix-it: open pull request o/r#2 still uses it" || { echo "FAIL $name: a branch an open pull request uses was not kept: $out"; exit 1; }
[ ! -f "$stub/deleted" ] || { echo "FAIL $name: a branch an open pull request uses was deleted"; exit 1; }
: > "$stub/open"
out=$(hyg)
echo "$out" | grep -q "^deleted u/r fix-it" || { echo "FAIL $name: a branch no open pull request uses was not deleted: $out"; exit 1; }
echo "PASS $name"
