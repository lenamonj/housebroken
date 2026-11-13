#!/bin/bash
# file-pr.sh - the only way a PR gets filed: gh pr create behind its gates.
#
# Gate one is prior art: prior-art-<owner>-<repo>.md exists under
# $HOUSEBROKEN_HOME/prior-art/ and is under 24 hours old.
# Gate two is the policy: policy-<owner>-<repo>.md exists under
# $HOUSEBROKEN_HOME/policy/ (check-ai-policy.sh --out), is under 24 hours old,
# does not read BAN, and when its recorded reading says a disclosure is owed
# the body discloses.
# Gate three is the prose: no tool footer, session trailer, co-author trailer,
# em dash or en dash in the body or the title.
# Gate four is the branch: branch-check.sh passed this exact head and left its
# stamp under $HOUSEBROKEN_HOME/branch-checks/.
# Gate five is the adversarial review (review.sh): a different model attacked
# this exact head and this exact body file and said POST AS IS. An inline
# --body is refused, because a review cannot be bound to text that was never a
# file. Around them: every file the branch changes was searched for prior art,
# a body keeps the project's template and holds to 120 words of its own, every
# reference exists, the base has not moved under the branch's files, a proof
# and a declaration exist for the head, three open pull requests at most, and
# ten minutes since the last filing.
#
# Usage:
#   bash file-pr.sh owner/repo <gh pr create args...>
#   FILE_PR_DRY=1 bash file-pr.sh owner/repo ...   # print the command, run nothing
#   bash file-pr.sh --help
#
# Environment:
#   HOUSEBROKEN_HOME  work directory, default $HOME/.housebroken; the prior
#                     art, policy, branch stamps and reviews are read from it.
#   FILE_PR_DRY       set to 1 to print the gh command instead of running it.
#
# Assumes gh is installed and authenticated. It writes to GitHub only after every
# gate passes, and only when FILE_PR_DRY is not 1.
set -u
# shellcheck source=scripts/refuse.sh
. "$(cd "$(dirname "$0")" && pwd)/refuse.sh"

