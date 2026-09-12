#!/bin/bash
# file-pr.sh - the only way a PR gets filed: gh pr create behind three gates.
#
# Gate one is prior art. typer #1946 (closed 2026-08-31) duplicated an open PR
# and swift-http-types #153 (closed 2026-09-04) reargued a closed issue, both
# because the check was a memory rather than a file. This refuses unless
# prior-art-<owner>-<repo>.md exists under $HOUSEBROKEN_HOME/prior-art/ and is
# under 24 hours old.
# Gate two is the prose. Tool footers, session trailers and em or en dashes have
# no place in somebody else's repository, so a body carrying one is refused.
# Written 2026-09-07.
# Gate three is the adversarial review (review.sh). A different model attacked
# this exact head and this exact body file and said POST AS IS. An inline
# --body is refused, because a review cannot be bound to text that was never a
# file. Added 2026-09-12.
#
# Usage:
#   bash file-pr.sh owner/repo <gh pr create args...>
#   FILE_PR_DRY=1 bash file-pr.sh owner/repo ...   # print the command, run nothing
#   bash file-pr.sh --help
#
# Environment:
#   HOUSEBROKEN_HOME  work directory, default $HOME/.housebroken. The prior art
#                     is read from its prior-art/ subdirectory, where
#                     prior-art.sh --out puts it.
#   FILE_PR_DRY       set to 1 to print the gh command instead of running it.
#
# Assumes gh is installed and authenticated. This is the one script here that
# writes to GitHub, and only after both gates pass and only when FILE_PR_DRY
# is not 1.
set -u

usage() {
  cat <<'EOF'
usage: file-pr.sh owner/repo <gh pr create args...>
       file-pr.sh --help

  owner/repo  the upstream repository the PR is filed against
  the remaining arguments are passed to gh pr create unchanged

gates:
  prior art   $HOUSEBROKEN_HOME/prior-art/prior-art-<owner>-<repo>.md must
              exist and be under 24 hours old
  prose       no tool footer, session trailer, co-author trailer, em dash or
              en dash in --body or --body-file
  review      run from the clone being filed; the report at
              $HOUSEBROKEN_HOME/reviews/review-<owner>-<repo>-<head12>.md must
              pass review.sh check for this head and the --body-file, and an
              inline --body is refused

environment:
  HOUSEBROKEN_HOME  work directory, default $HOME/.housebroken
  FILE_PR_DRY       1 prints the gh command and files nothing
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
[ "$#" -gt 0 ] || { echo "REFUSED: no gh pr create arguments given" >&2; exit 2; }

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
bodyfile=""
inline_body=0
for arg in "$@"; do
  case "$prev" in
    --body-file|-F)
      [ -f "$arg" ] || { echo "REFUSED: body file $arg does not exist" >&2; exit 2; }
      check_text "body file $arg" "$(cat "$arg")"
      bodyfile="$arg"
      ;;
    --body|-b)
      check_text "--body" "$arg"
      inline_body=1
      ;;
  esac
  case "$arg" in
    --body-file=*)
      f="${arg#--body-file=}"
      [ -f "$f" ] || { echo "REFUSED: body file $f does not exist" >&2; exit 2; }
      check_text "body file $f" "$(cat "$f")"
      bodyfile="$f"
      ;;
    --body=*) check_text "--body" "${arg#--body=}"; inline_body=1 ;;
  esac
  prev="$arg"
done

head=$(git rev-parse HEAD 2>/dev/null) || { echo "REFUSED: run file-pr.sh from inside the clone being filed" >&2; exit 2; }
if [ "$inline_body" -eq 1 ]; then
  echo "REFUSED: pass the body as --body-file so the review can be bound to it" >&2
  exit 2
fi
review="$home/reviews/review-${repo%%/*}-${repo##*/}-${head:0:12}.md"
if [ ! -f "$review" ]; then
  echo "REFUSED: no adversarial review at $review - run review.sh brief and have a different model attack this head" >&2
  exit 2
fi
review_args=(check "$review" --clone .)
[ -n "$bodyfile" ] && review_args+=(--text "$bodyfile")
bash "$(dirname "$0")/review.sh" "${review_args[@]}" >/dev/null || exit 2

if [ "${FILE_PR_DRY:-0}" = "1" ]; then
  printf 'DRY RUN, not filed:\ngh pr create -R %s' "$repo"
  for arg in "$@"; do printf ' %q' "$arg"; done
  printf '\n'
  exit 0
fi
gh pr create -R "$repo" "$@"
