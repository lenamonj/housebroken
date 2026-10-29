#!/bin/bash
# gate-hook.sh - a Claude Code PreToolUse hook that keeps the door the only
# way out.
#
# The skill says never run the pull request creation command directly, and
# a rule an agent must remember is followed when remembered. This hook reads
# each Bash command before it runs and refuses one that writes to GitHub on
# its own: opening, commenting on, reviewing, editing, closing, merging or
# updating a pull request or an issue, a write through gh api (a writing
# method, fields without -X GET, or a GraphQL mutation), and a forced git
# push or a branch delete. The same action through its gate (housebroken
# file, issue, reply, push or hygiene) passes, because the gate runs gh
# inside its own script, where this hook does not look. Reads, releases and
# plain pushes are not touched.
#
# It reads the command text, so it holds the accident, not the intent: a
# write behind bash -c, eval, xargs, env, a script file, a full path to gh
# or an alias passes it.
#
# Writes to your own repositories pass when the owner is listed, one per
# line, in $HOUSEBROKEN_HOME/own (default ~/.housebroken/own); the owner is
# read from -R/--repo or from the repos/OWNER/... path of a gh api call, never
# from the clone, because in a fork's clone gh writes to the upstream parent
# while origin names you. A forced push
# is refused everywhere, because a fork carries your name too: push a rework
# with housebroken push, or run it yourself.
#
# `housebroken install-hook` copies this script to
# ~/.claude/hooks/housebroken-gate.sh, where an upgrade does not move it, and
# prints the entry to add to the "PreToolUse" list in ~/.claude/settings.json.
# It does not edit your settings.
#
# Usage:
#   bash gate-hook.sh             (as Claude Code runs it: the call on stdin)
#   bash gate-hook.sh --install
#   bash gate-hook.sh --help
#
# Exits 2 with the reason on stderr to refuse, which Claude Code shows the
# agent; 0 to let the command run; 1 when jq is missing and nothing was
# checked, which Claude Code shows the user and does not block.
set -u

usage() { awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"; }
own="${HOUSEBROKEN_HOME:-$HOME/.housebroken}/own"
case "${1:-}" in
  --help|-h) usage; exit 0 ;;
  --install)
    dest="$HOME/.claude/hooks/housebroken-gate.sh"
    if ! mkdir -p "$(dirname "$dest")" || ! cp "$0" "$dest"; then
      echo "install-hook: cannot write $dest" >&2
      exit 1
    fi
    echo "installed $dest"
    echo "Add this to the \"PreToolUse\" list under \"hooks\" in ~/.claude/settings.json:"
    printf '  {"matcher": "Bash", "hooks": [{"type": "command", "command": "bash %s", "timeout": 10}]}\n' "$dest"
    echo "Owners of your own repositories, whose writes pass, go one per line in $own."
    exit 0 ;;
esac

IFS= read -r -d '' input || true
# Without jq the command cannot be parsed, so any call that mentions a write
# anywhere is refused and everything else runs: degraded, never open. Bash
# alone does this, so a missing tool cannot open it.
if ! command -v jq >/dev/null 2>&1; then
  write_re='gh[[:space:]]+(pr|issue)[[:space:]]+(create|comment|review|edit|close|merge|ready|reopen|update-branch)|gh[[:space:]]+api|git[[:space:]].*push'
  if [[ $input =~ $write_re ]]; then
    echo "housebroken: refused: jq is not on PATH, so this command could not be checked; install jq." >&2
    exit 2
  fi
  exit 0
fi
cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -n "$cmd" ] || exit 0

# A here-document is text, not commands: its lines are dropped before the read.
text=$(printf '%s\n' "$cmd" | awk -v q="'" '
  BEGIN { open = "<<-?[[:space:]]*[\"" q "]?[A-Za-z_][A-Za-z0-9_]*" }
  stop != "" { if ($0 == stop) stop = ""; next }
  match($0, open) { stop = substr($0, RSTART, RLENGTH); sub("^<<-?[[:space:]]*[\"" q "]?", "", stop) }
  { print }')

# A command counts where it would run: at the start of a line or after a
# separator or a shell keyword, past any VAR=value prefixes and past git's
# -C and -c options. Text that only mentions one, in a commit message or a
# here-document, does not.
at='(^|[;&|({]|\$\(|\b(then|do|else|elif)[[:space:]]+)[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*'
git='git([[:space:]]+-[Cc][[:space:]]+[^[:space:]]+)*[[:space:]]+'
runs() { printf '%s\n' "$text" | grep -qE "${at}$1"; }
has() { printf '%s' "$text" | grep -qiE "$1"; }

why=""; push=""
if runs 'gh[[:space:]]+pr[[:space:]]+(create|comment|review|edit|close|merge|ready|reopen|update-branch)\b'; then
  why="it writes to a pull request outside the gate; open one with housebroken file, answer one with housebroken reply"
elif runs 'gh[[:space:]]+issue[[:space:]]+(create|comment|edit|close|reopen)\b'; then
  why="it writes to an issue outside the gate; open one with housebroken issue, answer one with housebroken reply"
elif runs 'gh[[:space:]]+api[[:space:]]+graphql\b'; then
  has '\bmutation\b' && why="a GraphQL mutation changes GitHub outside the gate"
elif runs 'gh[[:space:]]+api\b'; then
  # gh api reads unless it names a writing method, or sends fields without
  # saying GET.
  if has '(-X|--method)[[:space:]=]*(POST|PATCH|PUT|DELETE)\b'; then
    why="gh api with a writing method changes GitHub outside the gate"
  elif printf '%s' "$text" | grep -qE '[[:space:]](-f|-F|--field|--raw-field|--input)[[:space:]=]' &&
       ! has '(-X|--method)[[:space:]=]*GET\b'; then
    why="gh api with fields and no -X GET is a POST, which changes GitHub outside the gate"
  fi
elif runs "${git}push\b" &&
     printf '%s' "$text" | grep -qE '[[:space:]](--force(-with-lease)?|--delete|--mirror|-[a-zA-Z]*[fd][a-zA-Z]*)\b|[[:space:]][+:][^[:space:]]'; then
  why="a forced push or a branch delete rewrites what a maintainer may already have reviewed; push a rework with housebroken push"
  push=1
fi
[ -n "$why" ] || exit 0

# Your own repositories: the door is for other people's.
if [ -z "$push" ] && [ -s "$own" ]; then
  # Only a repository the command names counts. With none named, gh picks
  # one from the clone, and in a fork's clone that is the upstream parent.
  owner=$(printf '%s' "$text" | grep -oE '((-R|--repo)[[:space:]=]+|repos/)[A-Za-z0-9_.-]+/' | head -1 | sed -E 's#/$##; s#.*[[:space:]=/]##')
  [ -n "$owner" ] && awk -v o="$owner" 'tolower($0) == tolower(o) {f = 1} END {exit !f}' "$own" && exit 0
fi

{
  echo "housebroken: refused: $why."
  if [ -n "$push" ]; then
    echo "If the user asked for exactly this, they can run it themselves."
  else
    echo "If the user asked for exactly this, they can run it themselves; a repository of their own passes once its owner is listed in $own."
  fi
} >&2
exit 2
