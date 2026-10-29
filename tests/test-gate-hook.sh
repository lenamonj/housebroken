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

hook() { # expected-exit command
  local got
  printf '%s' "$2" | jq -Rs '{tool_name: "Bash", tool_input: {command: .}}' | bash "$script" 2>"$tmp/err"
  got=$?
  [ "$got" = "$1" ] || fail "exit $got, expected $1, for: $2"
  if [ "$1" = 2 ]; then grep -q "^housebroken: refused: " "$tmp/err" || fail "no reason given for: $2"; fi
}

hook 2 'gh pr create -R a/b --title x --body y'
hook 2 'cd clone && gh pr comment 5 -R a/b --body hi'
hook 2 'GH_TOKEN=x gh issue create -R a/b --title t'
hook 2 'gh pr merge 5 -R a/b --squash'
# shellcheck disable=SC2016  # the command is text for the hook, never run
hook 2 'x=$(gh pr review 5 -R a/b --approve)'
hook 2 'gh api -X POST repos/a/b/issues/1/comments -f body=x'
hook 2 'gh api --method PATCH repos/a/b/pulls/1 -f title=x'
hook 2 'gh api repos/a/b/issues/1/comments -f body=x'
hook 2 'git push --force origin fix'
hook 2 'git push -f origin fix'
hook 2 'git push origin +fix'

hook 0 'gh api -X GET search/issues -f q=x'
hook 0 'gh api repos/a/b/pulls/1'
hook 0 'gh pr view 5 -R a/b --json body'
hook 0 'gh pr list -R a/b --author @me'
hook 0 'git commit -m "open it later with gh pr create"'
hook 0 'git push origin main'
hook 0 'gh release create v1 --notes-file n.md'
hook 0 'housebroken file a/b --title t --body-file b.md'
hook 0 'housebroken reply a/b 5 --body-file r.md'
printf '{"tool_name": "Read", "tool_input": {"file_path": "x"}}' | bash "$script" || fail "a non-Bash call was refused"

HOME="$tmp" bash "$script" --install > "$tmp/out" || fail "--install failed"
[ -f "$tmp/.claude/hooks/housebroken-gate.sh" ] || fail "--install wrote no hook"
grep -q '"matcher": "Bash"' "$tmp/out" || fail "--install printed no settings entry"

echo "PASS $name"
