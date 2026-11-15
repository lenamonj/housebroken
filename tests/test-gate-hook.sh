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
# git's own options before the verb do not hide the push, and --prune deletes
hook 2 'git --no-pager push -f origin fix'
hook 2 'git -c push.default=current push --force origin fix'
hook 2 'git --git-dir=/x/.git push -f origin fix'
hook 2 'git --git-dir /x/.git --work-tree /x push -f origin fix'
hook 2 'git -C clone --no-pager push -f origin fix'
hook 2 'git push --prune origin'
hook 0 'git --no-pager push origin fix'
hook 0 'git --no-pager log -f'
hook 0 'git -c core.pager=cat diff --force'

# a wrapper that runs the command, gh by a path, and gh.exe are the same write
hook 2 'timeout 60 gh pr create -R a/b --title x'
hook 2 'timeout -k 5 60s gh pr comment 5 -R a/b --body hi'
hook 2 'nohup gh pr comment 5 -R a/b --body hi'
hook 2 'env GH_TOKEN=x gh pr create -R a/b --title x'
hook 2 'env -u GH_HOST gh issue create -R a/b --title t'
hook 2 'sudo -E gh pr merge 5 -R a/b'
hook 2 'nice -n 5 timeout 30 gh pr close 5 -R a/b'
hook 2 'gh.exe pr create -R a/b --title x'
hook 2 '/usr/bin/gh pr create -R a/b --title x'
hook 2 'C:/tools/gh.exe api -X POST repos/a/b/issues/1/comments'
hook 2 'timeout 60 git push --force origin fix'
hook 2 '/usr/bin/git push -f origin fix'
hook 0 'timeout 60 gh pr view 5 -R a/b'
hook 0 'env GH_TOKEN=x gh pr checks 5 -R a/b'
hook 0 'sudo apt-get install gh'
hook 0 'timeout 60 git push origin fix'
hook 0 'echo timeout 60 gh pr create'
hook 0 'ls /usr/bin/gh pr create'
hook 2 'stdbuf -oL gh pr create -R a/b --title x'
hook 2 'winpty gh pr create -R a/b --title x'
hook 2 'setsid gh pr comment 5 -R a/b --body hi'
hook 2 'ionice -c3 gh pr merge 5 -R a/b'
hook 2 'doas gh pr close 5 -R a/b'
hook 2 'command -p gh pr create -R a/b --title x'
hook 2 'exec -a x gh pr create -R a/b --title x'
hook 2 'time -p gh pr create -R a/b --title x'
hook 2 'git.exe push -f origin fix'
hook 2 'GH.EXE pr create -R a/b --title x'
hook 2 'Git push -f origin fix'
hook 2 'C:\tools\gh.exe pr create -R a/b --title x'
hook 2 '/c/Program\ Files/GitHub\ CLI/gh.exe pr create -R a/b --title x'
hook 2 'C:\tools\git.exe push --force origin fix'
# a variable holding a path is not gh, and nor is a command a wrapper only names
hook 0 'x=/opt/gh pr create'
hook 0 'command -v gh'
hook 0 'time -p gh pr view 5 -R a/b'
hook 0 'winpty gh pr checks 5 -R a/b'

# every verb the hook names, on both nouns, and every writing method
for verb in create comment review edit close merge ready reopen update-branch lock unlock revert; do
  hook 2 "gh pr $verb 5 -R a/b"
done
for verb in create comment edit close reopen delete transfer lock unlock pin unpin; do
  hook 2 "gh issue $verb 5 -R a/b"
done
for verb in view list status checks diff checkout; do
  hook 0 "gh pr $verb 5 -R a/b"
done
for verb in view list status; do
  hook 0 "gh issue $verb 5 -R a/b"
done
for method in POST PATCH PUT DELETE; do
  hook 2 "gh api -X $method repos/a/b/x"
done

