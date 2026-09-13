#!/bin/bash
# branch-check.sh - the mechanical facts about the branch you are about to file.
#
# What you tested is what you file, and the branch carries nothing the project
# did not ask for. Refused: a dirty working tree; a file whose mode disagrees
# with its own siblings; a file the branch adds that the repository's own
# .gitignore excludes; a working artifact; a commit carrying a tool trailer, a
# session link or a tool identity; a sign-off naming a username; a branch that
# is not on top of its base; and a comment added to code, test files included,
# unless a maintainer asked for it (comment-check.sh). Absolute claims in added
# prose are printed for you to falsify one by one; some of them are true.
#
# A branch that passes gets a stamp at $HOUSEBROKEN_HOME/branch-checks/<head>,
# which file-pr.sh requires for the head it files.
#
# Usage:
#   bash branch-check.sh [CLONE] [--base REF] [--asked URL]
#   bash branch-check.sh --help
#
# CLONE defaults to the current directory. REF defaults to the first of
# upstream/main, upstream/master, origin/main, origin/master that resolves.
# --asked URL is the maintainer's request for documentation, which turns the
# comment refusal into a check.
#
# Exits 0 when nothing blocks, 1 on a refusal, 2 on a usage error.
set -u

usage() { awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"; }

here=$(cd "$(dirname "$0")" && pwd)
home="${HOUSEBROKEN_HOME:-$HOME/.housebroken}"
clone="."
base=""
asked=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --base)
      shift
      base="${1:-}"
      [ -n "$base" ] || { echo "REFUSED: --base needs a ref" >&2; exit 2; }
      ;;
    --base=*) base="${1#--base=}" ;;
    --asked)
      shift
      asked="${1:-}"
      [ -n "$asked" ] || { echo "REFUSED: --asked needs the URL of the maintainer's ask" >&2; exit 2; }
      ;;
    --asked=*) asked="${1#--asked=}" ;;
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
# Trailers are matched at the start of a line and a tool by its commit
# identity, so a subject that only names a trailer is not refused.
trailers=$(git log --format='%h author %an <%ae>, committer %cn <%ce>%n%b' "$base..HEAD" 2>/dev/null \
  | grep -iE '^co-authored-by:.*(claude|anthropic|copilot|cursor|aider|codex|gemini)|^claude-session:|claude\.ai/code/session_|generated with .*claude|noreply@anthropic\.com|cursoragent@cursor\.com|noreply@aider\.chat')
if [ -n "$trailers" ]; then
  block "a commit carries a tool trailer or a session link, or a tool identity, which no project asked for"
  printf '%s\n' "$trailers" | sed 's/^/    /'
fi

# DCO wants a human being. A one-word name is taken for a username whatever
# its case; a real one-word name is refused as well, which is the price of
# catching them.
usernames=$(git log --format='%b' "$base..HEAD" 2>/dev/null | grep -E '^Signed-off-by: [^ <]+ <')
if [ -n "$usernames" ]; then
  block "a Signed-off-by names a username; the DCO asks for a real name"
  printf '%s\n' "$usernames" | sed 's/^/    /'
fi

# A comment added to somebody else's code is refused unless its maintainer
# asked for it; a reworded comment and a new file's opening header pass.
comment_args=(--base "$base")
[ -n "$asked" ] && comment_args+=(--asked "$asked")
comments=$(bash "$here/comment-check.sh" . "${comment_args[@]}" 2>&1); comment_rc=$?
case "$comment_rc" in
  0) ;;
  1) block "the branch adds comments to code that nobody asked for"
     printf '%s\n' "$comments" | grep -E '^(REFUSED|CHECK): ' | sed 's/^REFUSED: /    /' ;;
  *) block "comment-check.sh could not run: $comments" ;;
esac
printf '%s\n' "$comments" | grep -E '^CHECK: ' | sed 's/^/    /'

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
# The stamp file-pr.sh reads: this head passed, against this base, at this time.
head=$(git rev-parse HEAD)
mkdir -p "$home/branch-checks"
printf 'head: %s\nbase: %s\nchecked: %s\n' "$head" "$(git rev-parse "$base")" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$home/branch-checks/$head"
echo
echo "branch-check: nothing mechanical blocks this branch."
