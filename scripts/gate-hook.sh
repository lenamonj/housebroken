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
# file, issue, reply, close, push or hygiene) passes, because the gate runs gh
# inside its own script, where this hook does not look. Reads, releases and
# plain pushes are not touched, and nor is any other gh command: this is a
# list of what a filing can go around the gates with, not a deny-all.
#
# Each command in a line is judged by itself, so a read beside a write does
# not excuse it, and quoted text is not a command. It still reads text, so it
# holds the accident, not the intent: a write behind bash -c, eval, xargs,
# env, a script file, a full path to gh or an alias passes it.
#
# Writes to your own repositories pass when the owner is listed, one per
# line, in $HOUSEBROKEN_HOME/own (default ~/.housebroken/own); the owner is
# read from the -R/--repo or the repos/OWNER/... path of that same command,
# never from the clone, because in a fork's clone gh writes to the upstream
# parent while origin names you. A forced push is refused everywhere, because
# a fork carries your name too: push a rework with housebroken push, or run it
# yourself.
#
# `housebroken install-hook` copies this script to
# ~/.claude/hooks/housebroken-gate.sh and prints the entry to add to the
# "PreToolUse" list in ~/.claude/settings.json. An upgrade does not move the
# copy; housebroken notes when it differs, and install-hook replaces it.
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
    # Quoted for the shell, then escaped for JSON: a home with a space must not
    # split the command, or the hook exits 126 and refuses nothing.
    esc=${dest//\\/\\\\}
    printf '  {"matcher": "Bash", "hooks": [{"type": "command", "command": "bash \\"%s\\"", "timeout": 10}]}\n' "$esc"
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
# <<- may indent its terminator with tabs, and <<< opens nothing.
text=$(printf '%s\n' "$cmd" | awk -v q="'" '
  BEGIN { open = "(^|[^<])<<-?[[:space:]]*[\"" q "]?[A-Za-z_][A-Za-z0-9_]*" }
  stop != "" { l = $0; if (strip) sub(/^\t+/, "", l); if (l == stop) stop = ""; next }
  match($0, open) {
    stop = substr($0, RSTART, RLENGTH); strip = (stop ~ /<<-/)
    sub("^.*<<-?[[:space:]]*[\"" q "]?", "", stop)
  }
  { print }')

# One command per line: split at the separators a shell would run them at, and
# never inside quotes, so text that only mentions a write is not one. A $(...)
# inside double quotes does run, with quotes of its own, and when it closes the
# string goes on: a stack holds where to come back to, or the first quote after
# it would swallow the rest of the line. Comments go, and a { in a path is not a
# brace.
commands=$(printf '%s\n' "$text" | LC_ALL=C awk '
  { src = src $0 "\n" }
  END {
    n = length(src); quote = ""; seg = ""; sq = "\047"; dq = "\042"; bt = "\140"; sp = 0
    for (i = 1; i <= n; i++) {
      c = substr(src, i, 1); d = substr(src, i + 1, 1); p = (i > 1) ? substr(src, i - 1, 1) : "\n"
      if (quote == sq) { seg = seg (c == "\n" ? " " : c); if (c == sq) quote = ""; continue }
      if (quote == "ansi") {
        if (c == "\\") { seg = seg c d; i++; continue }
        seg = seg (c == "\n" ? " " : c); if (c == sq) quote = ""; continue
      }
      if (quote == dq) {
        if (c == "\\") { seg = seg c d; i++; continue }
        if (c == dq) { quote = ""; seg = seg c; continue }
        if ((c == "$" && d == "(") || c == bt) {
          sp++; kind[sp] = (c == bt) ? bt : "("; depth[sp] = 0
          quote = ""; print seg; seg = ""; if (c == "$") i++; continue
        }
        seg = seg (c == "\n" ? " " : c); continue
      }
      if (c == "\\") { seg = seg ((d == "\n") ? " " : c d); i++; continue }
      if (c == "$" && d == sq) { quote = "ansi"; seg = seg c d; i++; continue }
      if (c == sq || c == dq) { quote = c; seg = seg c; continue }
      if (sp > 0) {
        if (c == "(") depth[sp]++
        else if (c == ")" && kind[sp] == "(") {
          if (depth[sp] == 0) { sp--; quote = dq; print seg; seg = ""; continue }
          depth[sp]--
        } else if (c == bt && kind[sp] == bt) { sp--; quote = dq; print seg; seg = ""; continue }
      }
      space = (p == " " || p == "\t" || p == "\n" || p == ";")
      if (c == "#" && space) { while (i < n && substr(src, i + 1, 1) != "\n") i++; continue }
      if (c == "\n" || c == ";" || c == "|" || c == "(" || c == ")" || c == bt) { print seg; seg = ""; continue }
      if (c == "&" && p != ">" && d != ">") { print seg; seg = ""; continue }
      if ((c == "{" || c == "}") && space && (d == " " || d == "\t" || d == "\n" || d == ";")) { print seg; seg = ""; continue }
      seg = seg c
    }
    print seg
  }')

shopt -s nocasematch
# A command counts where it would run: past keywords, a VAR=value prefix, and
# past the -R of gh and the -C and -c of git. Text after it is its arguments.
at='^[[:space:]]*((then|do|else|elif|if|while|until|time|command|exec|!)[[:space:]]+|[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*'
repo_flag='((-R|--repo)([[:space:]]+|=)[^[:space:]]+[[:space:]]+)*'
end='([[:space:]]|$)'
gh="${at}gh[[:space:]]+$repo_flag"
pr_re="${gh}pr[[:space:]]+$repo_flag(create|comment|review|edit|close|merge|ready|reopen|update-branch)$end"
issue_re="${gh}issue[[:space:]]+$repo_flag(create|comment|edit|close|reopen)$end"
graphql_re="${gh}api[[:space:]]+graphql$end"
api_re="${gh}api$end"
push_re="${at}git([[:space:]]+-[Cc][[:space:]]+[^[:space:]]+)*[[:space:]]+push$end"
quote="[\"']?"
mutation_re="(^|[^a-z])mutation([^a-z]|$)"
write_method_re="(-X|--method)[[:space:]=]*${quote}(POST|PATCH|PUT|DELETE)$quote$end"
get_method_re="(-X|--method)[[:space:]=]*${quote}GET$quote$end"
# -f and -F take their value glued too, as in -fbody=x.
fields_re='[[:space:]](-f|--field|--raw-field|--input)([[:space:]=]|$)|[[:space:]]-f[^[:space:]-]'
force_re='[[:space:]](--force(-with-lease)?|--delete|--mirror|-[a-zA-Z]*[fd][a-zA-Z]*)([[:space:]=]|$)|[[:space:]][+:][^[:space:]]'

why=""; push=""
judge() {
  why=""; push=""
  if [[ $1 =~ $pr_re ]]; then
    why="it writes to a pull request outside the gate; open one with housebroken file, answer one with housebroken reply, withdraw one with housebroken close"
  elif [[ $1 =~ $issue_re ]]; then
    why="it writes to an issue outside the gate; open one with housebroken issue, answer one with housebroken reply"
  elif [[ $1 =~ $graphql_re ]]; then
    if [[ $1 =~ $mutation_re ]]; then why="a GraphQL mutation changes GitHub outside the gate"; fi
  elif [[ $1 =~ $api_re ]]; then
    # gh api reads unless it names a writing method, or sends fields without
    # saying GET.
    if [[ $1 =~ $write_method_re ]]; then
      why="gh api with a writing method changes GitHub outside the gate"
    elif [[ $1 =~ $fields_re ]] && ! [[ $1 =~ $get_method_re ]]; then
      why="gh api with fields and no -X GET is a POST, which changes GitHub outside the gate"
    fi
  elif [[ $1 =~ $push_re ]] && [[ $1 =~ $force_re ]]; then
    why="a forced push or a branch delete rewrites what a maintainer may already have reviewed; push a rework with housebroken push"
    push=1
  fi
}

# Your own repositories: the door is for other people's. Only a repository this
# command names counts. With none named, gh picks one from the clone, and in a
# fork's clone that is the upstream parent.
is_own() {
  local owner="" o
  [ -s "$own" ] || return 1
  if [[ $1 =~ $api_re ]]; then
    [[ $1 =~ [[:space:]]/?repos/([A-Za-z0-9_.-]+)/ ]] && owner="${BASH_REMATCH[1]}"
  else
    [[ $1 =~ [[:space:]](-R|--repo)([[:space:]]+|=)([A-Za-z0-9_.-]+)/ ]] && owner="${BASH_REMATCH[3]}"
  fi
  [ -n "$owner" ] || return 1
  while IFS= read -r o; do
    if [[ ${o%$'\r'} == "$owner" ]]; then return 0; fi
  done < "$own"
  return 1
}

while IFS= read -r c; do
  [ -n "$c" ] || continue
  judge "$c"
  [ -n "$why" ] || continue
  if [ -z "$push" ] && is_own "$c"; then continue; fi
  {
    echo "housebroken: refused: $why."
    if [ -n "$push" ]; then
      echo "If the user asked for exactly this, they can run it themselves."
    else
      echo "If the user asked for exactly this, they can run it themselves; a repository of their own passes once its owner is listed in $own."
    fi
  } >&2
  exit 2
done <<< "$commands"
exit 0