# a write beside a read is still a write: each command is judged by itself
hook 2 'gh api repos/a/b/pulls/1 --jq .head.sha && git push --force origin fix'
hook 2 "gh api graphql -f query='query { viewer { login } }' && gh api -X POST repos/a/b/issues/1/comments -f body=x"
hook 2 'gh api -X GET search/issues -f q=x && gh api repos/a/b/issues/1/comments -f body=hi'

# ordinary spellings of a write
hook 2 'gh pr -R a/b create --title x --body y'
# shellcheck disable=SC2016
hook 2 'x=`gh pr review 5 -R a/b --approve`'
# shellcheck disable=SC2016
hook 2 'echo "$(gh pr create -R a/b --title x)"'
hook 2 'command gh pr create -R a/b --title x --body y'
hook 2 'time gh pr create -R a/b --title x --body y'
hook 2 '! gh pr create -R a/b --title x --body y'
hook 2 'gh api repos/a/b/issues/1/comments -fbody=x'
hook 2 'gh api repos/{owner}/{repo}/issues/1/comments -f body=x'
hook 2 $'cat <<-EOF > b.md\n\ttext\n\tEOF\ngh pr create -R a/b --title x --body-file b.md'
hook 2 $'grep x <<<hello\ngh pr create -R a/b --title x --body y'
hook 2 $'gh pr create -R a/b \\\n  --title x --body y'

# a substitution inside double quotes opens its own quotes and closes back into
# the string, and the line goes on after it
# shellcheck disable=SC2016  # the commands are text for the hook, never run
hook 2 'echo "$(date)" && gh pr create -R a/b --title x'
# shellcheck disable=SC2016
hook 2 'echo "$(ls "x")" && gh pr create -R a/b --title x'
# shellcheck disable=SC2016
hook 2 'echo "`date`" && gh pr create -R a/b --title x'
# shellcheck disable=SC2016
hook 2 'echo "a $(date) b" ; git push --force origin fix'
# shellcheck disable=SC2016
hook 2 'x="$(echo "$(gh pr create -R a/b --title x)")"'
# shellcheck disable=SC2016
hook 2 "echo \$'it\\'s' && gh pr create -R a/b --title x"
# shellcheck disable=SC2016
hook 0 'echo "n: $(ls "x" | wc -l)"; check '"'"'git push --force origin fix'"'"
# shellcheck disable=SC2016
hook 0 'echo "$(printf "%s" "(")"; echo "a"; check '"'"'gh pr create -R a/b'"'"

# a substitution does not end the command it sits in: the words after it are
# still that command's, what runs inside it is read too, and one left open
# loses nothing
# shellcheck disable=SC2016  # every command in the block is text for the hook, never run
{
  hook 2 'gh api "repos/a/b/issues/$(cat n)/comments" -f body=hi'
  hook 2 'gh api repos/a/b/issues/$(cat n)/comments -f body=hi'
  hook 2 'gh api "repos/a/b/git/refs/heads/$(git branch --show-current)" -X DELETE'
  hook 2 'git push origin "$(git branch --show-current)" --force'
  hook 2 'git push origin $(git branch --show-current) --force-with-lease'
  hook 2 'git push "$(git remote get-url origin)" --delete fix'
  hook 2 'GH_TOKEN="$(gh auth token --user other)" gh pr create -R a/b --title x'
  hook 2 'gh api `echo repos/a/b/issues` -f title=x'
  hook 2 'gh api graphql -F id="$(cat id)" -f query="mutation { x }"'
  hook 2 'gh api repos/a/b/issues --paginate <(echo x) -X POST'
  hook 2 'n=$(gh api repos/a/b/issues -f title=x --jq .number); echo "$n"'
  hook 2 'echo "a $( (ls) '"'"'it"s'"'"' ) b"; gh pr create -R a/b --title x'
  hook 2 'gh pr create -R a/b --title "$(cat t'
  hook 2 'gh api repos/a/b/issues -f title="$(cat t'
  hook 0 'gh api "repos/a/b/issues/$(cat n)/comments"'
  hook 0 'echo "$(gh pr view 5 -R a/b --json title)" > t.json'
  hook 0 'git push origin "$(git branch --show-current)"'
  hook 0 'diff <(gh pr view 5 -R a/b) <(gh pr view 6 -R a/b)'
}

