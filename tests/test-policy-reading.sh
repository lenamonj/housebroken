#!/bin/bash
# test-policy-reading.sh - the reading of a policy file. Ordinary ban and
# disclosure wording reads BAN and DISCLOSE in any case and across wrapped
# lines, a sentence that only sits near a prohibition does not, a policy kept
# where projects really keep it is opened, and a MENTION is a hold until a
# reading is recorded. Local, through a stub gh.
set -u
name=test-policy-reading
here=$(cd "$(dirname "$0")" && pwd)
script="$here/../scripts/check-ai-policy.sh"
root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
export HOUSEBROKEN_HOME="$root/home" STUB_DIR="$root"
mkdir -p "$root/bin" "$root/files"
cp "$here/stubs/policy-gh" "$root/bin/gh"
chmod +x "$root/bin/gh"
export PATH="$root/bin:$PATH"

fail() { echo "FAIL $name: $1" >&2; exit 1; }
result() { printf '%s\n' "$1" | grep -m1 '^RESULT: ' | awk '{print $2}'; }

printf 'CONTRIBUTING.md\n' > "$root/tree.txt"
reads() { # expected-result text
  printf '%b\n' "$2" > "$root/files/CONTRIBUTING.md"
  out=$(bash "$script" o/r)
  [ "$(result "$out")" = "$1" ] || fail "expected $1, read $(result "$out"), for: $2"
}

reads BAN "We do not accept AI-generated pull requests."
reads BAN "We don't accept AI-generated pull requests."
reads BAN "We won't accept AI-generated code."
reads BAN "AI-generated pull requests will be rejected."
reads BAN "We reject LLM-generated patches."
reads BAN "PRs written by AI are unwelcome."
reads BAN "Please don't send us AI-generated patches."
reads BAN "This project has a no-AI policy."
reads BAN "AI contributions are strictly disallowed."
reads BAN "AI-assisted contributions are never accepted."
reads BAN "Contributions created with generative AI are unacceptable."
reads BAN "We ask that you avoid AI tools entirely."
reads BAN "We can't review AI slop, so don't open such PRs."
reads BAN "no ai-generated code please, it will be closed"
reads BAN "ai generated pull requests are not accepted"
reads BAN "Code written by AIs is not accepted."
reads BAN "vibe-coded pull requests are not accepted."
reads BAN "Pull requests from coding agents will be closed."
reads BAN "Machine generated contributions are not accepted."
reads BAN "Do not submit code from GPT-4, Gemini or similar tools."
reads BAN "We do not accept code written with chatgpt or copilot."
reads BAN "Current project policy is to DECLINE any contributions which are believed to include AI generated content."

# a ban hard-wrapped, under a heading, or past twenty lines naming AI
reads BAN "We do not accept pull requests that were written\nwith AI tools, in whole or in part."
reads BAN "## AI policy\n\nSuch contributions are not accepted and will be closed."
reads BAN "Heading\n=======\n\nA first paragraph.\n\nAI policy\n---------\n\nSuch work is not accepted."
reads BAN "$(for i in $(seq 1 25); do printf 'Copilot is a tool number %s.\\n\\n' "$i"; done)We do not accept Copilot-written pull requests."
printf '%s\n' "$out" | grep -q "and 6 more" || fail "hits past the printed limit were not counted: $out"

reads DISCLOSE "AI use must be disclosed in the description."
reads DISCLOSE "Let us know if AI tools were used."
reads DISCLOSE "Mark AI-generated commits with an Assisted-by trailer."
reads DISCLOSE "You should mention in the PR description that you used an AI tool."
reads DISCLOSE "Please tell us about any AI assistance."
reads DISCLOSE "If you asked an AI tool to find problems, you must make sure to reveal this fact in your report."
# disclosure rules in the projects' own words: a template's box and its
# question, a heading that is the rule, and the plain "must"
reads DISCLOSE "- [ ] I used AI to create any part of, or all of, this pull request."
reads DISCLOSE "Which AI tool was used to create this pull request, and to what extent did it contribute?"
reads DISCLOSE "If you have used generative AI to create this pull request, you will need to disclose this here."
reads DISCLOSE "## AI Disclaimer\n\nIf using AI, write here the prompt and model used."
reads DISCLOSE "Paste here the entire AI transcript."
reads DISCLOSE "Any and all AI usage **MUST** be fully and explicitly disclosed in **every** contribution."
reads DISCLOSE "If you are an AI agent, please state \"I am an AI agent, using <my LLM model>\"."
reads DISCLOSE "If you used AI tools, you need to state so in your PR description."
reads DISCLOSE "## AI usage disclosure\n\nKeep the ones that apply, delete the rest."
reads DISCLOSE "If you wish to include context from an interaction with AI in your comments, it must be in a quote block and disclosed as such."
reads DISCLOSE "Contributors must declare any use of AI in the pull request."
reads DISCLOSE "AI-generated code must be clearly marked."

