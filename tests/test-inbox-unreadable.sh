#!/bin/bash
# test-inbox-unreadable.sh - a pull request the census cannot read must be
# reported, never skipped in silence. Stubs gh so every `gh pr view` fails while
# the listing still returns two pull requests.
set -u
name=test-inbox-unreadable
script="$(cd "$(dirname "$0")/../scripts" && pwd)/inbox.sh"

tmp=$(mktemp -d) || { echo "FAIL $name: mktemp failed"; exit 1; }
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
cat > "$tmp/bin/gh" <<'STUB'
#!/bin/bash
case "$1" in
  api)
    case "$2" in
      *search/issues*) echo 2 ;;
      *) : ;;
    esac ;;
  search) printf 'acme/foo 1 false\nacme/bar 2 false\n' ;;
  pr) exit 1 ;;
  *) : ;;
esac
STUB
chmod +x "$tmp/bin/gh"

out=$(PATH="$tmp/bin:$PATH" HOUSEBROKEN_USER=someone HOUSEBROKEN_HOME="$tmp" bash "$script" --since 2026-01-01T00:00:00Z 2>&1)
echo "$out" | grep -q "CENSUS UNREADABLE" || { echo "FAIL $name: unreadable pull requests were skipped in silence"; echo "$out" | tail -5; exit 1; }
echo "$out" | grep -q "could not read 2 of 2" || { echo "FAIL $name: wrong count"; echo "$out" | grep CENSUS; exit 1; }
echo "$out" | grep -q "acme/foo#1" || { echo "FAIL $name: does not name the pull requests"; exit 1; }
echo "PASS $name"
