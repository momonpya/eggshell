# Shared local execution over independently owned project streams

Isolated continuation of [project-matrix-scopes](../project-matrix-scopes/README.md),
source parent `4f3eca00`. Not adopted. The [plan](plan.json) fixes the intended
boundaries before native execution.

A logical project retains multiple independently owned original streams. The
selected project grants the write route; other configured projects remain
read-only. This candidate does not replace those streams with one mutable head.
It shares local execution capacity across session managers: three search workers,
two save workers and the existing three preparation workers. Original publication
still has its separate bounded parallel scheduler. These are worker slots, not
the number of permitted users or a guarantee of sustained throughput.

Managers submit authenticated private requests to the existing per-user local
service. They do not start private search/save fallback processes. The service
holds at most 160 pending/running operation requests and 16 MiB of encoded input.
Search/save response reservations are separate from nested source RPC capacity.
Queue wait, connection establishment, request writes and response reads consume
the caller's original cutoff. Only checked semantic-ready progress can use the
remaining original hook window. No timeout is increased. A completed JSON null
is a valid empty response, not an unavailable worker.

Only the authenticated local OS-user endpoint can execute private session work.
Project read capabilities do not grant this operation. Save paths must belong to
that session's durable deferred/checkpoint queue, with symlink ancestors rejected.
Admission is not a durable ACK. An already executing save keeps its bounded
original-publication path after its peer leaves; queued work is cancelled.
Cancellation and completion belong to a request token, so they cannot consume a
subsequent request occupying the same worker slot. Closing the service seals
admission before workers are stopped.

Lean state fields prove the request/byte bounds; the fixed vector bounds active
slots. Role selection, stale completion, expiry and terminal closure are also
checked by the native helper. These properties do not prove fairness, OS memory,
complete transport semantics or an 80-user latency bound.

The first native normal-lifecycle attempt exposed a validation error: the new
dispatcher compared the existing 29,000 ms hook window to the 28,000 ms source-RPC
budget. It was corrected by naming the existing hook budget and using it at both
ends. The first 80-search/80-save attempt then failed: every waiting operation
sent a 500 ms liveness ping; congestion sent callers into startup locking, and a
full transport handler set accepted and silently dropped sockets. The correction
uses the authenticated operation itself as the liveness check, permits recovery
only after a failed connection before sending, and applies handler backpressure
before accepting a socket. Uncertain executions are never automatically retried.
These negative trials are retained as failures, not reclassified as successes.

Backpressure alone did not pass the next mixed load: only one query delivered
both original items, and 78/80 saves returned checked durable ACKs. A separate
instrumented diagnostic reproduced the failure. Its source RPC computation was
short (selection 23 ms), while receive time reached 1,559 ms and 912 pre-admission
busy replies circulated. A 2-second service sample found handlers waiting on
operation completion and the scheduler mostly waiting, rather than evidence of
expensive selection. Instrumentation adds overhead and is not a speed comparison.
The candidate therefore gives long-lived operation waits their own authenticated
listener, separate from the source/control requests they require. Source handler
capacity remains 128; the operation count becomes 160 for the declared concurrent
80-search/80-save burst, while the 16 MiB input and aggregate RSS limits remain
unchanged. This separates the dependency rather than giving long waits the source
slots. This alone also failed (3/80 evidence queries and 78/80 durable replies;
runtime `98998026…`), with no busy retry. The new operation waiters were recreating
a read selector and timer every 5 ms per connection. They now keep one native
read promise per wait and explicitly cancel that read on exit. Native connect,
write and read waits check `isResolved` before accessing a promise's blocking
result, retaining cancellation and the original cutoff. The native checks below
pass with this implementation; the separate fixtures are not a matched token or
causal speed experiment.

