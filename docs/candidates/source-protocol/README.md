# Source acquisition under concurrent graph queries

This isolates the failed eighty-chat search before another ranking or capacity
change. It uses the same frozen sixteen-owner development fixture, full original
Heads and completed preparation manifests as the preceding source-lease study.
All eighty synthetic questions have already been seen. Product core is unchanged;
there are no answering-model calls or paid token/quality comparisons.

## Full source protocol alone

The sealed Lean controller performs actual `prepare-source-batch` RPC, checks
every received source binding and preparation manifest, retains all1,280 tokens
at a barrier, and then releases them through the scoped protocol. Each request
keeps its original28,800ms lifetime and7,200ms acquisition allowance. One priming
sixteen-source request is released before each wave. The two modes use the same
service implementation: an external process, or a hosted service in the native
controller. Neither mode performs WorkGraph search.

The [order and bounds](plan.json) were fixed before the six runs:

|Run|Complete received cuts|Median|Maximum|
|---|---:|---:|---:|
|external1|80/80|893ms|947ms|
|hosted1|80/80|1,175ms|1,244ms|
|hosted2|80/80|1,367ms|1,371ms|
|external2|80/80|996ms|1,037ms|
|external3|80/80|911ms|958ms|
|hosted3|80/80|1,392ms|1,397ms|

In total480 complete cuts and7,680 source tokens were received, excluding the
six priming cuts. Every barrier holds sixteen shared descriptors/cache pins and
1,280 request tokens in2,674,856 accounted bytes under the unchanged8 MiB limit.
Every release leaves zero tokens, descriptors and charge. All sources remain
unchanged and every owner shuts down cleanly. The [records](acquisition.json)
and [exact frozen cut](frozen-sources.json) retain the result. These are protocol
results, not eighty-hook capacity.

## Overlapping actual queries: still failed

The same sealed native hook client starts eighty full graph queries against
runtime`f332d24c852a0b52063b07ecb651ff37362ba7c644aa918b09e8e37213feb276`.
A two-second service stack sample is explicitly an observer perturbation.
The first failed hook's prepared source bindings match the standalone cut.
Actual delivery remains0/80, semantic handoff0/80, maximum17,070ms. Disabling
only optional service profiling also remains0/80, maximum17,172ms. Required
body/ACK/failure receipts and durability remain enabled. Turning off profiling
does not establish a fix.

The observed service consumes95.83 CPU seconds, including74.93 system seconds;
the numerical backend consumes30ms. Sampled stacks include task-state/global
mutex waits and project/source reopening. Stack occurrence counts are not CPU
percentages and do not identify a single dominant cause. `Project.current`
pins one specified owner; this record does not claim quadratic owner enumeration.

## Completion observation follow-ups: rejected

Two isolated Lean candidates register one completion observer per task and read
a task-local monotone flag instead of repeatedly inspecting global task state.
The first covers service task registries and search supervisors. The second also
covers the operation reply and peer-disconnect promises. Wait and cancellation
continue to belong to the original task. Valid empty replies and dropped promise
owners remain distinct. No extra heavy worker, broader source domain, new clock,
larger resource budget or changed ranking is introduced.

|Candidate|Actual queries|Original + ACK|Semantic handoff|Maximum|
|---|---:|---:|---:|---:|
|registry/supervisor observer|16×2|32/32|32/32|9,790ms|
|registry/supervisor observer|80|0/80|0/80|17,088ms|
|operation waiters included|16×2|32/32|32/32|10,389ms|
|operation waiters included|80|0/80|0/80|17,093ms|

Runtime identities are
`58d48c7ce3770bba82ababd044803746387d36a925efb9cee256880d293e4312`
and`19d0f1a06dc5908e39a3a95b41aa9b1910e211c75fcbb07ef921e879e11ea893`.
The final eighty-query run starts all eighty actors, admission wait at most49ms,
and shares one reader image/49 handles. The service still uses96.62 CPU seconds,
including75.78 system seconds; numerical backend work is40ms. Both candidates
fail and are unadopted. Removing these polling sites alone is insufficient.

Ordinary ContractAudit and native80-task payload/monotone completion, precompleted
empty result, original error, cancellation/finalizer and unaffected peer checks
pass. The final candidate additionally checks unresolved replies and valid-empty
versus dropped-owner replies. These validate wiring and ownership cases, not a
formal proof of the runtime scheduler or a lock-free implementation.

The [actual bodies](bodies.json), [402-output independent verification](verification.json),
[receipts and failed guards](evidence.json), [partial patch](partial-observer.patch)
and [final patch](candidate.patch) preserve the negative results. Patches apply
after the preceding [combined isolated overlay](../shared-leases/combined.patch).
The [entry patch](entry.patch) imports the Lean native checks. Build/checker and
record-helper failures are retained; they are not erased by later successful
preflights. All native runs finish below the unchanged aggregate memory stop,
with no surviving owned processes.

Next measure request-local stage boundaries for environment reopening, checked
source binding, shared-reader borrowing and preparation acquisition during the
same actual load. Reuse the existing receipt path, preserve complete certification
and cancellation, and measure the observer's effect. Use that attribution before
changing another path. Preparing an immutable checked cut once in its project
owner remains the intended interface; the fast standalone protocol does not
prove that its whole-query wrapper already shares all preparation.

Finished private DBs/caches/raw logs and superseded executables are deleted after
capture, without archives; [cleanup](cleanup.json) records exact scope and retained
inputs. Rebuild the retired diagnostic executable before rerunning its setup.
The four finished build directories are also [removed](compiled-cleanup.json)
after checking that none of the five retained native link responses references
them; those responses and all protected originals remain unchanged.
The eighty-person/eight-hour/growing-project/NAS, real-world98%, quality and total
token gates remain incomplete. Answering-model calls0; paid comparisons0/18.
