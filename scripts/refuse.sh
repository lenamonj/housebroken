#!/bin/bash
# refuse.sh - how a gate says no. Sourced, never run.
#
# Every refusal ends with the permanent name of the rule that made it, in
# brackets, and leaves one line in a local log: the UTC time, the name, and
# the repository when the script holds one in $repo. The log holds no message
# text, so nothing a stranger wrote reaches it, and it never leaves the
# machine. A log that cannot be written is said once on stderr and changes no
# verdict and no exit status.
#
#   refused NAME MESSAGE    prints "REFUSED: MESSAGE [NAME]" on stdout and logs
#                           it; the caller keeps its own redirect and exit. When
#                           MESSAGE runs over several lines the name ends the
#                           first, the one that says REFUSED
#   refusal_log NAME        the log line alone
#   reason NAME MESSAGE     prints "NAME|MESSAGE", for a check that hands its
#                           reasons back as text
#   refused_reason PAIR     refused, for one such "NAME|MESSAGE" line
#
# A name is lowercase words joined by hyphens and begins with its script's
# name. tests/test-refusal-ids.sh reads every name from the scripts and holds
# each to one site.
#
# Environment:
#   HOUSEBROKEN_HOME  work directory, default $HOME/.housebroken; the log is
#                     refusals.tsv in it

refusal_log_said=""

refusal_log() { # name
  local home="${HOUSEBROKEN_HOME:-$HOME/.housebroken}" where="-"
  if ! [[ "$1" =~ ^[a-z0-9]+(-[a-z0-9]+)+$ ]]; then
    echo "housebroken: a refusal that carries no rule name was not logged" >&2
    return 0
  fi
  if [[ "${repo:-}" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then where="$repo"; fi
  if ! { mkdir -p "$home" && printf '%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$where" >> "$home/refusals.tsv"; } 2>/dev/null; then
    [ -n "$refusal_log_said" ] || echo "housebroken: the refusal log at $home/refusals.tsv could not be written" >&2
    refusal_log_said=1
  fi
  return 0
}

refused() { # name message; the name ends the line that says REFUSED, whatever follows it
  local nl='
'
  case "$2" in
    *"$nl"*) echo "REFUSED: ${2%%"$nl"*} [$1]$nl${2#*"$nl"}" ;;
    *) echo "REFUSED: $2 [$1]" ;;
  esac
  refusal_log "$1"
}

reason() { # name message
  echo "$1|$2"
}

refused_reason() { # "name|message"
  case "$1" in
    *"|"*) refused "${1%%|*}" "${1#*|}" ;;
    *) echo "REFUSED: $1"; refusal_log "" ;;
  esac
}
