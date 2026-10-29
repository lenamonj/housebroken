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
# head by content, checked by hash. The stamp is written only when the base
# arm fails, the head arm passes, and the two arms ran different code.
#
# A change with nothing to prove red, a documentation fix or a refactor
# whose behaviour the existing suite already pins, says so with --none and a
# reason; the stamp records the reason and the filing prints it.
#
# Usage:
#   bash proof.sh [CLONE] --test 'COMMAND' [--base REF] [--keep PATH]...
#   bash proof.sh [CLONE] --none 'REASON'
#   bash proof.sh --help
#
# CLONE defaults to the current directory, REF to the base the branch-check
# stamp for the head names. COMMAND runs with bash -c from the clone's top;
# name the new test in it so the run is that test, not the whole suite. A
# changed file is taken for a test when its path says test or spec; --keep
# PATH keeps another changed file at the head in the base arm, such as a
# fixture the test reads.
#
# Writes $HOUSEBROKEN_HOME/proofs/<head>, which file-pr.sh requires.
# Exits 0 when the stamp is written, 1 when the experiment does not show the
# fix, 2 on a usage error or when the clone cannot be swapped safely.
set -u

usage() { awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"; }

home="${HOUSEBROKEN_HOME:-$HOME/.housebroken}"
clone="."; cmd=""; none=""; base=""
keeps=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --test) cmd="${2:-}"; [ -n "$cmd" ] || { echo "REFUSED: --test needs the command" >&2; exit 2; }; shift ;;
    --none) none="${2:-}"; [ -n "$none" ] || { echo "REFUSED: --none needs the reason" >&2; exit 2; }; shift ;;
    --base) base="${2:-}"; [ -n "$base" ] || { echo "REFUSED: --base needs a ref" >&2; exit 2; }; shift ;;
    --keep) [ -n "${2:-}" ] || { echo "REFUSED: --keep needs a path" >&2; exit 2; }; keeps+=("$2"); shift ;;
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

[ -z "$(git status --porcelain)" ] || { echo "REFUSED: the working tree is dirty; the arms would not be the commits" >&2; exit 2; }
if [ -z "$base" ]; then
  base=$(sed -n 's/^base-ref: //p' "$home/branch-checks/$head" 2>/dev/null | tr -d '\r')
  [ -n "$base" ] || { echo "REFUSED: no --base and no branch-check stamp for ${head:0:12} to read it from" >&2; exit 2; }
fi
mb=$(git merge-base "$base" HEAD 2>/dev/null) || { echo "REFUSED: $base and HEAD share no history" >&2; exit 2; }

kept() { local k; for k in ${keeps[@]+"${keeps[@]}"}; do [ "$1" = "$k" ] && return 0; done; return 1; }
fixes=()
while IFS= read -r f; do
  [ -n "$f" ] || continue
  case "$f" in *test*|*Test*|*spec*) continue ;; esac
  kept "$f" && continue
  fixes+=("$f")
done <<EOF
$(git diff --name-only "$mb" HEAD)
EOF
[ "${#fixes[@]}" -gt 0 ] || { echo "REFUSED: every changed file is a test or kept; there is no fix to take away" >&2; exit 2; }

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

# The base arm: each fix file by its content at the merge base, or gone when
# the branch added it. The restore below runs whatever happens in between.
restore() {
  local f
  for f in "${fixes[@]}"; do
    if git cat-file -e "HEAD:./$f" 2>/dev/null; then
      mkdir -p "$(dirname "$f")" && git show "HEAD:./$f" > "$f"
    else
      rm -f -- "$f"
    fi
  done
}
trap restore EXIT
for f in "${fixes[@]}"; do
  if [ -n "$(git ls-tree --name-only "$mb" -- "$f")" ]; then
    git show "$mb:./$f" > "$f"
  else
    rm -f -- "$f"
  fi
done
base_hashes=$(hashes)
run_arm base
base_rc=$arm_rc; base_out=$arm_out
restore
trap - EXIT

failed=""
if [ "$(hashes)" != "$head_hashes" ] || [ -n "$(git status --porcelain)" ]; then
  echo "REFUSED: the head did not come back byte for byte; check the clone before anything else" >&2
  exit 2
fi
[ "$base_hashes" != "$head_hashes" ] || failed="the two arms ran the same files, so they did not test the fix"
[ "$base_rc" -ne 0 ] || failed="${failed:+$failed; }the test passes without the fix, so it does not show the bug"
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
  printf 'base-output:\n%s\nhead-output:\n%s\n' "$(printf '%s\n' "$base_out" | sed 's/^/    /')" "$(printf '%s\n' "$head_out" | sed 's/^/    /')"
} > "$stamp"
echo "proof: red on the base, green on the head, for ${head:0:12}; stamped at $stamp"
