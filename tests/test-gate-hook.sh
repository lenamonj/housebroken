#!/bin/bash
# test-gate-hook.sh - the Claude Code hook refuses a Bash command that writes
# to GitHub outside the gates (exit 2, with the reason) and lets reads, the
# gates themselves, releases, plain pushes and text that only mentions a
# write run (exit 0). --install copies the hook and prints the settings
# entry. Local only: the hook never runs the commands it reads.
set -u
name=test-gate-hook
here=$(cd "$(dirname "$0")" && pwd)
script="$here/../scripts/gate-hook.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail() { echo "FAIL $name: $1" >&2; exit 1; }

bash "$script" --help | grep -q "Usage:" || fail "--help printed no usage"

export HOUSEBROKEN_HOME="$tmp/home"
hook() { # expected-exit command
  local got
  printf '%s' "$2" | jq -Rs --arg cwd "$tmp/own-clone" '{tool_name: "Bash", tool_input: {command: .}, cwd: $cwd}' | bash "$script" 2>"$tmp/err"
  got=$?
  [ "$got" = "$1" ] || fail "exit $got, expected $1, for: $2"
  if [ "$1" = 2 ]; then grep -q "^housebroken: refused: " "$tmp/err" || fail "no reason given for: $2"; fi
}

hook 2 'gh pr create -R a/b --title x --body y'
hook 2 'cd clone && gh pr comment 5 -R a/b --body hi'
hook 2 'GH_TOKEN=x gh issue create -R a/b --title t'
hook 2 'gh pr merge 5 -R a/b --squash'
hook 2 'gh pr update-branch 5 -R a/b'
# shellcheck disable=SC2016  # the command is text for the hook, never run
hook 2 'x=$(gh pr review 5 -R a/b --approve)'
# shellcheck disable=SC2016
hook 2 'for n in 1 2 3; do gh pr comment $n -R a/b --body hi; done'
hook 2 '{ gh pr create -R a/b --title x; }'
hook 2 'gh api -X POST repos/a/b/issues/1/comments -f body=x'
hook 2 'gh api --method PATCH repos/a/b/pulls/1 -f title=x'
hook 2 'gh api repos/a/b/issues/1/comments -f body=x'
hook 2 "gh api graphql -f query='mutation { addComment(input: {subjectId: \"x\", body: \"y\"}) { clientMutationId } }'"
hook 2 'git push --force origin fix'
hook 2 'git push -f origin fix'
hook 2 'git push -fu origin fix'
hook 2 'git push origin +fix'
hook 2 'git push origin :fix'
hook 2 'git push --delete origin fix'
hook 2 'git -C clone push --force-with-lease=fix:abc origin fix'

hook 0 'gh api -X GET search/issues -f q=x'
hook 0 'gh api repos/a/b/pulls/1'
hook 0 "gh api graphql -f query='query { repository(owner: \"a\", name: \"b\") { id } }'"
hook 0 'gh pr view 5 -R a/b --json body'
hook 0 'gh pr list -R a/b --author @me'
hook 0 'gh run rerun 1 -R a/b'
hook 0 'git commit -m "open it later with gh pr create"'
hook 0 $'cat > door.md <<\'EOF\'\ngh pr create is refused by the hook.\ngit push --force is never run by the agent.\nEOF'
hook 0 'git push origin main'
hook 0 'git push -u origin fix'
hook 0 'gh release create v1 --notes-file n.md'
hook 0 'housebroken file a/b --title t --body-file b.md'
hook 0 'housebroken reply a/b 5 --body-file r.md'
printf '{"tool_name": "Read", "tool_input": {"file_path": "x"}}' | bash "$script" || fail "a non-Bash call was refused"

# your own repositories pass once their owner is listed; a fork does not make a forced push yours
hook 2 'gh pr create -R acme/widgets --title x --body y'
mkdir -p "$HOUSEBROKEN_HOME" && printf 'acme\n' > "$HOUSEBROKEN_HOME/own"
hook 0 'gh pr create -R acme/widgets --title x --body y'
hook 0 'gh api repos/acme/widgets/issues/1/comments -f body=x'
hook 2 'gh pr create -R other/widgets --title x --body y'
grep -q "listed in $HOUSEBROKEN_HOME/own" "$tmp/err" || fail "the refusal did not name the own file"
# a fork's clone names you as origin while gh writes to the upstream parent,
# so only a repository the command names counts
git init -q "$tmp/own-clone" && git -C "$tmp/own-clone" remote add origin https://github.com/acme/widgets.git
hook 2 'gh pr create --title x --body y'
hook 2 'git push --force origin fix'

# without jq a write is refused unparsed, and anything else runs
mkdir -p "$tmp/nojq"
printf '{"tool_input": {"command": "gh pr create"}}' | PATH="$tmp/nojq" "$BASH" "$script" 2>"$tmp/err"
[ "$?" = 2 ] || fail "a write with jq missing was not refused"
grep -q "jq is not on PATH" "$tmp/err" || fail "a missing jq was not named"
printf '{"tool_input": {"command": "ls -la"}}' | PATH="$tmp/nojq" "$BASH" "$script" 2>/dev/null || fail "a read with jq missing was refused"

HOME="$tmp" bash "$script" --install > "$tmp/out" || fail "--install failed"
[ -f "$tmp/.claude/hooks/housebroken-gate.sh" ] || fail "--install wrote no hook"
grep -q '"matcher": "Bash"' "$tmp/out" || fail "--install printed no settings entry"

echo "PASS $name"
