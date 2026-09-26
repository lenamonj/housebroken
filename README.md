<p align="center">
  <img src="assets/door.jpg" width="560" alt="A white ceramic robot dog sits at an open, lit door, a scroll in its mouth, its paws stopped at a glowing amber line on the threshold">
</p>

<h1 align="center">housebroken</h1>

<p align="center"><em>Agent-written pull requests that do not make a mess in someone else's house.</em></p>

<p align="center">
  <img src="https://img.shields.io/github/stars/lenamonj/housebroken?style=flat-square&color=111111&label=stars" alt="Stars">
  <img src="https://img.shields.io/github/v/release/lenamonj/housebroken?style=flat-square&color=111111&label=release" alt="Release">
  <img src="https://img.shields.io/pypi/v/housebroken-cli?style=flat-square&color=111111&label=pypi" alt="PyPI">
  <img src="https://img.shields.io/badge/works%20with-Claude%20Code-111111?style=flat-square" alt="Works with Claude Code">
  <img src="https://img.shields.io/badge/shellcheck-clean-111111?style=flat-square" alt="shellcheck clean">
  <img src="https://img.shields.io/badge/license-MIT-111111?style=flat-square" alt="MIT license">
</p>

A maintainer runs her project on evenings and weekends. She opens GitHub to pull requests from accounts she has never seen, each rewriting a function she wrote years ago, each carrying comments in code that had none, a six-hundred-word body and a footer naming the tool that wrote it. She closes them without reading them, and she is right to.

housebroken is the set of rules that get a pull request past her, written as scripts that refuse to file until every rule is met. The rules are principles, not opinions, and the scripts are the enforcement: a gate that only suggests is followed when remembered.

## What passes the door

```
one finding, one pull request
the smallest diff in the project's own style, no comment added to their code
one test that fails on their main and passes with the patch
a body under 120 words, in their template, no footer, no trailer
their policy read first: no filing where AI is banned, disclosure where it is asked
prior art read and quoted before the branch existed
their CI target green on a fresh clone of their main
attacked by a second model before it left, evidence behind every finding
the CLA known before filing, the SECURITY.md route taken when it applies
```

## The rules

<img align="right" width="230" src="assets/treatise.jpg" alt="An obsidian book with chrome corners titled The Housebroken Agent, a treatise on manners for machines calling at the homes of maintainers">

A pull request passes through the door in order, and stops at the first rule it fails. Each rule is a script where a script can hold it. The maintainers' own verdicts that shaped them are kept separately, in [docs/lessons.md](docs/lessons.md).

**1. Read the house rules before knocking.**
`check-ai-policy.sh` reads every contributing guide, code of conduct, template and agent instruction file on the repository's branch and in the organization's `.github` repository, matched by name without regard to case, and prints each sentence that names AI with its reading: BAN, DISCLOSE, MENTION or CLEAN. A project that bans AI-written contributions never gets one. A project that asks for disclosure gets one truthful sentence in the body. `distinct-outside.sh` counts outside contributors merged in the last 120 days; a project that has merged none is closed to outsiders whatever its README says.

**2. Is it already on the table?**
`prior-art.sh` lists every issue and pull request, open, closed and merged, that touches the file or symbol, with the type taken from the API and the closing ruling quoted for every closed item. An open pull request that fixes the same thing, or a closed issue that ruled the behaviour intended, ends the work. A ruling is never argued with.

**3. Is it a fix or an opinion?**
A change that rejects an input the project tolerated, changes a default, or narrows what the project publishes is the maintainer's call. It is sent with the call stated in the body: what breaks for existing users, and an offer to narrow or close it. A finding whose only evidence is a measurement is a hold, not a pull request.

**4. Prove it red first, and prove the proof.**
On a fresh clone of the upstream default branch, the new test fails; with the patch, it passes. Every arm of the experiment prints evidence that its precondition held, files are swapped by content and checked by hash, and two arms that agree exactly have not tested the variable.

**5. Run their CI, not yours.**
The project's own test target on the fresh clone, and every gate its pull request workflow runs: lint, format, mutation, API check. A gate not run is a red check the maintainer sees first.

**6. Match the house style.**
`comment-check.sh` refuses any comment the branch adds to code, test files included; an existing comment may be reworded, a new file may open with the header its neighbours carry, and a maintainer's explicit request for documentation is the one exception. `comment-census.sh` measures density. The body is under 120 words, in the project's template, and says what was wrong, what changed and how it was verified, every sentence reproduced on the fresh clone. No tool footer, no session link, no co-author trailer, no typographic dash. `claim-check.sh` lists every counted or absolute claim in the body so each is re-derived against the exact revision it names.

**7. Know the paperwork.**
Before the first pull request to an organization: CLA, DCO, signed-commit requirement, disclosure trailer, and the identity clause. Author, committer and sign-off carry the contributor's real name.

**8. Security goes through the side door.**
A memory-safety, remote-abort, injection or path-escape finding goes by the project's SECURITY.md route, privately, and never becomes a public pull request until the project answers.

