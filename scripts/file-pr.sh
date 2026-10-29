#!/bin/bash
# file-pr.sh - the only way a PR gets filed: gh pr create behind five gates.
#
# Gate one is prior art: prior-art-<owner>-<repo>.md exists under
# $HOUSEBROKEN_HOME/prior-art/ and is under 24 hours old.
# Gate two is the policy: policy-<owner>-<repo>.md exists under
# $HOUSEBROKEN_HOME/policy/ (check-ai-policy.sh --out), is under 24 hours old,
# does not read BAN, and when it reads DISCLOSE the body discloses.
# Gate three is the prose: no tool footer, session trailer, co-author trailer,
# em dash or en dash in the body or the title.
# Gate four is the branch: branch-check.sh passed this exact head and left its
# stamp under $HOUSEBROKEN_HOME/branch-checks/.
# Gate five is the adversarial review (review.sh): a different model attacked
# this exact head and this exact body file and said POST AS IS. An inline
# --body is refused, because a review cannot be bound to text that was never a
# file.
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
# Assumes gh is installed and authenticated. It writes to GitHub only after all
# five gates pass, and only when FILE_PR_DRY is not 1.
set -u

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
              be under 24 hours old and not read RESULT: BAN; when it reads
              RESULT: DISCLOSE the body must name the AI use
  prose       no tool footer, session trailer, co-author trailer, em dash or
              en dash, in any case, in the --body-file or the --title; a
              body of at most 120 words
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

command -v gh >/dev/null 2>&1 || { echo "REFUSED: gh is not on PATH" >&2; exit 2; }

repo="$1"
shift
case "$repo" in
  */*) : ;;
  *) echo "REFUSED: first argument must be owner/repo" >&2; exit 2 ;;
esac
[ "$#" -gt 0 ] || { echo "REFUSED: no gh pr create arguments given" >&2; exit 2; }

home="${HOUSEBROKEN_HOME:-$HOME/.housebroken}"
art="$home/prior-art/prior-art-${repo%%/*}-${repo##*/}.md"
if [ ! -f "$art" ]; then
  echo "REFUSED: no prior art at $art - run prior-art.sh $repo <terms> --out first" >&2
  exit 2
fi
now=$(date +%s)
made=$(date -r "$art" +%s) || { echo "REFUSED: cannot read the age of $art" >&2; exit 2; }
if [ $((now - made)) -gt 86400 ]; then
  echo "REFUSED: prior art $art is $(( (now - made) / 3600 ))h old - rerun prior-art.sh --out" >&2
  exit 2
fi

policy="$home/policy/policy-${repo%%/*}-${repo##*/}.md"
if [ ! -f "$policy" ]; then
  echo "REFUSED: no policy printout at $policy - run check-ai-policy.sh $repo --out first" >&2
  exit 2
fi
made=$(date -r "$policy" +%s) || { echo "REFUSED: cannot read the age of $policy" >&2; exit 2; }
if [ $((now - made)) -gt 86400 ]; then
  echo "REFUSED: policy printout $policy is $(( (now - made) / 3600 ))h old - rerun check-ai-policy.sh --out" >&2
  exit 2
fi
policy_result=$(grep -m1 '^RESULT: ' "$policy" | awk '{print $2}')
case "$policy_result" in
  BAN) echo "REFUSED: $repo forbids AI-written contributions ($policy); never file here" >&2; exit 2 ;;
  DISCLOSE|MENTION|CLEAN) ;;
  UNREAD) echo "REFUSED: $policy reads UNREAD - GitHub did not give every policy file; rerun check-ai-policy.sh --out" >&2; exit 2 ;;
  *) echo "REFUSED: $policy has no RESULT line - rerun check-ai-policy.sh --out" >&2; exit 2 ;;
esac

em=$(printf '\xe2\x80\x94')   # em dash U+2014, built at runtime to keep this file ASCII
en=$(printf '\xe2\x80\x93')   # en dash U+2013
# Matched in any case, because GitHub itself writes "Co-authored-by", and the
# HTML entities render as the dashes they name.
banned_re="Generated with|Claude-Session|claude\.ai/code/session_|Co-Authored-By|$em|$en|&[mn]dash;|&#821[12];|&#x201[34];"
check_text() {
  local what="$1" text="$2" hit
  hit=$(printf '%s' "$text" | grep -ioE "$banned_re" | head -1) || true
  if [ -n "$hit" ]; then
    echo "REFUSED: $what contains '$hit' - strip it before filing" >&2
    exit 2
  fi
}

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
      echo "REFUSED: file-pr.sh does not pass $1 to gh pr create: the body comes from one --body-file, the head is the branch you are on, the repository is the first argument" >&2
      exit 2
      ;;
  esac
  shift
