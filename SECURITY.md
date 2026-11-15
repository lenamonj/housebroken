# Security

housebroken runs on your machine with your `gh` login. A defect that makes it write where the command did not ask, or run text a stranger wrote, is a security defect.

## Reporting one

Report it privately: on the repository's Security tab, choose "Report a vulnerability". Please do not open a public issue for it.

## What counts

- A gate that runs or evaluates text it read from a repository, a thread or a policy file.
- A gate or the hook writing to GitHub, or deleting a branch, that the command given did not ask for.
- A token, or a file from outside the clone, reaching a body, a log or a printout.
- A way for the published package to differ from the tagged source.

The hook is not a sandbox. It reads the text of a command and holds the accident, not the intent: a write behind `bash -c`, `eval`, a script file or an alias passes it, and the README says so. That is its stated limit, not a vulnerability.

## Versions

Only the latest release is supported. A fix ships in the next one.
