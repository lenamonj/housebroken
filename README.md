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
  <img src="https://img.shields.io/badge/license-MIT-111111?style=flat-square" alt="MIT license">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/gates-12-E8A23B?style=flat-square" alt="12 gates">
  <img src="https://img.shields.io/badge/merged%20upstream-24%20PRs%20in%2021%20projects-E8A23B?style=flat-square" alt="24 merged pull requests across 21 projects">
  <img src="https://img.shields.io/badge/closures%20turned%20into%20gates-5-E8A23B?style=flat-square" alt="5 closures turned into gates">
  <img src="https://img.shields.io/badge/shellcheck-clean-111111?style=flat-square" alt="shellcheck clean">
</p>

<p align="center">
  <strong>24 merged upstream &middot; 21 projects &middot; 5 closures, each one now a gate</strong><br>
  <sub>Derived from GitHub on 7 September 2026: one account, every patch written by an agent, every filing governed by these rules as they were learned. Apple, Microsoft, Google, Apache and JetBrains are among the mergers. <a href="#numbers">The numbers</a> &middot; <a href="#how-it-works">the twelve gates</a>.</sub>
</p>

You know the maintainer. She runs the project on evenings and weekends, has for nine years, and opened GitHub this morning to four pull requests from accounts created last month. Each one rewrites a function she wrote in 2019. Each carries a paragraph of comments in code that had none, a six-hundred-word body, and a footer naming the tool that wrote it. One of them re-argues a decision she closed in April. She closes all four without reading them.

She is right to.

housebroken is the set of rules that get a pull request past her, written as scripts that refuse to file until every rule is met. The rules are not opinions. Each one was paid for with a closed pull request, and the closure is named next to the rule.

## Before / after

Before: one branch, fourteen files, three unrelated fixes, a planning document and an agent config directory in the diff, a comment on every added line, a body that explains the tool, filed against a ruling already made in a closed issue, the project's own test target never run.

After:

```
one finding, one pull request
9 lines changed in the project's own style, no comment where the file has none
1 test that fails on their main and passes with the patch
body under 120 words, in their template, no footer
prior art read and quoted before the branch existed
their CI target green on a fresh clone of their main
the CLA known before filing, the SECURITY.md route taken when it applies
```

The second one gets merged. Sometimes in twelve minutes.

## Numbers

Every rule here was learned on real repositories with real maintainers. Between late July and 7 September 2026, one account filed pull requests on projects it had never touched before, every patch written by an autonomous agent, every filing governed by these gates as they were learned. Derived from GitHub on 7 September 2026:

| | count |
|---|--:|
| pull requests filed | 102 |
| merged | 24, across 21 projects |
| open, waiting on a maintainer | 73 |
| closed without merging | 5 |

The merged patches include ones accepted by Apple, Microsoft, Google, Apache, JetBrains, and the URL parser that Node.js ships. The fastest merge came twelve minutes after filing. Several came the same day.

The five closures matter more than the merges. Each became a gate. Two of the five were the same class, three days apart, because the first lesson was written as prose and prose is followed when remembered. That is why the rules here are scripts that refuse, not a checklist that suggests.

## How it works

<img align="right" width="230" src="assets/treatise.jpg" alt="An obsidian book with chrome corners titled The Housebroken Agent, a treatise on manners for machines calling at the homes of maintainers">

A pull request passes through the door in order. Each step is a script or a rule, and each names the closure that put it there.

**1. Read the house rules before knocking.**
`check-ai-policy.sh` reads the repository's contribution policy on its development branch and in the organization's `.github` repository, and prints the sentence, not a verdict. Some projects ask contributors not to use AI for pull request text; those are never filed. Some accept pull requests only for issues they have labelled; those get an issue with the fix offered.
`distinct-outside.sh` counts outside contributors merged in the last 120 days. A project that has merged none is closed to outsiders whatever its README says.

