# Durable preparation recovery and prepared query admission

This isolated Lean candidate follows the [mixed shared-service failure](../project-service-mixed/README.md).
It is unadopted and has no answering-model or matched token comparison.

The source publisher now discovers durable index and native-journal targets
at startup in a dedicated background task. It uses the existing bounded
preparation plan. Full admission retains its discovery cursor; shutdown stops
discovery before closing the worker pool. No source ACK waits for derived
completion, and no query performs this discovery or builds an index.

Recovery alone is insufficient: the first retried mixed workload still
receives an incomplete reply after restart. The search may capture source
publication before its background preparation has finished. That failed run
and the recovery-only source/runtime binding are retained separately.

## Prepared admission

A new admission operation freezes a complete original lower bound once. It
selects already published prepared prefixes covering that bound, validates
exact ancestry through the original head directory, and closes their recorded
dependencies. If closure raises a dependency, admission waits for preparation
covering the raised bound. It never returns an older or reduced inventory.
Cancellation and the caller's absolute deadline remain in force.

Each admitted source carries three immutable heads: the original source,
query-input metadata root and owner-input metadata root. These contain no host
paths, query text, private usage state or completion authority. Query execution
restores those exact roots, validates the source/model/public-storage binding,
and constructs its existing checked reader frame from them. It does not look
up the source in a later live 64-entry metadata directory. Logical name
retirement therefore cannot silently substitute or remove an admitted record.

The usual warm-source case uses direct metadata lookups. A missing exact name
examines at most the existing 64 preparation slots and chooses the earliest
available covering prefix. Neither path enumerates Work/Outcome objects,
copies source bodies, scores vectors or rebuilds lexical/synaptic indexes.
Admission retains only compact pins between owners, rather than accumulating
all decoded preparation records. Reply-byte reservation occurs after the
prepared result exists, with its actual envelope size; waiting for readiness
does not consume the reply reservation, and a complete large owner inventory
is not forced into the former fixed 64 KiB envelope.

The gateway, client and data service require the same complete source/pin
inventory. Original publication records still bind only original cuts; these
derived pin roots are not persisted as original dependencies. The existing
advisory/completion separation, ranking, model and extraction policy remain
unchanged. Protocol identity binds the actual new source bytes without a
manually assigned version.

## Validation status

Product `29c0daeed8f2b1da83874b87add64cd0a29a93203c823ee227c8d2f46e1cfc0f`
passes the complete base shared-service lifecycle workload. It uses two DBs,
four physical owners per DB, four writer sessions and up to twelve simultaneous
clients. Nine writer turns publish 27 original tool observations and nine
answers. Two turns hold actual tool results across an actual restart of all
three services. Late/duplicate results and Stops return to their captured DB;
an old ALPHA turn does not overwrite the newer active BETA turn.
Of the 27 observations, 23 have verified timing intervals; four late results
remain explicitly unverified in time. Their original bytes are present, but
this check does not turn unknown timing into completion authority.

Four initial readers finish in 1.507 seconds. Four writers overlapping eight
fresh/existing readers finish in 2.542 seconds. After restart, ten readers
mixing new, resumed, cleared and compacted contexts finish in 2.250 seconds.
All 22 reader queries complete semantic retrieval. Their actual visible
context contains 206/206 required original-field appearances, including 110
in fresh contexts. The final inventory has 18 distinct original fields; 206
is repeated appearances, not distinct facts. Existing contexts count only
previously delivered visible bytes; new/clear/compact contexts require a new
body. Single-project readers reject foreign-project original fields.

All 188 completed commands, including 161 hooks and 27 real shell tool calls,
return zero with empty stderr. The maximum hook is 2.120 seconds. All services
stop normally, the guard is untriggered and drained, and sampled peak RSS is
4,088,208 KiB. This is a small fixture with a 500,000-character allowance,
not production p99 or a token-reduction experiment. No manual keep/warm or
answering model is used. See [summary](admitted-summary.json) and
[actual calls, bodies and stage records](admitted-records.json).

The separate same-owner growth workload is **rejected**. Its base lifecycle
passes (1.427 / 2.453 / 2.205-second gates), but the first additional four-writer
plus ten-reader wave triggers aggregate-RSS protection at 4,408,720 KiB against
the unchanged 4,358,524 KiB guard threshold. No growth wave completes. The guard
drains all owned processes; this forced shutdown is not a normal service stop.
This run is not repeated unchanged or combined with the successful base result.
See [resource rejection](growing-rejection.json) and
[completed calls and partial stages](growing-records.json).

The final product's 344 native objects and the observer's 323 objects are
audited, with all product core and 321 common sources unchanged. Six kernel
laws use standard axioms only. A 1,879-declaration effect audit confirms that
prepared metadata selection/restoration does not build indexes, enumerate
original documents or write files. See [proof/effect audit](proofs.json),
[product closure](snapshot-native.json), [declared core changes](snapshot-sources.json)
and [observer binding](snapshot-mixed-sources.json). The initial unavailable
`LawfulBEq` proof rejection is retained. A separate retirement observer first
failed the full-core audit because it omitted ContractAudit; its failed audit
is retained and the corrected observer imports that same product module.

A native fault-injection check removes the live query/owner preparation names
for all five populated owners of the ended base fixture. All five previously
captured roots still restore the exact original preparation metadata, and all
five substituted wrong roots are rejected. Original publication heads and bytes
remain unchanged. This test starts no service or model. The corrected observer
has 320 consistent objects and all product core/319 common sources unchanged.
See [retirement checks](pin-retirement.json), [guard](pin-retirement.guard.json)
and [observer binding](pin-checked-sources.json).

Ended fixture DBs, caches, journals, diagnostic builds and the superseded
baseline observer copy were deleted: 25,249 entries / 2,919,715,536 logical bytes,
with no archive. Current product/model/native inputs and the protected LLVM
original remain intact; the product still has 344 consistent native objects
after cleanup. See [cleanup](retired.json) and [post-cleanup closure](product-after-cleanup.json).

The current storage is append-only. This design addresses logical directory
retirement, not yet physical compaction, remote authorization, SMB/NFS,
sustained 80-user traffic, growing production DBs or general 98% evidence
delivery. The LLVM accepted seed, both topic passes, repeated inclusive-token
and quality comparisons remain outstanding. No global installation or README
benchmark result is changed.
