#!/bin/bash
# proof.sh - run the red-first experiment and stamp what it showed.
#
# "The new test fails on main and passes with the patch" is the claim every
# pull request rests on, and the ledger has five runs that reported it while
# seeing nothing: a worktree whose checkout did nothing, a refused checkout
# that left the patch in place, a soft reset, a filtered count, a test that
# never compiled. This runs the experiment itself. On the clone's head it
# runs the test command; then it swaps every changed file that is not a test
# back to its content at the merge base, by content and checked by hash, so
# the tests stay and the fix goes; runs the command again; and restores the
# head from the commit, checked by hash. The stamp is written only when the
# base arm fails, the head arm passes, and the two arms ran different code.
#
# A change with nothing to prove red, a documentation fix or a refactor
# whose behaviour the existing suite already pins, says so with --none and a
# reason; the stamp records the reason and the filing prints it.
#
# Usage:
#   bash proof.sh [CLONE] --test 'COMMAND' [--base REF] [--keep PATH]...
#                 [--fix PATH]... [--base-file PATH=FILE]...
#   bash proof.sh [CLONE] --none 'REASON'
#   bash proof.sh --help
#
# CLONE defaults to the current directory. REF defaults to the base the
# branch-check stamp for the head names, then to the first of upstream/main,
# upstream/master, origin/main and origin/master that resolves. COMMAND runs
# with bash -c from the clone's top; name the new test in it so the run is
# that test, not the whole suite. A changed file is taken for a test when its
# path says test or spec; --keep PATH keeps another changed file at the head
# in the base arm, such as a fixture the test reads; --fix PATH takes a file
# away although its path says test, such as src/testing/util.go. When one
# file carries both the test and the fix, a Rust module with its #[cfg(test)]
# block, --base-file PATH=FILE puts FILE's content, the base plus the test,
# at PATH in the base arm.
#
# Writes $HOUSEBROKEN_HOME/proofs/<head>, which file-pr.sh requires.
# Exits 0 when the stamp is written, 1 when the experiment does not show the
# fix, 2 on a usage error or when the clone cannot be swapped safely.
set -u

usage() { awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"; }

home="${HOUSEBROKEN_HOME:-$HOME/.housebroken}"
clone="."; cmd=""; none=""; base=""
keeps=(); forces=(); basefiles=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --test) cmd="${2:-}"; [ -n "$cmd" ] || { echo "REFUSED: --test needs the command" >&2; exit 2; }; shift ;;
    --none) none="${2:-}"; [ -n "$none" ] || { echo "REFUSED: --none needs the reason" >&2; exit 2; }; shift ;;
    --base) base="${2:-}"; [ -n "$base" ] || { echo "REFUSED: --base needs a ref" >&2; exit 2; }; shift ;;
    --keep) [ -n "${2:-}" ] || { echo "REFUSED: --keep needs a path" >&2; exit 2; }; keeps+=("$2"); shift ;;
    --fix) [ -n "${2:-}" ] || { echo "REFUSED: --fix needs a path" >&2; exit 2; }; forces+=("$2"); shift ;;
    --base-file)
      case "${2:-}" in ?*=?*) ;; *) echo "REFUSED: --base-file needs PATH=FILE" >&2; exit 2 ;; esac
      [ -f "${2#*=}" ] || { echo "REFUSED: --base-file: ${2#*=} does not exist" >&2; exit 2; }
      basefiles+=("$2"); shift ;;
    -*) echo "REFUSED: unknown option $1" >&2; exit 2 ;;
    *) clone="$1" ;;
  esac
  shift
done
[ -n "$cmd" ] || [ -n "$none" ] || { echo "REFUSED: pass --test 'COMMAND', or --none 'REASON'" >&2; exit 2; }
[ -z "$cmd" ] || [ -z "$none" ] || { echo "REFUSED: --test and --none are exclusive" >&2; exit 2; }
if ! top=$(git -C "$clone" rev-parse --show-toplevel 2>/dev/null) || ! cd "$top"; then
  echo "REFUSED: $clone is not a git clone" >&2
  exit 2
