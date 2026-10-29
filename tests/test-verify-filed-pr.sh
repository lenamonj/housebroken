#!/bin/bash
# test-verify-filed-pr.sh - the verifier runs to completion on a merged public
# PR (spf13/pflag #507) and reports the head sha and the files. Read-only.
set -u
name=test-verify-filed-pr
script="$(cd "$(dirname "$0")/../scripts" && pwd)/verify-filed-pr.sh"

bash "$script" --help | grep -q "Usage:" || { echo "FAIL $name: --help has no usage"; exit 1; }
bash "$script" 2>/dev/null && { echo "FAIL $name: missing arguments exited 0"; exit 1; }

out=$(bash "$script" spf13/pflag 507)
echo "$out"
echo "$out" | grep -q "^state  *MERGED" || { echo "FAIL $name: state not reported"; exit 1; }
echo "$out" | grep -qE "^head  *[0-9a-f]{12}" || { echo "FAIL $name: head sha not reported"; exit 1; }
echo "$out" | grep -q "files in the PR" || { echo "FAIL $name: no files section"; exit 1; }
echo "$out" | grep -qE "^   .+  \+[0-9]+/-[0-9]+" || { echo "FAIL $name: no file rows"; exit 1; }
echo "$out" | grep -q "^PR-VERIFY:" || { echo "FAIL $name: no verdict line"; exit 1; }
# A fork's workflow waiting for a maintainer's approval is not in the rollup;
# a commit status reports .state, not .conclusion. A stub gh serves both.
command -v jq >/dev/null 2>&1 || { echo "SKIP $name: stub cases need jq"; echo "PASS $name"; exit 0; }
stub=$(mktemp -d) || exit 1
trap 'rm -rf "$stub"' EXIT
cat > "$stub/gh" <<'STUB'
#!/bin/bash
field=""; expr="."
args=("$@")
for i in "${!args[@]}"; do
  case "${args[$i]}" in
    --json) field="${args[$((i + 1))]}" ;;
    --jq) expr="${args[$((i + 1))]}" ;;
  esac
done
case "$1 $2" in
  "pr checks") exit 0 ;;
  "pr view") jq -r "$expr" "$STUB_DIR/pr.json" ;;
  "run list") jq -r "$expr" "$STUB_DIR/runs.json" ;;
  *) exit 1 ;;
esac
STUB
chmod +x "$stub/gh"
export HOUSEBROKEN_HOME="$stub/empty"
printf '%s' '{"state":"OPEN","headRefOid":"23893ddea90057ec3826050eedd360474e484e57","files":[{"path":"a.kt","additions":1,"deletions":0}],"statusCheckRollup":[{"context":"Task List Completed","state":"SUCCESS"}],"body":"b","comments":[]}' > "$stub/pr.json"

printf '%s' '[{"conclusion":"action_required"}]' > "$stub/runs.json"
out=$(STUB_DIR="$stub" PATH="$stub:$PATH" bash "$script" o/r 1); rc=$?
[ "$rc" = "3" ] || { echo "FAIL $name: a run awaiting approval exited $rc, expected 3"; exit 1; }
echo "$out" | grep -q "^   SUCCESS=1" || { echo "FAIL $name: a commit status's state was not read: $out"; exit 1; }
echo "$out" | grep -q "^PR-VERIFY: NOT SETTLED" || { echo "FAIL $name: a run awaiting approval did not read NOT SETTLED: $out"; exit 1; }
echo "$out" | grep -q "^PR-VERIFY: NOT SETTLED (1 workflow run(s) wait for a maintainer to approve them; nothing settles until one does, so move on)$" ||
  { echo "FAIL $name: a run awaiting approval did not say who it waits on: $out"; exit 1; }

printf '%s' '[{"conclusion":"success"}]' > "$stub/runs.json"
out=$(STUB_DIR="$stub" PATH="$stub:$PATH" bash "$script" o/r 1)
echo "$out" | grep -q "^PR-VERIFY: OK" || { echo "FAIL $name: a settled green head did not read OK: $out"; exit 1; }

# The files and body on GitHub are compared to the stamp and the filed copy.
h=23893ddea90057ec3826050eedd360474e484e57
mkdir -p "$stub/home/branch-checks" "$stub/home/filed"
vrun() { STUB_DIR="$stub" PATH="$stub:$PATH" HOUSEBROKEN_HOME="$stub/home" bash "$script" o/r 1; }
printf 'head: %s\nfile: a.kt\n' "$h" > "$stub/home/branch-checks/$h"
printf 'b\r\n\n' > "$stub/home/filed/o-r-$h.md"
out=$(vrun) || { echo "FAIL $name: matching files and body were refused: $out"; exit 1; }
echo "$out" | grep -q "files match the stamp  *yes" || { echo "FAIL $name: files were not compared: $out"; exit 1; }
echo "$out" | grep -q "body matches what was filed  *yes" || { echo "FAIL $name: the body was not compared: $out"; exit 1; }
printf 'head: %s\nfile: a.kt\nfile: b.kt\n' "$h" > "$stub/home/branch-checks/$h"
out=$(vrun) && { echo "FAIL $name: a PR missing an intended file read OK: $out"; exit 1; }
echo "$out" | grep -q "FILES DIFFER FROM STAMP" || { echo "FAIL $name: a file difference was not named: $out"; exit 1; }
printf 'head: %s\nfile: a.kt\n' "$h" > "$stub/home/branch-checks/$h"
printf 'c\n' > "$stub/home/filed/o-r-$h.md"
# a maintainer edits bodies; the difference is shown, and it is not a failure
out=$(vrun) || { echo "FAIL $name: a body edit failed the verify: $out"; exit 1; }
echo "$out" | grep -q "BODY DIFFERS" || { echo "FAIL $name: a body difference was not named: $out"; exit 1; }
echo "$out" | grep -q '^    > b' || { echo "FAIL $name: the body difference was not shown: $out"; exit 1; }

echo "PASS $name"
