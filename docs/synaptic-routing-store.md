# Read persisted advisory topology

Status: isolated storage primitive, **not connected to product warm or hooks**.
The product runtime remains `05e28ed8…`; no answering model was called.
Actual topic delivery is still 2/4, 0/6, 3/5. This work does not establish
95% delivery, token improvement, p99, or team-scale acceptance.

## Why the graph was ineffective

The actual hook allocates 500 ms to its graph walk. Its first lookup does
not complete and the current admission rule discards the entire incomplete
result. The independent complete walk finds all four frozen topic-1 originals,
so absence of graph paths is not the observed topic-1 failure. Final selection
after a complete walk still needs to be checked separately.

The earlier integer arena took 13 ms after preparing the whole fact set.
[SynapticRoutingStore.lean](candidates/synaptic-routing-store/Eggshell/SynapticRoutingStore.lean)
now persists the same adjacency in PageMap pages. Querying it does not load
the complete fact archive or build a resident Arena.

## Representation and bounds

Nodes and targets have interned integer handles. Arc values use a composed
binary codec with a Lean roundtrip theorem. They store evidence digests,
the existing relation kind, a coquotation/claim group handle where needed,
targets and next nodes. Original evidence stays in the pinned original
index; tool output and questions are not copied into this view.

Construction streams at most 1,024 facts and 8 MiB of source fact payload
per batch. The ready manifest is published only after all source facts
have been covered. It binds the exact original index head, source head,
privacy scope and implementation bytes. An interrupted/unsealed image
cannot be opened as ready.

Traversal uses the existing PageMap page cache, integer visitation and
explicit node/arc/queue/hint/byte bounds. Targets are fetched in groups to
avoid repeated decoding, then restored to the original traversal order.
Private query roots return to the shared reader for non-query descendants,
preserving the original usage→coquotation dispatch. Shared and private
numeric IDs are never treated as one ID namespace.

`Hint` is a separate advisory type. It is not the existing full-fact Offer,
an e-graph Match, or a completion certificate. The storage codec and actual
reference comparisons are verified; a complete storage/refinement proof and
the final transport adapter are not supplied by this prototype.

## Fixed actual snapshot

The verified build covers 39,757 shared facts and 20 private facts. Its
queries were compared with the saved independent complete walk, without
normalizing away offer order. Every target, evidence digest, kind, priority,
multiplicity and sequence matches. Claim/coquotation grouping is also
checked against the original `Bundles.reason?` for the source facts.

| Graph budget | Observed ms | Result |
| --- | ---: | --- |
| 500 ms | 501 | Incomplete, zero hints admitted by the audit |
| 1,500 ms | 617 | Complete, all 27,825 hints match |
| 5,000 ms | 230 | Complete, all 27,825 hints match |

The failed first trial warms some pages before subsequent trials. These
numbers are not independent cold/warm distributions or p99. The complete
walk reads about 4.26 MB of projection payload. Construction took 36,908 ms
for shared and 15 ms for private scope, outside the query clock. Aggregate
guarded peak RSS was 283,168 KiB.

A separately labelled **synthetic** private usage record forces a path into
the actual shared graph. All 9,689 hints, including 9,688 shared coquotation
hints, match the original dispatcher in sequence. This exercises a boundary
that the topic's unrelated private question hash would not exercise; it is
not evidence of real answering-model reuse. Scope mismatch, unsealed views,
trailing arc bytes and the traversal arc cap are rejected as expected.

The first storage trial lacked the grouping field needed by the downstream
selector. The second retained groups but had not preserved sequence and
had not tested positive usage dispatch. Their small metrics remain as
superseded diagnostic records; their DBs are disposable. The selected
prototype is the third, verified construction, not the fastest trial.

The two superseded storage trials and completed synthetic/unsealed images
were deleted: seven directories, 165,178,046 logical bytes, no archive.
The verified shared/private images remain active inputs for integration;
the original seed, actual graph input and build dependencies are retained.
The scoped Lean cleanup checks completed guards and live/link dependencies.
Its [record](candidates/synaptic-routing-store/records/cleanup-report.json)
lists the exact targets.

## Next connection

1. Connect the projection to the existing publication delta and warm owner.
   Rebuilding every fact on every publication is unacceptable. Keep original
   fact and feedback access paths that still have real callers; remove
   duplicate graph-only postings only after checking those callers.
2. Adapt transport to advisory hints while retaining group identity and
   verified original-row bindings. Arbitrary-output fragments still need
   their original consumption witness, fetched only where required.
3. Allocate graph work from the actual request deadline, then measure the
   complete hook. The fixed 500 ms slice still fails on the first disk walk;
   merely replacing the reader while keeping that policy is insufficient.
4. Rerun actual frozen-evidence delivery before any answering-model study.
   Fast, complete graph traversal alone does not prove selector success.

Records: [verified result](candidates/synaptic-routing-store/records/verified-report.json)
and [guard](candidates/synaptic-routing-store/records/run-order.guard.json).
