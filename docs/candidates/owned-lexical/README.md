# Remove an unused synchronous index from concurrent publication

Isolated continuation of [owned-append](../owned-append/README.md), not adopted.
One logical project DB still has multiple concurrent physical source owners.
This change does not turn it into one owner per user, duplicate canonical
vectors, remove required Work indexes or connect ordinary hooks to those owners.

## Source-path change

The [consumer inventory](consumers-before.txt) found that synchronous
`searchTerms/searchPosting/searchFrequency` had no runtime retrieval consumer.
Modern lexical retrieval uses `RetrievalResearch.Index`. The old source API
was used only by diagnostics and old tests; `SourceLexical` and its policy were
unconnected prototypes. The [patch](candidate.patch) removes that redundant
write/retraction/read path and both prototypes. Apply with
`git apply --unidiff-zero` to `owned-append-core`.

Original graph roots, membership, Exact dependencies, Work owner/class/surface
indexes, original `ownerTerms/frequency/posting`, source windows and locators
remain. The original postings still support complete Work discovery and cold
coarse advice. Prepared lexical production and strict readiness checks remain;
the rebuild diagnostic now explicitly prepares its index. Missing preparation
is not treated as absence.

## Canonical graph correction found by the checks

The unchanged baseline also constructs the native identified WorkGraph with
the same Outcome twice when two authorized DBs contain the same relation.
Its complete reference graph contains that relation once. This is an actual
model-body difference, not merely a diagnostic discrepancy.

The candidate canonicalizes full Outcome relation Values before extraction,
using the existing stable exact-key merge. New Lean theorems prove exact
membership and uniqueness; full equality resolves hash collisions. Every
physical admission and merged source provenance is retained. Recommendation
cannot grant authority or create Union/completed. The [axiom audit](proof-audit.txt)
uses only standard Lean axioms. This is not a proof of concurrent IO or capacity.

## Functional checks

The tracked [native check](/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/tools/research/OwnedLexicalChecks.lean)
uses two DBs, shared Outcomes, All topology, Unicode text, source additions,
retractions and re-additions. Both arms pass all 246 independent source and
prepared-index checks, including original window bytes and key order,
independently tokenized postings/frequencies, old pinned readers and rejection
of cold, stale and corrupt prepared indexes.

Across 24 full Handoff/reference comparisons, including 18 positive Handoffs,
the baseline has three duplicate-Outcome mismatches; the candidate has zero.
Only the private diagnostic reason suffix `producer=work-class` is normalized.
Model-visible body, packet, source and certification fields are compared intact.
The [results](checks.json) preserve the baseline counterexamples. The whole
check took 9,983 ms, with peak owned RSS 562,688 KiB and no surviving process.

Both native builds include ordinary ContractAudit. The broader PageDB test
module could not compile against the unchanged baseline because old Change
constructors and other APIs are stale. The [baseline errors](baseline-suite-errors.txt)
and failed [build record](baseline-suite-build.guard.json) are retained; this
work does not claim that full suite passed. An initial fixture root-order
mistake and proof/build failures are retained separately and were corrected
before the final checks and comparison.

## Fixed native comparison

The [predeclared plan](plan.json) retains the existing controller: one immutable
boot and logical path per output size, 80 real TCP sessions across 16 owners,
four waves, exactly 16 scheduled background pins per arm, three alternating
repetitions per size. Both arms start from the same original files and inputs.

| Output bytes | Repetition | Parent write waves, ms | Candidate write waves, ms | Parent max submit, ms | Candidate max submit, ms |
| --- | --- | ---: | ---: | ---: | ---: |
| 5,000 | 0 | 2,965 | 2,172 | 1,055 | 686 |
| 5,000 | 1 | 2,798 | 2,139 | 897 | 660 |
| 5,000 | 2 | 2,899 | 2,179 | 975 | 672 |
| 50,000 | 0 | 15,373 | 9,000 | 5,294 | 2,820 |
| 50,000 | 1 | 14,985 | 8,970 | 4,933 | 2,896 |
| 50,000 | 2 | 14,556 | 8,440 | 4,708 | 2,537 |

All 12 cells recover the same 320 acknowledged original observations,
provenance and independent 1,280-root graph, including fresh-process recovery.
The [complete results](comparison.json) preserve every submit and query sample;
the [summary](summary.json) separates write waves from complete load windows.
For 5 KB the candidate complete windows are 3,109–3,113 ms because the last
scheduled pin must finish. For 50 KB the complete windows equal write waves.

The comparison took 263,792 ms. The [guard](comparison.guard.json) sampled peak
owned RSS 1,841,344 KiB, fired no limit and found no surviving process. Original
inputs and both runtimes were rehashed after all cells.

Parent helper: `901b595ffb976c55f2de1b98eaed12092c0fc56aee9ca87d158f194067182839`.
Candidate helper: `80613c7ea72a25bd92f032231bcdebadff48c96e3fbb7744ebb047d4fe3f2a33`.

## Capacity and adoption limits

The 50 KB candidate reaches 35.6–37.9 source observations/s in this short test,
above the assumed maximum 22.2/s **only for source publication**. Derived lexical,
synapse and vector preparation is excluded. A short throughput result does not
establish stable backlog, eight-hour capacity, p99, 98% evidence delivery,
ordinary Pre/Post/Stop latency, NAS behavior or total-token improvement.

Multiple concurrent owners within each project are mandatory. Ordinary hooks
still use the serialized source path; they must be connected to the checked
project route and complete read boundary. Cross-project dependencies, shared
project/scope preparation and complete cross-owner certification remain
integration obligations. No answering models were called; matched paid
comparisons remain 0/18. This is not adopted into product, README results or a
release under the existing token/quality/deadline gate.

After sealing compact records, ended fixture DBs, caches, raw logs, generated C
and unused executables are deleted without archiving. Current candidate sources,
necessary objects/interfaces/link inputs and the current broker helper remain.
Protected originals and controls are checked before and after cleanup.
