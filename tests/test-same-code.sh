#!/bin/bash
# test-same-code.sh - scripts/same-code.sh lists every other place the base
# holds an expression the branch replaces, and nothing the branch changed
# itself. Each listing sits beside the case that must print none: a replaced
# expression too short to mean anything, a reworded comment, a site the branch
# fixed too. Local git only.
set -u
name=test-same-code
script="$(cd "$(dirname "$0")/../scripts" && pwd)/same-code.sh"

fail() { echo "FAIL $name: $1"; exit 1; }

bash "$script" --help | grep -q "Usage:" || fail "--help has no usage"
bash "$script" /definitely/not/a/directory --base main >/dev/null 2>&1
[ "$?" = "2" ] || fail "missing directory did not exit 2"

root=$(mktemp -d) || exit 1
trap 'rm -rf "$root"' EXIT
repo="$root/repo"
G="git -c user.email=t@example.com -c user.name=t -c core.autocrlf=false"
mkdir -p "$repo/src" || exit 1
cd "$repo" || exit 1
$G init -q -b main .
cat > src/stream.js <<'EOF'
function ReadableStreamStreamer(config) {
  var queue = [];
  this._streamData = function(chunk) {
    queue.push(typeof chunk === 'string' ? chunk : chunk.toString(config.encoding));
  };
}
function DuplexStreamStreamer(config) {
  this._write = function(chunk) {
    this.parseChunk(typeof chunk === 'string' ? chunk : chunk.toString(config.encoding));
  };
}
EOF
cat > src/other.js <<'EOF'
var text = typeof chunk === 'string' ? chunk : chunk.toString(config.encoding);
var n = i + 1;
var m = i + 1;
// the reader calls parseChunk once for every chunk it is handed
legacy.flushAll(buffer, config.encoding);
if (--depth > maxDepth(config)) return;
EOF
cat > src/notes.js <<'EOF'
// the reader calls parseChunk once for every chunk it is handed
function late() { legacy.flushAll(buffer, config.encoding); }
function deep() { if (--depth > maxDepth(config)) return; }
EOF
printf 'var a = load(path, options.encoding);\r\nvar b = 2;\r\nvar c = load(path, options.encoding);\r\n' > src/crlf.js
i=0; while [ "$i" -lt 13 ]; do printf 'var v%s = registry.lookup(name, scope);\n' "$i"; i=$((i + 1)); done > src/many.js
cat > src/decode.js <<'EOF'
var first = reader.decodeChunk(buffer, this._options.charset);
var second = reader.decodeChunk(other, options.charset);
if (ready(first)) emit(first);
if (ready(second)) emit(second);
EOF
i=0; while [ "$i" -lt 12 ]; do printf 'var w%s = helper.run(alpha%s);\n' "$i" "$i"; i=$((i + 1)); done > src/calls.js
{ i=0; while [ "$i" -lt 40 ]; do printf 'function f%s(){return 1}' "$i"; i=$((i + 1)); done
  printf 'x=reader.decodeChunk(b,c);y=typeof chunk === %sstring%s ? chunk : chunk.toString(config.encoding);\n' "'" "'"; } > src/bundle.min.js
{ $G add -A && $G commit -q -m base; } || fail "fixture failed"

run() { bash "$script" . --base main 2>&1; }
branch() { $G checkout -q -B "$1" main; }
commit() { $G add -A && $G commit -q -m "$1"; }
edit() { sed "$2" "$1" > "$1.new" && mv "$1.new" "$1"; }

bash "$script" . >/dev/null 2>&1
[ "$?" = "2" ] || fail "a run with no --base did not exit 2"
bash "$script" . --base no-such-ref >/dev/null 2>&1
[ "$?" = "2" ] || fail "a base that is no ref did not exit 2"

# control: a branch that replaces nothing lists nothing
branch nothing
printf 'var z = 1;\n' > src/new.js
commit "a new file"
out=$(run); rc=$?
[ "$rc" = "0" ] || fail "an added file exited $rc: $out"
echo "$out" | grep -q '^0 other sites hold code this branch replaces$' || fail "an added file did not summarise 0: $out"

