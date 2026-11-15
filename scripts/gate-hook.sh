#!/bin/bash
# gate-hook.sh - a Claude Code PreToolUse hook that keeps the door the only
# way out.
#
# The skill says never run the pull request creation command directly, and
# a rule an agent must remember is followed when remembered. This hook reads
# each command before it runs and refuses one that writes to GitHub on
# its own: opening, commenting on, reviewing, editing, closing, merging,
# reverting, locking or updating a pull request, the same for an issue with
# deleting, transferring and pinning, a write through gh api (a writing
# method, fields without -X GET, or a GraphQL mutation), and a forced git
# push or a branch delete. The same action through its gate (housebroken
# file, issue, reply, close, push or hygiene) passes, because the gate runs gh
# inside its own script, where this hook does not look. Reads, releases and
# plain pushes are not touched, and nor is any other gh command: this is a
# list of what a filing can go around the gates with, not a deny-all.
#
# Each command in a line is judged by itself, so a read beside a write does
# not excuse it, and quoted text is not a command. A $(...) is read twice: the
# command inside it by itself, and the command around it with the substitution
# as one word. It still reads text, so it holds the accident, not the intent:
# a write behind bash -c, eval, xargs, a script file, an alias, a quoted path
# to gh or a command that is itself a substitution passes it. A command typed
# in the PowerShell tool is read the same way, as if it were bash.
#
# Writes to your own repositories pass when the owner is listed, one per
# line, in $HOUSEBROKEN_HOME/own (default ~/.housebroken/own); the owner is
# read from that same command, from each -R/--repo, each link and each
# repos/OWNER/... path it names, and every one of them must be listed. It is
# never read from the clone, because in a fork's clone gh writes to the
# upstream parent while origin names you. A forced push is refused
# everywhere, because a fork carries your name too: push a rework with
# housebroken push, or run it yourself.
#
# A refusal ends with its rule's name in brackets and adds one line, the time
# and the name, to $HOUSEBROKEN_HOME/refusals.tsv, which stays on this machine.
#
# `housebroken install-hook` copies this script to
# ~/.claude/hooks/housebroken-gate.sh and prints the entry to add to the
# "PreToolUse" list in ~/.claude/settings.json. The entry names both shells
# Claude Code runs commands in, Bash and on Windows PowerShell, and sets
# onFailure to block, so a hook that times out or cannot start stops the
# command instead of letting it by. An upgrade does not move the copy;
# housebroken notes when it differs, and install-hook replaces it. It does
# not edit your settings.
#
# Usage:
#   bash gate-hook.sh             (as Claude Code runs it: the call on stdin)
#   bash gate-hook.sh --install
#   bash gate-hook.sh --help
#
# Exits 2 with the reason on stderr to refuse, which Claude Code shows the
# agent, and 0 to let the command run. Without jq, with a jq that fails, or
# on a call jq cannot read, a call that mentions a write anywhere is refused
# unread and every other call runs.
set -u

