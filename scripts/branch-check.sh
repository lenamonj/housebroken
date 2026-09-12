#!/bin/bash
# branch-check.sh - the mechanical facts about the branch you are about to file.
#
# Three defects on PaloAltoNetworks/docusaurus-openapi-docs #1624 were facts
# about the branch rather than about the patch, and git could have printed all
# three before anything left the machine.
#
# A reviewer had just shown that a sentence in the added documentation
# overclaimed. The wording was corrected in the working tree, the branch was
# rebuilt with `git reset --soft <base>`, and the commits still carried the old
# sentence: a soft reset leaves the index at the previous commit, so the
# corrected file was never staged. The tree was dirty and nobody looked. A
# dirty tree is a refusal here, because what you tested is not what you file.
#
# The new test file was committed 100755 where every other test in that
# repository is 100644, which GitHub renders in the diff. A mode that disagrees
# with the file's own siblings is a refusal.
#
# The overclaiming sentence was an absolute: "removes only the files the plugin
# generated", which the code falsifies for two file names. Absolutes in added
# prose are printed for you to check one by one; they are not refused, because
# some of them are true.
#
# Usage:
#   bash branch-check.sh [CLONE] [--base REF]
#   bash branch-check.sh --help
#
# CLONE defaults to the current directory. REF defaults to the first of
# upstream/main, upstream/master, origin/main, origin/master that resolves.
#
# Exits 0 when nothing blocks, 1 on a refusal, 2 on a usage error.
set -u

usage() { awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"; }

clone="."
base=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --base)
      shift
      base="${1:-}"
      [ -n "$base" ] || { echo "REFUSED: --base needs a ref" >&2; exit 2; }
      ;;
    -*) echo "REFUSED: unknown option $1" >&2; exit 2 ;;
    *) clone="$1" ;;
  esac
  shift
done

cd "$clone" 2>/dev/null || { echo "REFUSED: $clone is not a directory" >&2; exit 2; }
git rev-parse --git-dir >/dev/null 2>&1 || { echo "REFUSED: $clone is not a git clone" >&2; exit 2; }

if [ -z "$base" ]; then
  for candidate in upstream/main upstream/master origin/main origin/master; do
    if git rev-parse --verify -q "$candidate" >/dev/null 2>&1; then base="$candidate"; break; fi
  done
fi
[ -n "$base" ] || { echo "REFUSED: no base ref resolved - pass --base REF" >&2; exit 2; }
git rev-parse --verify -q "$base" >/dev/null 2>&1 || { echo "REFUSED: base $base does not resolve" >&2; exit 2; }

blocked=0
block() { echo "REFUSED: $*"; blocked=1; }

echo "== branch check: $(git rev-parse --abbrev-ref HEAD) against $base =="

# What you tested is what you file, or you do not know what you are filing.
dirty=$(git status --porcelain)
if [ -n "$dirty" ]; then
  block "the working tree is dirty, so the commits are not what you tested"
  printf '%s\n' "$dirty" | sed 's/^/    /'
fi

if ! git merge-base --is-ancestor "$base" HEAD 2>/dev/null; then
  block "HEAD is not on top of $base - rebase before filing"
fi

files=$(git diff --name-only "$base..HEAD" 2>/dev/null)
if [ -z "$files" ]; then
  block "no files differ from $base - there is nothing to file"
fi

while IFS= read -r f; do
  [ -n "$f" ] || continue
  entry=$(git ls-files -s -- "$f" 2>/dev/null)
  [ -n "$entry" ] || continue
  mode=$(printf '%s\n' "$entry" | awk '{print $1}')

  # A mode is only wrong relative to the file's own neighbours.
  if [ "$mode" = "100755" ]; then
    case "$f" in
      *.*) ext=".${f##*.}" ;;
      *) ext="" ;;
    esac
    if [ -n "$ext" ]; then
      sibs=$(git ls-files -s -- "*$ext" 2>/dev/null | awk -v self="$f" '$4 != self {print $1}')
      norm=$(printf '%s\n' "$sibs" | grep -c '^100644$')
      exec=$(printf '%s\n' "$sibs" | grep -c '^100755$')
      if [ "$norm" -gt "$exec" ]; then
        block "$f is committed 100755 but $norm of its $ext siblings are 100644"
      fi
    fi
  fi

  # The repository's own .gitignore is the authority on what is build output,
  # but only for a file this branch adds. Ignore rules never apply to a file the
  # project already tracks, which is why check-ignore skips tracked files unless
  # forced. NVIDIA/go-nvml ignores "dl" for a built binary, and that pattern also
  # matches the directory pkg/dl, so forcing the check called two upstream source
  # files build output.
  if ! git cat-file -e "$base:$f" 2>/dev/null; then
    if git check-ignore -q --no-index -- "$f" 2>/dev/null; then
      block "$f is added by this branch and the repository's .gitignore excludes it"
    fi
  fi

  case "$f" in
    .jeffy/*|*/.jeffy/*|PLAN.md|*/PLAN.md|JOURNAL.md|*/JOURNAL.md|*.orig|*.rej)
      block "$f is a working artifact and has no place in the diff" ;;
  esac
done <<EOF
$files
EOF

# A tool trailer is the one thing in a commit that cannot be argued as style.
# Thirteen open pull requests across ten organisations were found carrying
# "Co-Authored-By: Claude ..." and four of them a live claude.ai session URL,
# on NVIDIA, Microsoft, Apple, Uber, Tesla, Apache and IBM repositories. No
# project asked for it; a harness adds it by default and nobody read the commit
# before pushing. The body is checked for this at step 9; the commits were not.
trailers=$(git log --format='%H %s%n%b' "$base..HEAD" 2>/dev/null \
  | grep -inE 'Co-Authored-By: *Claude|Claude-Session:|https://claude\.ai/code|Generated with .*Claude')
if [ -n "$trailers" ]; then
  block "a commit carries a tool trailer or a session link, which no project asked for"
  printf '%s\n' "$trailers" | sed 's/^/    /'
fi

# DCO wants a human being, and several projects say so in as many words.
if git log --format='%b' "$base..HEAD" 2>/dev/null | grep -qE '^Signed-off-by:'; then
  usernames=$(git log --format='%b' "$base..HEAD" 2>/dev/null | grep -E '^Signed-off-by: [a-z0-9_-]+ <')
  if [ -n "$usernames" ]; then
    block "a Signed-off-by names a username; the DCO asks for a real name"
    printf '%s\n' "$usernames" | sed 's/^/    /'
  fi
fi

# Absolutes in added prose are the claims a maintainer can falsify in one grep.
claims=$(git diff -U0 "$base..HEAD" -- '*.md' '*.mdx' '*.rst' '*.txt' 2>/dev/null \
  | grep '^+' | grep -v '^+++' | sed 's/^+//' \
  | grep -nEi '\b(only|exactly|always|never|guaranteed|nothing|everything)\b')
if [ -n "$claims" ]; then
  echo "CHECK: added prose makes absolute claims - falsify each one against the code:"
  printf '%s\n' "$claims" | sed 's/^/    /'
fi

echo
echo "commits:"
git log --oneline "$base..HEAD" | sed 's/^/    /'
echo "diff (against the merge base, which is what the maintainer sees):"
git diff --stat "$(git merge-base "$base" HEAD)..HEAD" | sed 's/^/    /'

if [ "$blocked" -ne 0 ]; then
  echo
  echo "branch-check: refused. Fix the causes above; a refusal is a result."
  exit 1
fi
echo
echo "branch-check: nothing mechanical blocks this branch."
