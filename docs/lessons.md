# Lessons, in the maintainers' words

Every rule in the README came from a maintainer's verdict on a real pull
request. This is the ledger. Quotes are verbatim; the rule column is what the
verdict became. Newest first.

| Date | Pull request | What the maintainer said | What it became |
|---|---|---|---|
| 2026-09-08 | ARM-software/astc-encoder #669 and #670 | "Is there any actual bug here? Either a security issue where we read out-of-bounds, or a case where we claimed to succeed but returned incorrect output? If yes, please provide specific reproducer data files." And on the issue: "If an input file is corrupt, allocates lots of memory and then either works with more memory, or fails due to size but safely exits, this doesn't really seem like a problem." | A hardening change needs an out-of-bounds read or a wrong-output reproducer in the body, as a file or a generator, not a peak-memory number. A transient allocation that fails safely is not a bug to this maintainer. One sentence in the #669 body claimed a success with a truncated buffer that could not be reproduced; every loader checks its read. Verify every claim in a body against the fresh clone before filing, and concede the moment one fails. |
| 2026-09-08 | ARM-software/astc-encoder #668 | "Is this behavior actually reachable? Do you have any cases that trigger astcenc to actually try to convert a negative value into fp16? The only case where I think its possible gets clamped to zero before reaching the fp16 path." | A one-token SIMD fix is judged on reachability, not on the intrinsic. The body must name the input that reaches the path and the command that shows the difference: here a half-float DDS with negative texels under -pp-normalize, where AVX2 output differs from the other ISAs on main. Put the reproducer in the body the first time. |
| 2026-09-07 | google/benchmark #2294 | "unnecessary comment" on a one-line comment above the fix; "why are there defaults here?" on two default arguments added so ten existing call sites stayed untouched | Comment density is judged on the lines around the change, not on the file: one comment in a function that has none is one too many. A default argument, overload or wrapper that exists only to leave call sites unchanged hides the change; touch the call sites. |
| 2026-09-07 | cloudflare/circl #699 | "More precisely: ecdh GenerateKey sometimes reads an extra byte on purpose to break exactly what we tried to do here." Then: "Adjust the comment and this is good to merge." | The one comment you do write states the library's intent, not the observed behaviour. "May read an extra byte" reads as not knowing why; "reads an extra byte on purpose, to defeat deterministic derivation" reads as knowing. A review bot had flagged the sampling loop as a timing leak; the reply cited the RFC section and the maintainer wrote "agreed". Answer a bot with the specification, once, and let the maintainer rule. |
| 2026-09-07 | Kotlin/kotlinx-datetime #649 | "The fix looks correct, but the tests can be improved." The test belonged in the JVM-only suite whose helper checks every pattern against java.time. | Put the test where the project's own comparison lives, even at lower platform coverage, when that is where the maintainer proves things. Reworked as a second commit with a three-sentence reply; merged an hour later. |
| 2026-09-07 | Shopify/toxiproxy #770 | Nothing. The CLA action posts no comment and writes its instructions into a failed job's log. | A red check named cla or license with no comment on the thread means read the job log. The contributor agreement card records which organizations' bots are silent. |
| 2026-09-07 | luau-lang/luau #2738 | "Fix for this is already planned for a future Sync." | Some projects land changes through an internal sync. The bug was confirmed and the pull request closed. No public search could have found the fix; the residual risk the prior-art gate cannot remove. |
| 2026-09-06 | webmozarts/assert #366 | "Narrowing the methods would mean a new major release." | A change that rejects an input the project tolerated is breaking on a stable major, however wrong the old behaviour looks. It becomes an issue, never a pull request. |
| 2026-09-04 | thephpleague/csv #591 | "I will close the PR. Thanks for submitting it." after a discussion of whether an unparseable date should reset the field or keep it | The maintainer's preference for the tolerant behaviour stands. Concede in one sentence and let them close it. Same class as assert #366, four days earlier; two closures made the rule. |
| 2026-09-04 | apple/swift-http-types #153 | "What is the use case for a relative URLRequest / HTTPRequest? We had some related discussions in #98" | Closed issue #98 had already ruled. Nobody had read it. The prior-art printout now quotes the closing ruling of every closed item on the touched files. |
| 2026-09-04 | apple/swift-log #503 | Two review rounds: use the package's own Lock instead of NSLock in the compatibility test; then approved, merged three days later. | Use the project's own primitives in tests, not the platform's. Rework as a second commit so the reviewer sees exactly what moved. |
| 2026-09-04 | apache/commons-text #768 | Asked for a negative case inside the valid window and a direct call with explicit lengths. | A maintainer's test request is the review. Reworked and replied within the hour; merged fifty minutes after the reply. |
| 2026-09-03 | apple/swift-log #504 | Asked for the documentation-only form of the fix; the assertion stays. | When the maintainer wants the smaller change, ship the smaller change. Merged the same night. |
| 2026-09-02 | console-rs/console #296 | Comment density and the project's own CI gates the author had not run. | Run every gate in the project's pull request workflow before filing, mutation gates included. No comment in code that has none. The comment census became a script after the third maintainer said the same thing. |
| 2026-08-31 | fastapi/typer #1946 | "Closing, violates user contribution guidelines. ... 1881 is a PR, you don't close a PR with another PR" | The duplicate search had returned pull requests mixed with issues and nobody checked the type. The prior-art printout takes the type from the API field and never infers it. |

## The pattern across the ledger

- Reworks done as a second commit with a one-sentence reply were merged
  within the hour four times (commons-text, swift-log #504, kotlinx-datetime
  #649, circl #700) and within three hours a fifth (circl #699). The
  maintainers were ready; the pull request had to be in the shape they asked
  for.
- Every closure that was a mistake on this side was a mistake of reading:
  a closed issue not read, a search result type not checked, a stable-major
  contract not respected. Every one became a gate that reads for you.
- Three separate maintainers objected to comments in code that has none
  before the census existed, and a fourth did after it existed, because the
  census measured the file and the maintainer measured the function. The
  gate moved to match the judge.
