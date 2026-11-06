# Request-owned concurrent search over shared project preparation

2026-11-06 user direction. Required architecture, not an adopted implementation.
The target remains80 people using growing project DBs for eight-hour workdays,
98% necessary original evidence in actual delivery within30 seconds, complete
certification, and the matched total-token/quality adoption gates.

## Observed failure

The initial isolated service admitted independent requests but ran complete
searches through three fixed worker pipes. A lane remained occupied while the
query waited for source or numerical services and while it restored, extracted
and rendered evidence. In that eighty-request burst,68 configured searches
did not even start their semantic phase: the ingress-time semantic cutoff had
expired while they were queued. Their lexical delivery was a rescue result,
not evidence that eighty concurrent semantic searches were supported.

The candidate's queue median is18,935 ms and operation-work median570 ms in
that burst. Most of those operations are lexical;570 ms is **not** the cost
of eighty complete semantic searches. The previously reported semantic phase
also includes WorkGraph and delivery processing, not just vector similarity.
Do not attribute either number to an inherent vector-search limit.

The subsequent [numerical wait study](candidates/numerical-waits/README.md)
does start independent actors and passes32 simultaneous semantic deliveries,
but80 still delivers only2. Prompt actor admission alone does not provide
throughput. Returned numerical replies spend a median1,105ms from output-ready
to client receipt at80, while score-kernel median is5ms. The next boundary to
isolate is the same numerical protocol without whole-host graph load; source
option resolution is already memoized per exact source within each call.
Preserve independent chat actors and shared project data; avoid multiplying
dedicated blocking supervisors for every suspended phase. This candidate is
unadopted and does not meet the80-person or inclusive-token gates.

## Execution ownership

Each active chat gets an independently progressing lightweight search actor.
The actor owns the request identity, turn/epoch, deadline, private usage roots,
trace/counters, temporary bitmap/e-class overlays, and delivery/ACK state.
An idle chat does not retain a model or a heavy process. Completion or
cancellation releases only that actor's transient state.

The data-side service owns immutable original/index images for complete checked
project/read cuts, vectors, public synapse adjacency, certification indexes,
bounded original pages, and the numerical service/model lifetime. These are
prepared once per publication/cut and reused by actors. Private query text,
query vectors, feedback and mutable certification overlays do not become public
cache entries. Concurrent actors must not mutate a shared reader catalogue.

The first prerequisite is the isolated `PreparedReaders.Frozen` API. A single
coordinator freezes an existing checked image under its metadata/handle bound.
Each actor forks its own catalogue and original reader state while retaining
the immutable image and existing page pool. Changed source scope/order,
prepared producer or owner namespace is rejected and requires another checked
freeze. This API is not itself dynamic hook dispatch or shared base e-graph
compilation; those integrations remain explicit work.

The first [ordinary-hook connection](candidates/session-dispatch/README.md) is
now isolated and tested. It starts16 actors with at most2ms admission wait,
one public reader build and no search subprocess copies, but only3/32 known
originals reach actual body+ACK, against32/32 in the same-client parent control.
It is not adopted and the eighty-client gate was not run. The service sample
has216 threads: logical request independence must not multiply nested dedicated
supervisors and polling waiters. Reuse immutable router/page preparation and
make waits event driven before another capacity trial; attribution among runtime
scheduling, cache contention and repeated decoding still needs stage evidence.

The [subsequent isolated source-lease study](candidates/shared-leases/README.md)
separates three costs. Direct native event registration alone remains3/32.
One request-local page front reduces shared hit updates from422,288 to2,258 in
the first16-client wave, but delivers16/32. Interned immutable descriptors then
retain80 complete16-source cuts in90ms under the unchanged8 MiB budget, and
actual16-client waves reach32/32 original+ACK and32/32 semantic handoffs, max9.66s.
This is progress in components and16-client traffic, not an80-client pass.

Actual80 starts all80 actors, queue max75ms, but delivers20/80 originals and
16/80 semantic handoffs. Sixty-one complete cuts fail acquisition. Removing
self-endpoint pings is tested separately: the component resolves80×128 times
in3ms and32 hooks still pass, but80 hooks regress to0/80, max17.65s. That
candidate is rejected. Neither increasing actor count nor removing one
control-path check establishes capacity. No changed ranking, clock or inflated
resource limit is accepted as a remedy. Product core source remains unchanged.

