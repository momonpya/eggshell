# Project publication through the real service transport

Isolated, unadopted continuation of [owned-project-streams](../owned-project-streams/README.md).
The [plan](plan.json) keeps the 80-user, 30-second, 98% actual-delivery objective
and the matched total-token/quality/deadline adoption gate. This connects the
original-store prototype to the existing loopback publication service and Capsule
compiler; ordinary Pre/Post/Stop project selection is not connected yet.

A local administrator registers the complete immutable project inventory once.
The service retains one original-owner lease per physical region. A project grant
cannot register paths or select another project's originals. The service derives
a session's owner slot; rotating the scheduling queues does not change that slot.
The same project has several independently active publication lanes, with a bounded
shared queue and byte admission. Source IO runs outside the queue-metadata gate.
The existing control/single-source operations remain as the isolated control path,
not as a promised compatibility or migration design.

A publish request includes its original Capsule and complete caller-pinned source
cut. The service checks the cut against canonical history and all cross-owner
dependencies before queue admission. It joins the admitted cuts for a group,
publishes the native originals and logical project provenance, and returns the
existing exact source-coverage ACK. Clients check the physical route, authority
and every observation's receipt coverage. No ready index, top-K recommendation,
private Journal.Entry or delivery knowledge replaces the original cut.

Two defects were found while making that connection:

* An identical retry reached `authoritative writes cannot publish an empty graph
  delta`. The final path stores the digest of the original Capsule plus its exact
  cut atomically with original publication. The same request returns an ACK from
  its already committed source without appending another original or advancing
  the cut. Different content still reaches immutable-provenance checks and is
  rejected. This is source-publication idempotence, not a delivery ACK or a proof
  of remote failover/compaction.
* The service used the already expired payload deadline to send its refusal,
  producing an unaccounted diagnostic in the next trial. A small error response
  now has at most 100 ms within the connection's outer deadline. Successful source
  responses and ACKs retain the caller's original absolute deadline. The old raw
  warning was not retained by that driver, so the precise warning text is not
  available; the failed guard and all completed-round samples remain. The final
  identical rejection checks produced no service diagnostics.

The first failed retry trial's DB was independently reopened: all 320 original
observations and 1,280 unique graph roots were present with exact bytes and logical
provenance. Failure records are not reclassified as successful trials.

## Final native transport checks

[Runtime](runtime.sha256): `f0e291701838eb8ad1824d70f06e924088668a26fd3a80994e84afa73b7b1728`.
The [build](build.json) includes ordinary `ContractAudit` and the new owner-route
bound proof. The patch retains local mutexes and OS leases; it makes no lock-free,
linear-IO or global certification-refinement claim.

Each profile used four waves of 80 actual loopback TCP publication requests,
16 source owners, one concurrent complete-cut reader and one additional empty
project to test scope isolation. Outputs and intervals were controlled native
fixtures, not real MCP responses or answering-model turns. Generation was forced
before each publication wave. These are one functional trial per size, not a
matched performance comparison, p99 gate or eight-hour workload.

| Output per observation | Wave completion times (ms) | Largest individual submit (ms) | Complete concurrent pins |
| --- | --- | --- | --- |
| 5,000 bytes | 1,064 / 1,811 / 2,180 / 2,477 | 2,476 | 23 |
| 50,000 bytes | 4,281 / 6,489 / 9,125 / 10,803 | 10,802 | 118 |

Both [5 KB](5000.json) and [50 KB](50000.json) profiles:

* completed all 320 original publications, plus one idempotent retry;
* reached 16 concurrently active original-owner regions;
* reconstructed all input/output bytes, occurrence identities and logical project
  receipt destinations, with no duplicate or foreign observation;
* matched the complete federated graph to an independently materialized
  1,280-root union, and checked canonical indexed history against the source feed;
* rejected missing/foreign/dependency-omitting cuts, expired requests, another
  project's capability, path-registration escalation and immutable-content mutation;
* left the source cut unchanged after the duplicate and conflicting requests;
* shut down normally, removed the endpoint and released every owner lease;
* repeated the full original census in a separate process with a fresh private root.

Final source queues, active groups and admitted bytes were zero. Sampled aggregate
RSS was 670,592 KiB / 1,387,520 KiB; neither resource guard fired and no owned process
survived. The [summary](summary.json) distinguishes submission latency from the
full 17,717 / 49,662 ms audit process, which also includes verification and reopen.

Wave latency grows as originals accumulate. At 50 KB, 320 divided by the four wave
times is only about 10.4 observations/s, excluding output generation, pins between
waves and index preparation. It is below the user's maximum assumption of about
22.2 observations/s. Therefore sufficient sustained ingestion capacity is **not**
established. The service still repeatedly opens/checks identical complete cuts
per submit and per group; the next implementation must measure that work and
share exact immutable views and page budgets, rather than tune recommendation
weights or infer that parallel ownership alone solves throughput.

Remaining integration includes configured project writes versus authorized other
project reads, policy-approved private ingress, one canonical vector/content
store per project/permission scope, delta preparation, complete cross-owner
certification and ordinary hooks. Real MCP/NAS/remote authentication, crash/retry
under load, copy/failover/compaction, long-term growth, actual LLVM six-stage
98% delivery and the 80-user sustained gate remain. Answering-model calls and
matched token comparisons remain 0 and 0/18. Product and README results are unchanged.

Ended test DBs, private caches and raw compiler/service logs are deleted without
archives after sealing the compact reports. Current source, required objects and
interfaces, link responses and the current helper remain. Protected original,
selector and control-runtime digests are checked before and after cleanup.
Apply [candidate.patch](candidate.patch) on `owned-project-routed-core` after the
previous original-store and stable-routing patches; its source and native input
seals are recorded alongside this document.
