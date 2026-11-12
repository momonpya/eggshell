# A small Lean hook supervisor

This is an isolated, unadopted candidate. It preserves vector search, work
graphs, e-classes, synaptic recommendation, ranking and delivery policy. No
answering model, LLVM seed, token comparison or global installation ran.

The previous shared-service growth workload stopped at its first additional
four-writer/ten-reader wave. Its peak included fourteen complete runtime
supervisors, fourteen backend children and independent gateway processes.
Changing only the product entry had already failed to demonstrate a benefit
in [an earlier experiment](../product-entry/README.md); that experiment was
not repeated.

## Implementation

The supervisor and its JSON envelope move into `HookCommand` and `HookWire`.
The full entry delegates to the same supervisor function as the small native
client. The client selects its deadline before stdin can block, owns/kills/
joins each child, flushes the actual output, then sends its exact bytes,
SHA-256 and eligible ACK through the existing backend receipt operation.
No second implementation of the supervisor, search queue or shared mutex is
introduced. Valid empty JSON remains a valid response; absent or invalid
responses cannot create an ACK. Envelope completion is not memory certification.

Registered hook scripts now require the small companion and pass an explicit
absolute backend executable. Runtime installation requires the companion before
stopping the running service or copying payloads, checks ownership and removes
it on uninstall. The isolated prefix is bound by the actual product generator.
Release packaging/Setup distribution and real deployment are still unverified.

The final backend is `ea5b3861dfba62fe0e600552a13facb59595304c67b28fa9f2d3f395d66e0e35`.
The small client is `259d63ec1ca2c3b8f4dd8eb6c32a867b53055de3e1a2d20a2481cbc21a8cbe72`.
The [source patch](candidate.patch), [exact source comparison](connected-sources.json),
[346-object backend closure](connected-native.json) and
[11-object client closure](command-native.json) bind the implementation.
All eight Eggshell modules in the small client match their backend counterparts.
Its transitive 815-declaration action reaches no DB, graph, model, publication
service or shared mutex. Six [kernel laws](proofs.json) use standard axioms only.
ContractAudit checks both supervisor entries against the moved deadline and
child-retirement primitives; the initial stale-name rejection is retained.

## Protocol and controlled footprint

All eight native protocol cases pass: valid, valid-empty, invalid object,
missing field, malformed JSON, silent child, hung child and blocked stdin.
Actual output bytes, digest, ACK eligibility and observed child retirement
are checked. The first valid case took 445 ms; hung/blocked cases took
1,932 / 1,915 ms against the three-second external gate.
See [protocol checks](protocol-checks.json).

The footprint comparison uses the same backend and supervisor implementation,
with ABBA order, measuring owned processes from 400–1,200 ms while stdin is held.
Full pairs peak at 112,720 / 112,848 KiB; small pairs at 92,896 / 93,024 KiB.
The paired reduction is 19,824 KiB, about 19.4 MiB. All four stop in
2.018–2.206 seconds with empty stderr. This is a component measurement, not a
query, throughput or token benchmark. See [raw samples](footprint.json) and
[predeclared configuration](production-environment-plan.json).

This older observation window was not bound to the backend's ingress phase.
The later [runtime-stamp study](../runtime-stamp/README.md) identifies a
cold-start phase error in its own first run and adds PID-bound ingress
sampling. These older RSS observations remain raw component measurements,
not a separately verified comparison of fully initialized processes. The
whole mixed-workload failure below is unchanged.

Initial observer attempts are not counted as successful comparisons. One lacked
the metadata import path; another used the interpreter; the first native
observer called `wait` after `tryWait` had already reaped the child. The first
full-backend footprint attempt then exceeded its observation gate. The guard
sets `LEAN_NUM_THREADS=1`, whereas the ordinary installation unsets it; matching
that production environment allowed the four observations to finish. The
terminal diagnostic and failures remain in [guard records](guard-records.json).
These observations do not by themselves establish a general scheduling cause.

## Shared-service workload: more progress, still rejected

The ordinary registered scripts use the small client. The same two DBs,
four owners per DB, four writer sessions, same-owner placement, interrupted
turns, actual three-service restart, delayed/duplicate events, project switch,
new/resumed/cleared/compacted contexts and four planned growth waves are tested.
The [observer audit](mixed-sources.json) covers all product core and unchanged
common sources. No manual keep/warm is called.

| Completed stage | Clients | Gate |
| --- | --- | --- |
| Initial readers | 4 | 1.234 s |
| Concurrent writers/readers | 4 + 8 | 2.096 s |
| Restarted lifecycle mixture | 10 | 1.892 s |
| Additional wave 1 | 4 + 10 | 2.575 s |
| Additional wave 2 | 4 + 10 | 2.880 s |
| Additional wave 3 | 4 + 10 | 2.904 s |

The fourth additional wave triggers aggregate-RSS protection at **4,394,912 KiB**
against the unchanged **4,358,524 KiB** threshold. The whole run fails, and no
unchanged retry or 80-client test follows. Forced draining is not normal shutdown.

Only the completed 52 reader queries are independently reconstructed from the
actual callback bodies and lifecycle events. All complete semantic retrieval.
Their 34 distinct frozen source/fingerprint/text requirements appear 788/788
times: 270 in new bodies and 518 in retained visible context, including 110
fresh-context appearances. Maximum actual body is 26,325 UTF-8 bytes under the
unchanged 500,000-character fixture allowance. All 410 completed commands
(347 hooks) return zero with empty stderr; maximum hook is 3.042 seconds.
This does not count unfinished fourth-wave queries as successes.
See [independent completed-stage audit](completed-stages.json) and
[actual callbacks and stage records](growth-records.json).

A read-only native postmortem finds 63 original observations, 21 answers and
42 stored fields, corresponding to the completed writer turns. Four late
observations retain unknown timing rather than gaining completion authority.
The eight planned fields for the unfinished turns are absent. The 42 stored
fields are not claimed as all delivered: the completed queries froze only 34
distinct required fields. Original files remain unchanged during inspection.
See [storage audit](growth-storage-inspect.json).

At the failed peak there are still 33 other full-runtime processes (~2.02 GiB),
14 small supervisors (~501 MiB), a model pair (~1.08 GiB) and the services.
The publisher is ~244 MiB and frontend ~178 MiB. Their different-state RSS
values are not a matched leak measurement. The remaining process/import
overhead and service retention need investigation; another weight adjustment,
new cache or unchanged capacity retry is not justified by this result.

Ended fixture DBs, caches and diagnostic builds were removed: 12,804 entries /
1,349,991,462 logical bytes, without an archive. The fixed parent, current
backend/client, model and protected LLVM original remain. See [cleanup](retired.json),
[backend after cleanup](product-after-cleanup.json) and
[client after cleanup](command-after-cleanup.json).

The candidate remains unadopted. General 98% delivery, production p99, sustained
80-user operation, large growing DBs, cross-host/NAS/MCP policy, accepted LLVM
seed and both topic passes, inclusive-token improvement and quality remain
outstanding. The completed subset is evidence of progress, not completion.
