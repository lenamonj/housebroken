#!/bin/bash
# test-diff-defaults.sh - three fixture diffs through --diff -, checking the
# hits the heuristic must find and the body assignment it must not. No network,
# no clone.
set -u
name=test-diff-defaults
script="$(cd "$(dirname "$0")/../scripts" && pwd)/diff-defaults.sh"

fail() { echo "FAIL $name: $1"; exit 1; }

bash "$script" --help | grep -q "Usage:" || fail "--help has no usage"

bash "$script" --diff 2>/dev/null
[ $? = 2 ] || fail "--diff with no argument did not exit 2"
bash "$script" --diff /definitely/not/a/file 2>/dev/null
[ $? = 2 ] || fail "--diff on a missing file did not exit 2"
bash "$script" /definitely/not/a/directory 2>/dev/null
[ $? = 2 ] || fail "missing clone root did not exit 2"

cpp_out=$(bash "$script" --diff - <<'DIFF'
--- a/src/bench.cc
+++ b/src/bench.cc
@@ -10,1 +10,1 @@
-void Run(int iters);
+void Run(int iters, bool verbose = false);
DIFF
) || fail "C++ fixture exited non-zero"
echo "$cpp_out" | grep -q '^src/bench.cc:10  default-arg  ' || { echo "$cpp_out"; fail "no default-arg hit on the C++ signature"; }
echo "$cpp_out" | grep -q '^1 default arguments or forwarding wrappers added$' || { echo "$cpp_out"; fail "C++ fixture summary is not 1"; }

py_out=$(bash "$script" --diff - <<'DIFF'
--- a/tool/run.py
+++ b/tool/run.py
@@ -5,1 +5,3 @@
-def run(path):
+def run(path, strict=True):
+    limit = 10
+    return limit
DIFF
) || fail "Python fixture exited non-zero"
echo "$py_out" | grep -q '^tool/run.py:5  default-arg  ' || { echo "$py_out"; fail "no default-arg hit on the Python signature"; }
echo "$py_out" | grep -q 'run.py:6' && { echo "$py_out"; fail "body assignment was flagged"; }
echo "$py_out" | grep -q '^1 default arguments or forwarding wrappers added$' || { echo "$py_out"; fail "Python fixture summary is not 1"; }

fwd_out=$(bash "$script" --diff - <<'DIFF'
--- a/src/bench.h
+++ b/src/bench.h
@@ -20,0 +21,1 @@
+  void Run(int iters) { return Run(iters, false); }
DIFF
) || fail "forwarding fixture exited non-zero"
echo "$fwd_out" | grep -q '^src/bench.h:21  forwarding  ' || { echo "$fwd_out"; fail "no forwarding hit on the one-line overload"; }
echo "$fwd_out" | grep -q '^1 default arguments or forwarding wrappers added$' || { echo "$fwd_out"; fail "forwarding fixture summary is not 1"; }

echo "PASS $name"
