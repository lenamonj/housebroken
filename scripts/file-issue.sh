#!/bin/bash
# file-issue.sh - the only way an issue gets filed: gh issue create behind four
# gates.
#
# Gate one is prior art: prior-art-<owner>-<repo>.md exists under
# $HOUSEBROKEN_HOME/prior-art/ and is under 24 hours old.
# Gate two is the policy: policy-<owner>-<repo>.md exists under
# $HOUSEBROKEN_HOME/policy/ (check-ai-policy.sh --out), is under 24 hours old,
# does not read BAN, and when it reads DISCLOSE the body discloses.
# Gate three is the prose: no tool footer, session trailer, co-author trailer,
# em dash or en dash in the body or the title.
# Gate four is the link: a body that offers a fix, a patch or a pull request
# names a branch or commit on GitHub. On 2026-09-09 an issue that described a
# fix without linking one was answered by another contributor's pull request
# seven hours later; on 2026-09-23 it happened again. Work that exists is
# linked so it is attributable to whoever did it.
#
# Usage:
#   bash file-issue.sh owner/repo --title ... --body-file ...
#   FILE_ISSUE_DRY=1 bash file-issue.sh owner/repo ...   # print, run nothing
#   bash file-issue.sh --help
#
# Environment:
#   HOUSEBROKEN_HOME  work directory, default $HOME/.housebroken; the prior
#                     art and policy printouts are read from it.
#   FILE_ISSUE_DRY    set to 1 to print the gh command instead of running it.
#
# Assumes gh is installed and authenticated. It writes to GitHub only after all
# four gates pass, and only when FILE_ISSUE_DRY is not 1.
set -u

usage() {
  cat <<'EOF'
usage: file-issue.sh owner/repo --title ... --body-file ... [gh issue create args...]
       file-issue.sh --help

  owner/repo  the upstream repository the issue is filed on
  the remaining arguments go to gh issue create, and only these are accepted:
  --title (required), --body-file (required), --label, --assignee,
  --milestone and --project, each value as its own argument or after an
  equals sign

gates:
  prior art   $HOUSEBROKEN_HOME/prior-art/prior-art-<owner>-<repo>.md must
              exist and be under 24 hours old
  policy      $HOUSEBROKEN_HOME/policy/policy-<owner>-<repo>.md must exist,
              be under 24 hours old and not read RESULT: BAN; when it reads
              RESULT: DISCLOSE the body must name the AI use
  prose       no tool footer, session trailer, co-author trailer, em dash or
              en dash, in any case, in the --body-file or the --title
  link        a body that mentions a fix, a patch or a pull request must
              carry a github.com URL to a branch, commit or comparison, so
              the work it describes is attributable

environment:
  HOUSEBROKEN_HOME  work directory, default $HOME/.housebroken
  FILE_ISSUE_DRY    1 prints the gh command and files nothing
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
[ "$#" -gt 0 ] || { echo "REFUSED: no gh issue create arguments given" >&2; exit 2; }

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
banned_re="Generated with|Claude-Session|claude\.ai/code/session_|Co-Authored-By|$em|$en|&[mn]dash;|&#821[12];|&#x201[34];"
check_text() {
  local what="$1" text="$2" hit
  hit=$(printf '%s' "$text" | grep -ioE "$banned_re" | head -1) || true
  if [ -n "$hit" ]; then
    echo "REFUSED: $what contains '$hit' - strip it before filing" >&2
    exit 2
  fi
}

# gh issue create also takes a body from --body, --template, --recover, --web
# and stdin, and obeys the last -R it is given. Each of those files something
# no gate read, so only these flags pass.
bodyfile=""
title=""
pass=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    -F|--body-file) bodyfile="${2:-}"; pass+=("$1" "${2:-}"); shift ;;
    --body-file=*) bodyfile="${1#--body-file=}"; pass+=("$1") ;;
    -t|--title) title="${2:-}"; pass+=("$1" "${2:-}"); shift ;;
    --title=*) title="${1#--title=}"; pass+=("$1") ;;
    -l|--label|-a|--assignee|-m|--milestone|-p|--project) pass+=("$1" "${2:-}"); shift ;;
    --label=*|--assignee=*|--milestone=*|--project=*) pass+=("$1") ;;
    *)
      echo "REFUSED: file-issue.sh does not pass $1 to gh issue create: the body comes from one --body-file, the repository is the first argument" >&2
      exit 2
      ;;
  esac
  shift
done
[ -n "$title" ] || { echo "REFUSED: pass --title" >&2; exit 2; }
[ -n "$bodyfile" ] || { echo "REFUSED: pass the body as --body-file so the gates can read it" >&2; exit 2; }
if [ "$bodyfile" = "-" ] || [ ! -f "$bodyfile" ]; then
  echo "REFUSED: body file $bodyfile does not exist" >&2
  exit 2
fi
body=$(cat "$bodyfile")
check_text "body file $bodyfile" "$body"
check_text "--title" "$title"
if [ "$policy_result" = "DISCLOSE" ] && ! grep -qiE '\bAI\b|LLM|Claude|Copilot|ChatGPT|language model|assist' "$bodyfile"; then
  echo "REFUSED: $repo requires AI use to be disclosed ($policy) and the body does not name it" >&2
  exit 2
fi

offer_re='\b(fix|fixed|fixes|patch|patched|patches|pull request|PR)\b'
link_re='https://github\.com/[^/[:space:]]+/[^/[:space:]]+/(tree|commit|compare|blob)/[^[:space:])]+'
offer=$(printf '%s' "$body" | grep -ioE "$offer_re" | head -1) || true
if [ -n "$offer" ] && ! printf '%s' "$body" | grep -qE "$link_re"; then
  echo "REFUSED: the body says '$offer' and links no branch or commit - push the work to your fork and link it, or take it out of the body" >&2
  exit 2
fi

if [ "${FILE_ISSUE_DRY:-0}" = "1" ]; then
  printf 'DRY RUN, not filed:\ngh issue create -R %s' "$repo"
  for arg in "${pass[@]}"; do printf ' %q' "$arg"; done
  printf '\n'
  exit 0
fi
gh issue create -R "$repo" "${pass[@]}"
