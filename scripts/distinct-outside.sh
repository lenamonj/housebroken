#!/bin/bash
# distinct-outside.sh - distinct outside humans merged in 120d (the memory rule).
set -u
PY="/c/Users/lenam/AppData/Local/Programs/Python/Python313/python.exe"
for repo in "$@"; do
  { gh api "repos/$repo/pulls?state=closed&per_page=100&sort=updated&direction=desc" 2>/dev/null
    gh api "repos/$repo/pulls?state=closed&per_page=100&sort=updated&direction=desc&page=2" 2>/dev/null
  } > /tmp/prs.json
  "$PY" /c/jeffy-evals/distinct-outside.py "$repo" < /tmp/prs.json
done
