# Reuse checked public prepared readers

Isolated candidate following `4526171e`, **not adopted**. Runtime SHA-256:
`b996ee9d05ada0b2161f2b147ad9b72442678aee6f5c96e1776de5d1aeaa5311`.
The control is retained `owner-binding-build/StudyMain`, `613e3ba5…`.

The [patch](candidate.patch) retains immutable owner/shared-synapse preparation
inside each already serialized query worker, independent of user or question.
It compares the complete original directories/heads, project scopes, producer
and public prepared-root descriptors. Private usage is absent from this key and
still reopened/validated for each operation. Canonical source capabilities still
retain/release per operation. No ranking, vector model, source-domain reduction,
worker/queue increase, prompt or certification change is introduced.

Snapshot images contain immutable head/handle data. Borrowers get fresh read
counters, traces, private cache cells and bitmap arenas. The initial bitmap
maps are immutable persistent values, so subsequent query joins cannot mutate
the retained image. Original read observations replay at shared/owner activation
in the same phase as the complete lookup. The original complete restoration path
remains available when no matching prepared image can be used.

The worker owns its catalogue without a new lock/CAS; it continues to use the
existing verified PageMap page pool. Catalogue admission proves at most32 images,
512 retained derived handles and8 MiB of charged metadata. The serialized-page
allowance is the existing128 MiB, separate from those bounds. These are not a
total heap/RSS proof or bounds on arbitrary external holders of borrowed values.

## Native and Lean checks

The final audit compares all163 owners over sixteen originals in three
alternating direct/resident pairs. Positions, counts, shared-root descriptors
and complete original read traces are identical. Forked bitmap mutations and
trace/counter changes do not enter another borrower. Changed public roots,
producers, missing owners and foreign project bindings are refused. A changed
private usage root reuses public preparation but is still rejected by private
usage validation. Reordered complete inputs agree with direct restoration; a
mixed-project image cannot silently present only part of its source boundary.

| Pair | Direct restore | Resident restore |
| --- | ---: | ---: |
| 1, first image fill | 107.44 ms | 92.58 ms |
| 2, resident first | 82.83 ms | 9.88 ms |
| 3, direct first | 85.09 ms | 9.45 ms |

Separate native fixtures cover retained mixed/latest roots, duplicate originals,
retraction/reinsertion, structured Work and different Exact dependencies. The
frozen bitmap/positions/traces agree for four owners/five original positions and
eleven owners/eleven positions. The original fixture's independent federation
checks also pass, including all four source-cut combinations and concurrent
append retention. Those append checks are not an eighty-user whole-system test.

[Five Lean laws](proofs.lean) cover original heads, borrower trace identity,
private-usage exclusion, complete key equality and catalogue bounds. They use
only standard axioms; the ordinary ContractAudit passes. This is not a full IO,
concurrency, bitmap-algorithm, authorization or trace-replay equivalence proof.

## Actual paired hooks

Same retained original cut, MiniLM, question,120,000-character budget and harness.
Three meaning pairs alternate order. All sixteen actual bodies are byte-identical
by route, with both frozen original fields:88,578 meaning/13,566 lexical bytes.

| Meaning pair | Cold parent / candidate | Running parent / candidate |
| --- | ---: | ---: |
| 1 | 6,687 / 6,509 ms | 3,922 / 3,826 ms |
| 2 | 6,388 / 6,420 ms | 3,879 / 3,858 ms |
| 3 | 6,343 / 6,344 ms | 3,884 / 3,814 ms |

Running meaning saves96/21/70 ms; cold results are mixed. One lexical pair is
2,293/2,328 ms cold and1,403/1,358 ms running. Each candidate worker builds one
160,253-byte/33-handle image; the next hook hits it without rebuilding. None of
these timings establishes total-token improvement or quality.

## Eighty-reader gate still fails

| Actual outcome | Parent | Candidate |
| --- | ---: | ---: |
| Both original fields delivered / client success | 72/80 | 75/80 |
| Admitted operations / complete captured inputs | 80/80 | 80/80 |
| Failure-inclusive time range | 11,044–29,758 ms | 10,137–29,758 ms |
| Final operation observations | 75 | 78 |
| Observed work median / maximum | 584 / 7,904 ms | 519 / 7,207 ms |
| Observed queue median / maximum | 19,762 / 26,229 ms | 20,577 / 26,222 ms |

There are no ACK refusals. Candidate5/80 deadlines still fail; a single burst
difference of three clients is not demonstrated capacity improvement. Historical
64/60 or25/64 results are not this comparison's control. The75/78 final-operation
samples are not all-request p99. Four observed candidate worker processes each
build once and then reuse the image (one process retires/replaces during phases).
This does not mean the worker bound was increased.

The remaining [capture stage](next-public-capture.md) still reconstructs public
input/owner metadata before worker admission: at eighty-reader load its reference
median is431 ms and owner median276 ms. Parent values are482/295 ms. That code
is unchanged here, so their difference cannot be assigned directly to this patch.

The [evidence](evidence.json) preserves all failed attempts, actual output hashes,
deduplicated bodies, admission/capture/phase receipts, source/runtime hashes and
scope limitations. The first audit omitted warm in its isolated data root and
failed preparation; final controlled audits explicitly warm first. Checker syntax
and import errors remain recorded. All82 saved native input/output observations
are exact, all sixteen original heads and protected original files are unchanged,
no guard fires and no owned process survives. Peak aggregate RSS is2,723,040 KiB.
Ended DBs/caches, fixture binaries and raw logs are deleted without archives;
active isolated candidate/control/originals remain.

The goal remains active. This is a small two-field fixture, not real98% necessary
evidence, large/multiple-project whole-hook capacity, NAS, eighty-person mixed
eight-hour use or p99. Total-token/quality adoption is unverified: answering calls
zero, matched paid comparisons **0/18**. Keep the candidate isolated.