# a << that opens no here-document drops nothing, a delimiter is the whole
# word, and a mutation in a here-document is still a mutation
hook 2 $'git commit -am "Fix operator<< overload for Foo"\ngit push --force origin fix'
hook 2 $'grep -rn "os << value" src/\ngh pr create -R a/b --title x'
hook 2 $'n=$((1 << bits))\ngh pr create -R a/b --title x'
hook 2 $'# x << y\ngh pr create -R a/b --title x'
hook 2 $'cat > b.md <<\'END-BODY\'\ntext\nEND-BODY\ngh pr create -R a/b --title x'
hook 2 $'cat > b.md <<"EOF.md"\ntext\nEOF.md\ngh pr create -R a/b --title x'
hook 2 $'cat > b.md <<EOF\r\ntext\r\nEOF\r\ngh pr create -R a/b --title x\r\n'
hook 2 $'gh api graphql -f query="$(cat <<\'EOF\'\nmutation { addStar(input: {}) { clientMutationId } }\nEOF\n)"'
hook 2 $'gh api graphql -F query=@- <<\'EOF\'\nmutation { x }\nEOF'
hook 0 $'gh api graphql -F query=@- <<\'EOF\'\nquery { viewer { login } }\nEOF'
hook 0 $'cat > b.md <<\'END-BODY\'\ngh pr create is refused by the hook\nEND-BODY\nls'
hook 0 $'cat > b.md <<\'EOF\'\r\ngh pr create is refused by the hook\r\nEOF\r\nls\r\n'
hook 0 $'cat > b.md <<\'END OF BODY\'\ngh pr create is refused by the hook\nEND OF BODY\nls'
hook 0 $'cat > b.md <<END-BODY\ngh pr create is refused by the hook\nEND-BODY\nls'

# a quoted word is still the word: a sign, a directory or a value with a space
hook 2 'git push origin "+fix"'
hook 2 "git push origin ':fix'"
hook 2 'git push "--force" origin fix'
hook 2 'git -C "/c/my repo" push --force origin fix'
hook 2 "git -C '/c/my repo' push -f origin fix"
hook 2 'git --git-dir="/c/my repo/.git" push -f origin fix'
hook 2 'GIT_SSH_COMMAND="ssh -i ~/.ssh/work" git push --force origin fix'
hook 2 'GH_EDITOR="code --wait" gh pr create -R a/b --title x'
hook 0 'GIT_SSH_COMMAND="ssh -i ~/.ssh/work" git push origin fix'
hook 0 'git -C "/c/my repo" push origin fix'

# the other names of a write, and a help page is not one
hook 2 'gh pr new -R a/b --title x --body y'
hook 2 'gh issue new -R a/b --title x --body y'
hook 2 'gh issue develop 5 -R a/b --name fix'
hook 2 'gh pr create>/dev/null -R a/b --title x'
hook 2 'gh pr create -R a/b --title "--help"'
hook 2 'gh pr create -R a/b --title x --body "run tool --help for usage"'
hook 2 'gh issue comment 5 -R a/b --body "the --help output is wrong"'
hook 0 'gh pr create --help'
hook 0 'gh issue create -R a/b --help'
hook 2 "gh api --paginate graphql -f query='mutation { x }'"
hook 0 "gh api --paginate graphql -f query='query { viewer { login } }'"

