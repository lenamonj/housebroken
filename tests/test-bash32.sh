#!/bin/bash
# test-bash32.sh - the shell housebroken ships runs on the bash 3.2 of a stock
# macOS. A static scan of the scripts, the dispatcher and install.sh for what
# 3.2 lacks or misparses, proven first on a file that holds every construct and
# on a look-alike it must leave alone. And where a bash 3.2 is at hand, the one
# HOUSEBROKEN_BASH32 names or the /bin/bash of a macOS, a parse of each of those
# files and of every test. The rule was a note until 2026-11-11, when a `case`
# inside `$(...)` went out in another project and only its macOS job refused it.
set -u
name=test-bash32
here=$(cd "$(dirname "$0")" && pwd)
fail() { echo "FAIL $name: $1"; exit 1; }
cd "$here/.." || fail "cannot reach the repository"
tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT

# What bash 3.2 lacks or misparses, as file:line: what. A comment is not shell.
scan() {
  awk '
    function hit(what) { print FILENAME ":" FNR ": " what }
    /^[[:space:]]*#/ { next }
    /[$][(][[:space:]]*case[[:space:]]/ { hit("a case inside $(...)") }
    /(^|[;&|[:space:]])(mapfile|readarray)([[:space:]]|$)/ { hit("mapfile or readarray") }
    /(^|[;&|[:space:]])(declare|local|typeset)[[:space:]]+-[A-Za-z]*A/ { hit("an associative array") }
    /[$][{][A-Za-z0-9_]+(\[[^]]*\])?[,^]/ { hit("a case conversion in an expansion") }
    /&>>/ { hit("&>>") }
    /[|]&([[:space:]]|$)/ { hit("|&") }
    /(^|[;&|[:space:]])coproc([[:space:]]|$)/ { hit("coproc") }
  ' "$@"
}

# the scan can fail: each construct, on its own line, is flagged once
cat > "$tmp/bad.sh" <<'BAD'
x=$(case a in a) echo 1 ;; esac)
mapfile -t lines < file
readarray -t lines < file
declare -A map
local -A map
echo "${name,,}"
echo "${name^^}"
cmd &>> log
cmd |& tee log
coproc worker { cat; }
BAD
hits=$(scan "$tmp/bad.sh")
i=1
while [ "$i" -le 10 ]; do
  n=$(printf '%s\n' "$hits" | grep -c "bad.sh:$i: ")
  [ "$n" -eq 1 ] || fail "the scan flagged '$(sed -n "${i}p" "$tmp/bad.sh")' $n times"
  i=$((i + 1))
done
[ "$(printf '%s\n' "$hits" | grep -c .)" -eq 10 ] || fail "ten constructs made more than ten hits: $hits"

# and it leaves alone what only looks like one
cat > "$tmp/fine.sh" <<'FINE'
dash_re="$em|$en|&[mn]dash;|&#821[12];|&#x201[34];"
# mapfile, declare -A and coproc are named here, in a comment
case "$(uname -s)" in Linux*) os=linux ;; esac
local -a list
name="${name:-none}"
cmd > log 2>&1 &
grep -A 3 pattern file
FINE
hits=$(scan "$tmp/fine.sh")
[ -z "$hits" ] || fail "the scan flagged what bash 3.2 runs: $hits"

# what ships
files=(scripts/*.sh bin/housebroken install.sh)
problems=$(scan "${files[@]}")
[ -z "$problems" ] || problems="bash 3.2 lacks or misparses:
$problems"

b32="${HOUSEBROKEN_BASH32:-}"
if [ -z "$b32" ] && /bin/bash --version 2>/dev/null | head -1 | grep -q 'version 3\.2'; then
  b32=/bin/bash
fi
if [ -n "$b32" ]; then
  "$b32" --version 2>/dev/null | head -1 | grep -q 'version 3\.2' || fail "$b32 is not a bash 3.2"
  for f in "${files[@]}" tests/*.sh; do
    err=$("$b32" -n "$f" 2>&1) || problems="${problems:+$problems
}bash 3.2 cannot parse $f:
$err"
  done
fi
[ -z "$problems" ] || fail "$problems"

echo "PASS $name"
