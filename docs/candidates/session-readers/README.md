# Independent request readers over one checked public image

Isolated prerequisite for the user-directed
[request-owned search architecture](../../session-query-plan.md), not adopted.
This does **not** connect dynamic query actors to ordinary hooks yet. The
eighty-request semantic-completion problem remains open.

One coordinator freezes the existing checked public reader image for a complete
source cut. `Frozen.fork` creates an exclusively owned reader catalogue and fresh
original trace/counters for a request, retaining the immutable image and existing
bounded page pool. Bitmap overlays are independently instantiated from the
image. There is no new mutex/CAS in this API, and the coordinator's mutable pool
is never shared with concurrent request workers. Runtime and existing page-pool
synchronization are not claimed to be lock-free.

The same source order/scope, producer, prepared roots and owner namespace must
match the frozen key. Usage roots stay excluded from public preparation and are
still handled by the existing request-local path. Freezing checks the existing
catalogue's metadata and handle bounds. This is not a proof of total process RSS,
authorization of arbitrary IO, active-lease reclamation or a complete base
e-graph compiler.

The native check prepares the actual retained sixteen-source project using the
selected executable, rather than opening producer-specific roots in a differently
compiled client. It freezes once, creates eighty request states, proves their
source-counter separation by independent writes, and then observes their complete
owner bindings, shared readers and original dependency traces concurrently.
Each request also mutates its own bitmap overlay and verifies the shared image
and next borrower remain unchanged.

Results: coordinator freeze137 ms; creating80 request states sequentially152 ms;
the eighty simultaneous exhaustive binding/trace observations3,924 ms. These are
component timings, **not** eighty hook/search latencies. All observations match;
each worker has zero new public-image builds and one local cache hit. The
coordinator still has exactly one build and zero hits afterward. It retains one
160,230-byte metadata image and33 handles within existing bounds. Four altered
boundaries are rejected: source reordering, omitted source, missing owner
namespace and changed producer. All original heads remain unchanged.

The new exact-key law uses only standard Lean axioms. Ordinary ContractAudit
builds. The initial checker build fails on record-field layout after the product
and law have compiled; the corrected checker uses identical product bytes. Both
attempts remain in the evidence. The native check peaks at294,496 KiB; builds
peak at2,833,888 KiB. All three guards finish with no owned survivors or resource
trigger. This does not measure a model being copied eighty times or establish
eighty-person sustained capacity.

Next connect these exclusively owned pools to dynamically dispatched searches,
audit other provider/numerical mutable state, preserve request-local cancellation
and reply-byte accounting, and rerun fixed-snapshot semantic/evidence comparisons.
Do not call concurrent reader borrowing actual dynamic search dispatch. The
current three whole-query lanes are still the ordinary path in the compared
runtime; its68 skipped semantic phases are not a passing vector-search result.

[Plan](plan.json), [native checks](checks.json), [source/runtime identities](source-identities.json),
[law](laws.txt), [guards](guards.json), [attempts](attempts.json),
[reader patch](candidate.patch), [setup](setup.lean),
[native checker](../../../tools/research/SessionReaderChecks.lean).
Apply the focus-locator patch first when reproducing this exact combined runtime.
The reader API can be inspected separately; no token/quality adoption follows.

The exact parent source files are [restored](restoration.json). Ended profile and
component DB/cache/log data, obsolete diagnostic executable and temporary source
baselines are [deleted](cleanup.json):152,440,433 apparent bytes, without an
archive. Current originals, control executables and needed current link inputs
remain. Source/setup paths recorded in historical guards are not all retained.
Answering-model calls0; paid matched comparisons0/18; goal active.
