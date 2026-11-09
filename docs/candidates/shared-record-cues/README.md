# Share original-record cues until selection

**Unadopted.** Parent `c1de4407…`; candidate `a2de9114…`. The change removes a
real preparation loop, but the observed small-load run does not establish a
latency or capacity improvement. No 40/80-client escalation, paid answering-model
comparison, total-token result or adoption was performed.

Previously, preparation clipped the complete family cue list for all 2,124
original records. The candidate shares one immutable family context and cue list
and clips only selected records during `toDraft`. It adds no cache, queue, lock,
worker limit, ranking rule or authority rule. Model, source, question, prices,
keys and delivery envelope are unchanged.

Generic Lean theorems establish exact clipped-list bounds, final context/text
equality with eager clipping, and price/key independence from cue clipping.
Order and duplicates are preserved. The strengthened AST audit requires clipping
at materialization and forbids it in reference preparation. Existing fragment
and prepared-price proofs are unchanged. These facts do not close the older
full-query refinement obligation.

Six actual hooks (three topics, two independent chats each) enabled the existing
eager-reference comparison. It checked query serialization, every candidate's
context, original text, ranges and keys, and final delivered bodies. All six
canonical bodies and ACKs passed. Frozen DB-present evidence was 4/4, 7/7 and
5/5 in each repetition: 32/32 total. Three absent items remain explicitly
excluded. This interrupted-seed performance fixture is **not** an accepted new
seed or a completed first/history model benchmark.

| Topic | Chat 0 | Chat 1 |
| --- | ---: | ---: |
| 1 | 6,699 ms | 3,384 ms |
| 2 | 4,826 ms | 3,942 ms |
| 3 | 4,206 ms | 3,924 ms |

Preparation retains 435 shared cue cells for topic 1 and 956 for topics 2/3,
deferring 158,785 / 369,042 clipping-input comparisons respectively. These are
comparisons removed from preparation, **not** allocated-byte savings: most
comparisons yield no clipped cue. Diagnostic eager validation deliberately
materializes all candidates to test equivalence.

One normal changed-candidate capacity trial passed:

| Concurrent hooks | Successful semantic/synaptic bodies and ACKs | Wave time |
| --- | ---: | ---: |
| 4 | 4/4 | 4,433 ms |
| 16 | 16/16 | 11,388 ms |

Related RSS peaked at 3,951,392 KiB (about 4.05 decimal GB), within the 5 GB
ceiling and 4,358,524 KiB guard threshold. This is not a matched performance
comparison with the earlier parent trial. It does not establish repair of the
prior 80-client RSS stop, which occurred largely before this stage. No larger
retry was run. Product code and README results were not changed. The unadopted
runtime, compiler cache, raw hook outputs and ended private receipts were deleted
without archives: 6,281 files / 641,667,158 logical bytes (`cleanup.json`). Retained
parent native inputs and source DB hashes were checked before and after deletion.
