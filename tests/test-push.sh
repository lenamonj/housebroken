#!/bin/bash
# test-push.sh - push.sh refuses a head with no branch-check stamp or no
# POST AS IS review, a second push to the branch within thirty minutes, and a
# push that rewrites the branch unless --rework says why; a reviewed
# fast-forward goes. Local only: the "fork" is a bare repository beside the
# clone, and every push is a dry run or goes to that bare repository.
# shellcheck disable=SC2015  # "a && b || fail": fail exits, so it is the if-then-else it reads as
set -u
name=test-push
here=$(cd "$(dirname "$0")" && pwd)
script="$here/../scripts/push.sh"
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
export HOUSEBROKEN_HOME="$root/home"
G="git -c user.email=t@example.com -c user.name=t -c commit.gpgsign=false"

fail() { echo "FAIL $name: $1" >&2; exit 1; }
sha() { (sha256sum "$1" 2>/dev/null || shasum -a 256 "$1") | awk '{print $1}'; }

bash "$script" --help | grep -q "Usage:" || fail "--help printed no usage"

git init -q --bare "$root/fork.git"
mkdir -p "$root/clone" && cd "$root/clone" || fail "fixture failed"
$G init -q -b fix . && printf 'a\n' > a.txt && $G add -A && $G commit -q -m one || fail "fixture failed"
git remote add origin "$root/fork.git" && git push -q origin fix || fail "fixture failed"
printf 'b\n' >> a.txt && $G commit -q -am two || fail "fixture failed"

ready() { # stamp and review the current head
  local head; head=$(git rev-parse HEAD)
  mkdir -p "$HOUSEBROKEN_HOME/branch-checks" "$HOUSEBROKEN_HOME/reviews"
  printf 'head: %s\n' "$head" > "$HOUSEBROKEN_HOME/branch-checks/$head"
  printf 'diff --git a/a.txt b/a.txt\n--- a/a.txt\n+++ b/a.txt\n@@ -1 +1 @@\n-a\n+c\n' > "$root/blind.diff"
  printf 'review-of: o/r\nhead: %s\nauthor-model: opus\nreviewer-model: fable\nblind-fix: %s\nskipped: none\nverdict: POST AS IS\n\n1. NIT: fine.\n' \
    "$head" "$root/blind.diff" > "$HOUSEBROKEN_HOME/reviews/review-o-r-${head:0:12}.md"
}

out=$(bash "$script" o/r . 2>&1) && fail "a head with no stamp was pushed"
printf '%s' "$out" | grep -q "branch-check.sh has not passed" || fail "the missing stamp was not named: $out"
ready
rm "$HOUSEBROKEN_HOME/reviews/"*
out=$(bash "$script" o/r . 2>&1) && fail "a head with no review was pushed"
ready
# a remote that cannot be read, or that has no such branch, is a refusal, not a plain push
git remote add upstream "$root/upstream.git" && git init -q --bare "$root/upstream.git"
out=$(bash "$script" o/r . --remote upstream 2>&1) && fail "a push to a remote without the branch went"
printf '%s' "$out" | grep -q "cannot read fix on upstream" || fail "the unreadable remote was not named: $out"
[ -z "$(git -C "$root/upstream.git" for-each-ref)" ] || fail "the refused push reached upstream"
out=$(bash "$script" o/r . --remote nosuch 2>&1) && fail "a push to a remote that does not exist went"
out=$(bash "$script" o/r . 2>&1) || fail "a reviewed fast-forward was refused: $out"
[ "$(git -C "$root/fork.git" rev-parse fix)" = "$(git rev-parse HEAD)" ] || fail "the push did not reach the fork"
log=$(ls "$HOUSEBROKEN_HOME/pushes/"*)
printf '%s x old\n' "$(( $(date -u +%s) - 2000 ))" > "$log"
out=$(bash "$script" o/r . 2>&1) && fail "a push of a head already on the fork went"
printf '%s' "$out" | grep -q "nothing to push" || fail "the empty push was not named: $out"

# a second push inside thirty minutes
printf 'c\n' >> a.txt && $G commit -q -am three && ready
printf '%s x recent\n' "$(date -u +%s)" > "$log"
out=$(bash "$script" o/r . 2>&1) && fail "a second push within thirty minutes went"
printf '%s' "$out" | grep -q "push once, in 30 min" || fail "the spacing refusal did not say why or how long: $out"
printf '%s x old\n' "$(( $(date -u +%s) - 2000 ))" > "$log"

# a rewrite of the branch needs a reason
$G reset -q --hard HEAD~1 && $G commit -q --amend -m "two, reworded" && ready
out=$(PUSH_DRY=1 bash "$script" o/r . 2>&1) && fail "a rewrite without --rework went"
printf '%s' "$out" | grep -q "rewrites fix on origin" || fail "the rewrite refusal did not say why: $out"
out=$(PUSH_DRY=1 bash "$script" o/r . --rework "the maintainer asked for one commit" 2>&1) || fail "a rewrite with --rework was refused: $out"
printf '%s' "$out" | grep -q -- "--force-with-lease=fix:" || fail "the rewrite was not a lease-guarded force: $out"

echo "PASS $name"
