# Rejected append tuning; complete federation cost profile

This experiment rejects a small candidate based on `prepared-input-core`.
The current engineering helper remains `52e9dd63…`; no product or README
performance claim is changed. [The original plan](plan.json) is retained.

`Federated.prepare` enumerates every source's semantic nodes, roots, Outcome
headers and search windows before discovery. The candidate replaces repeated
prefix-copying list appends with reverse buffers and one final reversal.
Two Lean order identities use only `propext`; native ContractAudit passes.
This does not prove the complete IO interpreter equivalent or make it suitable
for the 80-person target.

The native fixture has 16 raw PageMap sources, one batched publication per
source, 1/8 identical Outcome relations across sources, and 5,000 `x` characters
plus a key/newline per result. The raw `outputCharacters` field names that
padding, not the full body length. This is not native hook ingress, a logical
project publication service or concurrent writer throughput. Parent and candidate
use the **same original files and heads**, with fresh pins. Execution order is
reference/candidate, candidate/reference, reference/candidate at every size.

| Raw Outcomes | Reference ms | Candidate ms | Median before / after |
| --- | --- | --- | --- |
| 256 | 100 / 101 / 102 | 100 / 97 / 100 | 101 / 100 |
| 1,024 | 394 / 403 / 403 | 413 / 400 / 411 | 403 / 411 |
| 4,096 | 1,625 / 1,708 / 1,644 | 1,634 / 1,582 / 1,654 | 1,644 / 1,634 |

Every comparison checks complete exact JSON of canonical nodes/aliases, roots,
orders, all owners and ordered originals, all document/window metadata,
topology, scoped Unions and semantic population. **All nine agree.** Physical
page reads and bytes agree too. The frozen reference is the parent's prepare
body with stage observation added; it shares the unmodified identity/reader
primitives. It is appropriate for this buffer change, not an independent oracle
for future changes to those primitives. No answering model is called.

The candidate has no consistent practical speedup: it is slower in two of the
three 1,024-row trials and two of the three 4,096-row trials. Its largest median
difference is only 10 ms; instrumentation/cache noise is not isolated at that
scale. [Summary](summary.json), [raw compact trials](4096.json),
[decision and identities](result.json), [rejected delta](rejected.patch).
The planned ordinary lifecycle rerun is **not performed**: reject before
spending more work on this candidate. The plan deviation is explicit in the
result; this is not a successful lifecycle or token comparison.

In the 1,644 ms reference observation, structural identity takes 643 ms,
document enumeration 479 ms, topology/Union loading 358 ms, Outcome headers
127 ms and root enumeration 36 ms. Thus roughly 90% is in the first three
preparation stages; removing a small list-copy cost does not address the
complete source scan. Phase observation has its own small overhead and does
not establish the share of a real end-to-end hook. These fixtures do not
justify extrapolated million-row latency.

Separate Work-class probes agree with the independently materialized graph.
The positive Union chain spans two sources and reaches an owner in a third;
all 16 physical copies of an equal owner remain represented; the negative query
returns none. Removing the bridge source removes the generated equality.
These probes run after oracle materialization warmed the page caches, with
generators/closure prepared outside their timer. The 4,096-row lookup times
17/27/3 ms are **not cold certification, freshness, actual completed reuse or
hook latency**. Nonempty class output still has its real data-dependent cost.

Build and fixture failures are retained: initial theorem/helper type errors,
and the first source initialization using raw text instead of GraphStore's
required JSON Value authority. Correcting that fixture does not change product
authority decoding. Final guarded profiling peaks at 215,152 KiB RSS; all guards
finish with zero owned processes and no resource-limit trigger. The 3.5 GiB
stop/4 GiB hard ceiling and disk floor remain unchanged.

[Cleanup](cleanup.json) deletes four ended fixtures, the rejected source clone,
the whole rejected native build/executable and 30 closed logs/guard records:
315,403,054 apparent bytes. No physical-space equivalence or archive is claimed.
Protected originals and the current helper hash remain unchanged.

Next implement [a prepared owner view](../../prepared-owner-view.md), preserving
complete recognition and exact original evidence while maintaining owner
equivalence/counts/postings from publication differences. Do not add more weight
tuning or list micro-optimizations to the hook. That design is not implemented
by this experiment. The target, 98% evidence, p99/80 people/eight hours and all
matched token/quality gates remain incomplete; paid comparisons remain 0/18.

To reproduce, copy `prepared-input-core`, apply `rejected.patch` only in the
isolated copy, build `tools.research.FederationOrderChecks` with the parent test
entry renamed `preparedInputMain`, and run `federation-order ROOT COUNT` for
COUNT 16/64/256. Keep aggregate resource guards and remove ended DB/cache.
