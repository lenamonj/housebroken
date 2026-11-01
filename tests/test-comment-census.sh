#!/bin/bash
# test-comment-census.sh - census counts 3 code lines and 2 comment lines on a
# branch of a local clone, then two more for the neighbourhood rule: a comment
# added into a comment-free body under a licence header is flagged, a comment
# added beside an existing comment is not.
set -u
name=test-comment-census
script="$(cd "$(dirname "$0")/../scripts" && pwd)/comment-census.sh"

bash "$script" --help | grep -q "Usage:" || { echo "FAIL $name: --help has no usage"; exit 1; }
bash "$script" /definitely/not/a/directory 2>/dev/null && { echo "FAIL $name: bad root exited 0"; exit 1; }

root=$(mktemp -d) || exit 1
trap 'rm -rf "$root"' EXIT
mkdir -p "$root/up/src" || exit 1
(
  cd "$root/up/src" || exit 1
  git init -q .
  printf 'package pflag\n' > flag.go
  git -c user.email=t@example.com -c user.name=t add flag.go
  git -c user.email=t@example.com -c user.name=t commit -q -m base
) || { echo "FAIL $name: source repo failed"; exit 1; }
git clone -q "$root/up/src" "$root/pflag" || { echo "FAIL $name: clone failed"; exit 1; }
rm -rf "$root/up"
(
  cd "$root/pflag" || exit 1
  git checkout -q -b census-fixture
  printf 'package pflag\n\nvar censusOne = 1\n// a comment line\nvar censusTwo = 2\n// another comment line\n' > census_fixture.go
  git -c user.email=t@example.com -c user.name=t add census_fixture.go
  git -c user.email=t@example.com -c user.name=t commit -q -m "census fixture"
) || { echo "FAIL $name: fixture branch failed"; exit 1; }

out=$(bash "$script" "$root") || { echo "FAIL $name: script exited non-zero"; echo "$out"; exit 1; }
echo "$out"
row=$(echo "$out" | grep -E '^pflag[[:space:]]+census-fixture[[:space:]]')
[ -n "$row" ] || { echo "FAIL $name: no row for census-fixture"; exit 1; }
code=$(echo "$row" | awk '{print $3}')
cmnt=$(echo "$row" | awk '{print $4}')
if [ "$code" != "3" ] || [ "$cmnt" != "2" ]; then
  echo "FAIL $name: expected code=3 cmnt=2, got code=$code cmnt=$cmnt"
  exit 1
fi
work=$(mktemp -d) || exit 1
trap 'rm -rf "$root" "$work"' EXIT
mkdir -p "$work/src/pkg" "$work/clones" || { echo "FAIL $name: mkdir failed"; exit 1; }
{
  i=1
  while [ "$i" -le 12 ]; do echo "// Copyright line $i"; i=$((i + 1)); done
  echo
  echo "package widget"
  echo
  i=1
  while [ "$i" -le 45 ]; do echo "var v$i = $i"; i=$((i + 1)); done
} > "$work/src/pkg/widget.go"
{
  i=1
  while [ "$i" -le 12 ]; do echo "// Copyright line $i"; i=$((i + 1)); done
  echo
  echo "package widget"
  echo
  i=1
  while [ "$i" -le 14 ]; do echo "var w$i = $i"; i=$((i + 1)); done
  echo "// existing note on the counters"
  i=15
  while [ "$i" -le 30 ]; do echo "var w$i = $i"; i=$((i + 1)); done
} > "$work/src/pkg/doc.go"
(
  cd "$work/src" || exit 1
  git init -q .
  git -c user.email=t@example.com -c user.name=t add pkg
  git -c user.email=t@example.com -c user.name=t commit -q -m "base"
) || { echo "FAIL $name: source repo failed"; exit 1; }
git clone -q "$work/src" "$work/clones/widget" || { echo "FAIL $name: local clone failed"; exit 1; }
(
  cd "$work/clones/widget" || exit 1
  start=$(git rev-parse --abbrev-ref HEAD)
  git checkout -q -b flag-case
  perl -pi -e 'print "// a note about the counters\n" if $. == 28' pkg/widget.go
  git -c user.email=t@example.com -c user.name=t commit -qam "comment into a comment-free body"
  git checkout -q "$start"
  git checkout -q -b noflag-case
  perl -pi -e 'print "// a second note on the counters\n" if $. == 32' pkg/doc.go
  git -c user.email=t@example.com -c user.name=t commit -qam "comment beside an existing comment"
) || { echo "FAIL $name: fixture branches failed"; exit 1; }

out2=$(bash "$script" "$work/clones") || { echo "FAIL $name: script exited non-zero on the local clones"; echo "$out2"; exit 1; }
echo "$out2"
echo "$out2" | grep -q '^FLAG .* pkg/widget.go:28 ' || { echo "FAIL $name: no FLAG for the comment-free neighbourhood"; exit 1; }
echo "$out2" | grep '^FLAG ' | grep -q 'pkg/doc.go' && { echo "FAIL $name: flagged a comment next to an existing comment"; exit 1; }
echo "$out2" | grep -q '^1 comment lines added into comment-free neighbourhoods$' || { echo "FAIL $name: summary line wrong"; exit 1; }

# a # comment counts and #include does not; what the base dropped since the
# branch forked is not something the branch added
hash=$(mktemp -d) || exit 1
trap 'rm -rf "$root" "$work" "$hash"' EXIT
mkdir -p "$hash/up" "$hash/clones"
(
  cd "$hash/up" || exit 1
  git init -q .
  printf 'x = 1\nold = 2\n' > a.py
  git -c user.email=t@example.com -c user.name=t add a.py
  git -c user.email=t@example.com -c user.name=t commit -q -m base
) || { echo "FAIL $name: hash fixture failed"; exit 1; }
git clone -q "$hash/up" "$hash/clones/h" || { echo "FAIL $name: hash clone failed"; exit 1; }
(
  cd "$hash/clones/h" || exit 1
  git checkout -q -b comments
  printf 'x = 1\nold = 2\n# one\n# two\n' > a.py
  printf '#include <a.h>\nint i;\n' > b.c
  git -c user.email=t@example.com -c user.name=t add -A
  git -c user.email=t@example.com -c user.name=t commit -q -m comments
) || { echo "FAIL $name: hash branch failed"; exit 1; }
(
  cd "$hash/up" || exit 1
  printf 'x = 1\n' > a.py
  git -c user.email=t@example.com -c user.name=t commit -qam "upstream drops old"
) || { echo "FAIL $name: upstream move failed"; exit 1; }
git -C "$hash/clones/h" fetch -q origin || { echo "FAIL $name: fetch failed"; exit 1; }
out3=$(bash "$script" "$hash/clones") || { echo "FAIL $name: script exited non-zero on the # fixture: $out3"; exit 1; }
row=$(echo "$out3" | grep -E '^h[[:space:]]+comments[[:space:]]')
code=$(echo "$row" | awk '{print $3}'); cmnt=$(echo "$row" | awk '{print $4}')
if [ "$code" != "2" ] || [ "$cmnt" != "2" ]; then
  echo "FAIL $name: expected code=2 cmnt=2 for the # fixture, got code=$code cmnt=$cmnt: $out3"
  exit 1
fi

echo "PASS $name"
