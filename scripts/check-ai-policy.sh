#!/bin/bash
# check-ai-policy.sh - independently verify a repo's stance on AI-assisted
# contributions. Scouts report a policy; this reads it. Never adopt a target on
# a scout's description of its policy (cold-cohort-2026-08-09 lesson, applied to
# a new criterion).
#
# Checks a branch of the real repo, not a memory of it, and then the
# organization's .github repository, where an org-wide policy often lives.
# Prints every hit with its file so the operator reads the sentence, not a
# verdict. The branch is overridable because some projects keep the policy on a
# development branch and not on the default branch.
#
# Usage:
#   ./check-ai-policy.sh [--branch <name>] owner/repo [owner/repo ...]
#   ./check-ai-policy.sh --help
#
# Environment:
#   HOUSEBROKEN_HOME  work directory, default $HOME/.housebroken. Not written
#                     by this script; it prints to stdout only.
#
# Assumes gh is installed and authenticated. Read-only: GET calls only.
set -u

usage() {
  cat <<'EOF'
usage: check-ai-policy.sh [--branch <name>] owner/repo [owner/repo ...]
       check-ai-policy.sh --help

  --branch <name>  read the policy files from this branch instead of the
                   repository default branch; some projects keep the policy
                   on a development branch

environment:
  HOUSEBROKEN_HOME  work directory, default $HOME/.housebroken (unused here)
EOF
}

FILES="CONTRIBUTING.md CONTRIBUTING.rst CONTRIBUTING .github/CONTRIBUTING.md
docs/CONTRIBUTING.md docs/contributing.md CODE_OF_CONDUCT.md
.github/CODE_OF_CONDUCT.md README.md AI.md AI_POLICY.md POLICY.md
.github/AI_POLICY.md .github/AI.md .github/POLICY.md .github/PULL_REQUEST_TEMPLATE.md .github/pull_request_template.md
.github/ISSUE_TEMPLATE/config.yml CLAUDE.md AGENTS.md .cursorrules"

PATTERN='[Aa][Ii]-generated|[Aa]rtificial [Ii]ntelligence|\bLLM|[Ll]arge [Ll]anguage [Mm]odel|Copilot|ChatGPT|[Cc]laude|[Gg]enerative|AI assistance|AI-assisted|AI tool|AI slop|machine-generated'

branch_opt=""
repos=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --branch) shift; [ "$#" -gt 0 ] || { echo "check-ai-policy.sh: --branch needs a name" >&2; exit 1; }
              branch_opt="$1" ;;
    --branch=*) branch_opt="${1#--branch=}" ;;
    --*) usage >&2; echo "check-ai-policy.sh: unknown option $1" >&2; exit 1 ;;
    */*) repos+=("$1") ;;
    *) usage >&2; echo "check-ai-policy.sh: '$1' is not owner/repo" >&2; exit 1 ;;
  esac
  shift
done
[ "${#repos[@]}" -gt 0 ] || { usage >&2; exit 1; }

command -v gh >/dev/null 2>&1 || { echo "check-ai-policy.sh: gh is not on PATH" >&2; exit 1; }

# print every policy hit in one repo at one ref; returns 1 when nothing matched
scan() {
  local target="$1" ref="$2" label="$3" found=0 f body hits
  for f in $FILES; do
    body=$(gh api "repos/$target/contents/$f?ref=$ref" --jq '.content' 2>/dev/null | base64 -d 2>/dev/null)
    [ -z "$body" ] && continue
    hits=$(printf '%s' "$body" | grep -nEi "$PATTERN" | head -12)
    if [ -n "$hits" ]; then
      found=1
      echo "  --- $label$f ---"
      printf '%s\n' "$hits" | cut -c1-300 | sed 's/^/      /'
    else
      echo "  (clean) $label$f"
    fi
  done
  [ "$found" -eq 1 ]
}

status=0
for repo in "${repos[@]}"; do
  echo "=================================================================="
  echo "$repo"
  branch="$branch_opt"
  if [ -z "$branch" ]; then
    branch=$(gh api "repos/$repo" --jq .default_branch 2>/dev/null) || branch=""
    if [ -z "$branch" ]; then
      echo "check-ai-policy.sh: cannot read $repo from GitHub" >&2
      status=1
      continue
    fi
  fi
  echo "  branch: $branch"
  found_any=0
  scan "$repo" "$branch" "" && found_any=1

  # an org-wide policy often lives in the organization's .github repository
  org="${repo%%/*}"
  org_branch=$(gh api "repos/$org/.github" --jq .default_branch 2>/dev/null) || org_branch=""
  if [ -n "$org_branch" ]; then
    echo "  org repo: $org/.github ($org_branch)"
    scan "$org/.github" "$org_branch" "$org/.github: " && found_any=1
  fi

  [ "$found_any" -eq 0 ] && echo "  RESULT: no AI/LLM language in any policy file checked"
done
exit "$status"
