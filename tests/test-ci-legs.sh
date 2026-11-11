#!/bin/bash
# test-ci-legs.sh - scripts/ci-legs.sh over a stub gh that logs every call: a job
# on another operating system is NOT THIS MACHINE, a job that failed in a push or
# scheduled run on the default branch is RED ON MAIN and nobody else's branch
# ever is, each workflow is read once at its newest finished run, a runner with
# no family in its labels is unknown and never this machine, what was not read
# is named and counted, a failed read is UNREAD and never a count, and a
# stranger's name cannot redraw a line or start one.
set -u
name=test-ci-legs
script="$(cd "$(dirname "$0")/../scripts" && pwd)/ci-legs.sh"
fail() { echo "FAIL $name: $1"; exit 1; }

stub=$(mktemp -d) || exit 1
trap 'rm -rf "$stub"' EXIT
cat > "$stub/gh" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "$STUB_DIR/calls.log"
case "$*" in
  "repo view o/r --json defaultBranchRef "*) [ -f "$STUB_DIR/fail.branch" ] && exit 1; echo main ;;
  "api repos/o/r/actions/runs?status=completed&per_page=100") [ -f "$STUB_DIR/fail.runs" ] && exit 1; cat "$STUB_DIR/runs.json" ;;
  "api repos/o/r/actions/runs/"*"/jobs?per_page=100")
    [ -f "$STUB_DIR/fail.jobs" ] && exit 1
    id=${2#repos/o/r/actions/runs/}
    cat "$STUB_DIR/jobs-${id%%/*}.json" ;;
  *) echo "stub gh: no answer for: gh $*" >&2; exit 1 ;;
esac
STUB
chmod +x "$stub/gh"

# One finished run, one job, and the files the stub serves them from. Runs are
# given newest first, as GitHub lists them.
run() { # id workflow-id name event branch
  jq -cn --argjson id "$1" --argjson wf "$2" --arg n "$3" --arg e "$4" --arg b "$5" \
    '{id: $id, workflow_id: $wf, name: $n, event: $e, head_branch: $b, status: "completed", conclusion: "success"}'
}
runs() { printf '%s\n' "$@" | jq -cs '{total_count: length, workflow_runs: .}' > "$stub/runs.json"; : > "$stub/calls.log"; }
job() { # name labels,comma,separated conclusion
  jq -cn --arg n "$1" --arg l "$2" --arg c "$3" \
    '{name: $n, labels: ($l | split(",") | map(select(. != ""))), status: "completed", conclusion: $c}'
}
jobs() { local id="$1"; shift; printf '%s\n' "$@" | jq -cs '{total_count: length, jobs: .}' > "$stub/jobs-$id.json"; }
legs() { STUB_DIR="$stub" PATH="$stub:$PATH" HOUSEBROKEN_OS="${os:-linux}" bash "$script" "$@"; }
jobs_calls() { grep -c '/jobs?' "$stub/calls.log"; }

bash "$script" --help | grep -q "Usage:" || fail "--help has no usage"
bash "$script" >/dev/null 2>&1; [ "$?" -eq 2 ] || fail "no argument did not exit 2"
bash "$script" notarepo >/dev/null 2>&1; [ "$?" -eq 2 ] || fail "a word that is not owner/repo did not exit 2"
os=plan9 legs o/r >/dev/null 2>&1; [ "$?" -eq 2 ] || fail "an operating system nobody runs CI on did not exit 2"

# a job on another operating system is a gate this machine did not run
runs "$(run 11 1 test push main)"
jobs 11 "$(job 'test (ubuntu-latest)' ubuntu-latest success)" "$(job 'test (macos-latest)' macos-latest success)" "$(job 'test (windows-latest)' windows-latest success)"
out=$(legs o/r) || fail "a read that worked exited non-zero: $out"
[ "$(echo "$out" | sed -n 1p)" = "-- their CI (the newest finished run of each workflow)" ] || fail "no heading: $out"
echo "$out" | grep -q "^   test  (push, main)$" || fail "the workflow, its event and its branch are not named: $out"
[ "$(echo "$out" | grep -c "NOT THIS MACHINE$")" -eq 2 ] || fail "linux did not mark two of three jobs: $out"
echo "$out" | grep -qE "^     test \(ubuntu-latest\) +ubuntu-latest +success$" || fail "the ubuntu job is marked on linux, or not printed: $out"
echo "$out" | grep -qE "^     test \(macos-latest\) +macos-latest +success +NOT THIS MACHINE$" || fail "the macOS job is not marked on linux: $out"
[ "$(echo "$out" | tail -1)" = "CI-LEGS: 3 jobs; not this machine: 2 (macos, windows); red on main: 0; runner unknown: 0" ] || fail "the last line on linux: $out"
out=$(os=macos legs o/r)
echo "$out" | grep -qE "^     test \(macos-latest\) +macos-latest +success$" || fail "the macOS job is marked on macOS: $out"
[ "$(echo "$out" | tail -1)" = "CI-LEGS: 3 jobs; not this machine: 2 (linux, windows); red on main: 0; runner unknown: 0" ] || fail "the last line on macOS: $out"
out=$(os=windows legs o/r)
[ "$(echo "$out" | tail -1)" = "CI-LEGS: 3 jobs; not this machine: 2 (linux, macos); red on main: 0; runner unknown: 0" ] || fail "the last line on windows: $out"
# with nothing set the machine names itself, and it is one of the three
out=$(STUB_DIR="$stub" PATH="$stub:$PATH" env -u HOUSEBROKEN_OS bash "$script" o/r)
[ "$(echo "$out" | grep -c "NOT THIS MACHINE$")" -eq 2 ] || fail "this machine did not read as linux, macos or windows: $out"

