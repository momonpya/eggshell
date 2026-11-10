# Measure a typed routing leaf before adding another cache

This is an isolated Lean component experiment, not an adopted product change.
The selected product remains `dd53c89b…`. No answering model was called.
The preceding immutable-page experiment reduced misses substantially but reduced
sixteen-client completion time by only 7.795%. Repeating that cache policy was
not a sufficient path to the few-second target.

[PreparedRoutingLeaf](../../../tools/research/PreparedRoutingLeaf.lean) binds a
decoded advisory arc to its canonical original bytes and a leaf to the complete
verified PageMap reference. Range reads preserve original order and payloads;
tombstones remain present, and malformed unselected rows remain cold. Namespaces
include directory, file identity, authority and authorization scope. Five generic
laws were checked using standard Lean axioms, without new axioms, `sorry`,
`native_decide`, or a solver. The 8 MiB cache allowance measures encoded charge,
not total heap, and does not establish publication/concurrent lifetime safety.

The native [controls and uniform probe](result.json) cover 28 valid/malformed arc
cases, tombstones, unselected errors, foreign scope and complete reference/file
identity mismatches. A uniform sample of 1,024 nodes reached only 916 arcs, so it
was insufficient for this skewed graph. Before the second measurement, the
[full-population plan](full-population-plan.json) expanded the probe to every
published node and retained the original measurement.

[Full-population results](full-result.json), three AB/BA/AB pairs:

| Work | Original | Typed leaf |
| --- | ---: | ---: |
| 5,237 nodes / 20,796 arcs | 75.24–77.53 ms | 11.92–12.51 ms |

Preparation took 353.21 ms, reading 731 pages and constructing 705 leaves with
5,040,685 charged bytes. Both paths returned the same arc values, order,
1,611,273 payload bytes, page dependencies and completion state. This probe uses
the default warm 4,096-page snapshot cache; it is not a whole-hook timing bound
for the product's private byte-bounded fronts. Its small absolute stage time
does not justify integrating another cache solely from the component speedup.

The first full-product source auditor correctly rejected this standalone helper
because it did not link the whole product. That rejection is preserved in
`sources.json`. The existing component auditor subsequently verified the actual
63/64 linked objects, 61 unchanged common product modules and the declared new
helpers. Entry/helper source witnesses, embedded literals and runtime hashes are
sealed separately. The full-product auditor was not weakened.

## Late observation of the actual product

[The late CPU observation](late-result.json) sampled the directly owned product
publisher during a four-client wave. The three primes and four actual hook bodies
passed canonical-byte, semantic, synaptic and ACK checks; sources stayed
unchanged. The workload wave was 6.543 seconds, with diagnostic interference
possible. This is **not a normal latency comparison**: after the workload exited,
the observer attempted to reap an already reaped child, so the guard exited 1.
Both publisher/frontend shutdown records are successful, and no owned processes
remained. The failure is retained rather than relabelled as a clean run.

The CPU sample contains `Tree.updated` and repeated `lean_nat_pow` under the
existing sparse winner index. It also contains big-natural comparisons. The
sample includes idle threads and supplies no whole-hook CPU percentages or
per-request attribution. Four actual selection plans had 46 families, 10,637
units and a 396-bit scalar scale; their scalar context was copied with receipt
hashes before retiring session state. The old batch-winner experiment was checked
before proposing a different point-update optimization; its roughly 50 ms replay
improvement is not being retried as a new idea.

[PreparedRoutingObserver](../../../tools/research/PreparedRoutingObserver.lean)
now keeps the reaped status in one owned reference across `try/finally`.
[Native lifecycle controls](observer-controls.json) check success, failure,
cancellation and repeated wait/close, under a clean guard. The unchanged actual
four-hook diagnostic was not repeated after that repair, so the repaired wrapper
is not claimed to have passed that full workload.

The component build/source and all seven ended diagnostic clients' session,
ledger and receipt trees were [deleted](retired-runtime-state.json), without an
archive. Actual stdout, the raw CPU sample, source witnesses in the audit records,
canonical bodies and current product/guard/model assets remain. The retired
native paths are not runnable inputs. No product adoption, token/quality benefit,
general 98% claim, p99, few-second sixteen-client or eighty-person result follows
from this study.
