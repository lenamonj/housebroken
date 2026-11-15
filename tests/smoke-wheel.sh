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

# Windows has python and venv/Scripts where the others have python3 and venv/bin,
# and its Python prints paths with backslashes and CRLF.
py=$(command -v python3 || command -v python) || fail "no python on PATH"
"$py" -m venv "$work/venv" || fail "cannot make a venv"
bin="$work/venv/bin"; [ -d "$bin" ] || bin="$work/venv/Scripts"
"$bin/python" -m pip install -q --no-index "$wheel" || fail "the wheel does not install"
export HOME="$work/home" HOUSEBROKEN_HOME="$work/home/.housebroken" PATH="$bin:$here/stubs:$PATH"
mkdir -p "$HOME"

want=$(sed -n 's/^version = "\(.*\)"$/\1/p' "$here/../pyproject.toml" | tr -d '\r')
got=$(housebroken version | tr -d '\r')
[ "$got" = "housebroken $want" ] || fail "the wheel says $got, the tree says $want"
housebroken help | grep -q "prior-art" || fail "housebroken help printed no door"

scripts="$(dirname "$(housebroken skill-path | tr -d '\r' | tr '\\' '/')")/../scripts"
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

# The installed hook, as Claude Code runs it: a write is refused, a read is not.
hook="$HOME/.claude/hooks/housebroken-gate.sh"
printf '{"tool_input": {"command": "gh.exe pr create -R a/b --title x"}}' | bash "$hook" 2>/dev/null
[ "$?" = 2 ] || fail "the installed hook did not refuse a write"
printf '{"tool_input": {"command": "gh pr view 5 -R a/b"}}' | bash "$hook" || fail "the installed hook refused a read"

echo "PASS smoke-wheel ($got)"
