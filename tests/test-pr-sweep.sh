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
# The Actions reads are served as the API's JSON and put through the caller's
# own --jq, so the program that classifies the runs is the one under test.
expr="."; prev=""
for a in "$@"; do [ "$prev" = "--jq" ] && expr="$a"; prev="$a"; done
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
  "api repos/o/r/actions/runs?head_sha=abc123&per_page=100 "*) jq -r "$expr" "$STUB_DIR/runs.head.json" ;;
  "api repos/o/r/actions/runs?event=pull_request_target&per_page=1 "*) jq -r "$expr" "$STUB_DIR/runs.target.json" ;;
  "api repos/o/r/actions/runs?event=pull_request&per_page=1 "*) jq -r "$expr" "$STUB_DIR/runs.pr.json" ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$tmp/bin/gh"
sweep() { PATH="$tmp/bin:$PATH" HOUSEBROKEN_USER=me bash "$script" --state "$state" "$@"; }
printf 'o/r\t1\t2026-11-01T10:00:00Z\tOpen one\n' > "$tmp/open"
printf 'MERGED\n' > "$tmp/state2"
printf 'there\n' > "$tmp/branch"
pr() { # rollup comments labels
  jq -n --argjson r "${1:-[]}" --argjson c "${2:-[]}" --argjson l "${3:-[]}" '{mergeable: "MERGEABLE", reviewDecision: "", headRefOid: "abc123", statusCheckRollup: $r, comments: $c, labels: $l, reviews: [], latestReviews: []}' > "$tmp/pr.json"
}
pr '[{"conclusion":"SUCCESS"}]'
# What the Actions API says behind an empty check list: the runs on the head,
# each a "status/conclusion" word, then how many runs the repository has for
# each pull request event. A missing file is a read that failed.
runs() { # runs-on-head pull_request-runs [pull_request_target-runs]
  jq -n --arg r "$1" '($r | split(" ") | map(select(length > 0) | split("/") | {status: .[0], conclusion: (if (.[1] // "") == "" then null else .[1] end)})) as $w
    | {total_count: ($w | length), workflow_runs: $w}' > "$tmp/runs.head.json"
  jq -n --argjson n "$2" '{total_count: $n}' > "$tmp/runs.pr.json"
  jq -n --argjson n "${3:-0}" '{total_count: $n}' > "$tmp/runs.target.json"
}
runs "" 0 0

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
said() { printf '[{"author":{"login":"%s"},"authorAssociation":"%s","createdAt":"2026-11-01T10:00:00Z"}]' "$1" "${2:-MEMBER}"; }
ball 'last-word:talbot@2026-11-01 role:member' '[]' "$(said talbot)"
ball 'last-word:stranger@2026-11-01 role:none' '[]' "$(said stranger NONE)"
ball 'last-word:fan@2026-11-01 role:contributor' '[]' "$(said fan CONTRIBUTOR)"
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

# an empty check list is read: a head no run was created for is ours to act on,
# a run awaiting approval is the maintainer's click, and a repository whose pull
# requests run nothing is quiet
runs "" 5;   ball '^ACT .*\[no-ci-on-head\]' '[]' '[]'
runs "" 0 3; ball '^ACT .*\[no-ci-on-head\]' '[]' '[]'
runs "" 0 0; ball '^ok .* ci=none ' '[]' '[]'
runs "completed/action_required completed/action_required" 5; ball '^ok .* ci=needs-approval ' '[]' '[]'
for going in in_progress queued waiting requested pending; do
  runs "$going/" 5; ball '^ok .* ci=pending ' '[]' '[]'
done
# a run that finished badly without reporting a check never started a job: an
# approval nobody gave before it lapsed, or a failure at startup. It is not a
# pending one, and it outranks a run that is still going.
for bad in failure startup_failure timed_out cancelled stale; do
  runs "completed/$bad" 5; ball '^ACT .*\[ci-never-started\]' '[]' '[]'