# 1. the expression one site replaces is listed at every other site, and not at its own
branch one-site
edit src/stream.js '4s/typeof chunk.*encoding)/decode(chunk)/'
commit "fix the reported site"
out=$(run); rc=$?
[ "$rc" = "0" ] || fail "a listing exited $rc, and it reports without judging: $out"
echo "$out" | grep -qF "src/stream.js:4 replaces: typeof chunk === 'string' ? chunk : chunk.toString(config.encoding)" ||
  fail "the replaced expression was not named with its line: $out"
echo "$out" | grep -qF "  src/stream.js:9  this.parseChunk(typeof chunk" || fail "the second site in the same file was not listed: $out"
echo "$out" | grep -qF "  src/other.js:1  var text = typeof chunk" || fail "the site in another file was not listed: $out"
echo "$out" | grep -q "^  src/stream.js:4  " && fail "the site the branch changed was listed as another site: $out"
[ "$(echo "$out" | grep -c 'src/stream.js:9')" = "1" ] || fail "a site was listed for the text and again for the call: $out"
echo "$out" | grep -q 'bundle.min.js' && fail "a minified line over 500 characters was listed as a site: $out"
echo "$out" | grep -q '^2 other sites hold code this branch replaces$' || fail "the summary is not 2: $out"

# 1b. a reader that dies is a usage error, never a branch with nothing to list
mkdir -p "$root/stub"
printf '#!/bin/sh\nexit 3\n' > "$root/stub/awk"
chmod +x "$root/stub/awk"
out=$(PATH="$root/stub:$PATH" bash "$script" . --base main 2>&1); rc=$?
[ "$rc" = "2" ] || fail "a failing awk exited $rc, expected 2: $out"
echo "$out" | grep -q 'other sites' && fail "a failing awk still printed a count: $out"

# 2. a site the branch fixed too is no longer listed
edit src/stream.js '9s/typeof chunk.*encoding)/decode(chunk)/'
commit "fix the second site"
out=$(run)
echo "$out" | grep -q "src/stream.js:9" && fail "a site the branch changed is still listed: $out"
echo "$out" | grep -q '^1 other site holds code this branch replaces$' || fail "the summary is not 1: $out"

# 3. a replaced expression too short to mean anything lists nothing, though the base holds it twice
branch short
edit src/other.js '2s/i + 1/i + 2/'
commit "a one-character change"
out=$(run)
echo "$out" | grep -q '^0 other sites' || fail "a one-character replacement listed sites: $out"

# 4. a deleted line is searched for whole
branch deleted
edit src/other.js '/legacy.flushAll/d'
commit "delete a call"
out=$(run)
echo "$out" | grep -qF "  src/notes.js:2  function late() { legacy.flushAll(buffer, config.encoding); }" ||
  fail "the other site of a deleted line was not listed: $out"

# 5. a reworded comment is not code
branch comment
edit src/other.js '4s/once for every chunk/once per chunk/'
commit "reword a comment"
out=$(run)
echo "$out" | grep -q '^0 other sites' || fail "a reworded comment listed sites: $out"

# 6. an expression that starts with a dash is still a pattern, not an option
branch dash
edit src/other.js '6s/--depth > maxDepth(config)/tooDeep(config)/'
commit "replace a guard"
out=$(run)
echo "$out" | grep -qF "  src/notes.js:3  function deep()" || fail "an expression starting with -- was not found: $out"

# 7. a file with CRLF line endings
branch crlf
printf 'var a = read(path);\r\nvar b = 2;\r\nvar c = load(path, options.encoding);\r\n' > src/crlf.js
commit "replace a load"
out=$(run)
echo "$out" | grep -qF "  src/crlf.js:3  var c = load(path, options.encoding);" || fail "the other site in a CRLF file was not listed: $out"
printf '%s' "$out" | grep -q "$(printf '\r')" && fail "a carriage return reached the listing"

# 8. an expression on more than ten other lines is an idiom, not a fault: counted once, never listed
branch many
edit src/many.js '1s/registry.lookup(name, scope)/resolve(name)/'
commit "replace one lookup of thirteen"
out=$(run)
echo "$out" | grep -qxF "on more than ten other lines each, not listed: registry.lookup(name, scope)" || fail "a common expression was not named on the idiom line: $out"
echo "$out" | grep -q '^  src/many.js:' && fail "a common expression's lines were listed: $out"
echo "$out" | grep -qF "registry.lookup(;" && fail "lines counted for the text were named again for the call: $out"
echo "$out" | grep -q '^0 other sites' || fail "a counted expression changed the summary: $out"
echo "$out" | grep -q 'hold code this branch replaces$' && fail "the summary said no other site holds the code, one line after naming code on more than ten: $out"

