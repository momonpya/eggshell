# Select local units without a metadata round trip

Isolated, not adopted. The vector model, ranking, work graph, certification,
synaptic edges and source-owner concurrency are unchanged. Selection remains a
query-dependent calculation. The correction removes a transport round trip for
plans that require no service-owned original rows, rather than caching a private
question or recomputing publication work during retrieval.

A guarded two-request trace on the existing sixteen-owner fixed snapshot found
that a generic-only plan sends about700 KB to `source-plan`. Selection takes
4–7 ms, while request transfer, decoding and the reply take about270 ms. The
service has no original rows to add to this particular plan. The full ordinary
request still takes several seconds; this round trip is not its entire cause.

The candidate constructs the same generic unit order and calls the existing
`selectView` directly. A `LocalChoice` carries proofs that the common finite-domain
check passed, there are no file requirements, and its original-fetch key list is
empty. Original-dependent queries continue through the service. The same domain
predicate replaces the service's previous inline predicate; owner, unit, payload
and scope limits are preserved. There is no tool-name or topic-specific branch.
No lock, worker, resource bound, response budget or deadline is added or raised.

Fifty native cases compare the complete choice against an independent literal
construction of the previous service domain, across five sizes, five budgets and
both diagnostic modes. Four malformed domains are rejected. The two rejection
theorems and two `LocalChoice` invariants compile with the ordinary ContractAudit.
The initial draft is compiled but not exercised; common domain validation is
added before runtime tests. An optional audit switch compares the local choice
with the actual service choice. Both real diagnostic hooks pass that complete
comparison, including receipts. A pure/select test alone does not establish
delivery, token savings or capacity.

Three fixed pairs alternate parent/candidate, candidate/parent, parent/candidate.
They use the same source snapshot, question, MiniLM, settings and controller.
Each starts a fresh service and then queries from a second new chat. Operation
records confirm both calls use lane0; the second uses the existing worker. These
are not OS-cold measurements or the README answering-model/history experiment.

| Pair | First call, parent → candidate | Second call, parent → candidate |
| --- | ---: | ---: |
|0 |5,602 →5,354 ms |3,204 →2,953 ms |
|1 |5,657 →5,369 ms |3,236 →2,964 ms |
|2 |5,687 →5,413 ms |3,293 →2,978 ms |

All twelve actual delivery bodies are byte-identical, also matching the separate
baseline and live-service audit calls. Both frozen original fields are delivered.
Every profile verifies all sixteen original heads before/after. This is a small
transport improvement of248–315 ms, not a token improvement or a proof that the
remaining multi-second work is necessary.

The actual service executable also runs the ordinary mixed workload, retaining
sixteen original owners and the existing three preparation/search workers:

| Mixed-load observation | Result |
| --- | ---: |
| Successful query/Pre/Post/Stop writer lifecycles |80/80 |
| Exact original inputs/outputs after fresh-process reopen |82/82 |
| Posted but unpublished / pending saved sessions |0 /0 |
| Source/owner readiness gate |112,830 ms |
| Pending / active preparation at that gate |0 /1 |
| Fresh readers delivering both original fields within30 seconds |74/80 |
| Semantic / lexical delivery |9 /65 |
| Failure-inclusive hook min / median / max |8,026 /23,343 /29,754 ms |
| Observed queue median / max |19,343 /26,489 ms |
| Observed work median / max |611 /5,446 ms |

There are78 final operation observations, not all-request p99. All sixteen source
heads are compared with the pre-read frozen cut, separately from the fresh-process
payload audit. Readiness is not complete maintenance drainage: one preparation
remains active at the gate. Six readers fail, so the capacity gate still fails.
This independently generated workload is not a causal comparison with58/80 or
126 seconds from the previous fixture. The matched fixed-snapshot profiles above
are the evidence for the small transport improvement.

All guards finish without owned survivors or resource stops. Maximum related
RSS is3,402,752 KiB, below the unchanged3,670,016 KiB stop/4 GiB ceiling. The initial
summary includes writer phases in the reader counters; the repaired summary uses
the exact eighty reader receipt IDs. The prior summary/digest and the bounded
recorder correction are retained. Native experiments are not rerun to repair an
aggregate. Ended DBs, private caches and raw logs are deleted after sealing;
active originals, candidate sources and compilation inputs remain, without an
archive. `candidate.patch` is relative to the captured parent source tree.
Fixture/cache/log cleanup releases442,198,471 apparent bytes. Two ended component
executables release another265,576,784 bytes after their hashes and live-process
absence are checked. The parent and candidate service executables, source trees,
object files and link inputs remain; component checks require rebuilding their
entry points. Active original heads and protected control hashes remain equal.

Remaining work is substantial: roughly113-second background preparation, the
request's other public restoration/hydration/focus work, six deadline failures,
growing projects and multi-host/NAS/sustained eighty-person use. Next, profile
the remaining work and make project preparation shared across source owners;
do not repeat this burst or tune retrieval weights without a concrete correction.
Real98% necessary evidence, total-token improvement and quality are unverified.
Answering calls0; paid matched comparisons0/18. Product source and release/README
performance claims are unchanged; the full goal remains active.
