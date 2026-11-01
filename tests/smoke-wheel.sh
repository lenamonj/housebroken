#!/bin/bash
# smoke-wheel.sh - what a release ships actually runs. Installs the built wheel
# into a fresh venv under a throwaway HOME, checks every gate script arrived and
# parses, and drives the shipped command. publish.yml runs this before upload:
# a wheel that builds is not a wheel that works.
#
# Usage:
#   bash tests/smoke-wheel.sh dist/housebroken_cli-X.Y.Z-py3-none-any.whl
set -u

fail() { echo "FAIL smoke-wheel: $1" >&2; exit 1; }

wheel="${1:-}"
[ -f "$wheel" ] || fail "name the wheel to test"
here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d) || exit 1
trap 'rm -rf "$work"' EXIT

python3 -m venv "$work/venv" || fail "cannot make a venv"
"$work/venv/bin/python" -m pip install -q --no-index "$wheel" || fail "the wheel does not install"
export HOME="$work/home" HOUSEBROKEN_HOME="$work/home/.housebroken" PATH="$work/venv/bin:$here/stubs:$PATH"
mkdir -p "$HOME"

want=$(sed -n 's/^version = "\(.*\)"$/\1/p' "$here/../pyproject.toml" | tr -d '\r')
[ "$(housebroken version)" = "housebroken $want" ] || fail "the wheel says $(housebroken version), the tree says $want"
housebroken help | grep -q "prior-art" || fail "housebroken help printed no door"

scripts="$(dirname "$(housebroken skill-path)")/../scripts"
for f in "$here"/../scripts/*; do
  shipped="$scripts/$(basename "$f")"
  [ -f "$shipped" ] || fail "$(basename "$f") is not in the wheel"
  bash -n "$shipped" || fail "$(basename "$f") does not parse"
done
[ -f "$scripts/housebroken" ] || fail "the dispatcher is not in the wheel"

housebroken install-skill >/dev/null || fail "install-skill failed"
[ -f "$HOME/.claude/skills/housebroken/SKILL.md" ] || fail "install-skill wrote no skill"
housebroken install-hook >/dev/null || fail "install-hook failed"
[ -f "$HOME/.claude/hooks/housebroken-gate.sh" ] || fail "install-hook wrote no hook"
housebroken prior-art --help | grep -q "usage: prior-art.sh" || fail "a subcommand did not reach its script"

echo "PASS smoke-wheel ($(housebroken version))"