fi
head=$(git rev-parse HEAD)
mkdir -p "$home/proofs"
stamp="$home/proofs/$head"
when=$(date -u +%Y-%m-%dT%H:%M:%SZ)

if [ -n "$none" ]; then
  printf 'head: %s\nproof: none\nreason: %s\nchecked: %s\n' "$head" "$none" "$when" > "$stamp"
  echo "proof: none recorded for ${head:0:12}: $none"
  exit 0
fi

[ -z "$(git status --porcelain)" ] || { echo "REFUSED: the working tree is dirty, so the arms would not be the commits; after a proof run that was killed, git checkout -- . puts the head back" >&2; exit 2; }
[ -n "$base" ] || base=$(sed -n 's/^base-ref: //p' "$home/branch-checks/$head" 2>/dev/null | tr -d '\r')
if [ -z "$base" ]; then
  for candidate in upstream/main upstream/master origin/main origin/master; do
    if git rev-parse --verify -q "$candidate" >/dev/null 2>&1; then base="$candidate"; break; fi
  done
fi
[ -n "$base" ] || { echo "REFUSED: no --base, no branch-check stamp for ${head:0:12} to read it from, and no upstream or origin main or master" >&2; exit 2; }
mb=$(git merge-base "$base" HEAD 2>/dev/null) || { echo "REFUSED: $base and HEAD share no history" >&2; exit 2; }

listed() { local n="$1" k; shift; for k in "$@"; do [ "$n" = "$k" ] && return 0; done; return 1; }
base_file_for() { local e; for e in ${basefiles[@]+"${basefiles[@]}"}; do case "$e" in "$1="*) printf '%s' "${e#*=}"; return 0 ;; esac; done; return 1; }
mode_in() { git ls-tree "$1" -- "$2" | cut -c1-6; }
# Renames are read as the delete and the add they are, so the base arm gets
# the old path back; quotePath off, so a non-ASCII path is the path.
changed=$(git -c core.quotePath=false diff --name-only --no-renames "$mb" HEAD)
for p in ${keeps[@]+"${keeps[@]}"} ${forces[@]+"${forces[@]}"} ${basefiles[@]+"${basefiles[@]%%=*}"}; do
  printf '%s\n' "$changed" | grep -qxF -- "$p" || { echo "REFUSED: $p is not a file this branch changes (paths are as git diff --name-only prints them)" >&2; exit 2; }
done
fixes=(); kept=()
while IFS= read -r f; do
  [ -n "$f" ] || continue
  if listed "$f" ${keeps[@]+"${keeps[@]}"}; then kept+=("$f"); continue; fi
  if ! listed "$f" ${forces[@]+"${forces[@]}"}; then
    case "$f" in *test*|*Test*|*spec*) kept+=("$f"); continue ;; esac
  fi
  for t in HEAD "$mb"; do
    case "$(mode_in "$t" "$f")" in
      100644|100755|"") ;;
      *) echo "REFUSED: $f is not a regular file in $t (a symlink, a submodule or a directory); the experiment swaps regular files only" >&2; exit 2 ;;
    esac
  done
  fixes+=("$f")
done <<EOF
$changed
EOF
if [ "${#fixes[@]}" -eq 0 ]; then
  echo "REFUSED: every changed file is a test or kept (${kept[*]}); there is no fix to take away - --fix PATH takes one away although its path says test" >&2
  exit 2
fi
echo "proof: taking away ${#fixes[@]} file(s): ${fixes[*]}${kept[0]:+; keeping ${#kept[@]} at the head: ${kept[*]}}"

hash_of() { if [ -f "$1" ]; then git hash-object -- "$1"; else echo absent; fi; }
hashes() { local f; for f in "${fixes[@]}"; do printf '%s %s\n' "$(hash_of "$f")" "$f"; done; }
run_arm() { # label -> rc in arm_rc, output tail in arm_out
  arm_out=$(bash -c "$cmd" 2>&1); arm_rc=$?
  arm_out=$(printf '%s\n' "$arm_out" | tail -15)
  echo "== $1 arm: exit $arm_rc"
  printf '%s\n' "$arm_out" | sed 's/^/    /'
}