usage() { awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"; }
own="${HOUSEBROKEN_HOME:-$HOME/.housebroken}/own"

# One line per refusal in the local log, in the shape refuse.sh writes: the UTC
# time, the rule's name, and "-" where a gate puts the repository. The hook is
# installed as one file with nothing beside it, so it carries its own writer.
# A log that cannot be written is said and changes nothing.
log_refusal() { # name
  local home="${HOUSEBROKEN_HOME:-$HOME/.housebroken}"
  [[ "$1" =~ ^[a-z0-9]+(-[a-z0-9]+)+$ ]] || return 0
  if ! { mkdir -p "$home" && printf '%s\t%s\t-\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" >> "$home/refusals.tsv"; } 2>/dev/null; then
    echo "housebroken: the refusal log at $home/refusals.tsv could not be written" >&2
  fi
  return 0
}
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
    printf '  {"matcher": "Bash|PowerShell", "hooks": [{"type": "command", "command": "bash \\"%s\\"", "timeout": 10, "onFailure": "block"}]}\n' "$esc"
    echo "An entry added before 0.21.0 names Bash alone: replace it with this one."
    echo "onFailure needs Claude Code 2.1.295 or newer; on an older one leave it out."
    echo "Owners of your own repositories, whose writes pass, go one per line in $own."
    exit 0 ;;
esac

IFS= read -r -d '' input || true
# What cannot be parsed is not let through: a call that mentions a write
# anywhere is refused and everything else runs. Degraded, never open, and
# bash alone does it, so a missing tool cannot open it.
unparsed() { # reason, under the name in why_id
  local write_re='gh(\.exe)?[[:space:]]+(pr|issue)[[:space:]]([^|;&]*[[:space:]])?(create|new|comment|review|edit|close|merge|ready|reopen|update-branch|revert|delete|transfer|develop|lock|unlock|pin|unpin)([^a-z-]|$)|gh(\.exe)?[[:space:]]+api|git(\.exe)?[[:space:]].*push'
  [[ $input =~ $write_re ]] || exit 0
  echo "housebroken: refused: $1. [$why_id]" >&2
  log_refusal "$why_id"
  exit 2
}
if ! command -v jq >/dev/null 2>&1; then
  why_id=gate-jq-missing
  unparsed "jq is not on PATH, so this command could not be checked; install jq"
fi
if ! cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null); then
  why_id=gate-jq-failed
  unparsed "jq could not read this call, so the command could not be checked"
fi
[ -n "$cmd" ] || exit 0

# A here-document is text, not commands: its lines are dropped before the read.
# <<- may indent its terminator with tabs, and <<< opens nothing. The delimiter
# is the whole word, quoted or not. A << that is no here-document (a shift, an
# operator in a message) has no terminator, so what was dropped after it is
# given back and read.
text=$(printf '%s\n' "$cmd" | awk -v q="'" '
  function delimiter(rest,   c, w) {
    c = substr(rest, 1, 1)
    if (c == q || c == "\"") { w = substr(rest, 2); return (index(w, c) > 1) ? substr(w, 1, index(w, c) - 1) : "" }
    if (match(rest, /^[^ \t;|&<>()]+/) == 0) return ""
    w = substr(rest, 1, RLENGTH); gsub(/\\/, "", w); gsub(/"/, "", w); gsub(q, "", w)
    return w
  }
  { sub(/\r$/, "") }
  stop != "" {
    l = $0; if (strip) sub(/^\t+/, "", l)
    if (l == stop) { stop = ""; kept = "" } else kept = kept $0 "\n"
    next
  }
  match($0, /(^|[^<])<<-?[ \t]*/) {
    strip = (substr($0, RSTART, RLENGTH) ~ /<<-/)
    stop = delimiter(substr($0, RSTART + RLENGTH))
  }
  { print }
  END { if (stop != "") printf "%s", kept }')

# One command per line: split at the separators a shell would run them at, and
# never inside quotes, so text that only mentions a write is not one. A $(...),
# a backtick pair or a <(...) runs a command of its own, with quotes of its own:
# what is inside is printed as its own command, and the command around it is
# held and goes on after it with an x where the substitution stood, so the
# words after a substitution are still read as that command. One left open at
# the end gives back what it held. Comments go, and a { in a path is not a
# brace.
commands=$(printf '%s\n' "$text" | LC_ALL=C awk '
  function sub_open(k) { sp++; kind[sp] = k; depth[sp] = 0; held[sp] = seg; back[sp] = quote; seg = ""; quote = "" }
  function sub_shut() { print seg; seg = held[sp] "x"; quote = back[sp]; sp-- }
  { src = src $0 "\n" }
  END {
    n = length(src); quote = ""; seg = ""; sq = "\047"; dq = "\042"; bt = "\140"; sp = 0
    for (i = 1; i <= n; i++) {
      c = substr(src, i, 1); d = substr(src, i + 1, 1); p = (i > 1) ? substr(src, i - 1, 1) : "\n"
      if (quote == sq) { seg = seg (c == "\n" ? " " : c); if (c == sq) quote = ""; continue }
      if (quote == "ansi") {
        if (c == "\\") { seg = seg ((d == "\n") ? " " : c d); i++; continue }
        seg = seg (c == "\n" ? " " : c); if (c == sq) quote = ""; continue
      }
      if (quote == dq) {
        if (c == "\\") { seg = seg ((d == "\n") ? " " : c d); i++; continue }
        if (c == dq) { quote = ""; seg = seg c; continue }
        if (c == "$" && d == "(") { sub_open("("); i++; continue }
        if (c == bt) { sub_open(bt); continue }
        seg = seg (c == "\n" ? " " : c); continue
      }
      if (c == "\\") { seg = seg ((d == "\n") ? " " : c d); i++; continue }
      if (c == "$" && d == sq) { quote = "ansi"; seg = seg c d; i++; continue }
      if (c == sq || c == dq) { quote = c; seg = seg c; continue }
      if ((c == "$" || c == "<" || c == ">") && d == "(") { sub_open("("); i++; continue }
      if (c == bt) { if (sp > 0 && kind[sp] == bt) sub_shut(); else sub_open(bt); continue }
      if (sp > 0 && kind[sp] == "(") {
        if (c == "(") depth[sp]++
        else if (c == ")") {
          if (depth[sp] == 0) { sub_shut(); continue }
          depth[sp]--
        }
      }
      space = (p == " " || p == "\t" || p == "\n" || p == ";")
      if (c == "#" && space) { while (i < n && substr(src, i + 1, 1) != "\n") i++; continue }
      if (c == "\n" || c == ";" || c == "|" || c == "(" || c == ")") { print seg; seg = ""; continue }
      if (c == "&" && p != ">" && d != ">") { print seg; seg = ""; continue }
      if ((c == "{" || c == "}") && space && (d == " " || d == "\t" || d == "\n" || d == ";")) { print seg; seg = ""; continue }
      seg = seg c
    }
    print seg
    while (sp > 0) { print held[sp]; sp-- }
  }')

shopt -s nocasematch
# A command counts where it would run: past keywords, a VAR=value prefix, a
# wrapper that runs it (time, command, exec, timeout 60, nohup, env, sudo,
# doas, nice, ionice, stdbuf, setsid, winpty, each by its path too, with its
# options and a duration), and past the -R of gh and git's own options before
# its verb. gh and git are themselves by any unquoted path, a space in it
# escaped or not there, and as gh.exe; a path after an = is a value, not a
# command. A value, a directory or a refspec may be quoted and hold a space.
# Text after the command is its arguments.
piece="(\"[^\"]*\"|'[^']*'|[^[:space:]\"'])"
# shellcheck disable=SC1003  # a slash or a backslash, not an escaped quote
by_path='(([^[:space:]\\=]|\\.)*[/\\])?'
wrapper='(time|command|exec|sudo|doas|nohup|env|nice|ionice|g?timeout|stdbuf|setsid|winpty)'
# 60, 2.5s, or a variable that holds one; a variable in the command's place
# is skipped the same way.
duration='"?(\$\{?[A-Za-z_][A-Za-z0-9_]*\}?|[0-9]+(\.[0-9]+)?)[smhd]?"?'
at="^[[:space:]]*((then|do|else|elif|if|while|until|!)[[:space:]]+|${by_path}${wrapper}([[:space:]]+-[^[:space:]]+([[:space:]]+[^-=[:space:]][^=[:space:]]*)?)*[[:space:]]+|${duration}[[:space:]]+|[A-Za-z_][A-Za-z0-9_]*=${piece}*[[:space:]]+)*"
repo_flag='((-R|--repo)([[:space:]]+|=)[^[:space:]]+[[:space:]]+)*'
end='([[:space:]<>]|$)'
gh="${at}${by_path}gh(\.exe)?[[:space:]]+$repo_flag"
pr_re="${gh}pr[[:space:]]+$repo_flag(create|new|comment|review|edit|close|merge|ready|reopen|update-branch|revert|lock|unlock)$end"
issue_re="${gh}issue[[:space:]]+$repo_flag(create|new|comment|edit|close|reopen|delete|transfer|develop|lock|unlock|pin|unpin)$end"
# --help anywhere among the words prints the help and writes nothing.
help_re='[[:space:]]--help([[:space:]]|$)'
graphql_re="${gh}api([[:space:]]+(--paginate|--slurp|--include|-i|--silent|--verbose))*[[:space:]]+graphql$end"
api_re="${gh}api$end"
# Git's options before the verb: -C, -c, --git-dir, --work-tree and --namespace
# may take their value as the next word; every other one is a single word.
git_opts="([[:space:]]+(-C|-c|--git-dir|--work-tree|--namespace)[[:space:]]+${piece}+|[[:space:]]+-${piece}+)*"
push_re="${at}${by_path}git(\.exe)?${git_opts}[[:space:]]+push$end"
quote="[\"']?"
mutation_re="(^|[^a-z])mutation([^a-z]|$)"
write_method_re="(-X|--method)[[:space:]=]*${quote}(POST|PATCH|PUT|DELETE)$quote$end"
get_method_re="(-X|--method)[[:space:]=]*${quote}GET$quote$end"
# -f and -F take their value glued too, as in -fbody=x, and ride behind another
# short flag, as in -if.
fields_re='[[:space:]](-[a-z]*f|--field|--raw-field|--input)([[:space:]=]|$)|[[:space:]]-[a-z]*f[^[:space:]-]'
force_re="[[:space:]]${quote}(--force(-with-lease)?|--delete|--mirror|--prune|-[a-zA-Z]*[fd][a-zA-Z]*)${quote}([[:space:]=]|\$)|[[:space:]]${quote}[+:][^[:space:]]"

why=""; why_id=""; push=""
judge() {
  why=""; why_id=""; push=""
  # A pattern costs, and a long script is mostly other commands: one with no
  # "gh" in it is none of the first four, one with no "push" is not the last.
  case "$1" in *[Gg][Hh]*)
    if [[ $1 =~ $pr_re ]]; then
      if [[ $1 =~ $help_re ]]; then return; fi
      why="it writes to a pull request outside the gate; open one with housebroken file, answer one with housebroken reply, withdraw one with housebroken close"
      why_id=gate-pr-write
      return
    elif [[ $1 =~ $issue_re ]]; then
      if [[ $1 =~ $help_re ]]; then return; fi
      why="it writes to an issue outside the gate; open one with housebroken issue, answer one with housebroken reply"
      why_id=gate-issue-write
      return
    elif [[ $1 =~ $graphql_re ]]; then
      # The query may sit in a here-document, which is not among the commands.
      if [[ $1 =~ $mutation_re ]] || [[ $cmd =~ $mutation_re ]]; then why="a GraphQL mutation changes GitHub outside the gate"; why_id=gate-graphql-mutation; fi
      return
    elif [[ $1 =~ $api_re ]]; then
      # gh api reads unless it names a writing method, or sends fields without
      # saying GET.
      if [[ $1 =~ $write_method_re ]]; then
        why="gh api with a writing method changes GitHub outside the gate"
        why_id=gate-api-write-method
      elif [[ $1 =~ $fields_re ]] && ! [[ $1 =~ $get_method_re ]]; then
        why="gh api with fields and no -X GET is a POST, which changes GitHub outside the gate"
        why_id=gate-api-fields-post
      fi
      return
    fi ;;
  esac
  case "$1" in *[Pp][Uu][Ss][Hh]*) ;; *) return ;; esac
  if [[ $1 =~ $push_re ]] && [[ $1 =~ $force_re ]]; then
    why="a forced push or a branch delete rewrites what a maintainer may already have reviewed; push a rework with housebroken push"
    why_id=gate-push-force-or-delete
    push=1
  fi
}

# The command with its quotes gone: quoted text that holds a space is prose (a
# body, a title) and is dropped, any other is the word it quotes.
unquoted() {
  local s="$1" out="" buf="" q="" c i
  for ((i = 0; i < ${#s}; i++)); do
    c=${s:i:1}
    if [ -n "$q" ]; then
      if [ "$c" != "$q" ]; then buf+=$c; continue; fi
      case "$buf" in *[[:space:]]*) ;; *) out+=$buf ;; esac
      q=""; buf=""
    elif [ "$c" = '"' ] || [ "$c" = "'" ]; then q=$c
    else out+=$c
    fi
  done
  printf '%s' "$out$buf"
}

# Your own repositories: the door is for other people's. Only a repository this
# command names counts, and every one it names must be yours: with none named,
# gh picks one from the clone, and in a fork's clone that is the upstream
# parent; with two, gh takes the last, and a link outranks -R. The flag is read
# as typed, because -r is a reviewer.
is_own() {
  local text rest re group owners="" owner o listed
  [ -s "$own" ] || return 1
  if [[ $1 =~ $api_re ]]; then
    re='[[:space:]]/?repos/([A-Za-z0-9_.-]+)/'; group=1
  else
    re='[[:space:]]((-R|--repo)([[:space:]]+|=)|https?://[^/[:space:]]+/)([A-Za-z0-9_.-]+)/'; group=4
  fi
  text=" $(unquoted "$1")"
  shopt -u nocasematch
  rest=$text
  while [[ $rest =~ $re ]]; do
    owners="$owners${BASH_REMATCH[$group]}"$'\n'
    rest=${rest#*"${BASH_REMATCH[0]}"}
  done
  shopt -s nocasematch
  [ -n "$owners" ] || return 1
  while IFS= read -r owner; do
    [ -n "$owner" ] || continue
    listed=0
    while IFS= read -r o || [ -n "$o" ]; do
      o=${o%"${o##*[![:space:]]}"}
      if [[ $o == "$owner" ]]; then listed=1; break; fi
    done < "$own"
    [ "$listed" = 1 ] || return 1
  done <<< "$owners"
  return 0
}

while IFS= read -r c; do
  # Most commands in a long script name neither tool, and are not read further.
  case "$c" in *[Gg][Hh]*|*[Gg][Ii][Tt]*) ;; *) continue ;; esac
  judge "$c"
  [ -n "$why" ] || continue
  if [ -z "$push" ] && is_own "$c"; then continue; fi
  {
    echo "housebroken: refused: $why. [$why_id]"
    if [ -n "$push" ]; then
      echo "If the user asked for exactly this, they can run it themselves."
    else
      echo "If the user asked for exactly this, they can run it themselves; a repository of their own passes once its owner is listed in $own."
    fi
  } >&2
  log_refusal "$why_id"
  exit 2
done <<< "$commands"
exit 0
