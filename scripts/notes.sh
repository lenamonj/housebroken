#!/bin/bash
# notes.sh - what a repository's maintainers have asked for before.
#
# Preferences outlive one pull request. google/benchmark wants no comment and
# no default arguments; Kotlin/kotlinx-datetime wants the test in the JVM suite
# that compares against java.time; apple/swift-log wants the package's own Lock
# in tests; cloudflare/circl answers its review bots itself. A note is written
# once, when the maintainer says it, and read before the next pull request and
# before every rework.
#
# Usage:
#   bash notes.sh owner/repo                # print the notes for one repository
#   bash notes.sh owner/repo add "<text>"   # append a dated line
#   bash notes.sh --list                    # repositories that have notes
#   bash notes.sh --help
#
# Environment:
#   HOUSEBROKEN_HOME  workshop root, default $HOME/.housebroken. A repository's
#                     notes live in $HOUSEBROKEN_HOME/notes/<owner>-<repo>.md
#
# Assumes: bash. No network, no gh, no jq.
set -u

usage() {
  sed -n '2,/^set -u$/p' "$0" | sed 's/^# \{0,1\}//; /^set -u$/d'
}

NOTES_DIR="${HOUSEBROKEN_HOME:-$HOME/.housebroken}/notes"

list_repos() {
  found=0
  for f in "$NOTES_DIR"/*.md; do
    [ -f "$f" ] || continue
    # the header line names the repository; the file name cannot, because an
    # owner and a repository may both contain a hyphen
    name="$(sed -n '1s/^# notes: //p' "$f")"
    [ -n "$name" ] || name="$(basename "$f" .md)"
    echo "$name"
    found=1
  done
  [ "$found" = 1 ] || echo "no repositories have notes yet"
}

case "${1:-}" in
  --help|-h) usage; exit 0 ;;
  --list) list_repos; exit 0 ;;
  "") echo "notes.sh: expected owner/repo, --list or --help" >&2; usage >&2; exit 2 ;;
esac

target="$1"
case "$target" in
  */*/*|/*|*/) echo "notes.sh: expected owner/repo, got: $target" >&2; exit 2 ;;
  */*) ;;
  *) echo "notes.sh: expected owner/repo, got: $target" >&2; exit 2 ;;
esac
file="$NOTES_DIR/${target%%/*}-${target#*/}.md"
shift

if [ $# -eq 0 ]; then
  if [ -f "$file" ]; then
    cat "$file"
  else
    echo "no notes for $target"
  fi
  exit 0
fi

[ "$1" = "add" ] || { echo "notes.sh: unknown action: $1" >&2; usage >&2; exit 2; }
shift
text="${1:-}"
[ -n "$text" ] || { echo "notes.sh: add needs the note text" >&2; exit 2; }

if ! mkdir -p "$NOTES_DIR"; then
  echo "notes.sh: cannot create $NOTES_DIR" >&2
  exit 1
fi
if [ ! -f "$file" ]; then
  printf '# notes: %s\n' "$target" > "$file" || {
    echo "notes.sh: cannot write $file" >&2; exit 1; }
fi
printf -- '- %s: %s\n' "$(date -u +%Y-%m-%d)" "$text" >> "$file" || {
  echo "notes.sh: cannot append to $file" >&2; exit 1; }
echo "noted for $target in $file"