usage() {
  cat <<'EOF'
usage: file-pr.sh owner/repo <gh pr create args...>
       file-pr.sh --help

  owner/repo  the upstream repository the PR is filed against
  the remaining arguments go to gh pr create, and only these are accepted:
  --title, --body-file (required), --base, --draft, --label, --assignee,
  --reviewer, --milestone, --project and --no-maintainer-edit, each value
  as its own argument or after an equals sign

gates:
  prior art   $HOUSEBROKEN_HOME/prior-art/prior-art-<owner>-<repo>.md must
              exist and be under 24 hours old
  policy      $HOUSEBROKEN_HOME/policy/policy-<owner>-<repo>.md must exist,
              be under 24 hours old and not read RESULT: BAN or UNREAD;
              RESULT: MENTION or DISCLOSE needs a recorded --reading and
              --disclosure, and when that says DISCLOSURE: owed the body
              must name the AI use
  prose       no tool footer, session trailer, co-author trailer, em dash or
              en dash, in any case, in the --body-file or the --title; a
              body of at most 120 words of its own, the answer to the
              template's AI question counted apart and held to 50
  branch      $HOUSEBROKEN_HOME/branch-checks/<head> must exist, written by
              branch-check.sh when this head passed, against the branch this
              files into (--base, or the repository's default branch)
  review      run from the clone being filed; the report at
              $HOUSEBROKEN_HOME/reviews/review-<owner>-<repo>-<head12>.md must
              pass review.sh check for this head and the --body-file, and an
              inline --body is refused

environment:
  HOUSEBROKEN_HOME  work directory, default $HOME/.housebroken
  FILE_PR_DRY       1 prints the gh command and files nothing
EOF
}

if [ "$#" -eq 0 ] || [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  [ "$#" -eq 0 ] && exit 2
  exit 0
fi

command -v gh >/dev/null 2>&1 || { refused file-pr-gh-missing "gh is not on PATH" >&2; exit 2; }

repo="$1"
shift
case "$repo" in
  */*) : ;;
  *) refused file-pr-repo-form "first argument must be owner/repo" >&2; exit 2 ;;
esac
[ "$#" -gt 0 ] || { refused file-pr-no-arguments "no gh pr create arguments given" >&2; exit 2; }

home="${HOUSEBROKEN_HOME:-$HOME/.housebroken}"
# shellcheck source=scripts/common.sh
. "$(dirname "$0")/common.sh"
read_printouts "$repo" "$home"

# gh pr create also takes a body from --body, --fill, --template, --recover and
# stdin, reads -F glued to its value (-Fbody.md, -dF body.md), obeys the last
# -R it is given, and files whatever branch --head names without pushing. Each
# of those files something no gate read, so only these flags pass, each value
# as its own argument or after an equals sign.
bodyfile=""
title=""
filebase=""
pass=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    -F|--body-file) bodyfile="${2:-}"; pass+=("$1" "${2:-}"); shift ;;
    --body-file=*) bodyfile="${1#--body-file=}"; pass+=("$1") ;;
    -t|--title) title="${2:-}"; pass+=("$1" "${2:-}"); shift ;;
    --title=*) title="${1#--title=}"; pass+=("$1") ;;
    -B|--base) filebase="${2:-}"; pass+=("$1" "${2:-}"); shift ;;
    --base=*) filebase="${1#--base=}"; pass+=("$1") ;;
    -l|--label|-a|--assignee|-r|--reviewer|-m|--milestone|-p|--project) pass+=("$1" "${2:-}"); shift ;;
    --label=*|--assignee=*|--reviewer=*|--milestone=*|--project=*) pass+=("$1") ;;
    -d|--draft|--no-maintainer-edit) pass+=("$1") ;;
    *)
      refused file-pr-argument-not-passed "file-pr.sh does not pass $1 to gh pr create: the body comes from one --body-file, the head is the branch you are on, the repository is the first argument" >&2
      exit 2
      ;;
  esac
  shift
done
[ -n "$bodyfile" ] || { refused file-pr-no-body-file "pass the body as --body-file so the review can be bound to it" >&2; exit 2; }
if [ "$bodyfile" = "-" ] || [ ! -f "$bodyfile" ]; then
  refused file-pr-body-file-missing "body file $bodyfile does not exist" >&2
  exit 2
fi
check_text "body file $bodyfile" "$(cat "$bodyfile")"
check_text "--title" "$title"
prose_gate "$repo" "$bodyfile" "$home"
if [ "$disclosure_owed" -eq 1 ] && ! discloses "$bodyfile" "$template"; then
  refused file-pr-disclosure-missing "$repo requires AI use to be disclosed ($policy) and the body does not name it" >&2
  exit 2
fi
if ! refs=$(bash "$(dirname "$0")/ref-check.sh" "$repo" "$bodyfile" --clone . 2>&1); then
  refused file-pr-reference-not-found "the body names something that does not exist:" >&2
  printf '%s\n' "$refs" | grep -E 'NOT FOUND|REFUSED' >&2
  exit 2
fi

head=$(git rev-parse HEAD 2>/dev/null) || { refused file-pr-not-in-clone "run file-pr.sh from inside the clone being filed" >&2; exit 2; }
if [ ! -f "$home/branch-checks/$head" ]; then
  refused file-pr-head-not-stamped "branch-check.sh has not passed head ${head:0:12} - run it from this clone first" >&2
  exit 2
fi
# The prior art has to be about this change: every file the branch changes,
# tests aside, is a term in the printout, by path or by name. One printout per
# repository means another branch's run replaces it.
searched=$(sed -n 's/^### //p' "$art" | tr -d '\r')
ours=$(sed -n 's/^file: //p' "$home/branch-checks/$head" | tr -d '\r')
# Both sides of a rename: an upstream change to the old path meets this branch.
touched=$(sed -n -e 's/^file: //p' -e 's/^from: //p' "$home/branch-checks/$head" | tr -d '\r')
[ -n "$ours" ] || { refused file-pr-stamp-no-files "the branch-check stamp for head ${head:0:12} lists no files - rerun branch-check.sh" >&2; exit 2; }
unsearched=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  is_test_path "$f" && continue
  printf '%s\n' "$searched" | grep -qxF -e "$f" -e "$(basename "$f")" || unsearched="$unsearched $f"
done <<EOF
$ours
EOF
if [ -n "$unsearched" ]; then
  refused file-pr-prior-art-missed-files "the prior art at $art never searched files this branch changes:$unsearched - rerun prior-art.sh $repo with them --out" >&2
  exit 2
fi
# Every diff gate read the diff against the stamp's base; it must be the branch this files into.
checked=$(sed -n 's/^base-ref: //p' "$home/branch-checks/$head" | tr -d '\r')
if [ -z "$checked" ]; then
  refused file-pr-stamp-no-base "the branch-check stamp for head ${head:0:12} names no base - rerun branch-check.sh" >&2
  exit 2
fi
target="$filebase"
if [ -z "$target" ]; then
  target=$(gh repo view "$repo" --json defaultBranchRef --jq .defaultBranchRef.name 2>/dev/null | tr -d '\r')
  [ -n "$target" ] || { refused file-pr-default-branch-unreadable "cannot read the default branch of $repo - pass --base" >&2; exit 2; }
fi
case "$checked" in
  "$target"|*/"$target") ;;
  *) refused file-pr-base-not-target "branch-check.sh measured this head against $checked, but it is filed into $target - rerun branch-check.sh --base <remote>/$target" >&2
     exit 2 ;;
