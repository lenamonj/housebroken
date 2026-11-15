# Contributing

## What a change needs

- A test that fails without it. Tests live in `tests/`, one file per script, and run offline behind a stub `gh`.
- `bash tests/run.sh` passing and `shellcheck -x scripts/*.sh bin/housebroken install.sh tests/*.sh tests/stubs/*` clean. CI runs both, on Ubuntu and macOS, and installs and drives the built wheel on Ubuntu and Windows.
- bash 3.2 syntax, because macOS ships it: no associative arrays, no `${var,,}`, no `mapfile`, no `case` inside `$(...)`.
- No new dependency. The gates use bash, git, gh, jq and the POSIX tools.
- A refusal goes through `refused NAME "message"` under a name no other refusal has. The name never changes once released.
- A rule in the README or the skill changes in the same pull request as the script that holds it.

## Where a rule comes from

Every rule here came from a maintainer's verdict on a real pull request, and `docs/lessons.md` is the record. A new rule is easier to accept with the thread that taught it.

## AI-written changes

Welcome, and held to the same bar as any other change. Please say in the pull request that an AI wrote or helped write it. Whoever opens the pull request has read every line, has run the tests and answers the review.

## Security

A security defect is reported privately; see `SECURITY.md`.
