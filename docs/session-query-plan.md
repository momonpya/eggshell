# Request-owned concurrent search over shared project preparation

2026-11-06 user direction. Required architecture, not an adopted implementation.
The target remains80 people using growing project DBs for eight-hour workdays,
98% necessary original evidence in actual delivery within30 seconds, complete
certification, and the matched total-token/quality adoption gates.

## Observed failure

The current isolated service admits independent requests but runs complete
searches through three fixed worker pipes. A lane remains occupied while the
query waits for source or numerical services and while it restores, extracts
and renders evidence. In the last eighty-request burst,68 configured searches
do not even start their semantic phase: the ingress-time semantic cutoff has
expired while they are queued. Their lexical delivery is a rescue result,
not evidence that eighty concurrent semantic searches are supported.

The candidate's queue median is18,935 ms and operation-work median570 ms in
that burst. Most of those operations are lexical;570 ms is **not** the cost
of eighty complete semantic searches. The previously reported semantic phase
also includes WorkGraph and delivery processing, not just vector similarity.
Do not attribute either number to an inherent vector-search limit.

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
