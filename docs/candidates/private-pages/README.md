# Request-local page fronts: faster, incomplete delivery

This isolated candidate gives each search one small page front across its
original and derived readers. It holds references to already checked decoded
pages from the shared backing cache. A private hit no longer updates the shared
cache's recency/counter table. DB/model/immutable payloads remain shared; mutable
fronts and counters belong to one request. Lean checks the2 MiB encoded-reference
and512-slot bounds and full checked-reference/scope rejection. Those laws are
not a complete bound on heap usage; the aggregate RSS monitor remains enforced.

Native checks pass independent fronts, full descriptor/scope rejection,513
pressure insertions, existing event/cancellation tests and ordinary ContractAudit.
The [plan](plan.json), [identities](identity-before.json),
[actual observations](evidence.json), [actual bodies](bodies.json), and
[body verification](verification.json) distinguish component success from the
failed actual-hook gate.

|16 simultaneous clients|Required original + ACK|Median|Maximum|
|---|---:|---:|---:|
|First wave|8/16|7,564ms|8,250ms|
|Second wave|8/16|8,784ms|9,474ms|

The first wave updates the shared page-hit table2,258 times, down from422,288 in
the direct-event candidate. Service CPU is45.46s, including17.75s system time,
versus93.95/44.79s previously. These are whole-wave observations with different
completion counts, not an identical-work microbenchmark. The32-query actual
delivery rate remains16/32, and only7 semantic completions contain a handoff.
Fifteen semantic completions are empty. No80-client burst or paid model call was
started. Required head/tail original fields and ACK are independent checks.

The smoke guard detects leftover processes after the nominal client exits and
retires them. This is a failed lifecycle gate, even though the monitor finishes
with no survivors. Peak related RSS is2,666,832KiB; the3.5 GiB stop,4 GiB ceiling,
disk floor and original30-second deadline were unchanged.

The failed rows have incomplete synaptic inputs, despite163 ranked nominations
and8 related candidates. The old diagnostic records `canonicalFailure` but omits
the separate acquisition `failure`. Incomplete source acquisition must not be
reported as successful empty search. A separate
[budget witness](lease-budget-replay.json) uses the actual existing Lean budget:
each16-source cut costs1,364,136 bytes under the old per-request formula;8 MiB
holds only six whole cuts. Without releases,98 source tokens are admitted and
1,182 of1,280 are refused. This proves eager retention cannot accommodate80 full
cuts simultaneously; it does not replay the observed scheduler or establish the
exact cause of every missing body.

Next share immutable source descriptors once and issue thin per-request leases,
release partial unusable cuts, preserve explicit acquisition errors and fix
shutdown. See the [shared-source lease plan](../../shared-source-lease-plan.md).
Do not inflate budgets, reduce certification to top-K or restart deadlines.

Runtime SHA256:
`7195049a584a8adabc2d8e2d04dcdeca46727b72852bde3f042d774adaedf1fe`.
Not adopted; answering-model calls0, paid token/quality comparisons0/18.
All80 synthetic questions were already seen; this does not establish real-world
98% delivery,80-person daily use, database growth or multi-host operation.