done
runs "in_progress/ completed/failure completed/failure" 5; ball '^ACT .*\[ci-never-started\]' '[]' '[]'
# an approval that is still awaited outranks one that lapsed
runs "completed/failure completed/action_required" 5; ball '^ok .* ci=needs-approval ' '[]' '[]'
# a run that finished well and reported nothing is nothing to act on
for fine in success neutral skipped; do
  runs "completed/$fine" 5; ball '^ok .* ci=none ' '[]' '[]'
done
# a read that failed, or an answer that is not the API's, is not quiet
runs "" 5; rm -f "$tmp/runs.pr.json"; ball '^ACT .*\[ci-unread\]' '[]' '[]'
runs "" 5; printf 'not json\n' > "$tmp/runs.head.json"; ball '^ACT .*\[ci-unread\]' '[]' '[]'
runs "" 5; printf '{}\n' > "$tmp/runs.head.json"; ball '^ACT .*\[ci-unread\]' '[]' '[]'
rm -f "$tmp/runs.head.json"; ball '^ACT .*\[ci-unread\]' '[]' '[]'
# a check list that is not empty never asks
ball '^ok .* ci=green ' '[{"conclusion":"SUCCESS"}]' '[]'
runs "" 0 0

# a stale bot's warning that still stands is ours, with the day it closes
green='[{"conclusion":"SUCCESS"}]'
c() { jq -cn --arg a "$1" --arg t "$2" --arg b "$3" '{author: {login: $a}, authorAssociation: "NONE", createdAt: $t, body: $b}'; }
labelled() { # comments labels: the row sweep prints for them
  pr "$green" "$1" "$2"
  out=$(sweep --all)
}
warn="$(c github-actions 2026-11-06T05:02:52Z 'This PR is stale because it has been open 60 days with no activity. Remove stale label or comment or this will be closed in 7 days.')"
ball '^ACT .*\[stale:closes-2026-11-13\]' "$green" "[$warn]"
echo "$out" | grep -qx '     before any bump: re-derive the body.s claims on the default branch, read ci on the head, and check whether upstream changed the touched files' || fail "no pre-bump line under a stale row: $out"
# an answer resets the timer, even while the label lingers
labelled "[$warn,$(c me 2026-11-06T09:05:36Z 'A correction.')]" '[{"name":"Stale"}]'
echo "$out" | grep -q 'stale:' && fail "an answered warning was still flagged: $out"
echo "$out" | grep -q 'before any bump' && fail "the pre-bump line printed with no stale row: $out"
# the days may come before the close, and may not be stated at all
ball 'stale:closes-2026-11-20' "$green" "[$(c 'stale[bot]' 2026-11-06T05:00:00Z 'Marked as stale. If no further activity occurs within 14 days, it will be closed.')]"
ball 'stale:warned-2026-11-06' "$green" "[$(c github-actions 2026-11-06T05:00:00Z 'This is stale and will be closed if nothing happens.')]"
# the newest warning is the one that counts
ball 'stale:closes-2026-11-27' "$green" "[$warn,$(c me 2026-11-06T09:05:36Z 'A correction.'),$(c github-actions 2026-11-20T05:00:00Z 'This PR is stale. It will be closed in 7 days.')]"
# a label alone is flagged, by the word and not by its letters
labelled '[]' '[{"name":"lifecycle/stale"}]'
echo "$out" | grep -q '^ACT .*\[stale:label\]' || fail "a stale label alone was not flagged: $out"
labelled '[]' '[{"name":"stalemate"}]'
echo "$out" | grep -q 'stale:' && fail "a label that only contains the letters was flagged: $out"
# a bot that says something else, and a person who says the word
ball '^ok ' "$green" "[$(c github-actions 2026-11-06T05:00:00Z 'Coverage is unchanged.')]"
labelled "[$(c talbot 2026-11-06T05:00:00Z 'This looks stale, closing in 7 days.')]" '[]'
echo "$out" | grep -q 'stale:' && fail "a person's comment was read as the bot's warning: $out"
# both marks stand side by side
runs "" 5; ball '^ACT .*\[no-ci-on-head stale:closes-2026-11-13\]' '[]' "[$warn]"
runs "" 0 0

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