# 8b. a line the branch moves is not one it replaces
branch moved
{ printf 'legacy.flushAll(buffer, config.encoding);\n'; grep -v 'legacy.flushAll' src/other.js; } > src/other.js.new && mv src/other.js.new src/other.js
commit "move a call up"
out=$(run)
echo "$out" | grep -q '^0 other sites' || fail "a moved line listed the other sites of its text: $out"
echo "$out" | grep -qE ':[0-9]+ replaces' && fail "a moved line was named as replaced: $out"

# 9. a renamed file is its changed lines, not every line it holds
branch renamed
$G mv src/many.js src/registry.js
commit "rename a file"
out=$(run)
echo "$out" | grep -q '^0 other sites' || fail "a rename alone listed sites: $out"

# 10. the same call spelled with other arguments is listed by the call (PapaParse #1133: this._config.encoding at
#     the site that was fixed, config.encoding at the one that was not)
branch spelled
edit src/decode.js '1s/reader.decodeChunk(buffer, this._options.charset)/decoder.write(buffer)/'
commit "replace one decode"
out=$(run)
echo "$out" | grep -qF "src/decode.js:1 replaces a call to reader.decodeChunk(, also made at:" || fail "the replaced call was not named: $out"
echo "$out" | grep -qF "  src/decode.js:2  var second = reader.decodeChunk(other, options.charset);" ||
  fail "the same call with other arguments was not listed: $out"
echo "$out" | grep -q '^1 other site holds code this branch replaces$' || fail "the summary for a call site is not 1: $out"

# 11. a call whose arguments the branch keeps is still the call it replaces
branch kept-arguments
edit src/decode.js '1s/reader.decodeChunk(/reader.decodeAll(/'
commit "call another method with the same arguments"
out=$(run)
echo "$out" | grep -qF "  src/decode.js:2  var second = reader.decodeChunk(other" || fail "a renamed call's other caller was not listed: $out"

# 12. a call the branch keeps on the line is not one it replaces, and a keyword is not a call
branch kept-call
edit src/decode.js '3s/emit(first)/emit(first, 1)/'
commit "add an argument"
out=$(run)
echo "$out" | grep -q '^0 other sites' || fail "a kept call or an if( was listed as replaced: $out"

# 13. a call made on more than ten other lines is counted, not listed
branch common-call
edit src/calls.js '1s/helper.run(alpha0)/direct(alpha0)/'
commit "replace one call of twelve"
out=$(run)
echo "$out" | grep -qxF "on more than ten other lines each, not listed: helper.run(" || fail "a common call was not named on the idiom line: $out"
echo "$out" | grep -q '^  src/calls.js:' && fail "a common call's lines were listed: $out"
echo "$out" | grep -q '^0 other sites' || fail "a counted call changed the summary: $out"

# 14. the rules the header names, each with a case that would list a site if the rule were gone
$G checkout -q -B rules-base main
printf '# helper.flushAll(buffer, config.encoding) runs once per chunk\nhelper.flushAll(buffer, config.encoding)\n' > src/c.py
printf '// helper.flushAll(buffer, config.encoding) runs once per chunk\n' > src/c.js
printf 'while(pending.length > 0) drain();\nwhile(other.size > 0) flush();\n' > src/k.js
printf 'var a = load(fileA);\nvar b = load(fileB);\n' > src/s.js
printf 'a[i][j] = b[j][i] + c[i][j];\nt = b[j][i] + c[i][j];\n' > src/m.js
printf 'var u1 = encodeURI(query);\nvar u2 = encodeURI(name);\nqueue.push(decode(chunk, config.encoding));\nthis.parseChunk(decode(chunk, this._config.encoding));\nout.write(first);\nout.write(second);\n' > src/u.js
printf 'var one = spaced.decodeChunk(buffer, 1);\n' > "src/my file.js"
printf 'var two = spaced.decodeChunk(other, 2);\n' > src/unspaced.js
commit "rules base"
runb() { bash "$script" . --base rules-base 2>&1; }
rbranch() { $G checkout -q -B "$1" rules-base; }

rbranch comment-call
edit src/c.py '1s/.*/# the helper runs once per chunk/'
edit src/c.js '1s/.*/\/\/ the helper runs once per chunk/'
commit "reword two comments that name a call"
out=$(runb)
echo "$out" | grep -q '^0 other sites' || fail "a removed comment was searched as code: $out"

