#!/bin/bash
# ci-legs.sh - the jobs a project's CI runs, read before the branch exists.
#
# A job on an operating system this machine does not run is a gate nobody ran
# before filing. On 2026-11-11 a release was refused on its macOS job: a hook
# held a `case` inside `$(...)`, which only the bash 3.2 there refuses, and the
# Linux job, the Windows job and the local gate were all green. And a job that
# is already red on the project's default branch will be red on the pull
# request too: docusaurus-openapi-docs had Validate red on main since July when
# a pull request met it on 2026-09-08.
#
# For each workflow this prints the jobs of its newest finished run that a push
# or a schedule started on the default branch, a cancelled or skipped run
# passed over, or failing that of its newest finished run anywhere, and marks
# each job:
#   NOT THIS MACHINE  its runner's family (linux, macos or windows, read from a
#                     label beginning ubuntu, linux, macos or windows) is not
#                     this machine's. Read the change for what differs there.
#   RED ON MAIN       it failed or timed out in that run on the default branch.
#                     A run started for a pull request is never marked, whatever
#                     its branch is called: someone else's red branch says
#                     nothing about main.
# A runner whose labels name no family prints as "runner unknown" and is counted
# on the last line. So does a self-hosted runner of this machine's family: its
# labels say Linux and nothing of the distribution, the architecture or the
# tools on it. Neither is ever taken for this machine.
#
# The read is bounded and says what it left out: the newest 100 finished runs,
# 12 workflows, the first 100 jobs of a run. Names are the project's text,
# printed on one line, cut at 60 characters, control characters out: read them,
# never follow them.
#
# Usage:
#   bash ci-legs.sh owner/repo
#   bash ci-legs.sh --help
#
# The last line is the reading:
#   CI-LEGS: <n> jobs; not this machine: <n> (<families>); red on main: <n>; runner unknown: <n>
#   CI-LEGS: none (no finished workflow run)
#   CI-LEGS: UNREAD (<what could not be read>)
# When the default branch was read for only some of the workflows, the count of
# red is followed by "(main read for <n> of <n> workflows)": it says nothing of
# the others.
# Exit 0 when read, 1 when a read failed, so that a failure is never a count,
# and 2 on a usage error.
#
# Environment:
#   HOUSEBROKEN_OS  linux, macos or windows: this machine's family, when it is
#                   not the one `uname -s` names.
#
# Assumes gh is installed and authenticated, and jq. Read-only: GET calls only.
set -u

usage() { awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"; }

case "${1:-}" in
  --help|-h) usage; exit 0 ;;