esac
# The upstream may have moved since the check. A move that touches none of the
# branch's files is reported; one that touches them means the branch and its
# review were measured against code that is no longer there.
stamped=$(sed -n 's/^base: //p' "$home/branch-checks/$head" | tr -d '\r')
upstream=$(gh api "repos/$repo/branches/$target" --jq .commit.sha 2>/dev/null | tr -d '\r')
[ -n "$upstream" ] || { refused file-pr-target-unreadable "cannot read $target of $repo to confirm the base is current" >&2; exit 2; }
if [ "$stamped" != "$upstream" ]; then
  if ! cmp=$(gh api "repos/$repo/compare/$stamped...$upstream" 2>/dev/null); then
    refused file-pr-base-compare-failed "the checked base ${stamped:0:12} is not on $repo $target - fetch, rebase and rerun branch-check.sh" >&2
    exit 2
  fi
  # Any 200 is not enough. Diverged means the checked base carries commits the
  # upstream lacks, so the pull request would too, and behind means the upstream
  # was rewound past it.
  moved_how=$(printf '%s' "$cmp" | jq -r '.status // "unknown"' | tr -d '\r')
  if [ "$moved_how" != ahead ]; then
    refused file-pr-base-diverged-or-behind "the checked base ${stamped:0:12} is not on $repo $target (compare reads $moved_how) - fetch, rebase and rerun branch-check.sh" >&2
    exit 2
  fi
  if [ "$(printf '%s' "$cmp" | jq -r '.files | type' | tr -d '\r')" != array ]; then
    refused file-pr-moved-files-unlisted "GitHub listed no files for $target since ${stamped:0:12}, so what moved is unknown - fetch, rebase, rerun branch-check.sh and the review" >&2
    exit 2
  fi
  # GitHub lists at most 300 files here; past that the overlap cannot be known.
  if [ "$(printf '%s' "$cmp" | jq '.files | length')" -ge 300 ]; then
    refused file-pr-target-moved-too-far "$target moved by 300 files or more since branch-check (${stamped:0:12} to ${upstream:0:12}) - fetch, rebase, rerun branch-check.sh and the review" >&2
    exit 2
  fi
  moved=$(printf '%s' "$cmp" | jq -r '.files[] | .filename, (.previous_filename // empty)')
  overlap=$(printf '%s\n' "$moved" | tr -d '\r' | grep -Fx -f <(printf '%s\n' "$touched"))
  if [ -n "$overlap" ]; then
    refused file-pr-target-moved-our-files "$target moved since branch-check (${stamped:0:12} to ${upstream:0:12}) and changed files this branch changes - fetch, rebase, rerun branch-check.sh and the review:" >&2
    printf '%s\n' "$overlap" | sed 's/^/    /' >&2
    exit 2
  fi
  echo "note: $target moved since branch-check (${stamped:0:12} to ${upstream:0:12}); none of its new commits touch this branch's files" >&2
