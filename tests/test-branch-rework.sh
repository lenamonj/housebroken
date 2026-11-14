#!/bin/bash
# test-branch-rework.sh - a rework on an open, mergeable pull request keeps its
# base (#24): behind the base, --rework URL turns the refusal into a CHECK only
# when GitHub says the pull request is open, is this branch into this base, and
# merges cleanly. Every other answer refuses by its own name. A head that is
# behind is measured from the merge base, so upstream's newer code is never read
# as the branch's. gh is a stub serving the API's JSON. Local git only.
set -u
name=test-branch-rework
script="$(cd "$(dirname "$0")/../scripts" && pwd)/branch-check.sh"
root=$(mktemp -d) || exit 1
trap 'rm -rf "$root"' EXIT
fail() { echo "FAIL $name: $1" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP $name: jq is not installed"; exit 0; }

HOUSEBROKEN_HOME="$root/hbhome"
export HOUSEBROKEN_HOME
G="git -c user.email=t@example.com -c user.name=t -c core.autocrlf=false"

# The stub answers `gh pr view URL --json ...` with $PR_JSON, or fails when it
# is empty, and logs what it was asked.
mkdir -p "$root/bin"
cat > "$root/bin/gh" <<'EOF'
#!/bin/bash
echo "$*" >> "$GH_LOG"
case "$*" in
  "pr view https://github.com/up/proj/pull/7 --json "*) [ -n "${PR_JSON:-}" ] || exit 1; printf '%s\n' "$PR_JSON" ;;
  *) echo "stub gh: no answer for: gh $*" >&2; exit 1 ;;
esac
EOF
chmod +x "$root/bin/gh"
PATH="$root/bin:$PATH"
GH_LOG="$root/gh.log"
export PATH GH_LOG
url=https://github.com/up/proj/pull/7

repo="$root/repo"
mkdir -p "$repo/src" || exit 1
(
  cd "$repo" || exit 1
  $G init -q -b main .
  git init -q --bare "$root/up.git"
  git remote add upstream "$root/up.git"
  # Upstream later drops this suppression; a two-dot read of a head that is
  # behind would call it added by the branch.
  printf 'from m import a  # noqa: E402\n' > src/k.py
  printf 'export const a = 1;\n' > src/a.ts
  $G add -A && $G commit -q -m base
  git push -q upstream main && git fetch -q upstream
  $G checkout -q -b fix
  printf 'export const a = 2;\n' > src/a.ts
  $G add -A && $G commit -q -m "fix a"
  $G checkout -q main
  printf 'x = 1\n' > src/k.py
  $G add -A && $G commit -q -m "upstream moves"
  git push -q upstream main && git fetch -q upstream
  $G checkout -q fix
) || fail "fixture failed"

run() { bash "$script" "$repo" --base upstream/main "$@" 2>&1; }
pushed=$(cd "$repo" && git rev-parse HEAD)
pr() { # state mergeable head base [pushed head]
  PR_JSON=$(printf '{"state":"%s","mergeable":"%s","headRefName":"%s","baseRefName":"%s","headRefOid":"%s"}' "$1" "$2" "$3" "$4" "${5:-$pushed}")
  export PR_JSON
}

# Without --rework a head that is behind is refused, as a first filing must be.
out=$(run); rc=$?
[ "$rc" = 1 ] || fail "a head behind its base without --rework exited $rc: $out"
printf '%s' "$out" | grep -q "branch-check-not-on-base" || fail "the refusal for a head behind its base is gone: $out"

# --rework with no URL is a usage error.
out=$(run --rework); rc=$?
[ "$rc" = 2 ] || fail "--rework with no URL exited $rc: $out"
printf '%s' "$out" | grep -q "branch-check-rework-no-url" || fail "--rework with no URL was not named: $out"

# Open, this branch into this base, mergeable: the rework keeps its base.
pr OPEN MERGEABLE fix main
out=$(run --rework "$url"); rc=$?
[ "$rc" = 0 ] || fail "a mergeable rework exited $rc: $out"
printf '%s' "$out" | grep -q "^CHECK: .*1 commit.* behind upstream/main.*$url" || fail "the head's distance behind is not said: $out"
printf '%s' "$out" | grep -q "branch-check-not-on-base" && fail "a mergeable rework was still refused: $out"
printf '%s' "$out" | grep -q "warning suppression" && fail "upstream's dropped line was read as the branch's: $out"
head=$(cd "$repo" && git rev-parse HEAD)
mb=$(cd "$repo" && git merge-base upstream/main HEAD)
stamp="$HOUSEBROKEN_HOME/branch-checks/$head"
grep -qx "base: $mb" "$stamp" || fail "the stamp does not record the merge base: $(cat "$stamp")"
grep -qx "file: src/a.ts" "$stamp" || fail "the stamp does not list the branch's file: $(cat "$stamp")"
grep -q "src/k.py" "$stamp" && fail "the stamp lists upstream's file as the branch's: $(cat "$stamp")"

