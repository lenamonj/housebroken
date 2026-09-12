#!/bin/bash
# review.sh - the adversarial review: a different model attacks the change
# before it leaves the machine, and the filing is held to exactly what it read.
#
# The gates before this one read code and count prose. None of them asks
# whether the idea of the patch was complete, or whether a sentence is true,
# and those are the defects that got furthest: a reply saying five new
# static_asserts fail on main when four did, a new test file committed 100755
# among 100644 siblings, a patch that removed behaviour the repository
# documents. A second session's review caught each of them (docs/lessons.md,
# 2026-09-10). Asked how a smaller model could catch what a larger one missed,
# the ledger answered that it was the seat, not the model: the author had
# decided the patch was good before writing the sentence. So the reviewer is
# never the model that wrote the change. It is one tier down by default, which
# costs less and still brings different blind spots, and never below Sonnet,
# because a review has to be able to check a standard citation or a CI matrix:
# Fable's work goes to Opus, Opus's to Sonnet, Sonnet's to Opus.
#
# A review that passed is not a proof. On 2026-09-12 a review passed a reply
# packet whose author then found, re-reading, that the two functions it cited
# as precedent compile only under MSVC. The author still re-reads every claim
# the reviewer did not re-derive.
#
# The report is bound to what it read. Its header records the head it attacked
# and the sha256 of every text, and check refuses when the branch or the text
# has moved since, or when the verdict is anything but POST AS IS: a fix the
# reviewer asked for is a new head, and a new head is reviewed again.
#
# Usage:
#   bash review.sh reviewer MODEL
#   bash review.sh brief --author MODEL --repo owner/repo [--reviewer MODEL]
#                        [--clone DIR [--base REF]] [--text FILE]...
#                        [--context FILE]...
#   bash review.sh check REPORT [--clone DIR] [--text FILE]...
#   bash review.sh --help
#
# reviewer  prints the model that reviews work written by MODEL.
# brief     prints on stdout the brief to hand a fresh session running the
#           reviewer model, and on stderr who that is and where its report
#           goes: $HOUSEBROKEN_HOME/reviews/review-<owner>-<repo>-<key>.md,
#           keyed by the clone's head, or by the first text's sha256 when there
#           is no clone.
# check     exits 0 when REPORT may gate a filing or a reply, 1 when it may
#           not, with the reason on stderr, and 2 on a usage error.
#
# Environment:
#   HOUSEBROKEN_HOME  work directory, default $HOME/.housebroken.
#
# Assumes git, and sha256sum or shasum.
set -u

usage() { awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"; }
refuse() { echo "REFUSED: $1" >&2; exit 1; }
bad_usage() { echo "review.sh: $1" >&2; exit 2; }

home="${HOUSEBROKEN_HOME:-$HOME/.housebroken}"
here=$(cd "$(dirname "$0")" && pwd)

family() {
  local m
  m=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  case "$m" in
    *fable*) echo fable ;;
    *opus*) echo opus ;;
    *sonnet*) echo sonnet ;;
    *haiku*) echo haiku ;;
    *) printf '%s\n' "$m" ;;
  esac
}

# One tier down, never below sonnet. A family not listed has no default.
default_reviewer() {
  case "$1" in
    fable) echo opus ;;
    opus) echo sonnet ;;
    sonnet) echo opus ;;
    haiku) echo sonnet ;;
  esac
}

# Prints why REVIEWER may not review AUTHOR's work, or nothing when it may.
objection() {
  if [ -z "$2" ]; then
    echo "no reviewer model named"
  elif [ "$2" = "$1" ]; then
    echo "the reviewer is the model that wrote the change ($1)"
  elif [ "$2" = haiku ]; then
    echo "haiku is below the floor: a reviewer has to be able to check a standard citation or a CI matrix"
  fi
}

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

cmd_reviewer() {
  [ "$#" -eq 1 ] || bad_usage "reviewer takes one model name"
  local r
  r=$(default_reviewer "$(family "$1")")
  [ -n "$r" ] || bad_usage "no default reviewer for '$1'; name one with brief --reviewer: any model other than the author's, not below sonnet"
  echo "$r"
}

