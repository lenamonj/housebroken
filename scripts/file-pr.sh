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
              en dash, in any case, in the --body-file or the --title
  branch      $HOUSEBROKEN_HOME/branch-checks/<head> must exist, written by
              branch-check.sh when this head passed
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
pass=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    -F|--body-file) bodyfile="${2:-}"; pass+=("$1" "${2:-}"); shift ;;
    --body-file=*) bodyfile="${1#--body-file=}"; pass+=("$1") ;;
    -t|--title) title="${2:-}"; pass+=("$1" "${2:-}"); shift ;;
    --title=*) title="${1#--title=}"; pass+=("$1") ;;
    -B|--base|-l|--label|-a|--assignee|-r|--reviewer|-m|--milestone|-p|--project) pass+=("$1" "${2:-}"); shift ;;
    --base=*|--label=*|--assignee=*|--reviewer=*|--milestone=*|--project=*) pass+=("$1") ;;
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
if [ "$policy_result" = "DISCLOSE" ] && ! grep -qiE '\bAI\b|LLM|Claude|Copilot|ChatGPT|language model|assist' "$bodyfile"; then
  echo "REFUSED: $repo requires AI use to be disclosed ($policy) and the body does not name it" >&2
  exit 2
fi

head=$(git rev-parse HEAD 2>/dev/null) || { echo "REFUSED: run file-pr.sh from inside the clone being filed" >&2; exit 2; }
if [ ! -f "$home/branch-checks/$head" ]; then
  echo "REFUSED: branch-check.sh has not passed head ${head:0:12} - run it from this clone first" >&2
  exit 2
fi
review="$home/reviews/review-${repo%%/*}-${repo##*/}-${head:0:12}.md"
if [ ! -f "$review" ]; then
  echo "REFUSED: no adversarial review at $review - run review.sh brief and have a different model attack this head" >&2
  exit 2
fi
bash "$(dirname "$0")/review.sh" check "$review" --clone . --text "$bodyfile" >/dev/null || exit 2

if [ "${FILE_PR_DRY:-0}" = "1" ]; then
  printf 'DRY RUN, not filed:\ngh pr create -R %s' "$repo"
  for arg in "${pass[@]}"; do printf ' %q' "$arg"; done
  printf '\n'
  exit 0
fi
gh pr create -R "$repo" "${pass[@]}"