The [full protocol isolation](candidates/source-protocol/README.md) now passes
480/480 complete received cuts across six eighty-client waves, maximum1,397ms,
with exact full Head/manifest checks and zero retained charge after release.
The same cut with whole graph queries still fails0/80; disabling optional
profiling also fails0/80. Task-local completion observers pass32/32 actual hooks
but remain0/80, even when operation reply/disconnect polling is included. Those
changes are rejected. Neither source RPC alone nor those polling sites explain
the full failure. All eighty actors start; the final run queues at most49ms,
while its service uses96.62 CPU seconds and numerical backend work only40ms.

The [whole-query stage study](candidates/query-stages/README.md) now measures
those boundaries. At80 actors, project reopening is median325ms, frame5ms,
reader borrow92ms and prepared-reader acquisition9ms. All80 ON and OFF queries
enter the typed provider, whose entry-to-result interval is median9,990/9,948ms.
Recorded numerical backend CPU is100ms in the ON wave. Both modes still deliver
0/80. The corrected32-query control is31/32 OFF versus32/32 ON; the failed case
is retained and neither observer equivalence nor capacity is claimed.

All69 ON and71 OFF final source-error files occur after the semantic phase;
they belong to lexical fallback. The older unavailable-cut counts are final
stage-file observations, not proof of first-phase acquisition failure. Do not
optimize the source protocol or task cancellation again on that inference.
Next pass the existing request-local callback inside typed runtime/encoder
setup, scope pinning, prepared input restoration, routing, scoring/wait and
response validation. Determine the dominant provider substage before another
cache or ownership change, and review the rejected search-inputs candidate
before reusing it. Complete certification, immutable-cut sharing, observer-cost
reporting and original weight/cutoff/resource limits remain requirements.

The subsequent[provider-stage attribution](candidates/provider-stages/README.md)
finds a concrete startup bottleneck: all80 restore provider inputs, but only21
finish startup-lock acquisition and none finish query encoding. Repeated
authenticated ping is inside that lock. The same observer's16-client controls
both deliver32/32 identical outputs;80 ON delivers0/80 and OFF1/80.

The isolated[ready-endpoint candidate](candidates/numerical-ready/README.md)
removes that startup path from all80 measured queries. Fifty-seven finish
encoding and reach scoring;none finish scoring or deliver the original fields.
The guard stops at3,683,280KiB and drains all owned processes. No OFF80 control
is run after this resource failure. The candidate remains unadopted; all153
actual outputs, including the stopped wave, are retained without inventing
missing client latencies or receipt-to-case associations.

The next measured range is backend numerical admission/preparation/exchange,
not another whole-query worker-count adjustment. Existing failed-query metrics
show completed-reply scoring wall median3,335ms against reported arithmetic299µs
and projection reads7ms,with no projection misses. These do not measure the
unfinished current RPC. Attribute queue/transport wait and memory before another
capacity run; keep request actors independent and share immutable preparation.
Component accounting is not a proof of the wrapper's active-read shutdown order.
All actual bodies, failures and cleanup are retained as compact evidence, not
as old DBs or raw run caches. Paid token/quality comparisons remain0/18.

## Dispatch and resource contract

Replace the fixed three whole-search lanes with request-owned tasks. Admission
remains bounded by live request metadata, retained handles, transient query
state and response bytes. The existing4 GiB aggregate ceiling/3.5 GiB stop and
2 GiB disk floor remain. The old count of three search processes is an
implementation choice, not the concurrency requirement; it must not be used
to serialize unrelated chats in the replacement.

Source publication keeps its independent parallel append owners. Save ACKs
remain separate from index readiness and delivery ACKs. Source/control RPCs
retain separate handler capacity so parked search requests cannot occupy the
handlers they need. Numerical kernels can have bounded CPU/batch admission
without holding a global whole-query slot while a request waits.

Response reservation must also be reviewed: reserving a maximum-size frame
before starting every query can recreate a hidden three-query semaphore even
after the dispatcher is changed. Account live result bytes and retain the
global bound; do not multiply a maximum reply allocation by eighty.

