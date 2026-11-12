# Concurrent writers to the same project owner, then fresh readers

The isolated product remains `5d37ec1454fe36e1247e0488646d70886312c5a701638c102fe691fdc83a352d`.
No product, embedding model, selector, prompt, or deadline change is made here.
The new Lean fixture extends the previous mixed-lifecycle workload to cover a
missing condition: multiple writer sessions routed to the **same physical owner**.
Each logical project still has four owners; both ALPHA writers use slot zero,
and both BETA writers also use slot zero. All other owners stay unpopulated.

The real registered hooks execute actual source commands. The test retains the
earlier interruption/restart, late and duplicate Post/Stop, project switch,
resume, clear, and compaction checks. Four additional rounds then each overlap
four writers with ten continuing readers: fourteen simultaneous clients. The
final source inventory is 25 turns, 75 complete native observations, 25 final
answers, and 50 independently fingerprinted source fields. Every original is
checked against its immutable tool receipt and original project destination.
The base result fields still describe its initial nine turns; the growing
inventory and `finalOriginalObservations` explicitly describe all 25 turns.

## Gates and independently checked delivery

| Gated workload | Entire gate |
| --- | ---: |
| Initial four fresh readers | 1.281 s |
| Four writers + eight fresh/existing readers | 2.475 s |
| Ten readers after restart/reset/resume | 2.027 s |
| Growth round 1: four writers + ten readers | 2.723 s |
| Growth round 2 | 2.933 s |
| Growth round 3 | 3.153 s |
| Growth round 4 | 3.436 s |
| Final ten continuing readers | 2.623 s |
| Ten new readers from a different empty client data root | 3.439 s |

Gates include reader Stop and exclude preceding SessionStart. Publication and
preparation are automatic; separate bounded waits verify that the new original
inventory and prepared roots catch up after every round. The complete growth
process takes 123.424 seconds, including writers, setup, lifecycle events, and
those waits. This is not the latency of one hook.

The fresh-reader follow-up starts both services again using a different,
initially empty private data root and the same completed project DBs. It copies
no chat state, receipt, query cache, or delivery ledger. Original requirements
are independently frozen from the current DB before querying. ALPHA-only
readers receive all 24 fields, BETA-only readers all 26, and combined readers all
50, in each new body. Their semantic searches complete with zero warm requests.
No manual warm or repair command is issued. Original publication heads and
bytes remain unchanged. This follow-up takes 20.746 seconds including source
verification, service startup, hooks, and shutdown; the ten-client gate itself
is 3.439 seconds. It is an empty *client data root*, not an assertion that the
operating-system disk cache was cold.

Independent reconstruction from actual returned bodies verifies **1,800/1,800**
required row appearances over 82 queries. Of these, 324 are in the ten entirely
new replies after growth. Continuing contexts may also count previously
returned text. Clear and compact discard the test's visible context and require
new delivery. Each row must occur inside its own SOURCE path/fingerprint's CODE
block. Requirements in an overlapping write/read gate concern the previously
committed cut; the final stable gates check the complete grown cut.

The pre-existing fixture budget is 500,000 characters, not the public default.
The largest actual query body here is 71,150 characters. Neither quantity is
reported as token savings or proof that another configured budget is equivalent.

All 469 actual callbacks have exit zero, empty stderr, and no incomplete notice.
No failure receipt is present. UserPromptSubmit maximum is 3.715 seconds; Pre
p95/max are 1.719/1.848 seconds and Post p95/max are 0.846/0.883 seconds. These are
small-fixture measurements, not production p99. The service log retains one
unfinished-publication warning, one private state.guard wait warning, and two
cancellation warnings; the durable original census subsequently passes. The
new service's existing MiniLM pooling warning is also retained. No model or
encoder implementation was changed.

Both populated owners retain all three advisory edge types. ALPHA has 11
consumption, 48 support, and 48 coquotation facts; BETA has 12/52/52. Sampled
related RSS peaks at 3,737,968 KiB during growth and 2,712,112 KiB in the fresh
follow-up. Guards do not trigger. Every frontend/publisher instance shuts down normally;
all native jobs are terminal with no owned process remaining.

The first fresh-observer build had a Lean try/catch layout error before any
follow-up hook. Its failed guard/output are retained; the syntax repair has a
separate successful build tag. Exact executed fixture sources are retained for
both stages, and both 315-object native controllers have all product core and
313 byte-identical common imported sources.

## Unknown clocks and remaining scope

There are 71 verified intervals and four unknown late intervals. Inspection of
the actual product shows why: `Daemon.chatClock` includes the endpoint secret,
`Synapses.Live.contextClock` includes the context epoch, and `Live.finish` uses
the currently loaded state. Restart and interruption can change those domains.
`NativePublication.agrees` correctly requires equal clock domains and increasing
observed time. The retained events have no verified bridge between domains;
their wall-clock receipt times do not supply that proof. We do not weaken that
predicate or backfill old observations using a newer context. All 75 raw native
observations remain available independently of this interval classification.

This is one Mac/Unix user and one project-publishing service at a time. It does
not exercise remote users, competing project publishers on different machines,
NAS filesystem semantics, real dumps/MCP/email workloads, or sustained 80-user
operation. Current transport is loopback; the remote shared-service entry is a
remaining implementation requirement. The earlier LLVM benchmark, answering
model, token savings, and adoption gates are not replaced by this fixture.

No paid answering-model call runs. Adoption remains zero. Ended experimental
DBs, caches, sources, and native-controller copies are deleted without archive:
19,251 entries and 1,413,326,377 logical bytes. Protected originals and current
runtime/model/input hashes remain unchanged, and the current product's
336-object native closure passes again after deletion.
