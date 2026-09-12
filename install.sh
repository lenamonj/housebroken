#!/bin/bash
# install.sh - put housebroken where the current user's agent can reach it.
#
# Two destinations and nothing else: the gate scripts, the `housebroken`
# dispatcher and a VERSION file go into $HOUSEBROKEN_HOME/bin, and the skill
# directory goes into $HOME/.claude/skills/housebroken, which is where Claude
# Code looks for a user skill. No profile is edited, no PATH is changed, no
# state is written anywhere else; when the bin directory is not on PATH the
# one line to add is printed for the operator to add by hand.
#
# Other agent hosts (Codex, Cursor, Copilot) are not wired up yet.
# skills/housebroken/SKILL.md is the source of truth for every future adapter:
# an adapter converts that file, it does not restate its rules.
#
# Usage:
#   bash install.sh              # install
#   bash install.sh --dry-run    # print what it would do, change nothing
#   bash install.sh --uninstall  # remove exactly what install put there
#   bash install.sh --help
#
# Environment:
#   HOUSEBROKEN_HOME  install root, default $HOME/.housebroken. The scripts and
#                     the dispatcher go in its bin/ subdirectory.
#   HOME              the user home; $HOME/.claude/skills is the skill root.
#
# Assumes bash and a writable HOME. Works from any working directory: the repo
# root is resolved from this file's own location.
set -u

usage() {
  sed -n '2,/^set -u$/p' "$0" | sed 's/^# \{0,1\}//; /^set -u$/d'
}

mode=install
case "${1:-}" in
  --help|-h) usage; exit 0 ;;
  --dry-run|-n) mode=dry ;;
  --uninstall) mode=uninstall ;;
  "") ;;
  *) echo "install.sh: unknown argument: $1" >&2; usage >&2; exit 2 ;;
esac

repo=$(cd "$(dirname "$0")" && pwd)
HOUSEBROKEN_HOME="${HOUSEBROKEN_HOME:-$HOME/.housebroken}"
bindir="$HOUSEBROKEN_HOME/bin"
skilldir="$HOME/.claude/skills/housebroken"

for need in "$repo/scripts" "$repo/bin/housebroken" "$repo/skills/housebroken" "$repo/pyproject.toml"; do
  if [ ! -e "$need" ]; then
    echo "install.sh: missing from the repository: $need" >&2
    exit 1
  fi
done
version=$(sed -n 's/^version = "\(.*\)"/\1/p' "$repo/pyproject.toml" | head -1)

if [ "$mode" = uninstall ]; then
  for f in "$repo"/scripts/*.sh; do
    target="$bindir/$(basename "$f")"
    [ -e "$target" ] && rm -f "$target" && echo "removed $target"
  done
  for target in "$bindir/housebroken" "$bindir/VERSION"; do
    if [ -e "$target" ]; then
      rm -f "$target"
      echo "removed $target"
    fi
  done
  if [ -d "$skilldir" ]; then
    rm -rf "$skilldir"
    echo "removed $skilldir"
  fi
  rmdir "$bindir" 2>/dev/null && echo "removed $bindir"
  rmdir "$HOUSEBROKEN_HOME" 2>/dev/null && echo "removed $HOUSEBROKEN_HOME"
  echo "uninstalled housebroken"
  exit 0
fi

if [ "$mode" = dry ]; then
  echo "would create $bindir"
  for f in "$repo"/scripts/*.sh; do
    echo "would copy $(basename "$f") to $bindir"
  done
  echo "would copy housebroken to $bindir"
  echo "would write VERSION (housebroken $version) to $bindir"
  echo "would create $skilldir"
  echo "would copy the skill from $repo/skills/housebroken to $skilldir"
  exit 0
fi

mkdir -p "$bindir"
for f in "$repo"/scripts/*.sh; do
  cp "$f" "$bindir/"
  chmod +x "$bindir/$(basename "$f")" 2>/dev/null || true
  echo "installed $bindir/$(basename "$f")"
done
cp "$repo/bin/housebroken" "$bindir/housebroken"
chmod +x "$bindir/housebroken" 2>/dev/null || true
echo "installed $bindir/housebroken"
echo "housebroken $version" > "$bindir/VERSION"
echo "installed $bindir/VERSION"

rm -rf "$skilldir"
mkdir -p "$skilldir"
cp -R "$repo/skills/housebroken/." "$skilldir/"
echo "installed $skilldir"

case ":${PATH:-}:" in
  *":$bindir:"*) ;;
  *)
    echo
    echo "$bindir is not on PATH. Add this line to your shell profile:"
    echo "  export PATH=\"$bindir:\$PATH\""
    ;;
esac
