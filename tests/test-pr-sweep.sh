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
pr() { # rollup comments labels commits
  jq -n --argjson r "${1:-[]}" --argjson c "${2:-[]}" --argjson l "${3:-[]}" --argjson m "${4:-[]}" '{mergeable: "MERGEABLE", reviewDecision: "", headRefOid: "abc123", statusCheckRollup: $r, comments: $c, labels: $l, commits: $m, reviews: [], latestReviews: []}' > "$tmp/pr.json"
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

# a stale bot's notice that still stands is ours, with the day it closes. The
# notice is dated a day ago, so the day it names is still ahead.
green='[{"conclusion":"SUCCESS"}]'
t0=$(jq -rn 'now - 86400 | floor')
at() { jq -rn --argjson t "$t0" --argjson h "$1" '$t + $h * 3600 | strftime("%Y-%m-%dT%H:%M:%SZ")'; }  # hours after the notice
day() { jq -rn --argjson t "$t0" --argjson d "$1" '$t + $d * 86400 | strftime("%Y-%m-%d")'; }          # days after it
c() { jq -cn --arg a "$1" --arg t "$2" --arg b "$3" '{author: {login: $a}, authorAssociation: "NONE", createdAt: $t, body: $b}'; }
row() { # comments [labels] [commits]: the rows sweep prints for them, over green checks
  pr "$green" "$1" "${2:-[]}" "${3:-[]}"
  out=$(sweep --all)
}
marked() { row "$2" "${3:-[]}" "${4:-[]}"; echo "$out" | grep -q "$1" || fail "expected $1 for $2 ${3:-} ${4:-}: $out"; }
unmarked() { row "$2" "${3:-[]}" "${4:-[]}"; echo "$out" | grep -q 'stale:' && fail "$1: $out"; return 0; }
# the three wordings are the bots' own, from Netflix/zuul, frappe/erpnext and cpinitiative/usaco-guide
zuul='This PR is stale because it has been open 60 days with no activity. Remove stale label or comment or this will be closed in 7 days.'
erpnext='This pull request has been automatically marked as inactive because it has not had recent activity. It will be closed within 3 days if no further activity occurs, but it only takes a comment to keep a contribution alive :)'
usaco='This pull request has been automatically marked as stale because it has not had recent activity. Please address the requested changes and re-request reviews. Thank you for your contribution!'
warn="$(c github-actions "$(at 0)" "$zuul")"
marked "^ACT .*\[stale:closes-$(day 7)\]" "[$warn]"
echo "$out" | grep -qx '     before any bump: re-derive the body.s claims on the default branch, read ci on the head, and check whether upstream changed the touched files' || fail "no pre-bump line under a stale row: $out"
# probot's bot is the login stale in what gh prints, says "within", and may never say "stale"
marked "stale:closes-$(day 3)" "[$(c stale "$(at 0)" "$erpnext")]" '[{"name":"inactive"}]'
# a notice that names no close is still a notice, dated
marked "stale:warned-$(day 0)" "[$(c stale "$(at 0)" "$usaco")]" '[{"name":"stale"}]'
# an answer resets the bot's timer, even while the label lingers; so does a push
unmarked "an answered notice was still flagged" "[$warn,$(c me "$(at 4)" 'A correction.')]" '[{"name":"Stale"}]'
echo "$out" | grep -q 'before any bump' && fail "the pre-bump line printed with no stale row: $out"
unmarked "a notice answered by its author was flagged by the label" "[$(c stale "$(at 0)" "$usaco"),$(c hippi "$(at 70)" 'Still interested.')]" '[{"name":"stale"}]'
unmarked "a push after the notice did not clear it" "[$warn]" '[]' "[{\"committedDate\":\"$(at 5)\"}]"
marked "stale:closes-$(day 7)" "[$warn]" '[]' "[{\"committedDate\":\"$(at -48)\"}]"
# only the stated days count: a spelled number, hours, or a number that is not the close gives the notice's own date
marked "stale:warned-$(day 0)" "[$(c github-actions "$(at 0)" 'This PR is stale: open 60 days with no activity, and it will be closed in seven days.')]"
marked "stale:warned-$(day 0)" "[$(c github-actions "$(at 0)" 'This PR is stale with no activity and will be closed in 48 hours.')]"
marked "stale:warned-$(day 0)" "[$(c github-actions "$(at 0)" 'Stale after 90 days of no activity; closing soon.')]"
marked "stale:warned-$(day 0)" "[$(c 'stale[bot]' "$(at 0)" 'Marked as stale. If no further activity occurs within 14 days, it will be closed.')]"
# the newest notice is the one that counts
marked "stale:closes-$(day 8)" "[$(c github-actions "$(at -480)" "$zuul"),$(c me "$(at -470)" 'A correction.'),$(c github-actions "$(at 24)" 'This PR is stale with no activity. It will be closed in 7 days.')]"
# a deadline that passed on a pull request still open no longer stands
unmarked "a deadline three weeks gone was still flagged" "[$(c github-actions "$(at -720)" "$zuul")]"
# a label alone is flagged, by the word, and not when the label is the exemption
marked '^ACT .*\[stale:label\]' '[]' '[{"name":"lifecycle/stale"}]'
unmarked "a label that only contains the letters was flagged" '[]' '[{"name":"stalemate"}]'
for exempt in no-stale not-stale stale-exempt never-stale; do
  unmarked "the exemption label $exempt was flagged" '[]' "[{\"name\":\"$exempt\"}]"
done
# a bot that says something else, and a person who says the word
unmarked "another bot's comment was read as a notice" "[$(c github-actions "$(at 0)" 'Coverage is unchanged; the cached report was stale.')]"
unmarked "a person's comment was read as the bot's notice" "[$(c talbot "$(at 0)" 'This looks stale with no activity, closing in 7 days.')]"
# a notice that cannot be dated is not read as none
marked '^ACT .*\[stale:unread\]' "[$(c github-actions 'not-a-time' "$zuul")]"
echo "$out" | grep -q 'before any bump' && fail "the pre-bump line printed under an unread notice: $out"
# both marks stand side by side
runs "" 5; ball "^ACT .*\[no-ci-on-head stale:closes-$(day 7)\]" '[]' "[$warn]"
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
