#!/bin/bash
# check-ai-policy.sh - read a repository's stance on AI-assisted contributions
# where it actually lives, and say what it requires.
#
# The rule: a project that bans AI-written contributions never gets one; a
# project that asks for disclosure gets a truthful sentence in the body; a
# project that says nothing gets nothing. The policy is read from the
# repository itself, never from a description of it: every file on the branch
# whose name is a contributing guide, a code of conduct, a pull request or
# issue template, a README or an agent instruction file, matched without
# regard to case, plus the same files in the organization's .github
# repository.
#
# Usage:
#   bash check-ai-policy.sh [--branch <name>] [--out] owner/repo [owner/repo ...]
#   bash check-ai-policy.sh --help
#
#   --branch <name>  read this branch instead of the default; some projects
#                    keep the policy on a development branch
#   --out            also save the printout to $HOUSEBROKEN_HOME/policy/
#                    policy-<owner>-<repo>.md, which file-pr.sh reads
#
# Every hit is printed with its file and line so the sentence is read, not a
# verdict. The RESULT line is the reading: BAN when a sentence forbids or
# closes AI-written contributions, DISCLOSE when a sentence requires that AI
# use be disclosed, MENTION when AI is named without either, CLEAN when no
# policy file names it. Exit 0 for CLEAN or MENTION, 3 for DISCLOSE, 4 for BAN,
# 1 when the repository cannot be read. With several repositories the exit is
# the highest.
#
# Environment:
#   HOUSEBROKEN_HOME  work directory, default $HOME/.housebroken; --out writes
#                     to its policy/ subdirectory, created if missing.
#
# Assumes gh is installed and authenticated. Read-only: GET calls only.
set -u

usage() { awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"; }

# Policy files, matched against the repository's own tree listing without
# regard to case, so CONTRIBUTING.rst, contributing.md and Contributing.md
# are all read.
NAME_RE='(^|/)(contributing([._-][a-z]+)?\.(md|rst|txt|adoc)|contributing|code[_-]?of[_-]?conduct\.(md|rst|txt)|readme\.(md|rst|txt|adoc)|ai([_-]policy)?\.md|policy\.md|agents?\.md|claude\.md|gemini\.md|copilot-instructions\.md|\.cursorrules|\.cursor/rules/[^/]+|pull_request_template(\.md)?|pull_request_template/[^/]+\.md|issue_template/[^/]+\.(md|yml|yaml)|governance\.md|maintainers\.md)$'
MAX_FILES=40

# The word itself, plus its usual spellings and the tools by name.
PATTERN='\bAI\b|\bA\.I\.|[Aa]rtificial [Ii]ntelligence|\bLLMs?\b|[Ll]arge [Ll]anguage [Mm]odels?|Copilot|ChatGPT|[Cc]laude|[Gg]enerative|[Mm]achine-generated|[Cc]odex\b|[Cc]ursor\b|[Aa]gentic'
BAN_RE='not (be )?(accept|allow|permit|welcome)|prohibit|forbid|banned|\bban\b|will be closed|closed without|do not (use|submit|open)|don.t (use|submit)|refrain from|no (AI|LLM|AI-generated|machine-generated)|must not|may not (use|submit)|are not (allowed|accepted|permitted)|zero tolerance'
DISCLOSE_RE='disclos|disclaimer|declare|must (state|say|note|indicate|mention)|be transparent|label(l)?ed as|clearly (state|indicate|mark)|acknowledg|(if|whether) (you )?(use|used|using) (AI|an AI|LLM)|which (AI|LLM) tool|AI transcript|used AI to'

branch_opt=""
out=0
repos=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --branch) shift; [ "$#" -gt 0 ] || { echo "check-ai-policy.sh: --branch needs a name" >&2; exit 1; }
              branch_opt="$1" ;;
    --branch=*) branch_opt="${1#--branch=}" ;;
    --out) out=1 ;;
    --*) usage >&2; echo "check-ai-policy.sh: unknown option $1" >&2; exit 1 ;;
    */*) repos+=("$1") ;;
    *) usage >&2; echo "check-ai-policy.sh: '$1' is not owner/repo" >&2; exit 1 ;;
  esac
  shift
done
[ "${#repos[@]}" -gt 0 ] || { usage >&2; exit 1; }

command -v gh >/dev/null 2>&1 || { echo "check-ai-policy.sh: gh is not on PATH" >&2; exit 1; }
home="${HOUSEBROKEN_HOME:-$HOME/.housebroken}"

# List the policy files at one ref of one repository, from its tree listing.
policy_files() {
  gh api "repos/$1/git/trees/$2?recursive=1" --jq '.tree[] | select(.type == "blob") | .path' 2>/dev/null \
    | grep -Ei "$NAME_RE" | head -"$MAX_FILES"
}

# Print every hit in one repository at one ref; sets found, ban, disclose.
scan() {
  local target="$1" ref="$2" label="$3" f body hits
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    body=$(gh api "repos/$target/contents/$f?ref=$ref" --jq '.content' 2>/dev/null | base64 -d 2>/dev/null)
    [ -n "$body" ] || continue
    hits=$(printf '%s' "$body" | grep -nE "$PATTERN" | head -20)
    if [ -n "$hits" ]; then
      found=1
      echo "  --- $label$f ---"
      printf '%s\n' "$hits" | cut -c1-300 | sed 's/^/      /'
      printf '%s\n' "$hits" | grep -qiE "$BAN_RE" && ban=1
      printf '%s\n' "$hits" | grep -qiE "$DISCLOSE_RE" && disclose=1
    else
      echo "  (clean) $label$f"
    fi
  done < <(policy_files "$target" "$ref")
}

status=0
for repo in "${repos[@]}"; do
  found=0; ban=0; disclose=0
  report=$(
    echo "## AI policy: $repo"
    echo "read: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    branch="$branch_opt"
    if [ -z "$branch" ]; then
      branch=$(gh api "repos/$repo" --jq .default_branch 2>/dev/null) || branch=""
    fi
    if [ -z "$branch" ]; then
      echo "ERROR: cannot read $repo from GitHub"
      exit 1
    fi
    echo "branch: $branch"
    scan "$repo" "$branch" ""
    org="${repo%%/*}"
    org_branch=$(gh api "repos/$org/.github" --jq .default_branch 2>/dev/null) || org_branch=""
    if [ -n "$org_branch" ]; then
      echo "org repo: $org/.github ($org_branch)"
      scan "$org/.github" "$org_branch" "$org/.github: "
    fi
    if [ "$ban" -eq 1 ]; then echo "RESULT: BAN (a policy file forbids or closes AI-written contributions; never file here)"
    elif [ "$disclose" -eq 1 ]; then echo "RESULT: DISCLOSE (a policy file requires AI use to be disclosed; say so in the body)"
    elif [ "$found" -eq 1 ]; then echo "RESULT: MENTION (a policy file names AI; read the lines above and decide)"
    else echo "RESULT: CLEAN (no policy file names AI)"
    fi
  )
  rc=$?
  printf '%s\n' "$report"
  if [ "$rc" -ne 0 ]; then status=1; continue; fi
  case "$report" in
    *"RESULT: BAN"*) [ "$status" -lt 4 ] && status=4 ;;
    *"RESULT: DISCLOSE"*) [ "$status" -lt 3 ] && status=3 ;;
  esac
  if [ "$out" -eq 1 ]; then
    mkdir -p "$home/policy"
    printf '%s\n' "$report" > "$home/policy/policy-${repo%%/*}-${repo##*/}.md"
    echo "saved: $home/policy/policy-${repo%%/*}-${repo##*/}.md"
  fi
done
exit "$status"