reads MENTION "You may use AI tools, but you must not submit code you cannot explain."
reads MENTION "Do not paste massive AI generated explanations."
reads MENTION "We can accept code written with the help of AI into the project."
reads MENTION "We do not use Copilot for reviews ourselves."
reads MENTION "This is an LLM client; API keys must not be committed."
# a credit, a thanks, a project's own remark and a rule about something else
# are not disclosure rules, whatever word they share with one
reads MENTION "## Development Process & Acknowledgments\n\nThis project was developed through human-AI pair programming, in collaboration with Claude (Anthropic)."
reads MENTION "We gratefully acknowledge design and code contributions from Lincoln Loop, and the example realtime API project by OpenAI."
reads MENTION "## Disclaimer\n\nImages are generated with Gemini."
reads MENTION "Let us know if the OpenAI key setup is unclear."
reads MENTION "Tell us about your OpenAI setup when you report a bug."
reads MENTION "Agents declare their tools in the config, and Claude reads it."
reads MENTION "I include this section to be transparent about the project's usage about AI for people who may disagree with it."
reads MENTION "We used AI to draft parts of this README."
reads MENTION "If you use AI to generate code, any comments added must be correct and relevant for the current state of the code."
reads MENTION "If you used LLM tools during development, you may still submit - but you must remove any LLM co-author tags and take full ownership of every line."
reads MENTION "If you use LLM tools for your contributions, please read and follow our Generative AI Policy."
reads MENTION "- [ ] I acknowledge this project's AI policy."
reads MENTION "Security issues go through responsible disclosure; an AI tool may help you write the report."
reads MENTION "If you use AI, you are responsible for every line you submit."
reads CLEAN "The cursor will be closed when the connection ends."
reads CLEAN "Nothing about models here."

# the printout shows the whole sentence, not the wrapped fragment
reads BAN "We do not accept pull requests that were\nwritten with AI tools."
printf '%s\n' "$out" | grep -q "We do not accept pull requests that were written with AI tools" ||
  fail "the sentence was not printed whole: $out"

# where projects really keep it
for f in docs/devel/code-provenance.rst docs/CONTRIBUTE.md llvm/docs/AIToolPolicy.md CONTRIBUTING.markdown \
         docs/contributing.mdx docs/ai-contributions.md .windsurfrules; do
  printf '%s\n' "$f" > "$root/tree.txt"
  mkdir -p "$root/files/$(dirname "$f")"
  printf 'We do not accept AI-generated code.\n' > "$root/files/$f"
  out=$(bash "$script" o/r)
  [ "$(result "$out")" = BAN ] || fail "$f was not read: $out"
done

# the root README is read before forty of its children
: > "$root/tree.txt"
for i in $(seq 10 50); do
  printf 'Apps/a%s/README.md\n' "$i" >> "$root/tree.txt"
  mkdir -p "$root/files/Apps/a$i"
  printf 'an app\n' > "$root/files/Apps/a$i/README.md"
done
printf 'README.md\n' >> "$root/tree.txt"
printf 'We do not accept AI-generated code.\n' > "$root/files/README.md"
out=$(bash "$script" o/r)
[ "$(result "$out")" = BAN ] || fail "the root README fell past the cap: $out"

