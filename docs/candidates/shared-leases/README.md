# Shared immutable source descriptors and thin request leases

The preceding request-local page candidate delivers16/32 originals. Its8 MiB
retention budget charges the same full immutable source descriptor per request;
the captured16-source cut fits only six times. This candidate interns the exact
authorized scope, full original Head and preparation manifest once, and issues
independent1024-byte-accounted request tokens. The budget remains8 MiB. The
token count bound is derived from that byte allowance. Different neutral Heads
remain distinct; a matching saved manifest does not erase the original Head.

One descriptor owns one shared-cache borrow until its last token and actual
active reader retire. Expiry/release/close forbid new readers but keep a running
reader charged until its finalizer. A short metadata lock protects ownership;
no model, DB or arena is copied per chat. Unavailable acquisition is explicitly
reported and acquired references are released by the existing complete-cut
finalizer. A failed cut is not successful empty semantic search.

Lean checks exact-source acceptance and the existing byte-budget invariant,
with standard axioms, alongside ordinary ContractAudit. Accounting equality is
also checked at native transition boundaries; it is not a proved whole-heap bound.

## Component and actual hook results

Eighty concurrent16-source cuts retain1,280 tokens in90ms, with16 shared
descriptors,16 original-cache borrows and2,668,968 accounted bytes. Foreign
scope/full Head/manifest and foreign release are rejected. Release, expiry and
close during a read keep the charge; the final reader leaves zero token,
descriptor and original-cache borrows. This is not an80-hook test.

The initial runtime is
`16a2bf6303b56746b4d61b8120ecc5c6db1d3bfa54e0f130d3400a58dde6342e`.
On the frozen16-owner/82-observation development fixture, same questions,
MiniLM/settings and sealed native client, actual hook results are:

|Concurrent clients|Required original + ACK|Semantic handoff completed|Median|Maximum|
|---|---:|---:|---:|---:|
|16, first wave|16/16|16/16|8,477ms|8,707ms|
|16, second wave|16/16|16/16|9,306ms|9,664ms|
|80, simultaneous|20/80|16/80|16,852ms|20,878ms|

The [eighty-client diagnostic was fixed before execution](eighty-gate-plan.json).
It fails the98% gate. All80 actors start; maximum admission queue is75ms and
one shared reader build serves49 immutable handles. Sixty-one queries report
unavailable complete source cuts:48 publisher-resolution cancellations,8
startup-lock cancellations and5 task-deadline expirations, each affecting16
sources. The hosted service's query actors still ping that same service during
endpoint resolution and can enter its startup path after a busy ping times out.
This exposes an undesirable control path; cancellation in resolution alone does
not prove it is the dominant cause. No repeated matched80 pair or model
trial follows this failed gate.

Both actual-hook monitors finish without resource/lifecycle triggers or surviving
processes; shutdown commands succeed. Related peak RSS is2,681,376KiB for32
queries and3,376,640KiB for80. The4 GiB ceiling/3.5 GiB stop, disk floor, original
30-second clock, ranking/model/certification and16 append owners are unchanged.

The [observations](evidence.json), [actual bodies](bodies.json),
[body verification](verification.json), [source patch](candidate.patch), and
[identities](identity-before.json) preserve both positive and negative results.
All80 synthetic questions were already observed. These results do not establish
real-world98%, eight-hour use, growing projects, NAS/multi-host operation,
quality or total-token improvement. Not adopted; answering-model calls0, paid
matched comparisons0/18. Build/checker failures remain in the guard evidence.

## Endpoint-only follow-up: rejected regression

The [follow-up patch](hosted-endpoint.patch) reuses the endpoint installed only
by its owning service PID and implementation. A native component performs
80×128 resolutions in3ms with no listener, rejects foreign PID/implementation,
duplicate installation and foreign retirement, and retires its owner. The
[component record](hosted-component.json) does not claim real search performance.
Ordinary ContractAudit and the hosting-owner law pass. External clients retain
the original authenticated path; source authorization is unchanged.

Runtime`f332d24c852a0b52063b07ecb651ff37362ba7c644aa918b09e8e37213feb276`
delivers32/32 originals and semantic handoffs in the16-client waves, maximum
9,814ms. The following fixed80-client burst instead delivers0/80; semantic
completion is0/80. Median17,548ms, maximum17,652ms. All80 actors start, with
maximum operation admission wait22ms. Seventy complete cuts report acquisition
failure:65 owned-task cancellations and5 publisher-resolution cancellations.
The source-palette admission count stays at the three priming queries. At the
post-wave sample1,152 retained tokens still await release/expiry or service close;
the monitor ultimately observes clean shutdown and no surviving process.
Peak related RSS is2,912,640KiB, without a resource trigger.

This candidate is rejected. Removing self-pings alone does not solve80-client
delivery and must not be presented as its root-cause fix. No additional matched
capacity pair or paid model trial is run. The combined overlay is isolated and
product core source remains unchanged. In total236 actual outputs for the two
source-lease variants are retained and independently verified, including all
failures. Source acquisition/transport must be isolated from graph computation
before another implementation or capacity run.

Later [query-stage evidence](../query-stages/README.md) distinguishes phases:
all80 requests in each new diagnostic enter the typed provider, and the final
69/71 source-error files are written after the semantic phase. The earlier
sixty-one/seventy unavailable-cut counts above describe last stored error
records, whose original phase timestamps were not retained by that collector.
They do not establish first-phase acquisition failure. Keep the measured
delivery failures, but do not repeat a source/cancellation fix on that inference.

The [cleanup record](cleanup.json) deletes27,869 generated files/references,
810,872,003 logical bytes, including ended private DBs/caches/raw logs, five
superseded executables and regenerated C/compiler output. No archive is made.
The current source fixture, five protected inputs, positive control, sealed
client, current protocol diagnostic runtime and required native link inputs
remain. The old component helper names an ended pending-file path; after cleanup
its input must be regenerated from the retained source fixture before rerunning.
The retained result is historical evidence, not a claim that deleted run inputs
still exist. All28 captured trial guards and three finalization guards are
terminal with no owned process; the older leftover-process trigger and build/
collector preflight failures remain explicit. The combined overlay reverse-
checks against its candidate and forward-checks against the restored parent.
