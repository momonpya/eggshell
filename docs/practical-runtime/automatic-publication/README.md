# Automatic preparation during concurrent publication

The fixed isolated product is terminal-closure, SHA-256
`302ead2043af3ba3764668652f5543cdf330ca0dae16ac27784b7536ab116338`.
No product code changed. This test closes a gap in the earlier mixed-traffic
checks: those checks explicitly called `egg warm` after each wave.

Two initially empty logical projects each have four physical append owners.
Four writers create a baseline and three further waves add four writers each.
Each writer reads both projects and writes only its selected project. Ten new
read-only clients query after each wave; the three incremental waves also run
ten readers alongside the four writers. Registered plugin commands perform
real shell observations and automatic final-answer capture. There is no manual
keep, warm, generative answering model, or hook replay. Readiness probes only
inspect already stored preparation; they do not enqueue it.

Before each reader batch, the test freezes required fields from published
original observations and verifies their owner, occurrence, and synaptic
provenance. All 70 semantic searches complete. Actual returned bodies contain
640/640 required fields, with paths and product source fingerprints. Opposite
project markers do not leak into the read-only profile. All 48 observations and
16 final answers are automatically stored. Every owner retains consumed,
supports, and coquoted edges (2/8/8 per owner).

| Wave | Four writers, plus ten overlapping readers in waves 1–3 | Ten fresh readers |
| --- | ---: | ---: |
| 0 | 4.708 s | 1.892 s |
| 1 | 7.335 s | 1.940 s |
| 2 | 7.956 s | 1.989 s |
| 3 | 8.604 s | 2.057 s |

Setup/SessionStart precedes the batch gate; reader batch times include prompt
delivery and SessionEnd. Sequential readiness probes observe combined residual
waits of 1.756/2.491/3.497/4.095 seconds, not independent preparation latencies.
Answer discovery also polls sequentially and is not a publication-ACK latency
measurement. All reader searches report zero warm requests and zero warm time.
Sampled related RSS peaks at 3,823,408 KiB. Every guard ends successfully without
triggering, and every service stops with no owned process remaining.

## A real Pre failure remains

This is **not** a clean result for all hooks. One `consume-pre` callback returns
an incomplete notice with `storage object mutated during read`. Its exit status
is zero because the hook fails open. The full registered callback and five
receipt stages are retained. Background stderr also contains six state-guard
wait warnings and two unfinished-publication warnings; these are not hidden by
the successful final persistence checks.

A native postmortem finds all seven journal entries for the affected turn:
three starts, three finishes, and the answer. It separately reproduces a reader
failure mechanism: atomically replacing a path changes the old held inode's
ctime without changing its bytes. The existing reader rejects that otherwise
valid old committed image. External source freshness still rejects the replaced
path. The exact file behind the original Pre failure was not identified, so this
reproduction establishes the mechanism, not definitive attribution of that
callback. The next isolated change must retain full stable-read checks while
allowing a bounded new attempt on the same pinned descriptor. It must not weaken
source freshness, remove ctime checks, add read locks, or catch arbitrary IO
errors.

The first independent attribution audit incorrectly compared source fingerprints
to SHA-256. Original `queries.json` and `summary.json` preserve that verifier
mistake. `checked-queries.json` and `checked-summary.json` use independently
inspected `SourceEvidence.fingerprint` values: a length-bound BLAKE3 page chain.
The experiment was not rerun, and the product was not changed to pass the audit.

## Scope and retained evidence

The plan, actual requests/responses, unique returned bodies, source freeze,
readiness, persistence, process, warning, and corrected audit records are kept.
The ended DBs, caches, source copies, and helper executables are deleted without
an archive after checking protected runtime/model/native-input dependencies.
The cleanup and post-cleanup native closure are recorded separately.

This synthetic workload proves automatic preparation and project isolation for
these 14-client batches, not general 98% recall, growing large databases,
80 users over eight hours, NAS/multiple hosts, or MCP privacy. There is no accepted
new LLVM seed, no six answering-model stages, no quality comparison, and no
matched total-token comparison. Adoption remains zero; the paid matched gate
remains 0/18.