# a throttle message whose request id holds 409 or 404 is not an empty repository
printf 'CONTRIBUTING.md\n' > "$root/tree.txt"
printf 'We do not accept AI-generated code.\n' > "$root/files/CONTRIBUTING.md"
out=$(STUB_TREE_ERR='gh: API rate limit exceeded, request ID C409:2F1A:9B7 (HTTP 403)' bash "$script" o/r)
[ "$(result "$out")" = UNREAD ] || fail "a throttle naming 409 read $(result "$out"): $out"
out=$(STUB_TREE_ERR='gh: Git Repository is empty. (HTTP 409)' bash "$script" o/r)
[ "$(result "$out")" = CLEAN ] || fail "an empty repository read $(result "$out"): $out"
printf 'nothing here\n' > "$root/files/CONTRIBUTING.md"
out=$(STUB_ORG_ERR='gh: secondary rate limit, request ID A404:11B2 (HTTP 403)' bash "$script" o/r)
[ "$(result "$out")" = UNREAD ] || fail "an org throttle naming 404 read $(result "$out"): $out"

# a file GitHub lists with a size and serves empty was not read
out=$(STUB_EMPTY_BODY=1 bash "$script" o/r)
[ "$(result "$out")" = UNREAD ] || fail "a listed file served empty read $(result "$out"): $out"

# MENTION is a hold: the filing gates want a reading on the printout
printf 'CONTRIBUTING.md\n' > "$root/tree.txt"
printf 'You may use AI tools.\n' > "$root/files/CONTRIBUTING.md"
mkdir -p "$HOUSEBROKEN_HOME/prior-art"
printf '## Prior art: o/r\n' > "$HOUSEBROKEN_HOME/prior-art/prior-art-o-r.md"
bash "$script" --out o/r >/dev/null
msg=$(FILE_ISSUE_DRY=1 bash "$here/../scripts/file-issue.sh" o/r --title t --body-file /dev/null 2>&1)
printf '%s\n' "$msg" | grep -q "names AI without a recorded reading" || fail "file-issue.sh did not hold a MENTION: $msg"
msg=$(FILE_PR_DRY=1 bash "$here/../scripts/file-pr.sh" o/r --title t --body-file /dev/null 2>&1)
printf '%s\n' "$msg" | grep -q "names AI without a recorded reading" || fail "file-pr.sh did not hold a MENTION: $msg"
bash "$script" --out --reading "AI tools are allowed and nothing is asked of the body" o/r >/dev/null
grep -q '^READING: AI tools are allowed' "$HOUSEBROKEN_HOME/policy/policy-o-r.md" || fail "the reading was not saved"
msg=$(FILE_PR_DRY=1 bash "$here/../scripts/file-pr.sh" o/r --title t --body-file /dev/null 2>&1)
printf '%s\n' "$msg" | grep -q "without a recorded reading" && fail "a recorded reading did not lift the hold: $msg"

# a printout made for another repository does not pass, though the names collide
printf '## AI policy: foo/bar-baz\nRESULT: CLEAN\n' > "$HOUSEBROKEN_HOME/policy/policy-foo-bar-baz.md"
printf '## Prior art: foo-bar/baz\n' > "$HOUSEBROKEN_HOME/prior-art/prior-art-foo-bar-baz.md"
msg=$(FILE_PR_DRY=1 bash "$here/../scripts/file-pr.sh" foo-bar/baz --title t --body-file /dev/null 2>&1)
printf '%s\n' "$msg" | grep -q "is the printout of foo/bar-baz, not foo-bar/baz" || fail "another repository's printout passed: $msg"

# a BAN read on one branch today is not replaced by a clean read of another
printf 'We do not accept AI-generated code.\n' > "$root/files/CONTRIBUTING.md"
bash "$script" --out o/r >/dev/null
printf 'nothing here\n' > "$root/files/CONTRIBUTING.md"
out=$(bash "$script" --branch dev --out o/r)
printf '%s\n' "$out" | grep -q "BAN read on main stands" || fail "a clean read of another branch did not say the BAN stands: $out"
grep -q '^RESULT: BAN' "$HOUSEBROKEN_HOME/policy/policy-o-r.md" || fail "a clean read of another branch replaced a BAN"
bash "$script" --branch main --out o/r >/dev/null
grep -q '^RESULT: CLEAN' "$HOUSEBROKEN_HOME/policy/policy-o-r.md" || fail "a clean reread of the same branch did not replace the BAN"

echo "PASS $name"
