#!/bin/bash
# test-distinct-outside.sh - scripts/distinct-outside.sh over a stub page of
# closed pull requests: outside and team authors are counted apart, bots and
# old merges are left out, and --days moves the window.
set -u
name="distinct-outside.sh"
here=$(cd "$(dirname "$0")" && pwd)
script="$here/../scripts/distinct-outside.sh"
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
export HOUSEBROKEN_HOME="$root/home" STUB_DIR="$root"

fail() { echo "FAIL $name: $1" >&2; exit 1; }

iso() { date -u -d "$1 days ago" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-"$1"d +%Y-%m-%dT%H:%M:%SZ; }
mkdir -p "$root/bin"
cat > "$root/bin/gh" <<'STUB'
#!/bin/bash
case "$*" in
  *"&page=1"*) cat "$STUB_DIR/page1.json" ;;
  *) echo '[]' ;;
esac
STUB
chmod +x "$root/bin/gh"
export PATH="$root/bin:$PATH"
cat > "$root/page1.json" <<EOF
[{"user":{"login":"alice"},"author_association":"CONTRIBUTOR","merged_at":"$(iso 10)"},
 {"user":{"login":"bob"},"author_association":"NONE","merged_at":"$(iso 60)"},
 {"user":{"login":"team1"},"author_association":"MEMBER","merged_at":"$(iso 10)"},
 {"user":{"login":"dependabot[bot]"},"author_association":"NONE","merged_at":"$(iso 10)"},
 {"user":{"login":"late"},"author_association":"NONE","merged_at":"$(iso 200)"},
 {"user":{"login":"unmerged"},"author_association":"NONE","merged_at":null}]
EOF

help=$(bash "$script" --help) || fail "--help exited non-zero"
printf '%s' "$help" | grep -q "usage: distinct-outside.sh" || fail "--help printed no usage line"

out=$(bash "$script" o/r) || fail "run exited non-zero"
printf '%s\n' "$out" | grep -qE '^o/r: 2 distinct outside humans in 120d ->' || fail "wrong count for the default window: $out"
printf '%s\n' "$out" | grep -q '"team1":1' || fail "team merges were not reported: $out"
printf '%s\n' "$out" | grep -q 'dependabot' && fail "a bot was counted: $out"

out=$(bash "$script" --days 30 o/r) || fail "--days 30 run exited non-zero"
printf '%s\n' "$out" | grep -qE '^o/r: 1 distinct outside humans in 30d ->' || fail "--days was not applied: $out"

bash "$script" --days notanumber o/r >/dev/null 2>&1 && fail "--days notanumber was accepted"

echo "PASS $name"