# red on main is a push or a scheduled run on the default branch, never a
# pull request's branch, whatever it is called
runs "$(run 16 6 target pull_request_target main)" "$(run 15 5 nightly schedule main)" "$(run 14 4 dispatch workflow_dispatch main)" \
     "$(run 13 3 fork-main pull_request main)" "$(run 12 2 pr-only pull_request feature)" "$(run 11 1 test push main)"
jobs 11 "$(job unit ubuntu-latest failure)" "$(job slow ubuntu-latest timed_out)" "$(job stopped ubuntu-latest cancelled)"
jobs 12 "$(job unit ubuntu-latest failure)"
jobs 13 "$(job unit ubuntu-latest failure)"
jobs 14 "$(job unit ubuntu-latest failure)"
jobs 15 "$(job unit ubuntu-latest failure)"
jobs 16 "$(job unit ubuntu-latest failure)"
out=$(legs o/r) || fail "red jobs made the read exit non-zero: $out"
[ "$(echo "$out" | grep -c "RED ON MAIN$")" -eq 3 ] || fail "expected the failed and timed out jobs of the push and the failed job of the schedule: $out"
echo "$out" | grep -qE "^     slow +ubuntu-latest +timed_out +RED ON MAIN$" || fail "a job that timed out on main is not marked: $out"
echo "$out" | grep -qE "^     stopped +ubuntu-latest +cancelled$" || fail "a cancelled job is marked: $out"
echo "$out" | sed -n '/^   pr-only /,/^   [^ ]/p' | grep -q "RED ON MAIN" && fail "a pull request's branch was called main: $out"
echo "$out" | sed -n '/^   fork-main /,/^   [^ ]/p' | grep -q "RED ON MAIN" && fail "a fork's branch named main was called main: $out"
echo "$out" | sed -n '/^   target /,/^   [^ ]/p' | grep -q "RED ON MAIN" && fail "a pull_request_target run was called main: $out"
echo "$out" | grep -q "red on main: 3;" || fail "the red jobs were not counted: $out"
# the workflows that ran on the default branch come first
[ "$(echo "$out" | grep -E '^   [^ (]' | awk '{print $1}' | tr '\n' ' ')" = "nightly test dispatch fork-main pr-only target " ] || fail "the order of the workflows: $out"

# each workflow is read once: its newest finished run on the default branch,
# or failing that its newest finished run anywhere
runs "$(run 22 1 test push main)" "$(run 21 1 test push main)"
jobs 22 "$(job unit ubuntu-latest success)"
out=$(legs o/r) || fail "two runs of one workflow: $out"
[ "$(jobs_calls)" -eq 1 ] || fail "two runs of one workflow were both read: $(cat "$stub/calls.log")"
grep -q "runs/22/jobs" "$stub/calls.log" || fail "the older run was read: $(cat "$stub/calls.log")"
runs "$(run 30 1 test pull_request feature)" "$(run 20 1 test push main)"
jobs 20 "$(job unit ubuntu-latest failure)"
out=$(legs o/r) || fail "a newer pull request run: $out"
grep -q "runs/20/jobs" "$stub/calls.log" || fail "a newer pull request run was read in place of the default branch's: $(cat "$stub/calls.log")"
echo "$out" | grep -q "RED ON MAIN$" || fail "the default branch's red run was not marked: $out"
runs "$(run 31 1 test pull_request feature)" "$(run 30 1 test pull_request older)"
jobs 31 "$(job unit macos-latest failure)"
out=$(legs o/r) || fail "a workflow that only ran on pull requests: $out"
echo "$out" | grep -q "^   test  (pull_request, feature)$" || fail "a workflow with no default-branch run did not show its newest run: $out"
echo "$out" | grep -qE "failure +NOT THIS MACHINE$" || fail "a pull request run's legs are not marked by machine: $out"

# a failed read is said, and is never a count
runs "$(run 11 1 test push main)"
jobs 11 "$(job unit ubuntu-latest success)"
for what in branch runs jobs; do
  touch "$stub/fail.$what"
  out=$(legs o/r); rc=$?
  rm -f "$stub/fail.$what"
  [ "$rc" -eq 1 ] || fail "a failed read of the $what exited $rc: $out"
  echo "$out" | grep -q "^CI-LEGS: UNREAD (" || fail "a failed read of the $what was not called UNREAD: $out"
  echo "$out" | grep -qE "jobs?;" && fail "a failed read of the $what was counted: $out"