rbranch deleted-file
$G rm -q src/notes.js
commit "delete a file"
out=$(runb)
echo "$out" | grep -q '^0 other sites' || fail "a deleted file's lines were searched: $out"

rbranch keyword
edit src/k.js '1s/while(pending.length > 0)/for (const p of pending)/'
commit "replace a loop"
out=$(runb)
echo "$out" | grep -q '^0 other sites' || fail "while( was taken for a call: $out"

rbranch short-name
edit src/s.js '1s/load(fileA)/read(fileA)/'
commit "replace a short call"
out=$(runb)
echo "$out" | grep -q '^0 other sites' || fail "a call under five characters was listed: $out"

rbranch no-word
edit src/m.js '1s/b\[j\]\[i\] + c\[i\]\[j\]/0/'
commit "replace an expression with no word in it"
out=$(runb)
echo "$out" | grep -q '^0 other sites' || fail "an expression with no three-letter word was listed: $out"

rbranch kept-prefix-call
edit src/decode.js '3s/emit(first)/send(first)/'
commit "replace a call after a kept one"
out=$(runb)
echo "$out" | grep -q '^0 other sites' || fail "a call in the kept start of the line was listed: $out"

rbranch ten-sites
edit src/calls.js '1s/helper.run(alpha0)/direct(alpha0)/'
edit src/calls.js '2s/helper.run(alpha1)/direct(alpha1)/'
commit "replace two calls of twelve"
out=$(runb)
echo "$out" | grep -q '^10 other sites hold code this branch replaces$' || fail "a call on exactly ten other lines was not listed: $out"

# 15. a call replaced by one whose name extends it is still a replaced call (encodeURI to encodeURIComponent,
#     decode( to decoder.write()
rbranch extended-name
edit src/u.js '1s/encodeURI(/encodeURIComponent(/'
edit src/u.js '3s/decode(chunk, config.encoding)/decoder.write(chunk)/'
edit src/u.js '5s/out.write(/out.rewrite(/'
commit "replace three calls with ones whose names extend them"
out=$(runb)
echo "$out" | grep -qF "  src/u.js:6  out.write(second);" || fail "a call replaced by a name that ends with it was not listed: $out"
echo "$out" | grep -qF "  src/u.js:2  var u2 = encodeURI(name);" || fail "a call replaced by a longer name was not listed: $out"
echo "$out" | grep -qF "  src/u.js:4  this.parseChunk(decode(chunk, this._config.encoding));" ||
  fail "decode( replaced by decoder.write( was not listed: $out"

# 16. the listing is the same whatever the user's git config does to a diff or a grep
plain=$out
git config diff.interHunkContext 5
git config diff.srcPrefix old/
git config grep.column true
out=$(runb)
git config --unset diff.interHunkContext
git config --unset diff.srcPrefix
git config --unset grep.column
[ "$out" = "$plain" ] || fail "git config changed the listing: $out"

# 17. a base git cannot search is a usage error, never a short listing
blob=$(git rev-parse rules-base:src/s.js)
object=".git/objects/$(printf '%s' "$blob" | cut -c1-2)/$(printf '%s' "$blob" | cut -c3-)"
[ -f "$object" ] || fail "the fixture's object for src/s.js is not loose"
mv "$object" "$root/held-object"
out=$(runb); rc=$?
mv "$root/held-object" "$object"
[ "$rc" = "2" ] || fail "a base with an unreadable file exited $rc, expected 2: $out"
echo "$out" | grep -qE 'other sites?( |$)' && fail "a base with an unreadable file still printed a count: $out"

# 18. in a file whose path holds a space, the line the branch changed is its own, not another site
rbranch spaced-path
edit "src/my file.js" '1s/spaced.decodeChunk(buffer, 1)/decoder.write(buffer)/'
commit "replace a call in a file with a space in its name"
out=$(runb)
echo "$out" | grep -qF "  src/unspaced.js:1  var two = spaced.decodeChunk(other, 2);" || fail "the other site of a call in a spaced path was not listed: $out"
echo "$out" | grep -q '^  src/my file.js:1  ' && fail "the changed line of a file with a space in its path was listed as another site: $out"
echo "$out" | grep -q '^1 other site holds' || fail "the summary for the spaced path is not 1: $out"

echo "PASS $name"
