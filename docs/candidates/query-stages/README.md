# Whole-query stage attribution

The full source protocol alone passes480/480 cuts in the previous study, but
whole-query eighty-chat delivery still fails. This Lean-only diagnostic adds
request-local monotone timestamps, appends them to the existing `request-pages`
receipt once after computation/cancellation joins, and changes no ranking,
model, source domain, certification rule, cutoff, durability or resource limit.
Product core remains unchanged. No answering model is invoked.

The [plan](plan.json) precedes the build and workload. The first observer drops
the old page statistics because the `finally` closure captures the initial
mutable `none` binding. Its OFF/ON32 hooks both deliver32/32 and their actual
outputs are byte-identical, but it is rejected as instrumentation. No eighty
run uses that binary. The [correction](observer-correction.json) keeps the reader
in one request-owned IO.Ref through finalization;35/35 page-stat receipts,
including priming, are then preserved in both modes. ON also retains35/35
finalized timestamp traces.

|Observer|Trace|Actual queries|Original + ACK|Semantic handoff|Maximum|
|---|---|---:|---:|---:|---:|
|initial, missing old statistics|OFF|16×2|32/32|32/32|9,231ms|
|initial, missing old statistics|ON|16×2|32/32|32/32|9,983ms|
|corrected|OFF|16×2|31/32|31/32|18,973ms|
|corrected|ON|16×2|32/32|32/32|9,783ms|
|corrected|ON|80|0/80|0/80|17,264ms|
|corrected|OFF|80|0/80|0/80|17,427ms|

The failed OFF case15 remains a failure. It received progress2,673ms after
actor start, then returned incomplete with an actor deadline error and no ACK.
The other31 actual bodies match the corrected ON control byte-for-byte. The
32/32 gate is unmet; observation-independent capacity and latency equivalence
are unproved. Before the eighty runs, an explicit [amendment](diagnostic-amendment.json)
permits exactly one ON/OFF load diagnostic for attribution after observer,
identity, resource and lifecycle checks. It changes no adoption or paid-study
gate. Those eighty results do not erase the failed32 gate.

Initial runtime:
`6fa001f6d372ae677b555c6a08a4df9dbef9191ba3128a6b5a3619d4959172c8`.
Corrected runtime:
`4ee1e57cc28fd7726e2394133ca386135bb969a076955e8a7ba8af4b21ca5629`.
Both use the same sealed native client, frozen sixteen original owners,
eighty known synthetic questions and MiniLM/settings. [306 real outputs](evidence.json)
are independently [checked](verification.json) against retained [actual bodies](bodies.json).
The [initial patch](initial-observer.patch) and [corrected patch](candidate.patch)
apply after the prior isolated shared-lease overlay. Nothing is adopted.

## What the eighty-query observation establishes

All80 actors start. Completed stage wall spans in the traced wave are:

|Stage|Median|Maximum|
|---|---:|---:|
|project/context reopening|325ms|702ms|
|frame capture|5ms|244ms|
|shared reader borrow|92ms|499ms|
|configured prepared-reader acquisition|9ms|34ms|
|configured synaptic acquisition|2,724ms|3,608ms|

[Full traces and distributions](stages.json) preserve all spans and missing
ends. Wall spans include scheduling and IO waits. Nested spans and medians are
not additive; a missing end is unmeasured, not a duration to actor finalization.
These measurements reject project reopening/frame/reader acquisition as the
main measured delay in this fixture. They do not establish general scalability.

The [existing provider receipts](provider-gaps.json) narrow the next step without
another native experiment. All80 ON and all80 OFF queries enter the typed
provider. Entry is before `BuiltinSearch.withRuntime` and prepared-input
restoration. Entry-to-result wall time is median9,990/max11,385ms ON and
median9,948/max11,530ms OFF. The ON service uses102.86 CPU seconds, including
80.01 system seconds; numerical backend CPU is100ms for the wave. This locates
the unmeasured interval inside the typed provider. Recorded numerical CPU does
not account for its wall time; setup, input restoration, routing, IPC waits and
Lean-side processing remain to be separated. Its dominant substage is unproved.

The final source-acquisition error files are misleading if treated as the first
failure: all69 ON and71 OFF files were recorded **after** their semantic phase
finished. They belong to the subsequent lexical path. Receipt stage files can
be replaced by a later phase. Thus those files do not prove the initial source
acquisition failed. The earlier cancellation hypothesis remains unestablished.
A [review of the exact installed runtime source](runtime-source-review.json)
documents cancellation semantics without claiming a runtime bug.

The [next measurement](next-measurement.json) extends the same request-local
callback inside typed runtime setup, encoder open/close, scope pinning,
prepared window/lexical/numeric restoration, fixed-matrix binding, query
encoding, routing/nomination, owner deduplication, scoring/wait and response
validation. Determine that substage before changing another cache or ownership
path. Consult the earlier rejected search-inputs study before reusing its code.

Every native guard exits without a resource/lifecycle trigger or survivor;
maximum related RSS is3,355,968KiB, below the unchanged3.5 GiB stop and4 GiB
ceiling. [Cleanup](cleanup.json) deletes finished private DBs/caches/raw logs and
the superseded initial source copy, without archives. The current observer
executable, required link objects/interfaces and original source fixture remain
because they are inputs for the next provider measurement. [Final checks](completion.json)
cover retained body hashes, protected originals and restored isolated source.

No eight-hour/growing-project/NAS capacity, real-world98%, quality or total-token
improvement is demonstrated. Answering-model calls0; paid comparisons0/18.
