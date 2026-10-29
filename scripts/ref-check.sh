#!/bin/bash
# ref-check.sh - every reference in outbound text points at something that
# exists.
#
# A model writes "Fixes #412", a link, a test name or a commit hash with the
# same fluency whether the thing exists or not, and a maintainer who follows
# one to nothing stops reading. Each reference is looked up: an issue or pull
# request number on GitHub (its type and state printed, so "Fixes" naming a
# merged pull request is visible), a github.com link, and, with --clone, a
# file path, a test name or a commit hash named in backticks. Fenced code and
# quoted lines are evidence, not references, and are skipped.
#
# Usage:
#   bash ref-check.sh owner/repo FILE [--clone DIR]
#   bash ref-check.sh --help
#
# Exits 0 when every reference was found, 1 when any was not, 2 on a usage
# error. A lookup GitHub refuses reads NOT FOUND: unconfirmed is not found.
#
# Assumes gh is installed and authenticated. Read-only: GET calls only.
set -u

usage() { awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"; }

case "${1:-}" in
  --help|-h) usage; exit 0 ;;
esac
repo="${1:-}"; file="${2:-}"
case "$repo" in */*) ;; *) echo "REFUSED: name the repository as owner/repo" >&2; exit 2 ;; esac
[ -f "$file" ] || { echo "REFUSED: $file does not exist" >&2; exit 2; }
shift 2
clone=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --clone) clone="${2:-}"; [ -d "$clone" ] || { echo "REFUSED: --clone needs a directory" >&2; exit 2; }; shift ;;
    *) echo "REFUSED: unknown argument $1" >&2; exit 2 ;;
  esac
  shift
done

text=$(awk '/^(```|~~~)/ {fence = !fence; next} !fence && !/^ *>/ && !/^    / {print}' "$file")
found() { echo "  found      $1"; }
lost() { echo "  NOT FOUND  $1"; }

# owner/repo#N and bare #N, the bare ones in this repository
issue() { # owner/repo number label
  local got
  if got=$(gh api "repos/$1/issues/$2" --jq '(if .pull_request then "pull request" else "issue" end) + " " + .state + ": " + .title' 2>/dev/null); then
    found "$3 ($got)"
  else
    lost "$3"
  fi
}
out=$(
  printf '%s\n' "$text" | grep -oE '\b[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#[0-9]+\b' | sort -u | while IFS= read -r ref; do
    issue "${ref%#*}" "${ref##*#}" "$ref"
  done
  printf '%s\n' "$text" | sed -E 's/[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+#[0-9]+//g' | grep -oE '(^|[^A-Za-z0-9&/])#[0-9]+\b' \
    | grep -oE '[0-9]+' | sort -un | while IFS= read -r n; do
    issue "$repo" "$n" "#$n"
  done
  printf '%s\n' "$text" | grep -oE 'https://github\.com/[^ )>"]+' | sed 's/[.,;:]$//' | sort -u | while IFS= read -r url; do
    path="${url#https://github.com/}"
    case "$path" in
      */*/pull/[0-9]*|*/*/issues/[0-9]*)
        r=$(printf '%s' "$path" | cut -d/ -f1-2); n=$(printf '%s' "$path" | cut -d/ -f4 | grep -oE '^[0-9]+')
        issue "$r" "$n" "$url" ;;
      */*/commit/*)
        r=$(printf '%s' "$path" | cut -d/ -f1-2); c=$(printf '%s' "$path" | cut -d/ -f4)
        if gh api "repos/$r/commits/$c" --jq .sha >/dev/null 2>&1; then found "$url"; else lost "$url"; fi ;;
      */*/blob/*|*/*/tree/*)
        r=$(printf '%s' "$path" | cut -d/ -f1-2); ref=$(printf '%s' "$path" | cut -d/ -f4); p=$(printf '%s' "$path" | cut -d/ -f5- | sed 's/#.*//')
        if gh api "repos/$r/contents/$p?ref=$ref" --jq 'if type == "array" then "dir" else .path end' >/dev/null 2>&1; then found "$url"; else lost "$url"; fi ;;
    esac
  done
)

# Names in backticks, checked against the clone: a path, a test, a commit.
if [ -n "$clone" ]; then
  # shellcheck disable=SC2016  # the backticks are the markdown being matched
  names=$(printf '%s\n' "$text" | grep -oE '`[^`]+`' | tr -d '`' | sort -u)
  local_out=$(printf '%s\n' "$names" | while IFS= read -r n; do
    [ -n "$n" ] || continue
    if printf '%s' "$n" | grep -qE '^[0-9a-f]{7,40}$'; then
      if git -C "$clone" cat-file -e "$n^{commit}" 2>/dev/null; then found "commit $n"; else lost "commit $n"; fi
    elif printf '%s' "$n" | grep -qE '^[A-Za-z0-9_./-]+\.[A-Za-z0-9]{1,6}$'; then
      # A dotted name is a file when the clone has it; without a slash it may
      # be an identifier (os.path, t.Run, v1.2.3), so only a path is NOT FOUND.
      if git -C "$clone" ls-files --error-unmatch -- "$n" >/dev/null 2>&1 \
        || git -C "$clone" ls-files | grep -qE "(^|/)$(printf '%s' "$n" | sed 's/[.[\*^$]/\\&/g')$"; then
        found "file $n"
      elif printf '%s' "$n" | grep -q /; then
        lost "file $n"
      fi
    elif printf '%s' "$n" | grep -qE '^(Test[A-Z][A-Za-z0-9_]*|test_[A-Za-z0-9_]+|[A-Za-z0-9_]+_test|[A-Z][A-Za-z0-9_]*Tests?)$'; then
      if git -C "$clone" grep -qw -- "$n" 2>/dev/null; then found "test $n"; else lost "test $n"; fi
    fi
  done)
  out=$(printf '%s\n%s\n' "$out" "$local_out")
fi
out=$(printf '%s\n' "$out" | sed '/^$/d')

if [ -z "$out" ]; then
  echo "ref-check: no references in $file"
  exit 0
fi
echo "ref-check: every reference in $file, looked up:"
printf '%s\n' "$out"
if printf '%s\n' "$out" | grep -q 'NOT FOUND'; then
  echo
  echo "ref-check: a reference points at nothing; fix it or drop it."
  exit 1
fi
exit 0
