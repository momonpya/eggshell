# Typed builtin search dispatch

Isolated candidate after `f1cedf94`, **not adopted**. Candidate runtime
`da95d6b6…`, parent `b996ee9d…`, transport probe `9060163c…`.

The builtin keyed/focus handlers now run in the query worker. Only the exact
current executable is recognized; a separately configured executable keeps its
process transport. Both use one indexed repair/full-order/evidence checker.
Each typed invocation owns fresh temporary private query storage and a numerical
client. Cancellation joins the actual task; numerical startup/claim loops now
observe cancellation. Default response budget15 seconds, repair allowance32,
source-owner/search/save/preparation counts, ranking, model and authority remain
unchanged. No shared lock/CAS, metadata format or new Python/Ruby is introduced.

This removes the fresh search-provider process, not the separate numerical
service. Provider-specific source/window/lexical/matrix/owner views still restore
per call. It is not the completed shared-preparation design.

## Native evidence

The[probe](../../../tools/research/ProviderLifetimeChecks.lean) uses one frozen
request over sixteen original sources. The complete163-owner response, evidence
and coverage is identical in all seven calls, including the recorded cold prime.
The cold process call takes2396 ms; three alternating warm process/direct pairs
take627/348,621/354 and622/348 ms. Both arms retain complete per-call restoration.
This isolates whole-call transport/lifetime cost, not all remaining Handoff cost.

[Builtin checks](../../../tools/research/BuiltinSearchChecks.lean) compare actual
transient focus results and the same four original reads. They reject incomplete
ranks, foreign windows, repeated repair and a33rd cross-document repair. Deadline
and blocked numerical-claim tests return only after their actual cancelled tasks
finish. Current/wrong/relative/different executable cases pass. Standard
ContractAudit passes, including transitive preflight through the newly reachable
typed handler and the shared checker. These are not full IO or cancellation proofs.

All sixteen paired actual hook bodies are byte-identical by route:88,578 meaning
bytes (`fc2dca71…`) and13,566 lexical bytes (`df1090e2…`), with both frozen fields.
Actual receipts confirm both keyed and indexed transports are typed.

| Meaning pair | Cold parent / candidate | Running parent / candidate |
| --- | ---: | ---: |
| 1 | 6,635 / 6,021 ms | 3,874 / 3,374 ms |
| 2 | 6,352 / 5,906 ms | 3,871 / 3,423 ms |
| 3 | 6,445 / 5,885 ms | 3,869 / 3,369 ms |

Lexical control is2,312/2,363 ms cold and1,391/1,393 ms running. Do not claim
lexical acceleration. No worker, owner, queue or deadline bound is raised.

| Same-period eighty-reader burst | Parent | Candidate |
| --- | ---: | ---: |
| Both original fields / whole-client success | 73/80 | 80/80 |
| Admitted / complete captured inputs | 80/80 | 80/80 |
| Failure-inclusive latency | 10,946–29,759 ms | 9,694–29,378 ms |
| Semantic completion | 6 | 9 |
| Lexical after semantic timeout | 67 | 71 |

The candidate's80-request median is22,895 ms. Most requests still use lexical
fallback. This is a small two-field fixture and one burst, not practical98%,
semantic throughput, p99, sustained operation or an80-person deployment result.
Parent final-operation observations cover77 requests; do not compare them as
all-request latency quantiles.

## Mixed ordinary operation remains incomplete

An additional fresh synthetic fixture runs80 ordinary query/Pre/Post/Stop writer
loops with5,000-byte outputs, normal background preparation, and80 new-reader
chats. All80 writer loops succeed, and all82 saved original inputs/outputs are
exact. The source/prepared/owner gate is reached after145,514 ms. At that point
three preparation jobs remain pending and one active, with270 retries and23,041
coalesced requests; last retry says journal required, warm/synapse not required.
Three index workers were observed live and busy during this preparation interval.

New-reader success is only67/80; thirteen deadlines fail. The complete captures
still number80. Semantic completes9;58 delivered clients use lexical fallback.
This defeats any claim of mixed daily-use readiness. The synthetic fixture is
independently created, so its timing is not a causal comparison with the frozen
read-only pair. The readiness gate is not a proof that background work has drained.
Do not increase its180-second wait or stop useful prefix work on every new event.

All original retained heads and protected originals remain unchanged. All guards
end without owned survivors or an aggregate stop. Peak related RSS3,091,424 KiB,
below the unchanged3.5 GiB stop and4 GiB ceiling. Failed attempts are retained in
[evidence](evidence.json): initial probe directory initialization order, one test
JSON encoder mistake and one recording-script syntax error. Source/model calls
are numerical MiniLM only; answering calls zero and paid matched comparisons
**0/18**. Keep this patch isolated from product/README benchmark/release adoption.

Ended fixture DBs, private caches and raw logs are removed without archives.
The candidate, probe build dependency, control, active source and captured parent
are retained for the[next step](next-mixed-preparation.md).
