#!/bin/bash
# check-ai-policy.sh - independently verify a repo's stance on AI-assisted
# contributions. Scouts report a policy; this reads it. Never adopt a target on
# a scout's description of its policy (cold-cohort-2026-08-09 lesson, applied to
# a new criterion).
#
# Usage: ./check-ai-policy.sh owner/repo [owner/repo ...]
#
# Checks the default branch of the real repo, not a memory of it. Prints every
# hit with its file so the operator reads the sentence, not a verdict.
set -u

FILES="CONTRIBUTING.md CONTRIBUTING.rst CONTRIBUTING .github/CONTRIBUTING.md
docs/CONTRIBUTING.md docs/contributing.md CODE_OF_CONDUCT.md
.github/CODE_OF_CONDUCT.md README.md AI.md AI_POLICY.md POLICY.md
.github/AI_POLICY.md .github/AI.md .github/POLICY.md .github/PULL_REQUEST_TEMPLATE.md .github/pull_request_template.md
.github/ISSUE_TEMPLATE/config.yml CLAUDE.md AGENTS.md .cursorrules"

PATTERN='[Aa][Ii]-generated|[Aa]rtificial [Ii]ntelligence|\bLLM|[Ll]arge [Ll]anguage [Mm]odel|Copilot|ChatGPT|[Cc]laude|[Gg]enerative|AI assistance|AI-assisted|AI tool|AI slop|machine-generated'

for repo in "$@"; do
  echo "=================================================================="
  echo "$repo"
  branch=$(gh api "repos/$repo" --jq .default_branch 2>/dev/null)
  echo "  default branch: ${branch:-UNKNOWN}"
  found_any=0
  for f in $FILES; do
    body=$(gh api "repos/$repo/contents/$f?ref=$branch" --jq '.content' 2>/dev/null | base64 -d 2>/dev/null)
    [ -z "$body" ] && continue
    hits=$(printf '%s' "$body" | grep -nEi "$PATTERN" | head -12)
    if [ -n "$hits" ]; then
      found_any=1
      echo "  --- $f ---"
      printf '%s\n' "$hits" | cut -c1-300 | sed 's/^/      /'
    else
      echo "  (clean) $f"
    fi
  done
  [ "$found_any" -eq 0 ] && echo "  RESULT: no AI/LLM language in any policy file checked"
done
