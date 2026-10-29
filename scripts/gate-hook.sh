#!/bin/bash
# gate-hook.sh - a Claude Code PreToolUse hook that keeps the door the only
# way out.
#
# The skill says never run the pull request creation command directly, and
# a rule an agent must remember is followed when remembered. This hook reads
# each Bash command before it runs and refuses one that writes to GitHub on
# its own: opening, commenting on, reviewing, editing, closing or merging a
# pull request or an issue, a write through gh api, and a forced git push.
# The same action through its gate (housebroken file, issue, reply, push or
# hygiene) passes, because the gate runs gh inside its own script, where this
# hook does not look. Reads, releases and plain pushes are not touched.
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
# agent; 0 to let the command run.
set -u

usage() { awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"; }
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
    exit 0 ;;
esac

cmd=$(jq -r '.tool_input.command // empty' 2>/dev/null)
[ -n "$cmd" ] || exit 0

# A command counts where it would run: at the start of a line or after a
# separator, past any VAR=value prefixes. Text that only mentions one, in a
# commit message or a here-document line, does not.
at='(^|[;&|(]|\$\()[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*'
runs() { printf '%s\n' "$cmd" | grep -qE "${at}$1"; }

why=""
if runs 'gh[[:space:]]+pr[[:space:]]+(create|comment|review|edit|close|merge|ready|reopen)\b'; then
  why="it writes to a pull request outside the gate; open one with housebroken file, answer one with housebroken reply"
elif runs 'gh[[:space:]]+issue[[:space:]]+(create|comment|edit|close|reopen)\b'; then
  why="it writes to an issue outside the gate; open one with housebroken issue, answer one with housebroken reply"
elif runs 'gh[[:space:]]+api\b'; then
  # gh api reads unless it names a writing method, or sends fields without
  # saying GET.
  if printf '%s' "$cmd" | grep -qiE '(-X|--method)[[:space:]=]*(POST|PATCH|PUT|DELETE)\b'; then
    why="gh api with a writing method changes GitHub outside the gate"
  elif printf '%s' "$cmd" | grep -qE '[[:space:]](-f|-F|--field|--raw-field|--input)[[:space:]=]' &&
       ! printf '%s' "$cmd" | grep -qiE '(-X|--method)[[:space:]=]*GET\b'; then
    why="gh api with fields and no -X GET is a POST, which changes GitHub outside the gate"
  fi
elif runs 'git[[:space:]]+push\b' &&
     printf '%s' "$cmd" | grep -qE '[[:space:]](--force|--force-with-lease|-f)\b|[[:space:]]\+[^[:space:]]'; then
  why="a forced push rewrites what a maintainer may already have reviewed; push a rework with housebroken push"
fi

[ -z "$why" ] && exit 0
{
  echo "housebroken: refused: $why."
  echo "If the user asked for exactly this, they can run it themselves."
} >&2
exit 2