# a wrapper by its path, with a variable for its time or a name for its user
hook 2 '/usr/bin/env gh pr create -R a/b --title x'
hook 2 '/usr/bin/timeout 60 gh pr create -R a/b --title x'
hook 2 'gtimeout 60 gh pr create -R a/b --title x'
# shellcheck disable=SC2016
hook 2 'timeout $T gh pr create -R a/b --title x'
# shellcheck disable=SC2016
hook 2 'timeout "${T}s" gh pr create -R a/b --title x'
hook 2 'sudo -u build-bot gh pr create -R a/b --title x'
hook 0 'sudo -u build-bot gh pr view 5 -R a/b'
hook 0 '/usr/bin/env gh pr view 5 -R a/b'

# every way gh api takes a field, and every way a push deletes
hook 2 'gh api repos/a/b/issues/1/comments -F body=x'
hook 2 'gh api repos/a/b/issues/1/comments --field body=x'
hook 2 'gh api repos/a/b/issues/1/comments --raw-field body=x'
hook 2 'gh api repos/a/b/issues --input b.json'
hook 2 'gh api repos/a/b/issues/1/comments -if body=x'
hook 2 'git push -d origin fix'
hook 2 'git push --mirror origin'
hook 2 'git push --force origin gh-pages'
hook 0 'gh api --method GET search/issues -f q=x'
hook 0 'gh api -X "GET" search/issues -f q=x'
hook 2 'gh api repos/a/b/issues/1/comments -f body="use gh api -X GET for search"'
hook 0 'gh api repos/a/b/pulls -q .[0].title'
# a comment ends at its line, whatever it holds
hook 2 $'# don\'t forget the title\ngh pr create -R a/b --title x'
# a line that goes on inside double quotes is still inside them
hook 0 $'git commit -m "one \\\ngh pr create is refused by the hook"'

# text that only mentions a write is not one, and a push is read for its own flags
hook 0 "grep -n -E 'unset X|gh pr create|gh issue create' tests/x.sh"
hook 0 "git commit -m 'file: refuse (gh pr create without a body)'"
hook 0 "gh api repos/a/b/pulls/1 --jq '.title' 2>&1 | head -5"
hook 0 $'# gh pr create is what we are not doing\nls'
hook 0 'git push origin fix && rm -rf build'
hook 0 'git commit -m "handle the -f flag" && git push origin fix'
hook 0 'git add -f dist/x.txt && git push origin fix'

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
hook 0 'housebroken close a/b 5 --body-file n.md'
hook 2 'gh pr close 5 -R a/b --comment done'
grep -q "withdraw one with housebroken close" "$tmp/err" || fail "the refused close did not name the gate: $(cat "$tmp/err")"
printf '{"tool_name": "Read", "tool_input": {"file_path": "x"}}' | bash "$script" || fail "a non-Bash call was refused"

