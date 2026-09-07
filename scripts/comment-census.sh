#!/usr/bin/env bash
cd ~/jeffy-prs || exit 1
printf '%-28s %-36s %5s %5s %5s\n' repo branch code cmnt tests
for d in *-fresh; do
  cd ~/jeffy-prs/$d 2>/dev/null || continue
  base=$(git rev-parse --verify -q origin/main >/dev/null && echo origin/main || echo origin/master)
  for br in $(git for-each-ref --format='%(refname:short)' refs/heads/ | grep -v -E '^(main|master|gsl-both|cli-both|zuul-both|swf-all|ion-red)$'); do
    [ "$(git rev-list --count $base..$br)" = "0" ] && continue
    added=$(git diff $base..$br -- . ':(exclude)*test*' ':(exclude)*Test*' ':(exclude)*_test.go' ':(exclude)Tests/*' ':(exclude)*.md' ':(exclude)*.sum' | grep '^+' | grep -v '^+++')
    code=$(echo "$added" | grep -v -E '^\+\s*(//|/\*|\*|#|///|\*/)' | grep -v -E '^\+\s*$' | wc -l)
    cmnt=$(echo "$added" | grep -E '^\+\s*(//|/\*|\*|///|\*/)' | wc -l)
    tests=$(git diff $base..$br --numstat | awk '/[Tt]est/{s+=$1} END{print s+0}')
    printf '%-28s %-36s %5s %5s %5s\n' "${d%-fresh}" "$br" "$code" "$cmnt" "$tests"
  done
done