done
[ -n "$bodyfile" ] || { echo "REFUSED: pass the body as --body-file so the review can be bound to it" >&2; exit 2; }
if [ "$bodyfile" = "-" ] || [ ! -f "$bodyfile" ]; then
  echo "REFUSED: body file $bodyfile does not exist" >&2
  exit 2
fi
check_text "body file $bodyfile" "$(cat "$bodyfile")"
check_text "--title" "$title"
# The project's own template text is kept verbatim and is not ours to count:
# HTML comments and every line the saved template carries, a ticked box read
# as its unticked line, are left out before the words are counted.
template="$home/policy/template-${repo%%/*}-${repo##*/}.md"
[ -f "$template" ] || template=/dev/null
words=$(awk -v T="$template" '
  function norm(s) { gsub(/\[[xX]\]/, "[ ]", s); gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
  BEGIN { while ((getline l < T) > 0) { l = norm(l); if (l != "") t[l] = 1 } }
  { l = norm($0); if (l in t) next
    for (k in t) if (index(l, k) == 1) { l = substr(l, length(k) + 1); break }
    print l }' "$bodyfile" | wc -w | tr -d ' ')
if [ "$words" -gt 120 ]; then
  echo "REFUSED: the body is $words words outside the project's template - say what was wrong, what the change does and how it was verified in 120 or fewer" >&2
  exit 2
fi
if [ "$policy_result" = "DISCLOSE" ] && ! grep -qiE '\bAI\b|LLM|Claude|Copilot|ChatGPT|language model|assist' "$bodyfile"; then
  echo "REFUSED: $repo requires AI use to be disclosed ($policy) and the body does not name it" >&2
  exit 2
fi
if ! refs=$(bash "$(dirname "$0")/ref-check.sh" "$repo" "$bodyfile" --clone . 2>&1); then
  echo "REFUSED: the body names something that does not exist:" >&2
  printf '%s\n' "$refs" | grep -E 'NOT FOUND|REFUSED' >&2
  exit 2
fi

head=$(git rev-parse HEAD 2>/dev/null) || { echo "REFUSED: run file-pr.sh from inside the clone being filed" >&2; exit 2; }
if [ ! -f "$home/branch-checks/$head" ]; then
  echo "REFUSED: branch-check.sh has not passed head ${head:0:12} - run it from this clone first" >&2
  exit 2
fi
# The prior art has to be about this change: every file the branch changes,
# tests aside, is a term in the printout, by path or by name. One printout per
# repository means another branch's run replaces it.
searched=$(sed -n 's/^### //p' "$art" | tr -d '\r')
ours=$(sed -n 's/^file: //p' "$home/branch-checks/$head" | tr -d '\r')
[ -n "$ours" ] || { echo "REFUSED: the branch-check stamp for head ${head:0:12} lists no files - rerun branch-check.sh" >&2; exit 2; }
unsearched=""
while IFS= read -r f; do
  case "$f" in ""|*test*|*Test*|*spec*) continue ;; esac
  printf '%s\n' "$searched" | grep -qxF -e "$f" -e "$(basename "$f")" || unsearched="$unsearched $f"
done <<EOF
$ours
EOF
if [ -n "$unsearched" ]; then
  echo "REFUSED: the prior art at $art never searched files this branch changes:$unsearched - rerun prior-art.sh $repo with them --out" >&2
  exit 2
fi
# Every diff gate read the diff against the stamp's base; it must be the branch this files into.
checked=$(sed -n 's/^base-ref: //p' "$home/branch-checks/$head" | tr -d '\r')
if [ -z "$checked" ]; then
  echo "REFUSED: the branch-check stamp for head ${head:0:12} names no base - rerun branch-check.sh" >&2
  exit 2
fi
target="$filebase"
if [ -z "$target" ]; then
  target=$(gh repo view "$repo" --json defaultBranchRef --jq .defaultBranchRef.name 2>/dev/null | tr -d '\r')
  [ -n "$target" ] || { echo "REFUSED: cannot read the default branch of $repo - pass --base" >&2; exit 2; }
fi
case "$checked" in
  "$target"|*/"$target") ;;
  *) echo "REFUSED: branch-check.sh measured this head against $checked, but it is filed into $target - rerun branch-check.sh --base <remote>/$target" >&2
     exit 2 ;;