# your own repositories pass once their owner is listed; a fork does not make a forced push yours
hook 2 'gh pr create -R acme/widgets --title x --body y'
mkdir -p "$HOUSEBROKEN_HOME" && printf 'acme\n' > "$HOUSEBROKEN_HOME/own"
hook 0 'gh pr create -R acme/widgets --title x --body y'
hook 0 'gh api repos/acme/widgets/issues/1/comments -f body=x'
hook 2 'gh pr create -R other/widgets --title x --body y'
grep -q "listed in $HOUSEBROKEN_HOME/own" "$tmp/err" || fail "the refusal did not name the own file"
# the owner comes from the write itself, not from anything near it
hook 2 'cd ~/repos/acme/widgets && gh pr create --title x --body y'
hook 2 'gh api repos/acme/widgets/pulls/1 --jq .title && gh pr create -R upstream/thing --title t --body b'
hook 0 'gh api repos/acme/widgets/pulls/1 --jq .title && gh pr create -R acme/widgets --title t --body b'
hook 2 'gh pr create --body-file repos/acme/b.md --title t'
# a forced push is refused on your own too, however it names the repository
hook 2 'git push --force --repo=acme/widgets origin fix'
# a fork's clone names you as origin while gh writes to the upstream parent,
# so only a repository the command names counts
git init -q "$tmp/own-clone" && git -C "$tmp/own-clone" remote add origin https://github.com/acme/widgets.git
hook 2 'gh pr create --title x --body y'
hook 2 'git push --force origin fix'
# a quoted owner is the owner; -r is a reviewer, not a repository; a body or a
# link that names another repository is not yours; every repository named counts
hook 0 'gh pr create -R "acme/widgets" --title x --body y'
hook 0 'gh api "repos/acme/widgets/issues/1/comments" -f body=x'
hook 0 "gh api 'repos/acme/widgets/issues' -f title=x"
hook 0 'gh pr comment 5 -R acme/widgets --body "see -R other/thing for the rest"'
hook 0 'gh pr create -R Acme/widgets --title x --body y'
hook 2 'gh pr create --title x --body y -r acme/core'
hook 2 'gh pr create -r acme/core -R victim/repo --title x --body y'
hook 2 'gh pr comment 5 --body "same as -R acme/widgets" -R victim/repo'
hook 2 'gh pr comment https://github.com/victim/repo/pull/5 -R acme/widgets --body hi'
hook 2 'gh pr comment 5 -R acme/widgets -R victim/repo --body hi'
hook 2 'gh api repos/acme/widgets/issues repos/victim/repo/issues -f title=x'
# the own file as an editor leaves it: no last newline, a space after the name, CRLF
printf 'other\nacme' > "$HOUSEBROKEN_HOME/own"
hook 0 'gh pr create -R acme/widgets --title x --body y'
printf 'acme \n' > "$HOUSEBROKEN_HOME/own"
hook 0 'gh pr create -R acme/widgets --title x --body y'
printf 'acme\r\nother\r\n' > "$HOUSEBROKEN_HOME/own"
hook 0 'gh pr create -R acme/widgets --title x --body y'
hook 2 'gh pr create -R acm/widgets --title x --body y'
printf 'acme\n' > "$HOUSEBROKEN_HOME/own"

# without jq a write is refused unparsed, and anything else runs
mkdir -p "$tmp/nojq"
printf '{"tool_input": {"command": "gh pr create"}}' | PATH="$tmp/nojq" "$BASH" "$script" 2>"$tmp/err"
[ "$?" = 2 ] || fail "a write with jq missing was not refused"
grep -q "jq is not on PATH" "$tmp/err" || fail "a missing jq was not named"
printf '{"tool_input": {"command": "ls -la"}}' | PATH="$tmp/nojq" "$BASH" "$script" 2>/dev/null || fail "a read with jq missing was refused"
for c in 'gh pr -R a/b create --title x' 'gh issue -R a/b new --title x' 'gh api -X POST repos/a/b/issues/1/comments' 'git push --force origin fix'; do
  printf '{"tool_input": {"command": "%s"}}' "$c" | PATH="$tmp/nojq" "$BASH" "$script" 2>/dev/null
  [ "$?" = 2 ] || fail "with jq missing, $c was not refused"
done
for c in 'gh pr view 5 --json comments' 'gh pr list --state merged' 'gh pr diff 5 | grep create'; do
  printf '{"tool_input": {"command": "%s"}}' "$c" | PATH="$tmp/nojq" "$BASH" "$script" 2>/dev/null || fail "with jq missing, the read $c was refused"
done
# a jq that fails, or a call it cannot read, is the same as no jq: never open
mkdir -p "$tmp/badjq"
printf '#!/bin/sh\necho "jq: no version is set" >&2\nexit 126\n' > "$tmp/badjq/jq"
chmod +x "$tmp/badjq/jq"
printf '{"tool_input": {"command": "git push --force origin fix"}}' | PATH="$tmp/badjq:$PATH" bash "$script" 2>"$tmp/err"
[ "$?" = 2 ] || fail "a write behind a jq that fails was not refused"
grep -q ' \[gate-jq-failed\]$' "$tmp/err" || fail "a jq that fails is not named: $(cat "$tmp/err")"
printf '{"tool_input": {"command": "ls -la"}}' | PATH="$tmp/badjq:$PATH" bash "$script" 2>/dev/null || fail "a read behind a jq that fails was refused"
printf '{"tool_input": {"command": "gh pr create -R a/b --title x' | bash "$script" 2>/dev/null
[ "$?" = 2 ] || fail "a write in a call jq cannot read was not refused"