**9. File through the gate.**
`branch-check.sh` refuses a dirty working tree, a file whose mode disagrees with its siblings, a file the repository's own `.gitignore` excludes, a working artifact, a commit carrying a tool trailer, a session link or a tool identity, a sign-off naming a username, a branch not on top of its base, and any comment added to code; it prints every absolute claim in added prose for falsification, and stamps the head it passed.
`review.sh` names the adversarial reviewer: a different model from the one that wrote the change, one tier down, never below Sonnet. The reviewer gets a fresh context, hard read-only limits and an attack list that starts with every claim the prose makes and includes the form of the code: the reviewer writes the changed block the way the strongest engineer in that language would, in the repository's own idioms, and a smaller or clearer version is a finding; every finding carries evidence it produced itself, and its report is bound to the head and the text it read. A fix is a new head and gets a new review.
`file-pr.sh` is the only way a pull request is opened. It refuses without a prior-art printout under a day old, a policy printout under a day old that does not read BAN, a body that discloses when the policy asks, a branch stamp for the exact head, and a POST AS IS review of that head and that body.
`file-issue.sh` is the only way an issue is opened. It refuses without the same prior-art and policy printouts, refuses the same prose, and refuses a body that mentions a fix, a patch or a pull request without a GitHub link to the branch or commit, so work that exists is attributable to whoever did it.

**10. Watch it land.**
`verify-filed-pr.sh` re-derives from GitHub that the head is the intended commit, the diff is exactly the intended files, and CI settled. `inbox.sh` prints every event on your threads since the last acknowledged cursor, bodies included, with a census of failing, blocked and conflicting checks. Every maintainer comment gets a same-day answer in the contributor's voice, checked by `claim-check.sh` and, when it concedes, disagrees or rides on a code change, by the adversarial review. Replies to one repository are spaced ten minutes apart. When the maintainer is right, concede in one sentence. A silent maintainer is never nudged.

**11. Clean up.**
`fork-hygiene.sh` deletes the fork branch of every merged or closed pull request and lists forks with no pull request left. No planning file, agent directory, journal or build output ever enters a diff.

**12. Three per repository, one finding each.**
A repository gets at most three open pull requests, each one finding, each meeting every rule above on its own, filed at least ten minutes apart.

**13. Write it down before you leave.**
A house rule learned about a repository goes into `notes.sh` the same session. A maintainer's verdict goes into docs/lessons.md the same day, quoted verbatim with the rule it became. A gate that was wrong, missing or done by hand becomes an issue before the run ends.

## Install

You need `bash`, `gh` (signed in) and `jq`. Then, from PyPI; `pipx install housebroken-cli` and `uv tool install housebroken-cli` work the same way:

```
pip install housebroken-cli
housebroken install-skill
```

The first line puts the `housebroken` command on your path. The second puts the skill where Claude Code loads it, so the agent runs the door itself before it opens anything upstream. To run the main branch between releases, install from the repository instead:

```
uv tool install git+https://github.com/lenamonj/housebroken
```

`housebroken help` prints the door in order. Every gate is also a plain bash script under `scripts/`, runnable on its own.

## What is in the repository

| script | gate |
|---|---|
| `scripts/check-ai-policy.sh` | the AI-contribution policy, read where it lives, with its reading: BAN, DISCLOSE, MENTION, CLEAN |
| `scripts/distinct-outside.sh` | outside contributors merged in 120 days |
| `scripts/prior-art.sh` | issues and pull requests on the touched files, type stated, rulings quoted |
| `scripts/comment-check.sh` | refuses a comment added to code nobody asked for |
| `scripts/comment-census.sh` | added code versus added comments, per branch |
| `scripts/diff-defaults.sh` | default arguments and one-line wrappers added to keep call sites untouched |
| `scripts/claim-check.sh` | every falsifiable claim in a body or a reply, listed to re-derive |
| `scripts/branch-check.sh` | the branch's mechanical facts: clean tree, modes, artifacts, trailers, sign-offs, comments, absolute claims |
| `scripts/review.sh` | the adversarial review: a different model attacks the change, and the filing is held to exactly what it read |
| `scripts/file-pr.sh` | the only way a pull request gets filed: five gates in front of `gh pr create` |
| `scripts/file-issue.sh` | the only way an issue gets filed: the same printouts and prose, and a fix offered is a fix linked |
| `scripts/verify-filed-pr.sh` | the filed pull request is what was meant, and CI settled |
| `scripts/pr-sweep.sh` | every open pull request where the ball is in your court |
| `scripts/inbox.sh` | what GitHub has to tell you since you last looked, bodies included, with a census of every open pull request |
| `scripts/notes.sh` | what this repository's maintainers have asked for before |
| `scripts/fork-hygiene.sh` | branches deleted after merge or close, orphan forks listed |

The scripts are bash and need `gh` and `jq`. Each script's header says what it assumes.

## Not in scope

housebroken does not find bugs and does not write patches. Any agent that produces a change can use it. It governs what leaves your machine and how it behaves once it arrives.

## FAQ

**Is this only for AI-written pull requests?**
No. Every rule here predates agents. Agents made it cheap to break all of them at once, on a hundred repositories, before breakfast.

**Does it make maintainers like agent pull requests?**
No. It makes the pull request indistinguishable from a careful human's, and answers truthfully when they ask.

**What if the maintainer closes it anyway?**
Then the maintainer is the judge and the ruling stands. Read why, write it down, and if it is a class of mistake, make it a gate.

**Why "housebroken"?**
Because the alternative is what maintainers are calling it.

## License

MIT.