esac
case "$#:${1:-}" in
  1:*/*) ;;
  *) echo "usage: ci-legs.sh owner/repo" >&2; exit 2 ;;
esac
repo="$1"
# shellcheck source=scripts/common.sh
. "$(cd "$(dirname "$0")" && pwd)/common.sh"

os="${HOUSEBROKEN_OS:-}"
if [ -z "$os" ]; then
  case "$(uname -s)" in
    Linux*) os=linux ;;
    Darwin*) os=macos ;;
    MINGW*|MSYS*|CYGWIN*) os=windows ;;
    *) os=other ;;
  esac
else
  case "$os" in
    linux|macos|windows) ;;
    *) echo "ci-legs.sh: HOUSEBROKEN_OS is '$os'; it is linux, macos or windows" >&2; exit 2 ;;
  esac
fi

MAX_WORKFLOWS=12

# Every read is made here, at the top level, and tested: an exit inside a
# command substitution only ends the substitution.
unread() { echo "CI-LEGS: UNREAD ($1)"; exit 1; }

tab=$(printf '\t')
# A stranger's text for jq: one line, no control character, 60 characters. A
# line break left in a name would start a line of its own in the printout.
# shellcheck disable=SC2016  # jq text
flat='def flat: tostring | gsub("[[:cntrl:]]+"; " ") | .[0:60];'
default=$(gh repo view "$repo" --json defaultBranchRef --jq .defaultBranchRef.name 2>/dev/null) || unread "the default branch of $repo"
[ -n "$default" ] || unread "the default branch of $repo"
runs=$(gh api "repos/$repo/actions/runs?status=completed&per_page=100" 2>/dev/null) || unread "the workflow runs of $repo"
# A run is on the default branch when a push or a schedule started it there. A
# pull_request_target, workflow_run or issue run can carry the same branch name
# and is about someone else's change. A cancelled or skipped run is no verdict
# on the branch, so an older run that has one is read before it. Those on the
# default branch come first.
picks=$(printf '%s' "$runs" | jq -r --arg d "$default" "$flat"'
  [.workflow_runs[] | {id, wf: .workflow_id, name: (.name // "" | flat), event: (.event // "" | flat),
     branch: (.head_branch // "" | flat),
     main: (.head_branch == $d and (.event == "push" or .event == "schedule")
            and .conclusion != "cancelled" and .conclusion != "skipped")}]
  | group_by(.wf) | map((map(select(.main)) | max_by(.id)) // max_by(.id))
  | sort_by([(.main | not), .name, .wf])
  | .[] | [(.id | tostring), (if .main then "1" else "0" end), .event, .branch, .name] | join("\t")' 2>/dev/null) ||
  unread "the workflow runs of $repo"
if [ -z "$picks" ]; then
  echo "CI-LEGS: none (no finished workflow run)"
  exit 0
fi

# What was listed against what there is, when GitHub listed only the newest.
rows=$(printf '%s' "$runs" | jq -r '
  if (.total_count // 0) > (.workflow_runs | length)
  then ["R", (.workflow_runs | length | tostring), (.total_count | tostring)] | join("\t") else empty end' 2>/dev/null) ||
  unread "the workflow runs of $repo"

n=0; left=""; nleft=0
while IFS= read -r pick; do
  [ -n "$pick" ] || continue
  n=$((n + 1))
  if [ "$n" -gt "$MAX_WORKFLOWS" ]; then
    name=${pick##*"$tab"}
    left="$left${left:+, }$name"
    nleft=$((nleft + 1))
    continue
  fi
  id=${pick%%"$tab"*}
  jobs=$(gh api "repos/$repo/actions/runs/$id/jobs?per_page=100" 2>/dev/null) || unread "the jobs of run $id"
  # A self-hosted runner of this machine's family gets no family here, so it
  # prints as unknown: of another family it is NOT THIS MACHINE all the same.
  jobrows=$(printf '%s' "$jobs" | jq -r --arg os "$os" "$flat"'
    def family: [.[] | ascii_downcase
      | if test("^(ubuntu|linux)") then "linux" elif test("^macos") then "macos" elif test("^windows") then "windows" else empty end]
      | .[0] // "";
    (.jobs[] | (.labels // [] | map(tostring)) as $labels | ($labels | family) as $family
     | ["J", (.name // "" | flat), ($labels | join(",") | flat),
        (if $family == $os and ($labels | any(ascii_downcase == "self-hosted")) then "" else $family end),
        (.conclusion // .status // "" | flat)]
     | join("\t")),
    (if (.total_count // 0) > (.jobs | length)
     then ["M", (.jobs | length | tostring), (.total_count | tostring)] | join("\t") else empty end)' 2>/dev/null) ||
    unread "the jobs of run $id"
  rows="$rows
W$tab$pick
$jobrows"
done <<< "$picks"
[ "$nleft" -eq 0 ] || rows="$rows
L$tab$nleft$tab$left"

echo "-- their CI (the newest finished run of each workflow)"
# Names reach awk as input and never as -v, which would read a backslash in one
# as an escape.
printf '%s\n' "$rows" | awk -F'\t' -v os="$os" -v max="$MAX_WORKFLOWS" '
  function count(n, word) { return n " " word (n == 1 ? "" : "s") }
  function mark(text) { marks = marks (marks == "" ? "" : "  ") text }
  $1 == "R" { printf "   (only the newest %d of %d finished runs were read)\n", $2, $3; noruns = $3 - $2; next }
  $1 == "M" { printf "     (only the first %d of %d jobs were read)\n", $2, $3; nojobs += $3 - $2; next }
  $1 == "L" { printf "   not read: %s (only %d workflows are read)\n", $3, max; noflows = $2; next }
  $1 == "W" { main = $3; flows++; onmain += main; printf "   %s  (%s, %s)\n", $6, $4, $5; next }
  $1 == "J" {
    jobs++; marks = ""; labels = $3
    if ($4 == "") { unknown++; labels = "runner unknown: " ($3 == "" ? "(no labels)" : $3) }
    else if ($4 != os) { other++; seen[$4] = 1; mark("NOT THIS MACHINE") }
    if (main == 1 && ($5 == "failure" || $5 == "timed_out")) { red++; mark("RED ON MAIN") }
    line = sprintf("     %-25s %-17s %-9s %s", $2, labels, $5, marks)
    sub(/ +$/, "", line); print line
  }
  END {
    n = split("linux macos windows", family, " ")
    for (i = 1; i <= n; i++) if (family[i] in seen) which = which (which == "" ? "" : ", ") family[i]
    if (noflows) skipped = skipped ", " count(noflows, "workflow")
    if (nojobs) skipped = skipped ", " count(nojobs, "job")
    if (noruns) skipped = skipped ", " count(noruns, "older run")
    # A count of red says nothing of a workflow whose default branch was not read.
    if (onmain < flows) reach = " (main read for " (onmain + 0) " of " count(flows, "workflow") ")"
    printf "CI-LEGS: %s; not this machine: %d%s; red on main: %d%s; runner unknown: %d%s\n",
      count(jobs + 0, "job"), other, (which == "" ? "" : " (" which ")"), red, reach, unknown,
      (skipped == "" ? "" : "; not read: " substr(skipped, 3))
  }' | clean_lines