**2. Is it already on the table?**
`prior-art.sh` lists every issue and pull request, open, closed and merged, that touches the file or symbol, with the type taken from the API field and the closing ruling quoted for every closed item. Two closures built it: a pull request that duplicated an open pull request because a search mixed issues and pull requests and nobody checked the type, and a pull request that argued against a ruling in a closed issue nobody had read.

**3. Is it a fix or an opinion?**
A change that rejects an input the project tolerated, or changes a default, is a breaking change on a stable major. It becomes an issue, never a pull request. Two closures, one class, two projects, before this was a rule.

**4. Prove it red first.**
On a fresh clone of the upstream default branch, the new test fails. With the patch, it passes. The proof lives in the pull request as the test, not in the body as a claim.

**5. Run their CI, not yours.**
The project's own test target, on the fresh clone, including the lint, format and mutation gates its workflow runs. Two pull requests went red on gates the author had never run, and the maintainer saw it before the author did.

**6. Match the house style.**
`comment-census.sh` counts added code lines against added comment lines and compares them with the file. No comment in code that has none. Body under 120 words, in the project's template if it has one. No tool footer, no session link, no co-author trailer. When a template asks whether AI was used, the answer is one truthful sentence. Three maintainers said the same thing about comment density before it became a script.

**7. Know the paperwork.**
Every organization gets a card before the first filing: CLA, DCO, signed-commit requirement, template. Some CLA bots post nothing on the pull request and put the instructions in a failed job's log; the card is where that is written down.

**8. Security goes through the side door.**
A memory-safety or remote-abort finding in a library goes by the project's SECURITY.md route, privately, and never becomes a public pull request until the project answers.

**9. File through the gate.**
`file-pr.sh` wraps the pull request creation and refuses when the prior-art printout for that repository is missing or older than a day, or when the body carries a footer, a trailer, or a typographic dash.

**10. Watch it land.**
`verify-filed-pr.sh` re-derives from GitHub that the head is the intended commit, the diff is exactly the intended files, and CI settled green. `pr-sweep.sh` lists every open pull request where the ball is in your court: a maintainer's comment unanswered, a review requesting changes, a red check, a conflict. Every maintainer comment gets a same-day answer. A ruling in a closed issue is never argued with. When the maintainer is right, concede and let them close it.

**11. Clean up.**
`fork-hygiene.sh` deletes the fork branch of every merged or closed pull request and lists forks with no pull request left, which are deleted when the work is over. No planning file, agent directory or build output ever enters a diff.

**12. Three per repository, one finding each.**
A repository gets at most three pull requests, each one finding, each meeting every rule above on its own.

## Install

You need `bash`, `gh` (signed in) and `jq`. Then:

```
uv tool install housebroken-cli      # or: pipx install housebroken-cli, or: pip install housebroken-cli
housebroken install-skill
```

The first line puts the `housebroken` command on your path. The second puts the skill where Claude Code loads it, so the agent runs the door itself before it opens anything upstream. Until the package is on PyPI, install from the repository instead:

```
uv tool install git+https://github.com/lenamonj/housebroken
```

`housebroken help` prints the door in order. Every gate is also a plain bash script under `scripts/`, runnable on its own.

## What is in the repository

| script | gate |
|---|---|
| `scripts/check-ai-policy.sh` | reads the AI-contribution policy where it actually lives |
| `scripts/distinct-outside.sh` | outside contributors merged in 120 days |
| `scripts/prior-art.sh` | issues and pull requests on the touched files, type stated, rulings quoted |
| `scripts/comment-census.sh` | added code versus added comments, per branch |
| `scripts/file-pr.sh` | the only way a pull request gets filed |
| `scripts/verify-filed-pr.sh` | the filed pull request is what was meant, and CI settled |
| `scripts/pr-sweep.sh` | every open pull request where the ball is in your court |
| `scripts/fork-hygiene.sh` | branches deleted after merge or close, orphan forks listed |

The scripts are bash and need `gh` and `jq`. They came out of one operator's workshop and some still carry that operator's assumptions; each script's header says what it assumes. Generalizing them is the current work.

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