fi
# Three open pull requests per repository, and ten minutes between filings:
# GitHub lets maintainers cap a non-collaborator's open pull requests, and two
# stamped the same minute read as a bot.
if ! mine=$(gh pr list -R "$repo" --author @me --state open --json createdAt --jq '[.[].createdAt] | sort' 2>/dev/null); then
  refused file-pr-open-prs-unreadable "cannot read your open pull requests on $repo" >&2
  exit 2
fi
open_count=$(printf '%s' "$mine" | jq 'length')
if [ "$open_count" -ge 3 ]; then
  refused file-pr-open-pr-cap "you have $open_count open pull requests on $repo - three is the most a repository gets" >&2
  exit 2
fi
since=$(printf '%s' "$mine" | jq -r --argjson now "$(date -u +%s)" 'if length > 0 then $now - (last | fromdateiso8601) else 99999 end')
if [ "$since" -lt 600 ]; then
  refused file-pr-too-soon-after-last "your last pull request on $repo was filed ${since}s ago - wait until ten minutes have passed" >&2
  exit 2
fi
spacing_gate "$repo" "$home"
# The experiment the body describes was run by proof.sh, not recounted, and
# against the base branch-check measured; the author's declaration of what
# was not tested passes and names a proof that was waived; and the review
# read the declaration. Proof and declaration come before the review because
# the review is bound to the declaration.
proof="$home/proofs/$head"
if [ ! -f "$proof" ]; then
  refused file-pr-no-proof "no proof for head ${head:0:12} - run proof.sh --test 'COMMAND', or --none 'REASON' when nothing can fail first" >&2
  exit 2
fi
decl="$home/declarations/$head.md"
if ! declared=$(bash "$(dirname "$0")/declare.sh" . 2>&1); then
  echo "$declared" >&2
  exit 2
fi
if grep -q '^proof: none' "$proof"; then
  reason=$(sed -n 's/^reason: //p' "$proof" | tr -d '\r')
  if ! grep -qF -- "$reason" "$decl"; then
    refused file-pr-proof-none-undeclared "the proof for ${head:0:12} is none ($reason) and the declaration does not say so - add it under not-tested, so the reviewer attacks it" >&2
    exit 2
  fi
  echo "note: no red-green proof for ${head:0:12}: $reason" >&2
else
  proved=$(sed -n 's/^base: //p' "$proof" | tr -d '\r')
  if [ "$proved" != "$stamped" ]; then
    refused file-pr-proof-other-base "the proof for ${head:0:12} ran against base ${proved:0:12}, branch-check measured ${stamped:0:12} - rerun proof.sh --base $checked" >&2
    exit 2
  fi
fi
review="$home/reviews/review-${repo%%/*}-${repo##*/}-${head:0:12}.md"
if [ ! -f "$review" ]; then
  refused file-pr-no-review "no adversarial review at $review - run review.sh brief with --text $decl and have a different model attack this head" >&2
  exit 2
fi
bash "$(dirname "$0")/review.sh" check "$review" --clone . --text "$bodyfile" --text "$decl" >/dev/null || exit 2

if [ "${FILE_PR_DRY:-0}" = "1" ]; then
  printf 'DRY RUN, not filed:\ngh pr create -R %s' "$repo"
  for arg in "${pass[@]}"; do printf ' %q' "$arg"; done
  printf '\n'
  exit 0
fi
# What was filed, kept so verify-filed-pr.sh can compare GitHub's copy to it.
mkdir -p "$home/filed"
cp "$bodyfile" "$home/filed/${repo%%/*}-${repo##*/}-$head.md"
gh pr create -R "$repo" "${pass[@]}" || exit $?
log_filing "$repo" "$home" "pull request $head"