# Each other answer refuses by its own name.
refuses() { # id why
  out=$(run --rework "$url"); rc=$?
  [ "$rc" = 1 ] || fail "$2 exited $rc: $out"
  printf '%s' "$out" | grep -q "\[$1\]" || fail "$2 was not refused as $1: $out"
}
pr OPEN CONFLICTING fix main;  refuses branch-check-rework-not-mergeable "a conflicting pull request"
pr OPEN UNKNOWN fix main;      refuses branch-check-rework-not-mergeable "a mergeable state GitHub has not computed"
printf '%s' "$out" | grep -q "run again in a minute" || fail "an UNKNOWN state does not say to wait: $out"
pr CLOSED MERGEABLE fix main;  refuses branch-check-rework-pr-not-open "a closed pull request"
pr MERGED MERGEABLE fix main;  refuses branch-check-rework-pr-not-open "a merged pull request"
pr OPEN MERGEABLE other main;  refuses branch-check-rework-wrong-pr "a pull request of another branch"
pr OPEN MERGEABLE fix develop; refuses branch-check-rework-wrong-pr "a pull request into another base"
PR_JSON=""; export PR_JSON;    refuses branch-check-rework-pr-unreadable "a pull request gh cannot read"
PR_JSON="not json"; export PR_JSON; refuses branch-check-rework-pr-unreadable "an answer that is not JSON"

# --rework=URL is the same option.
pr OPEN MERGEABLE fix main
out=$(run --rework="$url"); rc=$?
[ "$rc" = 0 ] || fail "--rework=URL exited $rc: $out"

# The pull request's pushed head must be in this head: a pull request of
# another project or another line of work with the same branch names is not it.
pr OPEN MERGEABLE fix main "$(cd "$repo" && git rev-parse upstream/main)"
refuses branch-check-rework-not-pr-head "a pull request whose head is not in this one"
pr OPEN MERGEABLE fix main 0123456789abcdef0123456789abcdef01234567
refuses branch-check-rework-not-pr-head "a pull request whose head this clone does not have"

# GitHub's answer is for the pushed head only: the rework's own commits may
# not touch a file upstream changed since the branch point.
(cd "$repo" && printf 'export const a = 3;\n' > src/a.ts && $G add -A && $G commit -q -m "rework a") || fail "rework commit failed"
pr OPEN MERGEABLE fix main
out=$(run --rework "$url"); rc=$?
[ "$rc" = 0 ] || fail "a rework touching only its own files exited $rc: $out"
(cd "$repo" && printf 'x = 2\n' > src/k.py && $G add -A && $G commit -q -m "rework k") || fail "rework commit failed"
refuses branch-check-rework-upstream-overlap "a rework touching a file upstream changed"
printf '%s' "$out" | grep -q "src/k.py" || fail "the overlapping file was not named: $out"
(cd "$repo" && $G reset -q --hard "$pushed") || fail "reset failed"

# A head that shares no history with its base is refused by its own name,
# with or without --rework.
(cd "$repo" && $G checkout -q --orphan lone && $G commit -q -m lone) || fail "orphan commit failed"
out=$(run); rc=$?
[ "$rc" = 1 ] || fail "an orphan head exited $rc: $out"
printf '%s' "$out" | grep -q "\[branch-check-no-shared-history\]" || fail "an orphan head was not named: $out"
pr OPEN MERGEABLE lone main "$(cd "$repo" && git rev-parse HEAD)"
out=$(run --rework "$url"); rc=$?
[ "$rc" = 1 ] || fail "an orphan head with --rework exited $rc: $out"
printf '%s' "$out" | grep -q "\[branch-check-no-shared-history\]" || fail "an orphan head with --rework was not named: $out"
printf '%s' "$out" | grep -q "keeps its base" && fail "an orphan head was said to keep its base: $out"
(cd "$repo" && $G checkout -q -f fix) || fail "checkout failed"

# A head on top of its base needs no pull request read.
(cd "$repo" && $G rebase -q upstream/main) || fail "rebase failed"
: > "$GH_LOG"
pr OPEN CONFLICTING fix main
out=$(run --rework "$url"); rc=$?
[ "$rc" = 0 ] || fail "a head on its base with --rework exited $rc: $out"
[ -s "$GH_LOG" ] && fail "a head on its base read the pull request: $(cat "$GH_LOG")"

echo "PASS $name"
