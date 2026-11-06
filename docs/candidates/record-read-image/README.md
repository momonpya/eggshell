# Immutable original-record reads

Isolated candidate, not adopted. Answering-model calls0, paid matched
comparisons0/18. This does not establish80-person capacity,98% real-evidence
delivery or token/quality improvement.

The original structure cache held one mutex while updating LRU stamps on hits,
reading the DB on misses, decoding geometry and evicting entries. The service
repeated that operation for every requested owner, then reacquired the same
cache for diagnostic statistics.

The candidate hands off one immutable map reference under a short snapshot
lock. Outside that lock it selects only the requested entries; unrelated cache
trees are not retained in the read image. The read phase receives no cache
owner, mutex, CAS, promise or mutable reference. Hits do not update shared LRU
or counters. Miss DB reads and geometry decoding run outside the structure
cache lock; only bounded insertion and FIFO eviction modify its owner state.
Full source heads, database identities, deadlines, owner order and encoded
reply bounds remain checked. Duplicate fills use immutable full-source keys.
Encoded sizes are computed once on fill and carry an erased Lean equality
proof. The old reply's unused cache-statistics field is null, avoiding an
additional shared lock merely to generate a read response.

This removes synchronization from the captured read phase, not from the live
cache snapshot handoff, admission, retained-source leases, PageMap caches or
all retrieval. Replacing these remaining ownership transfers with an
unsynchronized mutable reference is not part of this candidate.

Kernel laws cover source/database rejection, immutable lookup, encoded-size
equality, actual snapshot/collect/publish composition and the absence of any
update when there are no fills. A declaration audit connects the real service
handler to this batch and checks its read dependencies for synchronization.
The declaration audit checks1,016 dependencies. The ordinary ContractAudit
also passes. Native checks hold the original cache mutex throughout80 parallel
readers,each doing16 batches,and through actual miss DB reads. They verify
unchanged hit statistics,duplicate-fill idempotence,old-image reads after
eviction,source/database rejection,expiration and reply-budget rejection,
file/non-file JSON geometry,and the existing512-entry/16MiB limits.

The actual sealed native closure has253 modules,with only the two declared
source bodies and their exact embedded identity inputs changed. Build attempts
1/2 failed on record syntax,3 on check-entry namespace/do syntax and4 on a
missing check-state type annotation. They executed no hook cohorts. The fifth
build and native controls pass;failed guards remain in the control record.

The unchanged16-client/two-wave hook cohort delivers originals and ACKs and
completes semantic handoffs32/32. All32 complete stdout values are byte-equal
to the coherent parent. All35 actual outputs including prime are independently
verified. Latency min/median/max is6,621/7,614/9,084ms,versus the parent's
6,226/7,470/8,363ms. Related sampled peak RSS is2,726,000KiB. No performance or
memory improvement is established;no further80-client run is justified by
this control. The candidate remains unadopted under the token/quality gates.

[Scope](plan.json),[cache implementation](cache.lean.inc),
[record patch](ObservedRecordView.patch),[service patch](PublicationService.patch),
[native/kernel build](build.json),[native ownership checks](native-checks.json),
[body verification](verification.json),[byte parity](parity.json),
[guards](controls.json),[deletion](cleanup.json).