Keep the original upstream deadline and complete certification domain. Do not
hide queue time by restarting the hook clock. For the first dispatch comparison,
retain the current semantic/fallback cutoff policy so concurrency effects are
separate from a budget-policy change. Close admission before shutdown; cancel
and join request-local work without killing another actor or an acknowledged
source commit. Stale tokens and epochs cannot complete or publish another
actor's result. Runtime/stdlib synchronization is not claimed to be lock-free.

## Required checks

The operation client's deadline is now immutable in the isolated candidate.
Only its connection owner handles progress between frame reads;the checked
pure transition preserves the upstream identity and hard cutoff. Native
cancellation tests caught a promise-owner join bug before hook execution;the
corrected shared receive owner passes fragmentation/cancel/deadline/EOF/peer
checks. All32 ordinary hook bodies,original fields,ACKs and semantic handoffs
match the retained parent. This removes a deadline mutex,not all runtime or
shared-lifetime synchronization. The complete251-module native-source audit
limits differences to the declared code and its exact embedded identity bytes.

The memory sample at16 clients rules out resident thread stacks as the main
footprint at those samples. Quiescent hostRSS grows even while the measured
source/page/palette counters stay fixed. Separate retained graph/JSON/task
state from allocator-owned free pages before another80-client test. Do not
interpret a virtual stack reservation,an observer's exit failure,or a narrow
successful32-body control as the full80-person/98percent practical gate.

The isolated reader-page candidate now carries immutable verified page seeds
into actor-owned fronts. The reader constructor has no shared cache owner;
lookup, misses, insertion and statistics use local state. Lean checks the
owner-free operation equalities, page validity and original encoded-page
budgets. A held-owner-mutex native check and all32 ordinary hook receipts
confirm this path does not touch the shared page cache. Required originals,
semantic handoffs and exact parent output bytes pass at16 clients/two waves.

The gated80-client run stopped at3,673,600KiB aggregate RSS before a measured
client report existed. Retain that capacity failure and leave missing client
times unmeasured. This is not an80-person pass. Do not raise the guard, retry
unchanged load, or call the whole retrieval path lock-free: frame-preparation
coordination, canonical-source pages and prepared metadata bookkeeping still
require an ownership audit. Move immutable work out of the request path;
retain explicit lifetime/admission transitions until their replacement has
equivalent safety and resource guarantees.

1. Native80-borrower checks over the complete16-source cut: exact original
   bindings/dependency observations, independent counters/bitmap overlays,
   one coordinator build and zero new builds per worker; reject altered cuts.
2. Connect the request-owned executor and shared preparation to ordinary hooks.
   Check cancellation, cross-chat isolation, source changes with an older pin,
   wrong epochs, bounded reply retention, and shutdown with active searches.
3. On the same frozen snapshot/questions/MiniLM/settings, compare parent and
   candidate with three alternating repetitions. Report semantic completion
   separately from actual original evidence delivery. Both must reach98% for
   the eighty configured semantic queries; lexical fallback is not a semantic
   success. Keep all failures and actual bodies.
4. Run normal publication/preparation/query traffic, growing multiple projects,
   sustained eight-hour backlog/latency tests and NAS/multi-host fault checks.
   A read-only burst or the borrower component does not pass these gates.
5. Use a new fixed-runtime seed for matched initial/history rounds of topics
   1/2/3. Adoption still requires inclusive-token improvement and maintained
   answer quality; answering-model calls remain0 and paid comparisons0/18 now.

FAISS's official documentation describes concurrent CPU-index searches and
batching as supported execution patterns. That is an architectural reference,
not an Eggshell performance measurement or a proposal to replace its DB:
[Threads and asynchronous calls](https://github.com/facebookresearch/faiss/wiki/Threads-and-asynchronous-calls).

The owner-metadata-image candidate now captures checked immutable owner values
after the existing query reservation,then reads them directly in palette
rendering and source selection. Pure lookup laws and an actual-selector audit
pass;native reads complete while the originating cache mutex remains held.
The32 ordinary hooks preserve every parent stdout byte and complete semantic
delivery;max8,828ms,related RSS2,698,336KiB. This single control establishes
behavior preservation,not a measured performance or token improvement.
File-header/page/lease/admission synchronization remains separate. The80-hook
memory failure is unresolved;do not repeat unchanged80 traffic or increase
the guard. Product adoption and real98% evidence delivery remain open.