head_hashes=$(hashes)
run_arm head
head_rc=$arm_rc; head_out=$arm_out

# The base arm: each fix file by its content at the merge base, through the
# clone's own filters so line endings are what a checkout gives, or gone
# when the branch added it. The restore below runs whatever happens in
# between. It restores from the commit, not the index: the tree was clean,
# so the two agree, and the commit brings the mode and the line endings back
# with the content, which a plain write does not.
restore() {
  local f
  for f in "${fixes[@]}"; do
    if git cat-file -e "HEAD:./$f" 2>/dev/null; then
      git checkout -q HEAD -- "$f"
    else
      rm -f -- "$f"
    fi
  done
}
trap restore EXIT
for f in "${fixes[@]}"; do
  if bf=$(base_file_for "$f"); then
    cat "$bf" > "$f"
  elif git cat-file -e "$mb:./$f" 2>/dev/null; then
    mkdir -p "$(dirname "$f")" && git cat-file --filters "$mb:./$f" > "$f"
    [ "$(mode_in "$mb" "$f")" != 100755 ] || chmod +x "$f"
  else
    rm -f -- "$f"
  fi
done
base_hashes=$(hashes)
run_arm base
base_rc=$arm_rc; base_out=$arm_out
restore
trap - EXIT

if [ "$(hashes)" != "$head_hashes" ]; then
  echo "REFUSED: the head did not come back byte for byte; check the clone before anything else:" >&2
  diff <(printf '%s\n' "$head_hashes") <(hashes) | sed 's/^/    /' >&2
  exit 2
fi
dirt=$(git status --porcelain --untracked-files=no)
if [ -n "$dirt" ]; then
  echo "REFUSED: the test command changed tracked files; restore them with git checkout -- <path>, then make the command leave the tree alone or commit what it generates:" >&2
  printf '%s\n' "$dirt" | sed 's/^/    /' >&2
  exit 2
fi
left=$(git status --porcelain | sed -n 's/^?? //p')
[ -z "$left" ] || echo "note: the test command left untracked files, which branch-check refuses: $(printf '%s' "$left" | tr '\n' ' ')"

failed=""
[ "$base_hashes" != "$head_hashes" ] || failed="the two arms ran the same files, so they did not test the fix"
case "$base_rc" in
  126|127) failed="${failed:+$failed; }the base arm's command did not run (exit $base_rc: $(printf '%s' "$base_out" | head -1)); a test named in the command has to exist in both arms" ;;
  0) failed="${failed:+$failed; }the test passes without the fix, so it does not show the bug${kept[0]:+ (or the fix is in a kept file: ${kept[*]})}" ;;
esac
[ "$head_rc" -eq 0 ] || failed="${failed:+$failed; }the test fails with the fix"
if [ -n "$failed" ]; then
  echo "proof: not shown - $failed"
  exit 1
fi

{
  printf 'head: %s\nbase: %s\nproof: red-green\ncommand: %s\nchecked: %s\n' "$head" "$mb" "$cmd" "$when"
  printf 'base-exit: %s\nhead-exit: %s\n' "$base_rc" "$head_rc"
  printf '%s\n' "$head_hashes" | sed 's/^/head-file: /'
  printf '%s\n' "$base_hashes" | sed 's/^/base-file: /'
  for f in ${kept[@]+"${kept[@]}"}; do printf 'kept-file: %s\n' "$f"; done
  for e in ${basefiles[@]+"${basefiles[@]}"}; do printf 'base-from: %s\n' "$e"; done
  printf 'base-output:\n%s\nhead-output:\n%s\n' "$(printf '%s\n' "$base_out" | sed 's/^/    /')" "$(printf '%s\n' "$head_out" | sed 's/^/    /')"
} > "$stamp"
echo "proof: red on the base, green on the head, for ${head:0:12}; stamped at $stamp"
