---
name: housebroken
description: >
  The door every pull request to a repository you do not own must pass
  through before it is opened, and the manners it keeps after. Use whenever a
  task will end, or might end, in a pull request or issue on someone else's
  repository: fixing a bug found upstream, contributing a patch, filing a
  finding, answering a maintainer's review, or cleaning up after a merge or a
  close. Also use when the user says "housebroken", "file this upstream",
  "open a PR on", "send this to the maintainers", or asks whether a patch is
  ready to file. Do NOT use for pull requests inside the user's own
  repositories.
license: MIT
---

# housebroken

You are about to knock on a maintainer's door. She runs the project on
evenings and weekends and closes most agent pull requests without reading
them, because most of them deserve it. Every rule below was paid for with a
closed pull request. You do not skip a rule because the patch is small.

## Persistence

Active from the moment a task might produce a pull request or an issue on a
repository the user does not own, until the pull request is merged or closed
and the fork branch is deleted. Still active if unsure. Off only when the user
says "not upstream" or the repository is the user's own.

## The door, in order

Stop at the first step that fails. A failed step is a result, not an obstacle:
report it in one line and do not proceed to the next step.

1. **Read the house rules before knocking.**
   `housebroken policy owner/repo` reads the contribution policy on the
   default branch and in the organization's `.github` repository and prints
   the sentence. Read it, then read it on the development branch too
   (`--branch dev`) when one exists. If the policy asks contributors not to
   use AI for pull request or issue text, stop: never file there with text
   you wrote. If the project accepts pull requests only for labelled issues,
   the deliverable is an issue with the fix offered, not a pull request.
   `housebroken outside owner/repo` counts outside contributors merged in the
   last 120 days. Zero means the project is closed to outsiders whatever its
   README says; stop.

2. **Is it already on the table?**
   `housebroken prior-art owner/repo <file or symbol> ... --out` lists every
   issue and pull request, open, closed and merged, that touches what the
   patch touches, with the type stated and the closing ruling quoted for
   every closed item. Read every closed item. An open pull request that fixes
   the same thing means you stop and say so. A closed issue that ruled the
   behavior intended means you stop and say so; you never argue with a
   ruling. The printout is required by step 9; write it before the branch
   exists.

3. **Is it a fix or an opinion?**
   A change that rejects an input the project tolerated, or changes a
   default, is a breaking change on a stable major, however wrong the old
   behavior looks. It becomes an issue that describes the behavior and offers
   the patch, never a pull request. Classify every patch before writing a
   test for it. A finding whose only red evidence is a measurement, such
   as peak memory or elapsed time, is a hold: a pull request needs a test
   that fails on the default branch for a wrong value, a crash or an
   out-of-bounds access, and "less memory" is not that test.

4. **Prove it red first.**
   On a fresh clone of the upstream default branch, not the tree you found
   the bug in, write the test that fails. Run it and keep the failing output.
   Apply the patch. Run it again. Both results go into the pull request as
   the test itself; the body states the fact in one sentence. When the
   patched function serves several public entry points or has several
   branches, the test is a grid: every entry point through every branch,
   plus the zero, identity and signed-boundary rows. A reviewer lists the
   empty cells otherwise.

5. **Run their CI, not yours.**
   Run the project's own test target on the fresh clone, and every gate its
   pull request workflow runs: lint, format, mutation, API check. Read the
   workflow file to find them. A gate you did not run is a red check the
   maintainer sees before you do. When the repository ships a Dangerfile, a
   pre-commit config or a commitlint config, those are its acceptance
   criteria in machine-readable form; run them.

6. **Match the house style.**
   Run `housebroken notes owner/repo` before writing the pull request and
   again before any rework, and follow what is there.
   One finding, one pull request, the smallest diff that fixes it. No
   comment in code that has none: run `housebroken census <clone root>` and
   compare the added-comment ratio with the file. The body is under 120 words,
   in the project's template if it has one, and says what was wrong, what the
   change does, and how it was verified; every sentence in it is something
   you reproduced on the fresh clone in this session, never a line carried
   from a journal. No tool footer, no session link, no
   co-author trailer, no typographic dashes. When a template asks whether AI
   was used, answer in one truthful sentence.

