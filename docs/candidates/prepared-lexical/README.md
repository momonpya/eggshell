# Prepared postings audit and empty projection elision

Isolated continuation of `7fd3c3cd`, not adopted. Multiple append owners within
each project remain required and unchanged. All sixteen original sources remain
in routed synapse collection and the authorized certification domain. There is
no owner-count, worker-count, deadline, ranking, vector or authority change.

## Audit before product wiring

The [read-only native audit](../../../tools/research/PreparedLexicalChecks.lean)
compares every term in the sixteen captured source dictionaries against the
project's already-published canonical lexical bitmaps. It uses the explicit
`lexical/` namespace, not the distinct original-owner namespace. All 545 terms
(including one absent term), 544 positive terms and 17,073 posting members agree
in owner identity and global frequency. All nominations, ranks and window
observations agree for eight fixed questions. Original and dictionary heads
remain unchanged.

Five alternating paired calls to the complete nomination algorithm, including
original owner ordering, take 16.7–17.6 ms through source postings and 7.7–9.0 ms
through prepared postings. This is too small to explain the failed hook capacity.
**The alternative posting reader is not wired into the product candidate.**
It also requires the producer's candidate-eligibility invariant before adoption;
an absent posting must not conceal incomplete preparation.

## Actual avoidable IO

Two lexical-only normal hooks reveal 32 source-binding RPCs with zero requested
ranges and zero returned bytes. Original-structure RPCs also reach sources with
no requested owners. The isolated [patch](candidate.patch) changes only
`SynapseTransport.lean` (apply with `git apply --unidiff-zero`): a prepared empty binding demand returns the empty result,
and an empty owner demand skips structure retrieval. Missing preparation and
every nonempty binding demand retain the checked RPC. Every source still runs
the complete existing routed graph collection. Nonempty structure and palette
validation are unchanged; empty diagnostic cache observations can disappear.

The actual helper branches have three Lean laws and declaration-connectivity
checks; the ordinary ContractAudit also passes. These establish the stated
branch behavior and preserved dependencies, not complete concurrent IO or
distributed authorization proofs. See [laws](laws.txt) and [audit](contract-audit.txt).

| Sequential actual hooks | Parent | Candidate |
| --- | ---: | ---: |
| Lexical, cold frontend | 2,342 ms | 2,241 ms |
| Lexical, running frontend | 1,565 ms | 1,442 ms |
| Lexical, running operation work | 623 ms | 492 ms |
| Meaning, cold frontend | 6,859 ms | 6,798 ms |
| Meaning, running frontend | 4,421 ms | 4,221 ms |
| Binding RPCs across two lexical hooks | 32 | 0 |
| Structure RPCs across two lexical hooks | 32 | 8 |

The lexical control was measured this turn with unchanged production sources.
The meaning control is the sealed parent profile from `query-work`; its raw
trial directory has already been deleted. Both lexical bodies (13,566 UTF-8
bytes) and both meaning bodies (88,578 bytes) are byte-identical to their controls.
These are single observations with tracing, not repeated matched speedup or
p99 claims. The meaning encoder remains MiniLM.

## Native cold eighty-reader check

Same sixteen-owner retained cut, question, 82 exact original input/output
observations, MiniLM configuration, budget and native helper as shared-startup.
All eighty reach operation admission. Fifty-seven deliver both frozen original
fields (six meaning, fifty-one lexical); twenty-three expire. The parent delivered
35/80. One burst does not attribute the whole difference to this patch or establish
sustained capacity. **The eighty-reader gate still fails.**

All eighty turn-input captures report complete. The original sixteen heads are
unchanged. Warm takes 1,914 ms. All hook measurements, including failures, span
10,588–29,769 ms. The final sixty operation observations have queue median/max
18,397/25,215 ms and work median/max 780/7,785 ms; they are not all-request p99.
The test exits nonzero for the failed clients. Every guard terminates without
owned survivors or a memory trigger; the native burst peaks at 2,948,320 KiB.
The unchanged stop is 3.5 GiB with a 4 GiB ceiling and 2 GiB disk floor.

The remaining bottleneck is admitted query work and its queue, not loss of
parallel original ownership. Keep the candidate isolated while investigating
repeated source reconstruction and metadata transfers. Do not increase worker
or owner counts as a substitute for measuring service throughput and preparation
debt under combined save, preparation and read load.

[Evidence](evidence.json) preserves every failure, exact runtime/source identities,
actual bodies, stage observations, frozen heads and the read-only audit. Ended
trial DBs, caches and raw logs are deleted after sealing, without archives;
the retained original cut and needed build/comparison inputs remain.
Answering-model calls are zero; matched paid comparisons remain **0/18**.
No total-token improvement, real-evidence 98%, eight-hour 80-user capacity,
multi-host/NAS durability, product, README benchmark or release adoption follows.
