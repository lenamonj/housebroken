#!/bin/bash
# test-version-sync.sh - the package version in pyproject.toml is the one
# `housebroken --version` prints. __init__.py read 0.6.4 through all of 0.6.5.
set -u
name=test-version-sync
root="$(cd "$(dirname "$0")/.." && pwd)"
project=$(sed -n 's/^version = "\(.*\)"$/\1/p' "$root/pyproject.toml" | tr -d '\r')
package=$(sed -n 's/^__version__ = "\(.*\)"$/\1/p' "$root/src/housebroken/__init__.py" | tr -d '\r')
[ -n "$project" ] || { echo "FAIL $name: no version in pyproject.toml"; exit 1; }
[ "$project" = "$package" ] || { echo "FAIL $name: pyproject.toml says $project, __init__.py says $package"; exit 1; }
echo "PASS $name"
