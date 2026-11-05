# Capture one maintenance boundary instead of reopening it per target

Isolated and **not adopted**. The product and active runtime are restored to
the parent; the [patch](candidate.patch) can be reapplied. Parallel append owners,
the three search workers, certification, ranking, synapses and all limits stay
unchanged. Answering-model calls are zero; paid comparisons remain **0/18**.
The80-person, eight-hour, growing-project, NAS and real98% evidence goals remain
unproved.

## Measured cause and change

The new [CPU diagnostic](../worker-cpu/README.md) uses different questions over
the same sixteen-owner project. A running frontend spends17.4–18.0 CPU seconds
per sixteen-request wave, alongside28.3–28.5 CPU seconds across its three search
workers. CPU time can exceed wall time because multiple threads run; these
numbers are not percentages or recursive stack-sample counts.

The frontend sample reaches `Session.refresh → flushIndexWork →
drainRegisteredIndexes → drainIndexTarget → ProjectContext.open?`. Each target
reopens and validates the same complete retained project cut. Additional
synapse and source-inventory discovery reopens it again. This nests complete
owner/dependency validation inside the target loop, including already prepared
read-only traffic.

`MaintenanceScope.capture` now obtains the pending turn, checked project context
and complete source inventory once per maintenance pass. Registration and both
drains use that value. It is not cached across turns. Each target still opens
its current original and verifies source identity. The original writer-grant
predicate and standalone recovery behavior remain; read scope supplies no writer
grant. Capture failure leaves maintenance pending. No additional lock is added
and no existing synchronization or durability contract is weakened.

Two [Lean laws](laws.txt) identify the current-grant and standalone predicates.
The ordinary [ContractAudit](contract-audit.txt) compiles. Native [checks](checks.json)
open the actual complete sixteen-source cut for writable and read-only turns,
compare the old grant predicate for every source and reject a matching identity
at a foreign path. Original heads stay unchanged. These checks do not prove
arbitrary IO, distributed ownership or concurrent policy replacement.

## Fixed comparison

The [plan](plan.json) precedes the six profiles: parent/candidate,
candidate/parent, parent/candidate. Each arm uses the same snapshot, questions,
MiniLM, settings and compiled lightweight native client, explicitly warms and
independently audits all82 original input/output observations. The candidate's
diagnostic auditor delegates to that same fixed parent auditor outside timed
hooks. A bundled-executable alias selects the actual target server, and each
profile checks that target's SHA before requests.

Each arm primes three cases and then sends cases0–15 and16–31 as two distinct
sixteen-client waves. These are new-chat, read-only diagnostics, not Luna
first/history rounds, OS-cold tests or eighty concurrent users. Wave B samples
one persistent busy process for two seconds; its latency is diagnostic.

| Pair | Parent median A/B ms | Candidate median A/B ms | Parent frontend CPU A/B ms | Candidate frontend CPU A/B ms |
| --- | ---: | ---: | ---: | ---: |
| 0 |7806 /7952 |6843 /6878 |17530 /18100 |8540 /9140 |
| 1 |7708 /7675 |6833 /7662 |17450 /18440 |8280 /9560 |
| 2 |7837 /7863 |7214 /7437 |17660 /18210 |8510 /8280 |

All105 paired actual bodies are byte-identical. All210 hook protocols request
and receive their delivery ACK within30 seconds, and every arm retains all
sixteen original heads. Frontend CPU falls in every measured wave, but latency
does not improve uniformly: pair1/B's candidate maximum is13248ms versus12983ms,
and pair2/A is13253ms versus13207ms. This is not p99 or total-token evidence.
[Full observations](evidence.json), [runtime identities](identity.json).

Both arms deliver both required fields in30/32 distinct cases per repetition.
Cases0 and28 fail even though their protocols complete. The three prime calls
are reported separately in the evidence and are not extra distinct questions.
This93.75% fixture result fails the98% objective. This experiment does not change
selection policy or establish eighty-person capacity.

## Remaining delivery failure

The [selection audit](../worker-cpu/selection-evidence.json) confirms case0's
original is nominated at zero-based rank7, hydrated and assigned fourteen focus
positions. Its complete5,000-character original is present in three candidate
units; none is selected. All three have positive marginal value, but extending
the chosen plan exceeds its character limit. The charged cost is119988 against
120000, although the actual delivered body is88881 UTF-8 bytes. Do not equate
that difference with a proven removable cost: the plan deliberately reserves
graph/status bounds over the complete admitted domain.

Next audit that reservation against the graph actually rendered for selected
evidence. Reusing work-graph frame dependencies must preserve a sound bound for
the complete packet. Do not repeat scalar weight changes or silently expand
the budget. A tighter cost and explicit-question evidence still need actual
delivery checks; an optimizer's proxy score is not necessary-evidence recall.
Candidate CPU samples now reach source-owner membership and numerical focus,
which remain independent search costs.

## Attempts, cleanup and reproduction

All13 [guards](guards.json) are terminal with no owned survivors. The initial
interpreted client spawned a full CLI per request and hit the3.5GiB stop at
3707872KiB, below the4GiB ceiling; it is a harness failure, not product capacity
evidence. The native profile peaks at2420992KiB; the six-arm outer guard peaks
at2877280KiB. Worker/owner counts,30-second deadlines and resource limits never
increase.

Native-check drafts failed on a reserved identifier, a missing PendingTurn
field and an unchecked array lookup. A larger dispatcher build was deliberately
cancelled to avoid compiling unrelated research controllers; its guard cleaned
remaining compiler children. The smaller entry compiles the same product and
ordinary ContractAudit. [Attempt digests and bounded errors](attempts.json).
The initial standalone CPU diagnostic's first client executable hash was not
captured before its parameterization rebuild; it is not represented as the
later client's hash.

Ended trial DBs, private caches, raw logs, the superseded client build and
temporary source copies are [deleted](cleanup.json):293684516 apparent bytes,
without an archive. Active originals, protected controls, parent runtime and
the isolated candidate's build/link inputs were retained for the next comparison.
On2026-11-06 the later [focus-locator experiment](../focus-locators/cleanup.json)
retires that unused helper:311716642 apparent bytes after identity, process and
current-link checks. This experiment's patch and evidence remain; its old build
directory is no longer retained.
The current source and dispatcher are [restored](restoration.json). Current
results cannot be rerun from deleted trial directories.

Reproduction uses [setup](setup.lean), the [native client](../../../tools/research/WorkerCpuProfile.lean),
[scope checker](../../../tools/research/MaintenanceScopeChecks.lean),
[paired controller](paired.lean) and [recorder](records.lean). Capture the exact
recorded parent before applying the patch with `git apply --unidiff-zero`.
No Python or Ruby controller is added.