7. **Know the paperwork.**
   Before the first pull request to an organization, find its agreement: CLA,
   DCO sign-off, signed-commit requirement, disclosure trailer. Some CLA
   actions post nothing on the pull request and write the instructions into a
   failed job's log; read the log when a check named cla or license is red.
   Some organizations want a trailer such as Assisted-by or Generated-by and
   some forbid one; use exactly what the organization asks.

8. **Security goes through the side door.**
   A memory-safety, remote-abort, injection or path-escape finding in a
   library goes by the project's SECURITY.md route, privately, with the
   reproduction and the patch attached. It never becomes a public issue or
   pull request until the project answers.

9. **File through the gate.**
   `housebroken file owner/repo --title ... --body-file ...` is the only way a
   pull request is opened. Never run the pull request creation command
   directly. The gate refuses when the prior-art printout for that repository
   is missing or older than a day, or when the body carries a footer, a
   trailer or a dash character. A refusal is a result; fix the cause.

10. **Watch it land.**
    `housebroken verify owner/repo PR` re-derives from GitHub that the head is
    the intended commit, the diff is exactly the intended files, and CI
    settled. `housebroken sweep` lists every open pull request where the ball
    is in your court. `housebroken inbox` is the first thing a session does
    and the only way you learn a thread's state: it prints every event on
    your threads since the last acknowledged cursor with the full body, the
    thread's state, and a census of failing, blocked and conflicting checks
    on every open pull request. A list of who commented is not a read, and a
    conversion to draft is a review. Act on every human item, then run
    `housebroken inbox --ack`. Answer every maintainer comment the same day,
    in the user's voice. Rework what is asked for as a second commit so the reviewer sees
    the change. When the maintainer is
    right, concede in one sentence and let them close it. Never nudge a
    silent maintainer without the user's explicit word. After answering a
    review, record what the maintainer asked for with
    `housebroken notes owner/repo add "..."`.
    Write the reply the way one maintainer writes to another. Lead with the
    fact or the action, never with a verdict on the reviewer: no "you are
    right", "good catch", "great point", "thanks for the feedback", no
    apology, no restating their question, no closing summary or offer of
    further help. A concession is the corrected fact followed by what
    changed: "Every loader checks its read, so a truncated file fails on
    main; the description is corrected." A disagreement is the command and
    its result, without adjectives. An answer to a question is the answer
    first and the evidence second. One to three sentences, no bullet list
    under a paragraph's worth of content, no bold, no exclamation mark, no
    handle unless the thread has several people. Offer closure as a plain
    statement ("Fine to close."), and stop when the content stops.
    Never post two replies to one repository in the same minute: space them
    at least ten minutes apart, the one that matters most first, so a
    maintainer's inbox does not show three answers stamped the same second.

11. **Clean up.**
    `housebroken hygiene` deletes the fork branch of every merged or closed
    pull request and lists forks with no pull request left; delete those when
    the work is over. No planning file, agent directory, journal or build
    output ever enters a diff.

12. **Three per repository, one finding each.**
    Never more than three open pull requests on one repository. Each one
    finding, each passing every step above on its own. GitHub lets
    maintainers cap open pull requests from non-collaborators and counts
    agent-opened ones against that cap.
    The same spacing applies to filing: pull requests and issues on one
    repository go out at least ten minutes apart, the strongest first.

13. **Write it down before you leave.**
    A run through the door ends with its ledger, not with the pull
    request. A house rule learned about the repository goes into
    `housebroken notes owner/repo add "..."` the same session. A
    maintainer's verdict on a filed pull request is a lesson for everyone:
    it goes into docs/lessons.md in the housebroken repository the same
    day, quoted verbatim with the rule it became, by pull request when the
    repository is not yours. A gate that was wrong, missing, or done by
    hand goes on the housebroken repository as an issue before the run
    ends. A lesson that lives only in a chat is lost.

## What you say to the user

Before filing: the repository, the finding in one sentence, the prior-art
result in one sentence, the red-then-green result, the agreement the
organization wants, and the exact command you are about to run. After
filing: the pull request URL and the verify result. At the end of the run:
what went into the ledger, or that nothing did. On a refusal at any
step: which step, and the one sentence that explains it.

## Never

Never open a pull request without the prior-art printout. Never argue with a
ruling in a closed issue. Never file where the policy asks you not to. Never
put a footer, a session link or a co-author trailer on anything that leaves
the user's repositories. Never post a comment upstream that the user has not
seen. Never claim a test ran that you did not run.
