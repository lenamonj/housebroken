#!/bin/bash
# test-pr-sweep.sh - scripts/pr-sweep.sh over a stub gh: --all lists the open
# pull requests, the first run records its open set, a pull request that left it
# is reported on the next run and survives a failed read, the last one merging is
# reported, a merged one whose fork branch still exists prints TIDY on every run
# until GitHub says it is gone, and the ball-in-court reading holds.
set -u
name=test-pr-sweep
script="$(cd "$(dirname "$0")/../scripts" && pwd)/pr-sweep.sh"

fail() { echo "FAIL $name: $1"; exit 1; }

bash "$script" --help | grep -q "Usage:" || fail "--help has no usage"
bash "$script" --nonsense 2>/dev/null && fail "bad argument exited 0"
grep -q 'HOUSEBROKEN_USER' "$script" || fail "no HOUSEBROKEN_USER"
grep -qi 'lenamonj' "$script" && fail "literal username still present"

tmp=$(mktemp -d) || fail "mktemp failed"
trap 'rm -rf "$tmp"' EXIT
state="$tmp/sweep-state.json"
export STUB_DIR="$tmp"
mkdir -p "$tmp/bin"
cat > "$tmp/bin/gh" <<'STUB'
#!/bin/bash
case "$*" in
  "search prs --author me --state open"*) cat "$STUB_DIR/open" ;;
  "search prs --author me --state closed"*) cat "$STUB_DIR/closed" 2>/dev/null || true ;;
  "pr view 1 --repo o/r"*) [ -f "$STUB_DIR/view1.fail" ] && exit 1; cat "$STUB_DIR/pr.json" ;;
  "pr view 2 --repo o/r"*)
    [ -f "$STUB_DIR/view2.fail" ] && exit 1
    echo "{\"state\":\"$(cat "$STUB_DIR/state2")\",\"mergedAt\":\"2026-10-30T10:00:00Z\",\"mergedBy\":{\"login\":\"maint\"},\"headRefName\":\"fix-2\",\"headRepository\":{\"name\":\"r\"},\"headRepositoryOwner\":{\"login\":\"me\"}}" ;;
  "api repos/me/r/git/ref/heads/fix-2"*)
    case "$(cat "$STUB_DIR/branch")" in
      gone) echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
      throttled) echo "gh: API rate limit exceeded (HTTP 403)" >&2; exit 1 ;;
      *) echo '{}' ;;
    esac ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$tmp/bin/gh"
sweep() { PATH="$tmp/bin:$PATH" HOUSEBROKEN_USER=me bash "$script" --state "$state" "$@"; }
printf 'o/r\t1\t2026-11-01T10:00:00Z\tOpen one\n' > "$tmp/open"
printf 'MERGED\n' > "$tmp/state2"
printf 'there\n' > "$tmp/branch"
pr() { # rollup comments
  jq -n --argjson r "${1:-[]}" --argjson c "${2:-[]}" '{mergeable: "MERGEABLE", reviewDecision: "", statusCheckRollup: $r, comments: $c, reviews: [], latestReviews: []}' > "$tmp/pr.json"
}
pr '[{"conclusion":"SUCCESS"}]'

out=$(sweep --all); rc=$?
[ "$rc" -eq 0 ] || fail "--all exited $rc: $out"
echo "$out" | grep -qE '^ok +o/r +#1 ' || fail "no PR rows: $out"
echo "$out" | grep -qx -- '--- no previous sweep recorded' || fail "first run did not say there was no previous sweep"
echo "$out" | grep -q '^open PRs: 1; needing action: 0' || fail "wrong totals: $out"

[ -f "$state" ] || fail "no state file at $state"
jq -e -r '.lastRun | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")' "$state" >/dev/null || fail "lastRun is not an ISO time"
jq -e '.open == ["o/r#1"]' "$state" >/dev/null || fail "wrong open set in the state file"

# a read that fails does not lose a merge: it is reported when the read comes back
jq '.open += ["o/r#2"]' "$state" > "$state.new" && mv "$state.new" "$state"
touch "$tmp/view2.fail"
out=$(sweep 2>&1); rc=$?
rm -f "$tmp/view2.fail"
[ "$rc" -eq 1 ] || fail "a failed read of a closed pull request exited $rc: $out"
jq -e '.open | index("o/r#2") != null' "$state" >/dev/null || fail "a pull request that could not be read left the state"
out=$(sweep); rc=$?
[ "$rc" -eq 0 ] || fail "the run after a failed read exited $rc: $out"
echo "$out" | grep -qE '^--- merged or closed since [0-9]{4}-' || fail "no since-last-run section"
echo "$out" | grep -q '^MERGED o/r#2 by maint at 2026-10-30' || fail "merged PR not reported: $out"
jq -e '.open | index("o/r#2") == null' "$state" >/dev/null || fail "the merged PR survived in the state"

