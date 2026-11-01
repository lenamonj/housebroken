#!/bin/bash
# test-pr-sweep.sh - scripts/pr-sweep.sh over a stub gh: --all lists the open
# pull requests and exits 0, the first run records its open set in the state
# file, a pull request that left the open set is reported on the next run, one
# filed and merged between runs is reported once, and a merged one whose fork
# branch still exists prints TIDY on every run until the branch is gone.
set -u
name=test-pr-sweep
script="$(cd "$(dirname "$0")/../scripts" && pwd)/pr-sweep.sh"

bash "$script" --help | grep -q "Usage:" || { echo "FAIL $name: --help has no usage"; exit 1; }
bash "$script" --nonsense 2>/dev/null && { echo "FAIL $name: bad argument exited 0"; exit 1; }
grep -q 'HOUSEBROKEN_USER' "$script" || { echo "FAIL $name: no HOUSEBROKEN_USER"; exit 1; }
grep -qi 'lenamonj' "$script" && { echo "FAIL $name: literal username still present"; exit 1; }

tmp=$(mktemp -d) || { echo "FAIL $name: mktemp failed"; exit 1; }
trap 'rm -rf "$tmp"' EXIT
state="$tmp/sweep-state.json"
mkdir -p "$tmp/bin"
cat > "$tmp/bin/gh" <<'STUB'
#!/bin/bash
case "$*" in
  "search prs --author me --state open"*)
    printf 'o/r\t1\t2026-11-01T10:00:00Z\tOpen one\n' ;;
  "search prs --author me --state closed"*) cat "$STUB_DIR/closed" 2>/dev/null || true ;;
  "pr view 2 --repo o/r"*)
    echo '{"state":"MERGED","mergedAt":"2026-10-30T10:00:00Z","mergedBy":{"login":"maint"},"headRefName":"fix-2","headRepository":{"name":"r"},"headRepositoryOwner":{"login":"me"}}' ;;
  "pr view 1 --repo o/r"*)
    echo '{"mergeable":"MERGEABLE","reviewDecision":"","statusCheckRollup":[{"conclusion":"SUCCESS"}],"comments":[],"reviews":[],"latestReviews":[]}' ;;
  "api repos/me/r/git/refs/heads/fix-2"*) [ -f "$STUB_DIR/branch-gone" ] && exit 1; echo '{}' ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$tmp/bin/gh"
sweep() { STUB_DIR="$tmp" PATH="$tmp/bin:$PATH" HOUSEBROKEN_USER=me bash "$script" "$@"; }

out=$(sweep --all --state "$state"); rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL $name: --all exited $rc: $out"; exit 1; }
echo "$out" | grep -qE '^ok +o/r +#1 ' || { echo "FAIL $name: no PR rows: $out"; exit 1; }
echo "$out" | grep -qx -- '--- no previous sweep recorded' ||
  { echo "FAIL $name: first run did not say there was no previous sweep"; exit 1; }
echo "$out" | grep -q '^open PRs: 1; needing action: 0' || { echo "FAIL $name: wrong totals: $out"; exit 1; }

[ -f "$state" ] || { echo "FAIL $name: no state file at $state"; exit 1; }
jq -e -r '.lastRun | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")' "$state" >/dev/null ||
  { echo "FAIL $name: lastRun is not an ISO time"; exit 1; }
jq -e '.open == ["o/r#1"]' "$state" >/dev/null || { echo "FAIL $name: wrong open set in the state file"; exit 1; }

# a pull request that left the open set between runs
jq '.open += ["o/r#2"]' "$state" > "$state.new" && mv "$state.new" "$state"
out=$(sweep --state "$state"); rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL $name: second run exited $rc"; exit 1; }
echo "$out" | grep -qE '^--- merged or closed since [0-9]{4}-' || { echo "FAIL $name: no since-last-run section"; exit 1; }
echo "$out" | grep -q '^MERGED o/r#2 by maint at 2026-10-30' || { echo "FAIL $name: merged PR not reported: $out"; exit 1; }
jq -e '.open | index("o/r#2") == null' "$state" >/dev/null || { echo "FAIL $name: the merged PR survived in the state"; exit 1; }

# its fork branch prints TIDY on every run, the merge only once
echo "$out" | grep -q '^TIDY   o/r#2 ' || { echo "FAIL $name: no TIDY line: $out"; exit 1; }
echo "$out" | grep -q '^fork branches to tidy: 1' || { echo "FAIL $name: tidy count missing: $out"; exit 1; }
out=$(sweep --state "$state") || { echo "FAIL $name: third run exited non-zero"; exit 1; }
echo "$out" | grep -q '^TIDY   o/r#2 ' || { echo "FAIL $name: TIDY line did not persist: $out"; exit 1; }
echo "$out" | grep -q '^MERGED o/r#2 ' && { echo "FAIL $name: merge reported twice"; exit 1; }
touch "$tmp/branch-gone"
out=$(sweep --state "$state")
echo "$out" | grep -q '^TIDY' && { echo "FAIL $name: a deleted branch still printed TIDY: $out"; exit 1; }

# a pull request filed and merged between two runs was never in the stored open set
rm -f "$tmp/branch-gone"
printf 'o/r#2\n' > "$tmp/closed"
out=$(sweep --state "$state") || { echo "FAIL $name: between-runs run exited non-zero"; exit 1; }
[ "$(echo "$out" | grep -c '^MERGED o/r#2 ')" = "1" ] || { echo "FAIL $name: a merge between runs was not reported once: $out"; exit 1; }

echo "PASS $name"