The [lexical load](lexical-load.json) passes all 80 original-evidence queries and
80 durable saves over four independently owned streams in one selected write
project. Two configured read projects retain six captured source snapshots. Each
query returns both original JSON evidence items and excludes a later foreign
publication. Search latency, including queue wait, is p50 5,570 ms, p95 7,667 ms
and max 7,863 ms. The complete guarded scenario, including setup, cancellation
and teardown, took 14,481 ms with sampled peak aggregate RSS 1,069,696 KiB and no
surviving process. This is one small synthetic burst, not a p99 benchmark or a
causal speed comparison against an older runtime.

The same native check verifies actual queued expiry, cancelling one paused
worker without cancelling the other clients, subsequent worker reuse, valid
completed-empty replies and rejection of foreign private save paths. Deliberate
expiry and killing the one paused worker produce send-expiry/EOF diagnostics;
other requests and later reuse must still pass. At load completion one preparation
attempt was still active; after the cancellation checks preparation had no active
or pending job. These counters do not establish sustained preparation throughput.

The first numerical fixture failed before the burst because it tried to warm an
already historical snapshot after a newer synaptic publication. That refusal is
retained. The numerical fixture now prepares actual MiniLM vectors before query
capture. A semantic-only transport trial then returned 21 evidence replies before
its 14-second semantic cutoff and 59 unavailable replies. All 80 saves were durable.
That harness omitted the product's subsequent lexical fallback and cannot be
classified as 59 whole-hook failures. The final numerical trial calls the actual
`deliverForWork` function, including semantic-first discovery, fallback, final
turn/epoch/deadline validation and offer publication. It records semantic and
fallback counts separately rather than requiring all 80 to use one route. It does not
relax freshness or force historical roots over current publication. The fixture
controller changed; the product code stayed identical to the lexical check.

The final [numerical load](numeric-load.json) also configures MiniLM preparation
on all 80 saves, while 80 clients use the normal delivery function. All 80 queries
deliver both required original items and all 80 saves return durable ACKs across
four owned streams. Of these queries, 21 finish through semantics and 59 through
the existing lexical fallback. End-to-end delivery latency is p50 16,070 ms,
p95 18,346 ms and max 18,550 ms. The complete guarded scenario took 25,419 ms;
sampled aggregate RSS peaked at 2,299,504 KiB, with no guard trigger or surviving
process. The earlier numerical-query/lexical-save scenario also passed, but its
different save workload is not used as a performance comparison.

Numerical preparation is **not drained**: after the final cancellation checks,
one preparation job is active and one pending. Source ACKs and foreground
delivery are complete; background numerical readiness and sustained publication
throughput are not established. Shutdown cancels derived work, as required; it
does not retroactively certify those indexes. The 59/80 lexical fallbacks are
also a remaining numerical throughput limitation, not hidden semantic successes.

Native outcome records, [source/runtime identities](result.json),
[resource readings](resources.json), [negative trials](negative-loads.json) and the
[patch](candidate.patch) are sealed. The helper uses the
unchanged MiniLM runtime only at its existing numerical boundary. No answering-
model call or new Python/Ruby implementation is part of this candidate.

Apply the patch with `git apply --unidiff-zero` to `project-readset-core` and build
`tools.research.ProjectExecutionChecks` with the recorded native study builder.
Run `context FRESH_ROOT`, then `execution-load ROOT`. On a separate fresh root,
run `context-prepared-numeric FRESH_ROOT`, then `execution-load-numeric ROOT`.
Keep each root's private data path consistent between setup and load. The helper
owns numerical lifetime after the fresh-root check. Use the existing aggregate
resource guard and do not overlap guards that own the same experiment prefix.

This endpoint remains local. Separate PCs, remote authentication, NAS behavior,
long-running growth and preparation debt still require their own validation.
Eighty logical clients in one helper are not eighty people working for eight
hours. Small-fixture original-evidence checks do not establish 98% necessary
evidence delivery. Paid matched comparisons remain **0/18**; total-token
improvement, answer quality and production adoption are unverified. Production,
README benchmark claims and releases remain unchanged.
