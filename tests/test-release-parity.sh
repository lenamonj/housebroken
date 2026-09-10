#!/bin/bash
# test-release-parity.sh - the version in pyproject.toml is on PyPI, and every
# GitHub release produced an artifact.
#
# On 2026-09-10 version 0.3.0 was bumped, committed and pushed, and the release
# that publishes it was left for later, so the gate that had just been written
# was in git and nowhere a user could install it. Jeff: "let's make sure all our
# updates are being pushed to pypi or it kinda defeats the purpose of updating
# them." A bump and its release are one action; this test is what says so.
#
# Both lists are asserted non-empty first. A comparison against a list that
# failed to load reports parity for the wrong reason, which is how the first
# version of this check passed while reading no tags at all.
set -u
name=test-release-parity
root="$(cd "$(dirname "$0")/.." && pwd)"
repo=lenamonj/housebroken

command -v gh >/dev/null 2>&1 || { echo "SKIP $name: gh not on PATH"; exit 0; }
gh auth status >/dev/null 2>&1 || { echo "SKIP $name: gh not authenticated"; exit 0; }

current=$(grep -m1 '^version = ' "$root/pyproject.toml" | sed 's/.*"\(.*\)".*/\1/')
[ -n "$current" ] || { echo "FAIL $name: no version in pyproject.toml"; exit 1; }

releases=$(gh release list --repo "$repo" --limit 100 2>/dev/null | awk '/^v/ {print substr($1,2)}')
[ -n "$releases" ] || { echo "FAIL $name: read no releases, so any comparison is vacuous"; exit 1; }

published=$(curl -sS --max-time 30 "https://pypi.org/simple/housebroken-cli/" 2>/dev/null \
  | grep -oE 'housebroken_cli-[0-9]+\.[0-9]+\.[0-9]+-py3' | sed 's/housebroken_cli-//;s/-py3//' | sort -u)
[ -n "$published" ] || { echo "SKIP $name: could not read the PyPI index"; exit 0; }

missing=""
for v in $releases; do
  printf '%s\n' "$published" | grep -qx "$v" || missing="$missing $v"
done
if [ -n "$missing" ]; then
  echo "FAIL $name: released but not on PyPI:$missing"
  exit 1
fi

if ! printf '%s\n' "$published" | grep -qx "$current"; then
  echo "FAIL $name: pyproject is $current and PyPI has no such version - cut the release"
  exit 1
fi

echo "PASS $name ($current on PyPI, $(printf '%s\n' "$releases" | grep -c .) releases all published)"