cmd_brief() {
  local author="" repo="" reviewer="" clone="" base="" head="" key="" mb="" t
  local texts=() contexts=()
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --author) author="${2:-}"; shift ;;
      --repo) repo="${2:-}"; shift ;;
      --reviewer) reviewer="${2:-}"; shift ;;
      --clone) clone="${2:-}"; shift ;;
      --base) base="${2:-}"; shift ;;
      --text) texts+=("${2:-}"); shift ;;
      --context) contexts+=("${2:-}"); shift ;;
      *) bad_usage "unknown argument: $1" ;;
    esac
    shift
  done
  [ -n "$author" ] || bad_usage "brief needs --author, the model that wrote the change"
  case "$repo" in */*) : ;; *) bad_usage "brief needs --repo owner/repo" ;; esac
  local ntext=${#texts[@]}
  [ -n "$clone" ] || [ "$ntext" -gt 0 ] || bad_usage "brief needs --clone, --text, or both"
  for t in ${texts[@]+"${texts[@]}"} ${contexts[@]+"${contexts[@]}"}; do
    [ -f "$t" ] || bad_usage "$t does not exist"
  done

  local fa fr why
  fa=$(family "$author")
  if [ -n "$reviewer" ]; then fr=$(family "$reviewer"); else fr=$(default_reviewer "$fa"); fi
  [ -n "$fr" ] || refuse "no default reviewer for '$author'; name one with --reviewer"
  why=$(objection "$fa" "$fr")
  [ -z "$why" ] || refuse "$why"
  reviewer="${reviewer:-$fr}"

  if [ -n "$clone" ]; then
    head=$(git -C "$clone" rev-parse HEAD 2>/dev/null) || bad_usage "$clone is not a git clone"
    if [ -z "$base" ]; then
      for t in upstream/main upstream/master origin/main origin/master; do
        if git -C "$clone" rev-parse --verify --quiet "$t" >/dev/null; then base="$t"; break; fi
      done
    fi
    [ -n "$base" ] && mb=$(git -C "$clone" merge-base "$base" HEAD 2>/dev/null)
    key="${head:0:12}"
  else
    key=$(sha256 "${texts[0]}" | cut -c1-12)
  fi
  local report="$home/reviews/review-${repo%%/*}-${repo##*/}-$key.md"
  mkdir -p "$home/reviews"
  echo "housebroken review: hand the brief below to a fresh session running $reviewer; its report goes to $report" >&2

  printf 'ADVERSARIAL REVIEW BRIEF\n\n'
  printf 'You are the reviewer. The change below was written by %s. You are %s, chosen because you did not write it. ' "$author" "$reviewer"
  cat <<'EOF'
Find what is wrong with it before a maintainer does. Assume there is at least one defect and hunt for it. A finding needs evidence you produced yourself: a command and its output, a quoted line of code, a quoted document. An impression is not a finding.

Hard limits
- Nothing leaves this machine: no git push; no gh pr create, comment, review or merge; no gh api call with -X POST, PATCH, PUT or DELETE, or with -f or -F fields. Read-only gh calls are fine.
- Do not edit, commit in, or check out branches in the clone. To experiment, copy it and work in the copy. A copied build directory still points at the tree it was configured in, so reconfigure the build in the copy and make every arm's build log name the file that arm changed.
- Do not edit the text under review. Write only your report.

Under review
EOF
  printf -- '- repository: %s\n' "$repo"
  if [ -n "$clone" ]; then
    printf -- '- clone: %s at %s, the branch exactly as it will be filed\n' "$clone" "$head"
    if [ -n "$mb" ]; then
      printf -- '- what the maintainer sees: git -C %s diff %s..%s\n' "$clone" "$mb" "$head"
      git -C "$clone" diff --stat "$mb..HEAD" | sed 's/^/    /'
    else
      printf -- '- no upstream base found in the clone: ask which ref the branch is filed against\n'
    fi
  fi
  for t in ${texts[@]+"${texts[@]}"}; do
    printf -- '- text: %s (sha256 %s)\n' "$t" "$(sha256 "$t")"
  done
  for t in ${contexts[@]+"${contexts[@]}"}; do
    printf -- '- context from the author, to attack rather than trust: %s\n' "$t"
  done

  printf '\nAttack at least\n'
  printf '1. Every claim the text makes, re-derived now against the exact revision it names.\n'
  for t in ${texts[@]+"${texts[@]}"}; do
    printf '   %s:\n' "$t"
    bash "$here/claim-check.sh" "$t" | awk 'NF == 0 {exit} {print "   " $0}'
  done
  cat <<'EOF'
