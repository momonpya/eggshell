# Reader pages without shared-cache locks

Status: isolated and unadopted. The product core and README performance claims
remain unchanged. Answering-model calls: 0; paid matched comparisons: 0/18.

The old request-local front fell back to a shared page cache on a miss. Even a
shared cache hit took its mutex to mutate LRU state and counters. Immutable
page lookup does not require those writes.

The candidate separates the page-cache owner from a reader in the datatype.
A reader contains only a private front over immutable verified pages: no shared
owner, mutex, CAS or shared-LRU capability. A checked public image captures a
bounded immutable seed once. Each actor receives a fresh private front; misses
use the original verified backing reader and insert only locally. The complete
scope and page reference still decide cache validity.

Lean checks the pure lookup and page-validity laws, the definitional equality
of reader operations to their owner-free implementations, the reader-mode
invariant carried by every prepared Session, and the encoded-page budget.
The existing 2 MiB/512-entry private-front bound remains. Space for 32 image
seeds and one builder is reserved inside the existing 128 MiB shared
encoded-page allowance, rather than added to it. This is not a whole-heap RSS,
IO-runtime, ownership-linearity or distributed-lock-freedom proof.

The native check holds the shared owner mutex continuously while a separate
reader performs hits, misses, private insertion and statistics within one
second. Exact page bytes, foreign-scope/ref rejection, independent fronts and
unchanged owner state all pass. The candidate and ContractAudit build; the six
printed proof dependencies contain only Lean's standard propext,
Classical.choice and Quot.sound axioms.

The same native hook client then completes two 16-client waves: 32/32 required
originals plus ACKs and 32/32 semantic handoffs, with all parent output bytes
unchanged. Wave maxima are 7,856 and 9,181 ms. Related peak RSS is
2,702,224 KiB. These single controls do not establish a latency improvement.
The gated 80-client capacity check failed: the aggregate RSS guard stopped it
at 3,673,600 KiB after 24,403 ms and drained every owned process. The original
4 GiB ceiling and 3.5 GiB stop were not raised. Only the three prime outputs
were written before interruption; no complete measured client report or
client latencies exist for the 80-query wave. Do not infer a successful
delivery rate or completed deadline measurements from that interrupted wave.
[Stopped capacity record](stopped-capacity.json).

Remaining synchronization is explicit: the prepared-reader coordinator queues
frame preparation; source lease acquire/release and prepared metadata cache
management still use synchronization; canonical-source readers also still
have shared-cache access. These paths need separate ownership changes.
This candidate does not claim all retrieval locks or waits are removed.

[Implementation](candidate.patch), [native checks](../../../tools/research/ReadonlyPageChecks.lean),
[controls](controls.json), [actual hook evidence](evidence.json),
[actual bodies](bodies.json), [independent verification](verification.json).
80-person eight-hour mixed traffic, growing projects, shared storage, real
98% evidence delivery, answer quality and total-token improvement remain open.
