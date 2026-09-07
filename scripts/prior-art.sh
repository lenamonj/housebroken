#!/bin/bash
# prior-art.sh - list every prior issue and PR on a repo that touches a term,
# before a PR is written, so the duplicate check is a printout and not a memory.
#
#   bash prior-art.sh owner/repo <term> [<term> ...] [--out]
#
# Two PRs were closed as duplicates because this was done by hand. typer #1946
# (closed 2026-08-31) duplicated OPEN PR typer #1881: gh search issues returns
# issues and PRs mixed and the type was never checked, so this script prints the
# type from the API field and never infers it. swift-http-types #153 (closed
# 2026-09-04) argued against a ruling already made in CLOSED issue #98, which
# nobody read, so this script prints the last non-author comment on every closed
# item. A term containing a slash or a dot is treated as a file path and the
# commit history of that path is scanned for the PRs that touched it.
# Written 2026-09-07.
set -u
repo=""
out=0
terms=()
for arg in "$@"; do
  case "$arg" in
    --out) out=1 ;;
    */*) if [ -z "$repo" ]; then repo="$arg"; else terms+=("$arg"); fi ;;
    *) if [ -z "$repo" ]; then echo "usage: prior-art.sh owner/repo <term>... [--out]" >&2; exit 1; fi
       terms+=("$arg") ;;
  esac
done
if [ -z "$repo" ] || [ "${#terms[@]}" -eq 0 ]; then
  echo "usage: prior-art.sh owner/repo <term>... [--out]" >&2; exit 1
fi
calls=0
items=0
tmp=$(mktemp)
row=$(mktemp)
trap 'rm -f "$tmp" "$row"' EXIT

# last comment on a closed item written by somebody other than its author
last_word() {
  local num="$1" author="$2" body
  body=$(gh api "repos/$repo/issues/$num/comments?per_page=100" 2>/dev/null |
    jq -r --arg a "$author" '[.[] | select(.user.login != $a)] | last | .body // ""') || return 0
  printf '%s' "$body" | tr '\n\r\t|' '    ' | tr -s ' ' | cut -c1-160
}

emit() {
  local kind num state date author title word=""
  while IFS=$'\t' read -r kind num state date author title; do
    [ -n "$num" ] || continue
    word=""
    if [ "$state" = "closed" ]; then word=$(last_word "$num" "$author"); calls=$((calls+1)); fi
    printf '| %s | #%s | %s | %s | %s | %s | %s |\n' \
      "$kind" "$num" "$state" "$date" "$author" "$title" "$word" >>"$tmp"
    items=$((items+1))
  done <"$row"
}

printf '## Prior art: %s (%s)\n' "$repo" "$(TZ=America/New_York date '+%Y-%m-%d %H:%M ET')" >"$tmp"

for term in "${terms[@]}"; do
  {
    printf '\n### %s\n\n' "$term"
    printf '| type | number | state | date | author | title | last maintainer word |\n'
    printf '| --- | --- | --- | --- | --- | --- | --- |\n'
  } >>"$tmp"

  gh api -X GET search/issues -f q="repo:$repo type:issue \"$term\"" -F per_page=10 \
    --jq '.items[] | ["issue", (.number|tostring), .state, ((.closed_at // .created_at)[0:10]),
          .user.login, (.title|gsub("[|]";"/")|gsub("[\n\r\t]";" "))] | @tsv' >"$row" || exit 1
  calls=$((calls+1))
  emit

  gh api -X GET search/issues -f q="repo:$repo type:pr \"$term\"" -F per_page=10 \
    --jq '.items[] | ["PR", (.number|tostring),
          (if .pull_request.merged_at then "merged" else .state end),
          ((.pull_request.merged_at // .closed_at // .created_at)[0:10]),
          .user.login, (.title|gsub("[|]";"/")|gsub("[\n\r\t]";" "))] | @tsv' >"$row" || exit 1
  calls=$((calls+1))
  emit

  # a path term also gets the PRs whose merge commits touched that path
  case "$term" in
    */*|*.*)
      gh api "repos/$repo/commits?path=$term&per_page=30" \
        --jq '.[] | [(.commit.message|split("\n")[0]|gsub("[|]";"/")),
              (.commit.author.date[0:10]), (.author.login // .commit.author.name)] | @tsv' \
        2>/dev/null >"$row" || true
      calls=$((calls+1))
      while IFS=$'\t' read -r subject date author; do
        num=$(printf '%s' "$subject" | grep -oE '#[0-9]+' | head -1 | tr -d '#')
        [ -n "${num:-}" ] || continue
        grep -q "^| PR | #$num |" "$tmp" && continue
        printf '| PR | #%s | merged | %s | %s | %s |  |\n' "$num" "$date" "$author" "$subject" >>"$tmp"
        items=$((items+1))
      done <"$row"
      ;;
  esac
done

printf '\n%d items across %d terms. Read every closed item before filing; this script lists, it does not judge.\n' \
  "$items" "${#terms[@]}" >>"$tmp"
printf 'gh calls: %d\n' "$calls" >>"$tmp"

cat "$tmp"
if [ "$out" -eq 1 ]; then
  mkdir -p /c/jeffy-evals/pr-bodies
  cp "$tmp" "/c/jeffy-evals/pr-bodies/prior-art-${repo%%/*}-${repo##*/}.md"
fi
