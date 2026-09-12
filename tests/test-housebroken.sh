#!/bin/bash
# test-housebroken.sh - the dispatcher names its subcommands in the README
# order, refuses an unknown one, passes arguments through to the script, and
# install.sh installs and uninstalls exactly what it says, including the
# version it came from. Nothing here touches the network or the real HOME.
set -u
name=test-housebroken
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/.." && pwd)
hb="$repo/bin/housebroken"

fail() { echo "FAIL $name: $1" >&2; exit 1; }

# help lists the subcommands in the README order
help=$(bash "$hb" help) || fail "help exited non-zero"
order=$(printf '%s\n' "$help" |
  grep -oE '^ *[0-9]+ +(policy|outside|prior-art|census|review|file|verify|sweep|hygiene)\b' |
  awk '{print $2}' | tr '\n' ' ')
[ "$order" = "policy outside prior-art census review file verify sweep hygiene " ] ||
  fail "help subcommands out of order: $order"
printf '%s\n' "$help" | grep -qE '^ *2 +prior-art' || fail "prior-art is not step 2"
printf '%s\n' "$help" | grep -qE '^ *9 +review' || fail "review is not step 9"
printf '%s\n' "$help" | grep -qE '^ *11 +hygiene' || fail "hygiene is not step 11"

# no argument is the same door
bash "$hb" >/dev/null || fail "no argument exited non-zero"

# an unknown subcommand exits 2
bash "$hb" nosuch >/dev/null 2>&1
[ "$?" -eq 2 ] || fail "unknown subcommand did not exit 2"

# arguments reach the script
out=$(bash "$hb" prior-art --help) || fail "prior-art --help exited non-zero"
printf '%s\n' "$out" | grep -q "usage: prior-art.sh" || fail "prior-art usage not returned"
out=$(bash "$hb" sweep --help) || fail "sweep --help exited non-zero"
printf '%s\n' "$out" | grep -q "pr-sweep.sh" || fail "pr-sweep usage not returned"
out=$(bash "$hb" review --help) || fail "review --help exited non-zero"
printf '%s\n' "$out" | grep -q "review.sh" || fail "review usage not returned"

# install into a temporary HOME
tmp=$(mktemp -d) || fail "mktemp failed"
trap 'rm -rf "$tmp"' EXIT
bindir="$tmp/hbhome/bin"
skilldir="$tmp/home/.claude/skills/housebroken"
mkdir -p "$tmp/home"

dry=$(HOME="$tmp/home" HOUSEBROKEN_HOME="$tmp/hbhome" bash "$repo/install.sh" --dry-run) ||
  fail "--dry-run exited non-zero"
printf '%s\n' "$dry" | grep -qF "$bindir" || fail "--dry-run did not name $bindir"
printf '%s\n' "$dry" | grep -qF "$skilldir" || fail "--dry-run did not name $skilldir"
printf '%s\n' "$dry" | grep -q "VERSION" || fail "--dry-run did not mention the VERSION file"
[ -e "$bindir" ] && fail "--dry-run created $bindir"

HOME="$tmp/home" HOUSEBROKEN_HOME="$tmp/hbhome" bash "$repo/install.sh" >/dev/null ||
  fail "install exited non-zero"
[ -f "$bindir/housebroken" ] || fail "dispatcher not installed"
for f in "$repo"/scripts/*.sh; do
  [ -f "$bindir/$(basename "$f")" ] || fail "$(basename "$f") not installed"
done
[ -f "$skilldir/SKILL.md" ] || fail "SKILL.md not installed"

# the installed copy runs from its own directory
HOME="$tmp/home" HOUSEBROKEN_HOME="$tmp/hbhome" bash "$bindir/housebroken" help |
  grep -q "prior-art" || fail "installed dispatcher help failed"
HOME="$tmp/home" HOUSEBROKEN_HOME="$tmp/hbhome" bash "$bindir/housebroken" prior-art --help |
  grep -q "usage: prior-art.sh" || fail "installed dispatcher cannot find its scripts"

# the installed copy can say which version it is
want="housebroken $(sed -n 's/^version = "\(.*\)"/\1/p' "$repo/pyproject.toml" | head -1)"
got=$(HOME="$tmp/home" HOUSEBROKEN_HOME="$tmp/hbhome" bash "$bindir/housebroken" version) ||
  fail "installed dispatcher version exited non-zero"
[ "$got" = "$want" ] || fail "installed dispatcher says '$got', expected '$want'"

HOME="$tmp/home" HOUSEBROKEN_HOME="$tmp/hbhome" bash "$repo/install.sh" --uninstall >/dev/null ||
  fail "--uninstall exited non-zero"
[ -e "$bindir/housebroken" ] && fail "dispatcher survived uninstall"
[ -e "$bindir/VERSION" ] && fail "VERSION survived uninstall"
[ -e "$skilldir" ] && fail "skill directory survived uninstall"
for f in "$repo"/scripts/*.sh; do
  [ -e "$bindir/$(basename "$f")" ] && fail "$(basename "$f") survived uninstall"
done

rm -rf "$tmp"
trap - EXIT
echo "PASS $name"
