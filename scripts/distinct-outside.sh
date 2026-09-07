#!/bin/bash
# distinct-outside.sh - distinct outside humans whose PRs were merged in the
# last N days. A project that has merged none is closed to outsiders whatever
# its README says, so this number is read before a target is adopted.
#
# Outside means the PR's author_association is CONTRIBUTOR, FIRST_TIMER,
# FIRST_TIME_CONTRIBUTOR or NONE; everything else is counted as team. Known bot
# accounts are dropped. Only the two most recently updated pages of closed PRs
# are read, so a very busy repo is a lower bound on a long window.
#
# Usage:
#   bash distinct-outside.sh [--days N] owner/repo [owner/repo ...]
#   bash distinct-outside.sh --help
#
# Environment:
#   HOUSEBROKEN_HOME  work directory, default $HOME/.housebroken. The PR pages
#                     are staged in its cache/ subdirectory, created if missing.
#
# Assumes gh is installed and authenticated, and jq is on PATH. Read-only: GET
# calls only.
set -u

usage() {
  cat <<'EOF'
usage: distinct-outside.sh [--days N] owner/repo [owner/repo ...]
       distinct-outside.sh --help

  --days N  window in days, default 120

environment:
  HOUSEBROKEN_HOME  work directory, default $HOME/.housebroken
EOF
}

days=120
repos=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --days) shift; [ "$#" -gt 0 ] || { echo "distinct-outside.sh: --days needs a number" >&2; exit 1; }
            days="$1" ;;
    --days=*) days="${1#--days=}" ;;
    --*) usage >&2; echo "distinct-outside.sh: unknown option $1" >&2; exit 1 ;;
    */*) repos+=("$1") ;;
    *) usage >&2; echo "distinct-outside.sh: '$1' is not owner/repo" >&2; exit 1 ;;
  esac
  shift
done
[ "${#repos[@]}" -gt 0 ] || { usage >&2; exit 1; }
case "$days" in
  ''|*[!0-9]*) echo "distinct-outside.sh: --days must be a whole number, got '$days'" >&2; exit 1 ;;
esac

command -v gh >/dev/null 2>&1 || { echo "distinct-outside.sh: gh is not on PATH" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "distinct-outside.sh: jq is not on PATH" >&2; exit 1; }

home="${HOUSEBROKEN_HOME:-$HOME/.housebroken}"
cache="$home/cache"
mkdir -p "$cache" || { echo "distinct-outside.sh: cannot create $cache" >&2; exit 1; }

cutoff=$(date -u -d "$days days ago" '+%Y-%m-%dT%H:%M:%SZ') ||
  { echo "distinct-outside.sh: cannot compute the cutoff date" >&2; exit 1; }

for repo in "${repos[@]}"; do
  json="$cache/prs-${repo%%/*}-${repo##*/}.json"
  : >"$json"
  for page in 1 2; do
    gh api "repos/$repo/pulls?state=closed&per_page=100&sort=updated&direction=desc&page=$page" >>"$json" ||
      { echo "distinct-outside.sh: cannot list closed PRs for $repo" >&2; exit 1; }
  done
  jq -s -r --arg repo "$repo" --arg cutoff "$cutoff" --arg days "$days" '
    def bot: ascii_downcase | test("dependabot|renovate|github-actions|pre-commit-ci|allcontributors|snyk|\\[bot\\]");
    def tally: reduce .[] as $l ({}; .[$l] += 1);
    (add // [])
    | map(select(.merged_at != null and .merged_at >= $cutoff))
    | map(select((.user.login // "") | bot | not))
    | (map(select(.author_association as $a
        | ["CONTRIBUTOR","FIRST_TIME_CONTRIBUTOR","FIRST_TIMER","NONE"] | index($a)))
        | map(.user.login) | tally) as $out
    | (map(select(.author_association as $a
        | ["CONTRIBUTOR","FIRST_TIME_CONTRIBUTOR","FIRST_TIMER","NONE"] | index($a) | not))
        | map(.user.login) | tally) as $team
    | "\($repo): \($out | length) distinct outside humans in \($days)d -> \($out | tojson) | team merges \($team | tojson)"
  ' "$json" || { echo "distinct-outside.sh: cannot parse the PR list for $repo" >&2; exit 1; }
done