2. The proof: the new test fails on the base and passes with the change. Swap file content with git show <base>:<path> rather than switching branches, compare hashes, and make sure the two arms differ. Ask what each step would print if it did nothing.
3. The project's own CI, read from its workflow files: tests, lint, format, API and mutation checks, run on the change.
4. Scope: every changed line is needed for what was asked, nothing is unrequested, no comment appears where the surrounding code has none, and documentation, README and CHANGELOG that describe the changed behaviour change with it.
5. Prior art: nothing duplicates an open pull request or argues with a ruling in a closed issue.
6. The text: it leads with the fact; no verdict on the reviewer, no thanks, apology or offer of help; a reply runs one to three sentences and a body stays under 120 words; no footer, trailer or typographic dash; every sentence is true as literally worded.
7. Anything else that would embarrass the author in front of this maintainer.

Report
EOF
  printf 'Write it to %s. It must start with exactly these lines, with the verdict filled in:\n\n' "$report"
  printf 'review-of: %s\n' "$repo"
  [ -n "$head" ] && printf 'head: %s\n' "$head"
  for t in ${texts[@]+"${texts[@]}"}; do
    printf 'text: sha256:%s %s\n' "$(sha256 "$t")" "$(basename "$t")"
  done
  printf 'author-model: %s\nreviewer-model: %s\n' "$author" "$reviewer"
  printf 'verdict: POST AS IS | POST WITH CHANGES | DO NOT POST\n\n'
  cat <<'EOF'
POST AS IS means nothing BLOCKING or SHOULD FIX remains. POST WITH CHANGES means the author fixes what you found and the fixed version comes back for another review. DO NOT POST means it should not go at all. After the header, number your findings, each with a severity (BLOCKING, SHOULD FIX or NIT), the evidence, and the exact fix, with replacement text in full for any wording. A report with no findings says what was checked and how.
EOF
}

cmd_check() {
  local report="${1:-}" clone="" t
  local texts=()
  [ -n "$report" ] || bad_usage "check needs the report path"
  shift
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --clone) clone="${2:-}"; shift ;;
      --text) texts+=("${2:-}"); shift ;;
      *) bad_usage "unknown argument: $1" ;;
    esac
    shift
  done
  [ -f "$report" ] || refuse "no review report at $report"

  field() { sed -n "s/^$1: *//p" "$report" | head -1 | tr -d '\r' | sed 's/ *$//'; }
  local author reviewer verdict head why now
  author=$(field author-model)
  reviewer=$(field reviewer-model)
  verdict=$(field verdict | tr '[:lower:]' '[:upper:]')
  head=$(field head)
  [ -n "$author" ] || refuse "$report names no author-model"
  why=$(objection "$(family "$author")" "$(family "$reviewer")")
  [ -z "$why" ] || refuse "$why"
  [ "$verdict" = "POST AS IS" ] ||
    refuse "the verdict is '${verdict:-missing}' and only POST AS IS clears the gate: fix what the review found and review the new version"

  if [ -n "$clone" ]; then
    now=$(git -C "$clone" rev-parse HEAD 2>/dev/null) || bad_usage "$clone is not a git clone"
    [ -n "$head" ] || refuse "$report records no head, so it cannot clear a branch"
    if [ "${#head}" -lt 12 ] || [ "${now#"$head"}" = "$now" ]; then
      refuse "the branch moved after the review: it attacked ${head:0:12}, the clone is at ${now:0:12}"
    fi
  fi
  for t in ${texts[@]+"${texts[@]}"}; do
    [ -f "$t" ] || bad_usage "$t does not exist"
    grep -q "^text: sha256:$(sha256 "$t")" "$report" ||
      refuse "$t is not the text that was reviewed: its sha256 is not in $report"
  done
  echo "review: POST AS IS by $reviewer on work by $author${head:+ at ${head:0:12}}"
}

case "${1:-}" in
  --help|-h) usage; exit 0 ;;
  reviewer) shift; cmd_reviewer "$@" ;;
  brief) shift; cmd_brief "$@" ;;
  check) shift; cmd_check "$@" ;;
  "") usage >&2; exit 2 ;;
  *) bad_usage "unknown subcommand: $1 (reviewer, brief or check)" ;;
esac