# its fork branch prints TIDY on every run, the merge only once
echo "$out" | grep -q '^TIDY   o/r#2 ' || fail "no TIDY line: $out"
echo "$out" | grep -q '^fork branches to tidy: 1' || fail "tidy count missing: $out"
out=$(sweep) || fail "third run exited non-zero"
echo "$out" | grep -q '^TIDY   o/r#2 ' || fail "TIDY line did not persist: $out"
echo "$out" | grep -q '^MERGED o/r#2 ' && fail "merge reported twice"
# a throttled answer is not a deleted branch; a 404 is
printf 'throttled\n' > "$tmp/branch"
out=$(sweep 2>&1) || fail "a throttled ref read exited non-zero: $out"
jq -e '.tidy | length == 1' "$state" >/dev/null || fail "a throttled read dropped the TIDY entry"
printf 'gone\n' > "$tmp/branch"
out=$(sweep) || fail "a 404 ref read exited non-zero"
echo "$out" | grep -q '^TIDY' && fail "a deleted branch still printed TIDY: $out"
jq -e '.tidy | length == 0' "$state" >/dev/null || fail "a deleted branch stayed in the state"

# a pull request filed and merged between two runs was never in the stored open set
printf 'there\n' > "$tmp/branch"
printf 'o/r#2\n' > "$tmp/closed"
out=$(sweep) || fail "between-runs run exited non-zero"
[ "$(echo "$out" | grep -c '^MERGED o/r#2 ')" = "1" ] || fail "a merge between runs was not reported once: $out"
: > "$tmp/closed"
printf 'gone\n' > "$tmp/branch"; sweep >/dev/null

# an open pull request the search dropped is not something to tidy
jq '.open += ["o/r#2"]' "$state" > "$state.new" && mv "$state.new" "$state"
printf 'OPEN\n' > "$tmp/state2"; printf 'there\n' > "$tmp/branch"
out=$(sweep)
echo "$out" | grep -q '^TIDY' && fail "an open pull request was recorded for tidying: $out"
printf 'MERGED\n' > "$tmp/state2"; printf 'gone\n' > "$tmp/branch"

# whose turn it is, and what the checks say
ball() { # expected-word rollup comments
  pr "$2" "$3"
  out=$(sweep --all)
  echo "$out" | grep -q "$1" || fail "expected $1 for $2 $3: $out"
}
said() { printf '[{"author":{"login":"%s"},"createdAt":"2026-11-01T10:00:00Z"}]' "$1"; }
ball 'last-word:talbot' '[]' "$(said talbot)"
ball 'last-word:devinrsmith' '[]' "$(said devinrsmith)"
ball 'last-word:apache-fan' '[]' "$(said apache-fan)"
ball '^ok ' '[]' "$(said 'github-actions')"
ball '^ok ' '[]' "$(said 'renovate[bot]')"
for bad in TIMED_OUT STARTUP_FAILURE CANCELLED FAILURE STALE; do
  ball 'ci-failing' "[{\"conclusion\":\"$bad\",\"status\":\"COMPLETED\"}]" '[]'
done
ball 'ci=pending' '[{"conclusion":"","status":"IN_PROGRESS"}]' '[]'
ball 'ci=needs-approval' '[{"conclusion":"ACTION_REQUIRED","status":"COMPLETED"}]' '[]'
ball 'ci=green' '[{"conclusion":"SUCCESS"},{"conclusion":"SKIPPED"},{"state":"SUCCESS"}]' '[]'

# a pull request that cannot be read is not a clean one
touch "$tmp/view1.fail"
out=$(sweep 2>&1); rc=$?
rm -f "$tmp/view1.fail"
[ "$rc" -eq 1 ] || fail "an unreadable open pull request exited $rc: $out"
printf '%s' "$out" | grep -q "SWEEP UNREADABLE" || fail "an unreadable pull request was not named: $out"

# the last open pull request merging is a report, not a failure
jq '.open = ["o/r#2"]' "$state" > "$state.new" && mv "$state.new" "$state"
: > "$tmp/open"
printf 'there\n' > "$tmp/branch"
out=$(sweep); rc=$?
[ "$rc" -eq 0 ] || fail "no open pull requests left exited $rc: $out"
echo "$out" | grep -q '^MERGED o/r#2 ' || fail "the last merge was not reported: $out"
echo "$out" | grep -q '^TIDY   o/r#2 ' || fail "the last merge's branch was not reported: $out"
echo "$out" | grep -q '^open PRs: 0; needing action: 0' || fail "wrong totals with nothing open: $out"

echo "PASS $name"
