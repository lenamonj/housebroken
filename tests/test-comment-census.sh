#!/bin/bash
# test-comment-census.sh - census counts 3 code lines and 2 comment lines on a
# branch of a real clone. Read-only against GitHub (one shallow clone).
set -u
name=test-comment-census
script="$(cd "$(dirname "$0")/../scripts" && pwd)/comment-census.sh"

bash "$script" --help | grep -q "Usage:" || { echo "FAIL $name: --help has no usage"; exit 1; }
bash "$script" /definitely/not/a/directory 2>/dev/null && { echo "FAIL $name: bad root exited 0"; exit 1; }

root=$(mktemp -d) || exit 1
trap 'rm -rf "$root"' EXIT
git clone --depth 50 -q https://github.com/spf13/pflag "$root/pflag" || { echo "FAIL $name: clone failed"; exit 1; }
(
  cd "$root/pflag" || exit 1
  git checkout -q -b census-fixture
  printf 'package pflag\n\nvar censusOne = 1\n// a comment line\nvar censusTwo = 2\n// another comment line\n' > census_fixture.go
  git -c user.email=t@example.com -c user.name=t add census_fixture.go
  git -c user.email=t@example.com -c user.name=t commit -q -m "census fixture"
) || { echo "FAIL $name: fixture branch failed"; exit 1; }

out=$(bash "$script" "$root") || { echo "FAIL $name: script exited non-zero"; echo "$out"; exit 1; }
echo "$out"
row=$(echo "$out" | grep 'census-fixture')
[ -n "$row" ] || { echo "FAIL $name: no row for census-fixture"; exit 1; }
code=$(echo "$row" | awk '{print $3}')
cmnt=$(echo "$row" | awk '{print $4}')
if [ "$code" != "3" ] || [ "$cmnt" != "2" ]; then
  echo "FAIL $name: expected code=3 cmnt=2, got code=$code cmnt=$cmnt"
  exit 1
fi
echo "PASS $name"