esac
# The upstream may have moved since the check. A move that touches none of the
# branch's files is reported; one that touches them means the branch and its
# review were measured against code that is no longer there.
stamped=$(sed -n 's/^base: //p' "$home/branch-checks/$head" | tr -d '\r')
upstream=$(gh api "repos/$repo/branches/$target" --jq .commit.sha 2>/dev/null | tr -d '\r')
[ -n "$upstream" ] || { echo "REFUSED: cannot read $target of $repo to confirm the base is current" >&2; exit 2; }
if [ "$stamped" != "$upstream" ]; then
  if ! cmp=$(gh api "repos/$repo/compare/$stamped...$upstream" 2>/dev/null); then
    echo "REFUSED: the checked base ${stamped:0:12} is not on $repo $target - fetch, rebase and rerun branch-check.sh" >&2
    exit 2
  fi
  # GitHub lists at most 300 files here; past that the overlap cannot be known.
  if [ "$(printf '%s' "$cmp" | jq '.files | length')" -ge 300 ]; then
    echo "REFUSED: $target moved by 300 files or more since branch-check (${stamped:0:12} to ${upstream:0:12}) - fetch, rebase, rerun branch-check.sh and the review" >&2
    exit 2
  fi
  moved=$(printf '%s' "$cmp" | jq -r '.files[].filename')
  overlap=$(printf '%s\n' "$moved" | grep -Fx -f <(printf '%s\n' "$ours"))
  if [ -n "$overlap" ]; then
    echo "REFUSED: $target moved since branch-check (${stamped:0:12} to ${upstream:0:12}) and changed files this branch changes - fetch, rebase, rerun branch-check.sh and the review:" >&2
    printf '%s\n' "$overlap" | sed 's/^/    /' >&2
    exit 2
  fi
  echo "note: $target moved since branch-check (${stamped:0:12} to ${upstream:0:12}); none of its new commits touch this branch's files" >&2
fi
# Three open pull requests per repository, and ten minutes between filings:
# GitHub lets maintainers cap a non-collaborator's open pull requests, and two
# stamped the same minute read as a bot.
if ! mine=$(gh pr list -R "$repo" --author @me --state open --json createdAt --jq '[.[].createdAt] | sort' 2>/dev/null); then
  echo "REFUSED: cannot read your open pull requests on $repo" >&2
  exit 2
fi
open_count=$(printf '%s' "$mine" | jq 'length')
if [ "$open_count" -ge 3 ]; then
  echo "REFUSED: you have $open_count open pull requests on $repo - three is the most a repository gets" >&2
  exit 2
fi
since=$(printf '%s' "$mine" | jq -r --argjson now "$(date -u +%s)" 'if length > 0 then $now - (last | fromdateiso8601) else 99999 end')
if [ "$since" -lt 600 ]; then
  echo "REFUSED: your last pull request on $repo was filed ${since}s ago - wait until ten minutes have passed" >&2
  exit 2
fi
# The experiment the body describes was run by proof.sh, not recounted, and
# against the base branch-check measured; the author's declaration of what
# was not tested passes and names a proof that was waived; and the review
# read the declaration. Proof and declaration come before the review because
# the review is bound to the declaration.
proof="$home/proofs/$head"
if [ ! -f "$proof" ]; then
  echo "REFUSED: no proof for head ${head:0:12} - run proof.sh --test 'COMMAND', or --none 'REASON' when nothing can fail first" >&2
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
    echo "REFUSED: the proof for ${head:0:12} is none ($reason) and the declaration does not say so - add it under not-tested, so the reviewer attacks it" >&2
    exit 2
  fi
  echo "note: no red-green proof for ${head:0:12}: $reason" >&2
else
  proved=$(sed -n 's/^base: //p' "$proof" | tr -d '\r')
  if [ "$proved" != "$stamped" ]; then
    echo "REFUSED: the proof for ${head:0:12} ran against base ${proved:0:12}, branch-check measured ${stamped:0:12} - rerun proof.sh --base $checked" >&2
    exit 2
  fi
fi
review="$home/reviews/review-${repo%%/*}-${repo##*/}-${head:0:12}.md"
if [ ! -f "$review" ]; then
  echo "REFUSED: no adversarial review at $review - run review.sh brief with --text $decl and have a different model attack this head" >&2
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
gh pr create -R "$repo" "${pass[@]}"
