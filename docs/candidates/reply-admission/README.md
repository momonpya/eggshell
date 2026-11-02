# Reserve selection output after computation

Isolated candidate, **not adopted and not an eighty-client pass**. Runtime
`bd609e528a62a07dc45e745054cdc83ea061f72f820d86b88029af980965a4c0`.
[Plan](plan.json), [product patch](candidate.patch),
[matched comparison](comparison.json), [resource receipts](resources.json).
Apply the patch to `session-ack-candidate-core`. WorkGraph, vector, synapses,
e-class/Union/Exact, ranking and all byte/deadline limits remain unchanged.

Previously, `source-plan` reserved its maximum wire output before computing a
selection. This coupled the limited output slots to computation that already
held a charged read-view borrower. The candidate computes under that existing
view reservation, acquires the unchanged output reservation while still inside
the borrower, and only then returns for encoding and sending. There is no
increase of output capacity, view capacity, active-view count or deadlines.
An expired output waiter retains its read-view charge until the finalizer.

## Matched native results

Both arms use the same original source files and frozen denominators. All six
native [hook bodies](hooks.json), all three captured query hashes and all exact
choice hashes match the parent. Both initial chats delivered 4/4, 7/7 and 5/5
known requirements, 32/32 occurrences, with candidate hook times
14,792–16,547 ms. The original DB files were independently
[rechecked after the complete load](source-verification.json) and remain
unchanged. No answering-model or token comparison was run.

| Simultaneous selector clients | Parent complete/exact | Candidate complete/exact | Parent / candidate sample maximum |
| --- | --- | --- | --- |
| 1 | 1/1 | 1/1 | 1,381 / 1,369 ms |
| 4 | 4/4 | 4/4 | 2,560 / 2,027 ms |
| 16 | 16/16 | 16/16 | 7,809 / 6,304 ms |
| 40 | 40/40 | 40/40 | 18,693 / 15,046 ms |
| 80 | 61/80 | 73/80 | 28,611 / 28,536 ms |

The [complete results](result.json) retain every latency and error. The seven
remaining failures are in palette admission/receipt, before selection. One
burst at each level is diagnostic evidence, not a population p99 or statistical
throughput claim. Eighty clients were explicitly required to complete, so this
candidate has not passed that gate. It must not be described as eighty-person
operation or a 98% delivery result under eighty concurrent full hooks.

Source preparation remains one load and thirty owners; page misses stay at
888. No incomplete request is classified as a successful empty memory. All
ordinary session and publisher services exited normally; the guards reported
no trigger or surviving owned process. Candidate sampled aggregate peak was
3,067,488 KiB, within the unchanged 3.5 GiB stop and 4 GiB absolute ceiling.
The standard ContractAudit also compiles against the candidate dependency
closure. This does not prove latency or heap bounds for arbitrary workloads.

Thirteen background `state.guard` warnings were observed during the full
candidate hook run. The scheduling change does not address those waits. The
ACK-only microbenchmark remains narrower evidence; full-path state handling
still needs measurement and correction.

The next investigation is per-stage computation/serialization and the lifetime
and charging of shared immutable metadata. Queries carry 1–2 MB, choices about
1 MB, and each palette repeats about 607 KB of metadata. Reducing them to
references into a properly retained, scoped prepared view must preserve exact
selection and source/authority checks. Increasing timeouts or capacities is not
a substitute. Sustained publication, multiple projects/hosts, MCP policy,
eight-hour use, held-out evidence coverage, and matched total-token/quality
comparisons remain unfinished.

Ended fixture DBs, caches, raw receipts and helper executables are
[deleted](cleanup.json), without archives. Compact evidence and current
candidate/parent runtime and build inputs remain for continuing development.
