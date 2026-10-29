#!/bin/bash
# prior-art.sh - list every prior issue and PR on a repo that touches a term,
# before a PR is written, so the duplicate check is a printout and not a memory.
#
# Two PRs were closed as duplicates because this was done by hand. typer #1946
# (closed 2026-08-31) duplicated OPEN PR typer #1881: gh search issues returns
# issues and PRs mixed and the type was never checked, so this script prints the
# type from the API field and never infers it. swift-http-types #153 (closed
# 2026-09-04) argued against a ruling already made in CLOSED issue #98, which
# nobody read, so this script prints the last non-author comment on every closed
# item. A term containing a slash or a dot is treated as a file path and the
# commit history of that path is scanned for the PRs that touched it, and
# every open PR that changes it is listed, which no text search finds
# (Shopify/ruby-lsp #4103 deleted the file a fix was written against).
# Written 2026-09-07.
#
# Usage:
#   bash prior-art.sh owner/repo <term> [<term> ...] [--out]
#   bash prior-art.sh --help
#
#   --out  also save the printout to $HOUSEBROKEN_HOME/prior-art/, where
#          file-pr.sh looks for it before it will file anything.
#
# Environment:
#   HOUSEBROKEN_HOME  work directory, default $HOME/.housebroken. --out writes
#                     to its prior-art/ subdirectory, created if missing.
#
# Assumes gh is installed and authenticated, and jq is on PATH. Read-only: it
# makes GET calls and writes nothing to GitHub.
set -u

usage() {
  cat <<'EOF'
usage: prior-art.sh owner/repo <term>... [--out [--partial]]
       prior-art.sh --help

  owner/repo  the upstream repository to search
  <term>      a symbol, phrase or file path; a term with a slash or a dot is
              also treated as a path: its commit history is scanned and
              every open PR that changes it is listed
  --out       save the printout under $HOUSEBROKEN_HOME/prior-art/; a printout
              whose searches matched more than they returned is not saved
  --partial   save a partial printout anyway, marked as such

environment:
  HOUSEBROKEN_HOME  work directory, default $HOME/.housebroken
EOF
}

for arg in "$@"; do
  if [ "$arg" = "--help" ] || [ "$arg" = "-h" ]; then usage; exit 0; fi
done

command -v gh >/dev/null 2>&1 || { echo "prior-art.sh: gh is not on PATH" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "prior-art.sh: jq is not on PATH" >&2; exit 1; }

