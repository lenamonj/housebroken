#!/bin/bash
# fork-hygiene.sh - clean up after ourselves on GitHub (Jeff, 2026-09-06): delete fork branches whose
# upstream PR is merged or closed, and list forks that carry no PR at all (deleted by hand, on request).
# Never touches branches of open PRs, never touches Jeff's own repositories.
#   bash /mnt/c/jeffy-evals/fork-hygiene.sh [-n]   (-n = list only)
DRY="${1:-}"
gh search prs --author lenamonj --state closed --json repository,number --limit 100 --jq '.[] | "\(.repository.nameWithOwner) \(.number)"' | while read -r repo n; do
  case "$repo" in lenamonj/*) continue ;; esac
  info=$(gh pr view "$n" --repo "$repo" --json headRefName,headRepository,headRepositoryOwner,state --jq '"\(.headRepositoryOwner.login)|\(.headRepository.name)|\(.headRefName)|\(.state)"' 2>/dev/null)
  IFS='|' read -r owner fork branch state <<< "$info"
  [ "$owner" = "lenamonj" ] && [ -n "$branch" ] || continue
  gh api "repos/lenamonj/$fork/git/refs/heads/$branch" >/dev/null 2>&1 || continue
  if [ -n "$DRY" ]; then echo "would delete lenamonj/$fork $branch ($state $repo#$n)"; continue; fi
  gh api -X DELETE "repos/lenamonj/$fork/git/refs/heads/$branch" >/dev/null 2>&1 && echo "deleted lenamonj/$fork $branch ($state $repo#$n)" || echo "FAILED lenamonj/$fork $branch"
done
echo "--- forks with no PR (delete by hand when a wave is over):"
gh repo list lenamonj --fork --limit 200 --json name,parent --jq '.[] | "\(.parent.owner.login)/\(.parent.name)"' | sort -u > /tmp/forks.txt
gh search prs --author lenamonj --json repository --limit 200 --jq '.[].repository.nameWithOwner' | sort -u > /tmp/pr-repos.txt
comm -23 /tmp/forks.txt /tmp/pr-repos.txt | tr '\n' ' '; echo
