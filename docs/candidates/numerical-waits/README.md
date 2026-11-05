# Own numerical waits once; thirty-two improves, eighty still fails

This is an isolated candidate after numerical-stages, not an adopted product
change. Logical chat actors remain independent and share heavy immutable/model
state. No worker count, model, full source domain, numerical score, ranking,
selection, deadline or resource budget is changed. Answering-model calls are0;
paid matched token/quality comparisons remain0/18.

The [patch](candidate.patch) registers one native disconnect read per numerical
request instead of repeatedly registering socket/timer selectors while waiting
for an encoder or scorer gate. Admission checks stopping, peer and the same
absolute deadline before and inside the gate. Raw-pipe completion has one owned
observer; failure retires the child once and joins its IO. Lean admission laws
and ordinary ContractAudit pass. The source remains a reversible overlay.

The first raw cancellation test exposed a real ownership error in this candidate:
the raw wait reaped a child and the checker/backend could attempt to reap it
again, producing ECHILD. The corrected API requires an explicit retirement
owner, clears the backend reference and joins even on retirement error.
[Initial patch](initial-waits.patch) and [failed preflights](preflights.json) are
retained. Controlled native checks use Lean fixture children for live peer,
callback cleanup, EOF, exact raw reply, cancellation, deadline and backend
error preservation. All pass, with no surviving processes; no model is used by
these checks. This is not a proof of arbitrary scheduler or filesystem IO.

The fixed [plan](plan.json), runtime/controller [SHA values](seal.json),
[actual outputs](bodies.json) and [independent verification](verification.json)
preserve every case, including failures:

| Same-controller arm | Original + ACK | Semantic handoff | Maximum client time |
| --- | ---: | ---: | ---: |
| Parent observer trace ON,16 clients ×2 waves |32/32|32/32|8,964ms|
| Candidate trace OFF,16 ×2 |32/32|32/32|9,238ms|
| Candidate trace ON,16 ×2 |32/32|32/32|8,854ms|
| Parent observer,32 simultaneous |21/32|21/32|22,568ms|
| Candidate,32 simultaneous |32/32|32/32|20,688ms|
| Candidate,80 simultaneous |2/80|2/80|19,431ms|

A single sequential experiment is not a repeated performance estimate. All32 candidate
OFF and ON bodies equal the retained parent byte for byte. At32, all21 successful
parent bodies remain identical; the other11 cases now deliver their originals.
The32-client guard peaks at3,086,432KiB and passes the preregistered80-entry gate.
The one80 trial ends normally at2,715,760KiB, unlike the preceding resource-stop
trial. All80 latencies and receipts are recovered;78 are incomplete notices.
It is a capacity failure, not a successful80-person configuration.

Returned RPC medians at32 improve to289ms roundtrip,108ms scorer admission,
51ms output-ready to client and0ms after raw-read completion. At80, roundtrip
is2,101ms and output-ready to client1,105ms, while scorer kernel median is5ms.
The65 completed query encodings and106 returned score calls do not establish
completion of unfinished requests. Those failed current RPCs remain unobserved.

[Accounting](accounting.json) checks non-overlapping returned scoring calls
against their own completed scoring intervals. At80 they account for204,449ms
of205,278ms accumulated across67 profiles; these overlapping queries are not
205 seconds of wall time or CPU. Trace-off spans are explicitly unobserved.
This evidence does not support another per-document cache-option optimization
as the main scoring fix: the resolver already memoizes each exact source within
the call. It points to the numerical RPC/wakeup path under whole-host load.
The publication host uses94.06 CPU seconds, including60.61 system seconds,
against5.43 CPU seconds in the numerical daemon. Process totals do not isolate
a specific mutex, timer, syscall or allocation site.

Next isolate the exact numerical protocol, preserving80 distinct queries, in a
native client without WorkGraph work. Compare it with the retained loaded trace
to distinguish numerical service capacity from shared-host scheduling pressure.
Use events that expose send completion/receive wakeup; output-ready alone cannot
separate those. Do not repeat this unchanged80 hook burst or widen budgets.
Keep independently owned actors, but do not turn every suspended phase into
another dedicated supervisor. Changes to shared preparation need evidence;
the earlier search-inputs and task-observer failures remain rejected controls.

Finished DBs/caches/raw logs and obsolete standalone binaries are deleted after
capture, without archives. Current originals, compact actual-body evidence and
needed native link inputs remain. The product source is restored. The80-person,
eight-hour, growing-project/NAS, real98%, quality and inclusive-token goals are
still unproven; the goal remains active.

Cleanup's first interpreter attempt expanded multi-MB stack samples into several
full lists and exceeded its512MiB limit. Streaming bounded sample summaries fixed
it. The first final-verification wrapper also passed512MiB instead of the existing
1,536MiB compiler allowance to the shared record checker; this preflight failed
before verification. The corrected wrapper retains the original aggregate stop.
These helper failures remain in [cleanup](compiled-cleanup.json) and
[completion](completion.json), separately from actual hook failures. Retired
control executables must be rebuilt before their historical setup can run again.