repo=""
out=0
accept_partial=0
terms=()
for arg in "$@"; do
  case "$arg" in
    --out) out=1 ;;
    --partial) accept_partial=1 ;;
    --*) usage >&2; echo "prior-art.sh: unknown option $arg" >&2; exit 1 ;;
    */*) if [ -z "$repo" ]; then repo="$arg"; else terms+=("$arg"); fi ;;
    *) if [ -z "$repo" ]; then usage >&2; exit 1; fi
       terms+=("$arg") ;;
  esac
done
if [ -z "$repo" ] || [ "${#terms[@]}" -eq 0 ]; then
  usage >&2; exit 1
fi

home="${HOUSEBROKEN_HOME:-$HOME/.housebroken}"
calls=0
partial=0
notes=""
items=0
tmp=$(mktemp) || { echo "prior-art.sh: cannot create temp file" >&2; exit 1; }
row=$(mktemp) || { echo "prior-art.sh: cannot create temp file" >&2; exit 1; }
openfiles=$(mktemp) || { echo "prior-art.sh: cannot create temp file" >&2; exit 1; }
trap 'rm -f "$tmp" "$row" "$openfiles"' EXIT

# last comment on a closed item written by somebody other than its author
last_word() {
  local num="$1" author="$2" body
  body=$(gh api "repos/$repo/issues/$num/comments?per_page=100" 2>/dev/null |
    jq -r --arg a "$author" '[.[] | select(.user.login != $a)] | last | .body // ""') || return 0
  printf '%s' "$body" | tr '\n\r\t|' '    ' | tr -s ' ' | cut -c1-160
}

emit() { # label for the counts: issues or pull requests
  local label="$1" kind num state date author title word=""
  while IFS=$'\t' read -r kind num state date author title; do
    [ -n "$num" ] || continue
    # The search's own count against the rows it returned: a term matching more
    # than one page is a printout that has not read everything.
    if [ "$kind" = "TOTAL" ]; then
      if [ "$num" -gt "$state" ]; then
        notes="${notes}showing $state of $num $label for '$term'; narrow the term
"
        partial=1
      fi
      continue
    fi
    word=""
    if [ "$state" = "closed" ]; then word=$(last_word "$num" "$author"); calls=$((calls+1)); fi
    printf '| %s | #%s | %s | %s | %s | %s | %s |\n' \
      "$kind" "$num" "$state" "$date" "$author" "$title" "$word" >>"$tmp"
    items=$((items+1))
  done <"$row"
}

printf '## Prior art: %s (%s)\n' "$repo" "$(date '+%Y-%m-%d %H:%M %Z')" >"$tmp"

for term in "${terms[@]}"; do
  {
    printf '\n### %s\n\n' "$term"
    printf '| type | number | state | date | author | title | last maintainer word |\n'
    printf '| --- | --- | --- | --- | --- | --- | --- |\n'
  } >>"$tmp"

  gh api -X GET search/issues -f q="repo:$repo type:issue \"$term\"" -F per_page=10 \
    --jq '(["TOTAL", (.total_count|tostring), (if .incomplete_results then "0" else (.items|length|tostring) end)] | @tsv),
          (.items[] | ["issue", (.number|tostring), .state, ((.closed_at // .created_at)[0:10]),
          .user.login, (.title|gsub("[|]";"/")|gsub("[\n\r\t]";" "))] | @tsv)' >"$row" ||
    { echo "prior-art.sh: issue search failed for $repo term '$term'" >&2; exit 1; }
  calls=$((calls+1))
  emit issues

  gh api -X GET search/issues -f q="repo:$repo type:pr \"$term\"" -F per_page=10 \
    --jq '(["TOTAL", (.total_count|tostring), (if .incomplete_results then "0" else (.items|length|tostring) end)] | @tsv),
          (.items[] | ["PR", (.number|tostring),
          (if .pull_request.merged_at then "merged" else .state end),
          ((.pull_request.merged_at // .closed_at // .created_at)[0:10]),
          .user.login, (.title|gsub("[|]";"/")|gsub("[\n\r\t]";" "))] | @tsv)' >"$row" ||
    { echo "prior-art.sh: PR search failed for $repo term '$term'" >&2; exit 1; }
  calls=$((calls+1))
  emit "pull requests"

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

      # an open PR that changes the path is prior art even when no title or body names it
      if [ ! -s "$openfiles" ]; then
        # shellcheck disable=SC2016  # $p is a jq variable
        gh pr list -R "$repo" --state open --limit 200 --json number,createdAt,author,title,changedFiles,files \
          --jq '.[] | . as $p | (if .changedFiles > (.files | length) then ["MORE"] else [.files[].path] end)[] |
                [($p.number|tostring), $p.createdAt[0:10], $p.author.login,
                 ($p.title|gsub("[|]";"/")|gsub("[\n\r\t]";" ")), .] | @tsv' >"$openfiles" ||
          { echo "prior-art.sh: open PR listing failed for $repo" >&2; exit 1; }
        calls=$((calls+1))
        open_total=$(gh api -X GET search/issues -f q="repo:$repo is:pr is:open" --jq .total_count 2>/dev/null) || open_total=""
        calls=$((calls+1))
        if [ -z "$open_total" ] || [ "$open_total" -gt 200 ]; then
          notes="${notes}OPEN PR LIST INCOMPLETE: 200 of ${open_total:-an unknown number of} open pull requests read; one changing these paths may be missing
"
          partial=1
        fi
        # GitHub returns at most 100 files per PR here; a larger PR is read in full
        awk -F'\t' '$5 == "MORE"' "$openfiles" | while IFS=$'\t' read -r num date author title _; do
          gh api --paginate "repos/$repo/pulls/$num/files?per_page=100" --jq '.[].filename' |
            while IFS= read -r f; do printf '%s\t%s\t%s\t%s\t%s\n' "$num" "$date" "$author" "$title" "$f"; done
        done >"$row"
        cat "$row" >>"$openfiles"
        [ -s "$openfiles" ] || printf 'none\n' >"$openfiles"
      fi
      while IFS=$'\t' read -r num date author title path; do
        case "$path" in "$term"|*/"$term") ;; *) continue ;; esac
        grep -q "^| PR | #$num | open, changes this file |" "$tmp" && continue
        printf '| PR | #%s | open, changes this file | %s | %s | %s |  |\n' "$num" "$date" "$author" "$title" >>"$tmp"
        items=$((items+1))
      done <"$openfiles"
      ;;
  esac
done

printf '\n%d items across %d terms. Read every closed item before filing; this script lists, it does not judge.\n' \
  "$items" "${#terms[@]}" >>"$tmp"
printf 'gh calls: %d\n' "$calls" >>"$tmp"
if [ "$partial" -eq 1 ]; then
  printf '\nPARTIAL: these searches returned less than they matched:\n%s' "$notes" >>"$tmp"
  [ "$accept_partial" -eq 1 ] && printf 'saved with --partial: the rest was not read\n' >>"$tmp"
fi

cat "$tmp"
if [ "$out" -eq 1 ] && [ "$partial" -eq 1 ] && [ "$accept_partial" -eq 0 ]; then
  echo "prior-art.sh: not saved - the printout is partial; narrow the terms, or pass --partial to save it as read" >&2
  exit 1
fi
if [ "$out" -eq 1 ]; then
  dir="$home/prior-art"
  mkdir -p "$dir" || { echo "prior-art.sh: cannot create $dir" >&2; exit 1; }
  cp "$tmp" "$dir/prior-art-${repo%%/*}-${repo##*/}.md" ||
    { echo "prior-art.sh: cannot write $dir/prior-art-${repo%%/*}-${repo##*/}.md" >&2; exit 1; }
fi