HOME="$tmp" bash "$script" --install > "$tmp/out" || fail "--install failed"
[ -f "$tmp/.claude/hooks/housebroken-gate.sh" ] || fail "--install wrote no hook"
# the entry covers both shells Claude Code runs commands in, and a hook that
# times out or cannot start blocks the command
grep -q '"matcher": "Bash|PowerShell"' "$tmp/out" || fail "--install printed no settings entry for both shells"
[ "$(sed -n '/"matcher"/p' "$tmp/out" | jq -r '.hooks[0].onFailure')" = block ] || fail "the printed entry lets a failed hook through"
printf '%s' 'gh pr create -R a/b --title x' | jq -Rs '{tool_name: "PowerShell", tool_input: {command: .}}' | bash "$script" 2>/dev/null
[ "$?" = 2 ] || fail "a write through the PowerShell tool was not refused"

# the printed entry runs from a home with a space, and refuses
spaced="$tmp/home space/First Last"
mkdir -p "$spaced"
HOME="$spaced" bash "$script" --install > "$tmp/out" || fail "--install under a spaced home failed"
entry=$(sed -n '/"matcher"/p' "$tmp/out" | jq -r '.hooks[0].command') || fail "the printed entry is not JSON"
printf '{"tool_input": {"command": "gh pr create -R a/b --title x"}}' | bash -c "$entry" 2>/dev/null
[ "$?" = 2 ] || fail "the printed entry did not refuse under a home with a space: $entry"