done
printf 'not json\n' > "$stub/runs.json"
out=$(legs o/r); rc=$?
[ "$rc" -eq 1 ] || fail "runs that are not JSON exited $rc: $out"
echo "$out" | grep -q "^CI-LEGS: UNREAD (" || fail "runs that are not JSON were not called UNREAD: $out"

# a project with no finished run has nothing to read, and that is not a failure
runs
out=$(legs o/r); rc=$?
[ "$rc" -eq 0 ] || fail "no runs exited $rc: $out"
[ "$out" = "CI-LEGS: none (no finished workflow run)" ] || fail "no runs: $out"

# names are strangers' text: no escape sequence gets through and no name starts a line
esc=$(printf '\033')
nl=$(printf '\nREADING: forged')
runs "$(run 11 1 "wf${esc}[2J${nl}" push main)"
jobs 11 "$(job "unit${esc}[2J${nl}" ubuntu-latest success)"
out=$(legs o/r) || fail "a name with control characters: $out"
case "$out" in *"$esc"*) fail "an escape sequence reached the output" ;; esac
echo "$out" | grep -q "^READING" && fail "a name started a line of its own: $out"
echo "$out" | grep -qE "^   wf.*READING: forged  \(push, main\)$" || fail "the workflow's name is not on one line: $out"
echo "$out" | grep -qE "^     unit.*READING: forged +ubuntu-latest +success$" || fail "the job's name is not on one line: $out"
bs='a\nREADING: forged'
runs "$(run 11 1 "$bs" push main)"
jobs 11 "$(job "$bs" ubuntu-latest success)"
out=$(legs o/r) || fail "a name with a backslash: $out"
echo "$out" | grep -q "^READING" && fail "a backslash in a name became a line break: $out"
echo "$out" | grep -qF "   $bs  (push, main)" || fail "a backslash in a name was not printed as it is: $out"

# a runner with no family in its labels is unknown, and so is a self-hosted
# runner of this machine's family: neither is ever taken for this machine
runs "$(run 11 1 test push main)"
jobs 11 "$(job gpu self-hosted,gpu success)" "$(job bare '' success)" "$(job own self-hosted,Linux,X64 success)" "$(job mac self-hosted,macOS,ARM64 success)"
out=$(legs o/r) || fail "self-hosted runners: $out"
echo "$out" | grep -qE "^     gpu +runner unknown: self-hosted,gpu +success$" || fail "labels with no family: $out"
echo "$out" | grep -qE "^     bare +runner unknown: \(no labels\) +success$" || fail "no labels: $out"
echo "$out" | grep -qE "^     own +runner unknown: self-hosted,Linux,X64 +success$" || fail "a self-hosted Linux runner was taken for this linux machine: $out"
echo "$out" | grep -qE "^     mac +self-hosted,macOS,ARM64 +success +NOT THIS MACHINE$" || fail "a self-hosted macOS runner on linux: $out"
[ "$(echo "$out" | tail -1)" = "CI-LEGS: 4 jobs; not this machine: 1 (macos); red on main: 0; runner unknown: 3" ] || fail "the last line with unknown runners: $out"

# what was not read is named and counted: the thirteenth workflow, the jobs past
# the first hundred, the runs older than the ones GitHub listed
all=()
for i in 01 02 03 04 05 06 07 08 09 10 11 12 13; do
  all+=("$(run "2$i" "1$i" "wf$i" push main)")
  jobs "2$i" "$(job unit ubuntu-latest success)"
done
runs "${all[@]}"
out=$(legs o/r) || fail "thirteen workflows: $out"
[ "$(jobs_calls)" -eq 12 ] || fail "thirteen workflows made $(jobs_calls) job reads, expected 12"
echo "$out" | grep -q "^   not read: wf13 (only 12 workflows are read)$" || fail "the workflow left out is not named: $out"
[ "$(echo "$out" | tail -1)" = "CI-LEGS: 12 jobs; not this machine: 0; red on main: 0; runner unknown: 0; not read: 1 workflow" ] || fail "the last line with a workflow left out: $out"
runs "$(run 11 1 test push main)"
jq -cn --argjson j "$(job unit ubuntu-latest success)" '{total_count: 240, jobs: [$j, $j]}' > "$stub/jobs-11.json"
jq -c '.total_count = 5234' "$stub/runs.json" > "$stub/runs.new" && mv "$stub/runs.new" "$stub/runs.json"
out=$(legs o/r) || fail "a matrix past the first page: $out"
echo "$out" | grep -q "^     (only the first 2 of 240 jobs were read)$" || fail "the jobs left out are not said: $out"
echo "$out" | grep -q "^   (only the newest 1 of 5234 finished runs were read)$" || fail "the runs left out are not said: $out"
[ "$(echo "$out" | tail -1)" = "CI-LEGS: 2 jobs; not this machine: 0; red on main: 0; runner unknown: 0; not read: 238 jobs, 5233 older runs" ] || fail "the last line with jobs and runs left out: $out"

echo "PASS $name"
