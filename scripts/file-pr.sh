#!/bin/bash
# file-pr.sh - the only way a PR gets filed: gh pr create behind two gates.
#
#   bash file-pr.sh owner/repo <gh pr create args...>
#   FILE_PR_DRY=1 bash file-pr.sh owner/repo ...   # print the command, run nothing
#
# Gate one is prior art. typer #1946 (closed 2026-08-31) duplicated an open PR
# and swift-http-types #153 (closed 2026-09-04) reargued a closed issue, both
# because the check was a memory rather than a file. This refuses unless
# pr-bodies/prior-art-<owner>-<repo>.md exists and is under 24 hours old.
# Gate two is the prose. Tool footers, session trailers and em or en dashes have
# no place in somebody else's repository, so a body carrying one is refused.
# Written 2026-09-07.
set -u
repo="${1:?usage: file-pr.sh owner/repo <gh pr create args...>}"
shift
case "$repo" in
  */*) : ;;
  *) echo "REFUSED: first argument must be owner/repo" >&2; exit 2 ;;
esac
[ "$#" -gt 0 ] || { echo "REFUSED: no gh pr create arguments given" >&2; exit 2; }

art="/c/jeffy-evals/pr-bodies/prior-art-${repo%%/*}-${repo##*/}.md"
if [ ! -f "$art" ]; then
  echo "REFUSED: no prior art at $art - run prior-art.sh $repo <terms> --out first" >&2
  exit 2
fi
now=$(date +%s)
made=$(date -r "$art" +%s) || exit 2
if [ $((now - made)) -gt 86400 ]; then
  echo "REFUSED: prior art $art is $(( (now - made) / 3600 ))h old - rerun prior-art.sh --out" >&2
  exit 2
fi

em=$(printf '\xe2\x80\x94')   # em dash U+2014, built at runtime to keep this file ASCII
en=$(printf '\xe2\x80\x93')   # en dash U+2013
banned_re="Generated with|Claude-Session|Co-Authored-By|$em|$en"
check_text() {
  local what="$1" text="$2" hit
  hit=$(printf '%s' "$text" | grep -oE "$banned_re" | head -1) || true
  if [ -n "$hit" ]; then
    echo "REFUSED: $what contains '$hit' - strip it before filing" >&2
    exit 2
  fi
}

prev=""
for arg in "$@"; do
  case "$prev" in
    --body-file|-F)
      [ -f "$arg" ] || { echo "REFUSED: body file $arg does not exist" >&2; exit 2; }
      check_text "body file $arg" "$(cat "$arg")"
      ;;
    --body|-b)
      check_text "--body" "$arg"
      ;;
  esac
  case "$arg" in
    --body-file=*)
      f="${arg#--body-file=}"
      [ -f "$f" ] || { echo "REFUSED: body file $f does not exist" >&2; exit 2; }
      check_text "body file $f" "$(cat "$f")"
      ;;
    --body=*) check_text "--body" "${arg#--body=}" ;;
  esac
  prev="$arg"
done

if [ "${FILE_PR_DRY:-0}" = "1" ]; then
  printf 'DRY RUN, not filed:\ngh pr create -R %s' "$repo"
  for arg in "$@"; do printf ' %q' "$arg"; done
  printf '\n'
  exit 0
fi
gh pr create -R "$repo" "$@"
