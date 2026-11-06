# Locate the remaining host memory

Diagnostic only; not a memory repair or product adoption. The preceding goal
turn made concrete progress by sharing checked immutable source images in the
real hook. Its host still grew to895,520KiB. This study tests two possible
explanations before changing concurrency, ranking or allocator policy.

First, the exact same sealed runtime/client, sixteen sources and32 queries run
with all five optional detailed-tracing flags disabled. All32 semantic handoffs,
required originals and ACKs succeed; all35 actual stdout bodies, including
prime, equal the retained control. Host RSS is179,920→667,824→891,312KiB.
Detailed tracing therefore does not explain most of that growth. The single
latency observation5,852/6,637/7,542ms is not a speed-adoption comparison.
See the [plan](../shared-view/quiet-plan.json),
[actual control](../shared-view/quiet-result.json) and
[deleted trial state](../shared-view/quiet-cleanup.json).

Second, an isolated adapter queries the mimalloc2.2.3 already shipped by the
selected Lean toolchain. Lean implements the parser, controls, lifecycle,
experiments and records; C is confined to the allocator and OS diagnostic APIs.
No new allocator or application algorithm is introduced. The required
`visit_abandoned` diagnostic option is enabled only in the observer process.
The census consolidates delayed free lists, so it can perturb bookkeeping;
its timing/RSS is not an unmodified production benchmark. It never calls
`mi_collect`, changes reclaim policy or dereferences application objects.

The native positive control holds16MiB of byte payload after verifying its
producer OS thread has exited. The census counts20,976,640 allocation bytes.
After release it counts zero, while the pre-consolidation area bookkeeping
still reports20,976,640 bytes. Both controls pass before any actual search.
The installed header defines`area.used` as a block count, consistent with the
[pinned allocator implementation](https://github.com/microsoft/mimalloc/blob/v2.2.3/src/heap.c#L512-L543).
Thus the census, unlike that area field alone, distinguishes this retained
payload from delayed frees. It is still not a whole-process reachability proof.

The real service exposes the diagnostic only for explicit stats requests,
outside its state-lock scope. The exact native source audit permits only this
PublicationService instrumentation, its exact embedded bytes and the new
AbandonedHeap binding. The initial component changes no existing product source.
The separately sealed native adapter has its own source/object SHA. A failed
nested-branch return elaboration is retained in the development record;
the subsequent complete dependency/interface build passes.

The same real32-query cohort again has semantic/original/ACK32/32 and all35
complete stdout bytes equal the retained parent. Census results are complete:

| Observation | Host RSS KiB | Abandoned committed bytes | Still allocated bytes |
| --- | ---: | ---: | ---: |
| Prime | 178,304 | 17,201,072 | 2,724,208 |
| First16 | 661,072 | 16,491,712 | 2,480,304 |
| Second16 | 855,280 | 22,075,072 | 6,607,664 |

These abandoned areas do not account for most host RSS. This does **not** show
that the remainder is reachable work-graph data: live I/O-owner heaps and unused
allocator arenas are outside this census. Active search actors are zero at the
observations; background preparation is still active/pending and is recorded.
Census duration is3/3/4ms. Hook min/median/max is5,732/6,601/7,594ms; related peak
RSS2,747,440KiB, frontend/publisher exit0 and no guard intervention or survivors.
No eighty-full-search retry or answering-model call is made; paid comparisons
remain0/18. Real98% evidence, mixed growing-project/NAS/eight-hour eighty-user
capacity, quality and inclusive-token adoption remain open.

The next boundary to measure is allocations owned by the live native I/O
completion thread versus free allocator arenas. Do not retune ranking, shrink
the certification domain, reduce request actors, add collection or raise limits
on this evidence. Current immutable sharing remains the candidate parent.

All ended trial DB/cache/session/raw logs are deleted after actual body
verification. The observer's complete build/source tree and superseded frontend
finalizer executable are also deleted; required current native inputs remain.
No archives are made and the baseline alias is restored.

[Plan](plan.json), [native control](native-controls.json),
[component closure](component-native-closure.json),
[unchanged component sources](component-native-sources.json),
[adapter seal](native-adapter.json), [service patch](observer.patch),
[observer closure](native-closure.json), [exact sources](native-sources.json),
[actual evidence](evidence.json), [independent verification](verification.json), [summary](summary.json),
[guards](controls.json), [development](development.json),
[trial cleanup](cleanup.json), [artifact retirement](retirement.json),
[retained parent closure after cleanup](retained-parent-closure.json).
