#!/bin/bash
# test-policy-unread.sh - check-ai-policy.sh through a stub gh, no network: a
# throttled tree or file call, a truncated tree and a failing org .github call
# read UNREAD with exit 1, never CLEAN; --accept-truncated records the
# acceptance; a ban in a policy file past 40 READMEs is still read; a missing
# org .github repository (404) is not a failure; and file-pr.sh refuses an
# UNREAD printout.
set -u
name=test-policy-unread
here=$(cd "$(dirname "$0")" && pwd)
script="$here/../scripts/check-ai-policy.sh"
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
export HOUSEBROKEN_HOME="$root/home" STUB_DIR="$root"
mkdir -p "$root/bin" "$root/files"

fail() { echo "FAIL $name: $1" >&2; exit 1; }

cat > "$root/bin/gh" <<'STUB'
#!/bin/bash
args="$*"
case "$args" in
  *"git/trees/"*)
    [ "${STUB_TREE_FAIL:-0}" = 1 ] && exit 1
    json=$(jq -Rn --argjson t "${STUB_TRUNCATED:-false}" \
      '{truncated: $t, tree: [inputs | {path: ., type: "blob"}]}' < "$STUB_DIR/tree.txt")
    case "$args" in
      *--jq*) printf '%s' "$json" | jq -r '.tree[] | select(.type == "blob") | .path' ;;
      *) printf '%s' "$json" ;;
    esac ;;
  *"/contents/"*)
    [ "${STUB_CONTENTS_FAIL:-0}" = 1 ] && exit 1
    f=$(printf '%s' "$args" | sed -n 's/.*contents\/\([^?]*\)?.*/\1/p')
    base64 < "$STUB_DIR/files/$f" | tr -d '\n' ;;
  *"repos/o/.github"*)
    if [ "${STUB_ORG_FAIL:-0}" = 1 ]; then echo "gh: API rate limit exceeded (HTTP 403)" >&2
    else echo "gh: Not Found (HTTP 404)" >&2; fi
    exit 1 ;;
  *"repos/o/r"*) echo main ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$root/bin/gh"
export PATH="$root/bin:$PATH"

reading() { printf '%s\n' "$1" | grep -m1 '^RESULT: ' | awk '{print $2}'; }
want() { [ "$(reading "$out")" = "$1" ] && [ "$rc" -eq "$2" ]; }

printf 'CONTRIBUTING.md\n' > "$root/tree.txt"
printf 'We do not accept AI-generated pull requests.\n' > "$root/files/CONTRIBUTING.md"

out=$(bash "$script" o/r); rc=$?
want BAN 4 || fail "control: a readable ban read $(reading "$out") exit $rc"

out=$(STUB_CONTENTS_FAIL=1 bash "$script" o/r); rc=$?
want UNREAD 1 || fail "a failed contents call read $(reading "$out") exit $rc, expected UNREAD exit 1"
printf '%s\n' "$out" | grep -q "UNREAD: CONTRIBUTING.md" || fail "the unread file was not named"

out=$(STUB_TREE_FAIL=1 bash "$script" o/r); rc=$?
want UNREAD 1 || fail "a failed tree call read $(reading "$out") exit $rc"

out=$(STUB_ORG_FAIL=1 bash "$script" o/r); rc=$?
[ "$(reading "$out")" = BAN ] || fail "a ban with a failed org call read $(reading "$out"), a ban must still win"
printf 'nothing here\n' > "$root/files/CONTRIBUTING.md"
out=$(STUB_ORG_FAIL=1 bash "$script" o/r); rc=$?
[ "$(reading "$out")" = UNREAD ] || fail "a throttled org .github call read $(reading "$out"), expected UNREAD"
out=$(bash "$script" o/r); rc=$?
want CLEAN 0 || fail "a 404 org .github read $(reading "$out") exit $rc, expected CLEAN"

out=$(STUB_TRUNCATED=true bash "$script" o/r); rc=$?
want UNREAD 1 || fail "a truncated tree read $(reading "$out") exit $rc"
out=$(STUB_TRUNCATED=true bash "$script" --accept-truncated o/r); rc=$?
[ "$(reading "$out")" = CLEAN ] || fail "--accept-truncated read $(reading "$out")"
printf '%s\n' "$out" | grep -q "accepted by --accept-truncated" || fail "the acceptance was not recorded"

: > "$root/tree.txt"
for i in $(seq 1 41); do
  printf 'packages/p%02d/README.md\n' "$i" >> "$root/tree.txt"
  mkdir -p "$root/files/packages/p$(printf '%02d' "$i")"
  printf 'a package\n' > "$root/files/packages/p$(printf '%02d' "$i")/README.md"
done
printf 'tools/CONTRIBUTING.md\n' >> "$root/tree.txt"
mkdir -p "$root/files/tools"
printf 'AI-written pull requests are not accepted.\n' > "$root/files/tools/CONTRIBUTING.md"
out=$(bash "$script" o/r); rc=$?
[ "$(reading "$out")" = BAN ] || fail "a ban in file 42 behind 41 READMEs read $(reading "$out")"
printf '%s\n' "$out" | grep -q "only the first 40 of 41 READMEs" || fail "the README cap was not printed"

printf 'CONTRIBUTING.md\n' > "$root/tree.txt"
printf 'nothing here\n' > "$root/files/CONTRIBUTING.md"
STUB_CONTENTS_FAIL=1 bash "$script" --out o/r >/dev/null
grep -q '^RESULT: UNREAD' "$HOUSEBROKEN_HOME/policy/policy-o-r.md" || fail "--out did not save the UNREAD printout"
mkdir -p "$HOUSEBROKEN_HOME/prior-art"
printf 'prior art\n' > "$HOUSEBROKEN_HOME/prior-art/prior-art-o-r.md"
msg=$(FILE_PR_DRY=1 bash "$here/../scripts/file-pr.sh" o/r --title t --body-file /dev/null 2>&1)
printf '%s\n' "$msg" | grep -q "UNREAD" || fail "file-pr.sh did not refuse an UNREAD printout: $msg"

echo "PASS $name"