# each refusal ends with the name of its rule and leaves one line in the local log
log="$HOUSEBROKEN_HOME/refusals.tsv"
tab=$(printf '\t')
count() { if [ -f "$log" ]; then wc -l < "$log" | tr -d ' '; else echo 0; fi; }
named() { # name command
  hook 2 "$2"
  grep -q "^housebroken: refused: .*\. \[$1\]\$" "$tmp/err" || fail "the refusal is not named $1: $(cat "$tmp/err")"
  [ "$(tail -n 1 "$log" | cut -f2,3)" = "$1$tab-" ] || fail "the log's last line is not $1: $(tail -n 1 "$log" 2>&1)"
}
named gate-pr-write 'gh pr create -R a/b --title x --body y'
named gate-issue-write 'gh issue create -R a/b --title t'
named gate-graphql-mutation "gh api graphql -f query='mutation { addComment(input: {subjectId: \"x\", body: \"y\"}) { clientMutationId } }'"
named gate-api-write-method 'gh api -X POST repos/a/b/issues/1/comments -f body=x'
named gate-api-fields-post 'gh api repos/a/b/issues/1/comments -f body=x'
named gate-push-force-or-delete 'git push --force origin fix'
# a reason that lost its name is still refused, and nothing nameless reaches the log
n=$(count)
sed 's/^\( *\)why_id=gate-pr-write$/\1why_id=""/' "$script" > "$tmp/nameless.sh"
cmp -s "$script" "$tmp/nameless.sh" && fail "nothing was planted in the hook"
printf '{"tool_input": {"command": "gh pr create -R a/b --title x"}}' | bash "$tmp/nameless.sh" 2>/dev/null
[ "$?" = 2 ] || fail "the hook with a nameless reason did not refuse"
[ "$(count)" = "$n" ] || fail "a refusal with no name reached the log: $(tail -n 1 "$log")"
# a command that runs writes nothing
n=$(count)
hook 0 'git status'
hook 0 'gh pr view 5 -R a/b'
hook 0 'gh pr create -R acme/widgets --title x --body y'
[ "$(count)" = "$n" ] || fail "a command that was not refused wrote to the log"
# the hook is installed alone: copied into an empty directory it still names its rule and writes its line
mkdir "$tmp/alone" || fail "fixture failed"
cp "$script" "$tmp/alone/housebroken-gate.sh" || fail "fixture failed"
printf '{"tool_input": {"command": "gh pr create -R a/b --title x"}}' | bash "$tmp/alone/housebroken-gate.sh" 2>"$tmp/err"
[ "$?" = 2 ] || fail "the hook alone did not refuse"
grep -q ' \[gate-pr-write\]$' "$tmp/err" || fail "the hook alone did not name its rule: $(cat "$tmp/err")"
[ "$(count)" = "$((n + 1))" ] || fail "the hook alone did not write its line"
# without jq the refusal is named too, when the tools the line needs are there
mkdir "$tmp/tools" || fail "fixture failed"
for t in date mkdir; do ln -s "$(command -v "$t")" "$tmp/tools/$t" || fail "fixture failed"; done
printf '{"tool_input": {"command": "gh pr create"}}' | PATH="$tmp/tools" "$BASH" "$script" 2>"$tmp/err"
[ "$?" = 2 ] || fail "a write with jq missing was not refused"
grep -q '^housebroken: refused: jq is not on PATH.* \[gate-jq-missing\]$' "$tmp/err" || fail "the missing jq is not named: $(cat "$tmp/err")"
[ "$(tail -n 1 "$log" | cut -f2,3)" = "gate-jq-missing$tab-" ] || fail "the log's last line is not gate-jq-missing: $(tail -n 1 "$log")"
# Git for Windows ships no jq, and Windows is where gh.exe and git.exe are typed
for c in 'gh.exe pr create' 'git.exe push -f origin x' 'gh.exe api repos/a/b/issues -f title=x' 'gh pr lock 5' 'gh issue delete 5' 'gh issue transfer 5 a/c'; do
  printf '{"tool_input": {"command": "%s"}}' "$c" | PATH="$tmp/tools" "$BASH" "$script" 2>/dev/null
  [ "$?" = 2 ] || fail "with jq missing, $c was not refused"
done
printf '{"tool_input": {"command": "ls gh.exe"}}' | PATH="$tmp/tools" "$BASH" "$script" 2>/dev/null || fail "with jq missing, a command that writes nothing was refused"
# the hook's line and a gate's line are one shape: time, name, repository
(
  # shellcheck source=scripts/refuse.sh
  . "$here/../scripts/refuse.sh"
  repo="a/b"; refusal_log push-repo-form
)
[ "$(tail -n 1 "$log" | cut -f2,3)" = "push-repo-form${tab}a/b" ] || fail "the gate's line was not written beside the hook's"
bad=$(awk -F'\t' '!(NF == 3 && $1 ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z$/ && $2 ~ /^[a-z0-9]+(-[a-z0-9]+)+$/ && ($3 == "-" || $3 ~ /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/))' "$log")
[ -z "$bad" ] || fail "a log line is not time, name, repository: $bad"
# a log that cannot be written changes nothing but one line on stderr
printf 'x\n' > "$tmp/afile"
printf '{"tool_input": {"command": "gh pr create -R a/b --title x"}}' | HOUSEBROKEN_HOME="$tmp/afile" bash "$script" 2>"$tmp/err"
[ "$?" = 2 ] || fail "an unwritable log changed the hook's exit"
grep -q '^housebroken: refused: it writes to a pull request outside the gate.* \[gate-pr-write\]$' "$tmp/err" || fail "an unwritable log changed the refusal: $(cat "$tmp/err")"
[ "$(grep -c 'could not be written' "$tmp/err")" = 1 ] || fail "the unwritable log was not said: $(cat "$tmp/err")"

echo "PASS $name"
