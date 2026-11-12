#!/bin/bash
# fork-hygiene.sh - clean up after ourselves on GitHub (rule adopted 2026-09-06):
# delete the fork branch of every upstream PR that is merged or closed, and list
# the forks that carry no PR at all, which are deleted by hand when the work is
# over. Never touches the branch of an open PR, never touches our own repositories.
#
# Usage:
#   bash fork-hygiene.sh              # deletes the branches it names
#   bash fork-hygiene.sh --dry-run    # prints what it would delete, deletes nothing
#   bash fork-hygiene.sh --help
#
# Environment:
#   HOUSEBROKEN_USER  GitHub login whose forks are cleaned, default the
#                     authenticated user
#
# Assumes: gh is installed and authenticated with delete access to the fork,
# that our forks live under that login, and that a closed or merged PR's head
# branch has no other use. -n is accepted as a synonym for --dry-run.
set -u

usage() {
  sed -n '2,/^set -u$/p' "$0" | sed 's/^# \{0,1\}//; /^set -u$/d'
}
# shellcheck source=scripts/common.sh
. "$(cd "$(dirname "$0")" && pwd)/common.sh"
MAX=1000

DRY=0
case "${1:-}" in
  --help|-h) usage; exit 0 ;;
  --dry-run|-n) DRY=1 ;;
  "") ;;
  *) echo "fork-hygiene.sh: unknown argument: $1" >&2; usage >&2; exit 2 ;;
esac

ME="${HOUSEBROKEN_USER:-$(gh api user --jq .login)}"
if [ -z "$ME" ]; then
  echo "fork-hygiene.sh: cannot determine the GitHub login; set HOUSEBROKEN_USER" >&2
  exit 1
fi

if ! closed="$(gh search prs --author "$ME" --state closed --sort updated --json repository,number --limit "$MAX" \
  --jq '.[] | "\(.repository.nameWithOwner) \(.number)"')"; then
  echo "fork-hygiene.sh: gh search prs failed for author $ME" >&2
  exit 1
fi
[ "$(printf '%s\n' "$closed" | grep -c .)" -lt "$MAX" ] || echo "note: only the $MAX most recently updated closed pull requests were read"

while read -r repo n; do
  [ -n "$repo" ] || continue
  case "$repo" in "$ME"/*) continue ;; esac
  # Tabs and @tsv: a branch name can hold a | or a #.
  # shellcheck disable=SC2016  # jq text
  info=$(gh pr view "$n" --repo "$repo" --json headRefName,headRepository,headRepositoryOwner,state \
    --jq '[(.headRepositoryOwner.login // "-"), (.headRepository.name // "-"), (.headRefName // "-"), .state] | @tsv' 2>/dev/null) || {
    echo "fork-hygiene.sh: gh pr view $repo#$n failed" >&2
    continue
  }
  IFS=$'\t' read -r owner fork branch state <<< "$info"
  if [ "$owner" != "$ME" ] || [ "$fork" = "-" ] || [ "$branch" = "-" ]; then continue; fi
  drop_fork_branch "$ME" "$fork" "$branch" "$state $repo#$n" "$DRY"
done <<< "$closed"

echo "--- forks with no PR (delete by hand when a wave is over):"
forks=$(mktemp) || { echo "fork-hygiene.sh: mktemp failed" >&2; exit 1; }
prrepos=$(mktemp) || { echo "fork-hygiene.sh: mktemp failed" >&2; exit 1; }
trap 'rm -f "$forks" "$prrepos"' EXIT

# Without pipefail these would test sort, and a failed listing would call every
# fork an orphan.
set -o pipefail
if ! gh repo list "$ME" --fork --limit "$MAX" --json name,parent \
  --jq '.[] | "\(.parent.owner.login)/\(.parent.name)"' | sort -u > "$forks"; then
  echo "fork-hygiene.sh: gh repo list failed for $ME" >&2
  exit 1
fi
if ! gh search prs --author "$ME" --json repository --limit "$MAX" \
  --jq '.[].repository.nameWithOwner' | sort -u > "$prrepos"; then
  echo "fork-hygiene.sh: gh search prs failed for author $ME" >&2
  exit 1
fi
if [ "$(wc -l < "$prrepos")" -ge "$MAX" ] || [ "$(wc -l < "$forks")" -ge "$MAX" ]; then
  echo "note: a listing stopped at $MAX, so a fork named here may still carry a pull request"
fi
comm -23 "$forks" "$prrepos" | tr '\n' ' '; echo
