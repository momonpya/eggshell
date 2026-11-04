# Exclusive staging without clock-based allocation

Isolated continuation of [interest-traffic](../interest-traffic/README.md),
parent `31433fb2`. Not adopted. One logical project still has multiple original
append owners, with project-shared derived data and the complete authorized
source inventory. This change addresses staging allocation, not retrieval
weights, certification authority or delivery budgets.

The parent's failed repetition had 80 successful queries but only 79 durable
saves. A read-only native diagnosis found all 80 start and finish events in
private journals, while `save-client-13` had no original response in the shared
project. Original and journal heads were unchanged by diagnosis. No failed
request was retried. This narrows the failure to the post-journal/pre-publication
path, but the old error contains no exact path.

Both ordinary file publication and DB staging directories previously derived
temporary names from PID plus `IO.monoNanosNow`. An actual 80-thread native probe
returned 327,680 clock readings with only 40,563 distinct values. A timestamp is
not a unique allocation identity, even inside one process. This demonstrates a
design flaw; it does not conclusively identify the old `File exists` path.

The [allocation ablation](allocation-ablation.json) also exercises the exact
existing native exclusive-create primitive against one shared parent. It uses
the old PID/clock suffix and the candidate suffix in three fixed alternating
waves, with 80 clients × 64 allocations in each wave. The old allocator produced
2 / 3 / 2 `File exists` collisions; the candidate produced 0 / 0 / 0. All failures
were that precise exclusive-create error, every successful handle was closed,
and no target object or temporary leaf remained. This directly reproduces an
error mechanism in the old allocation path, while the exact historical save
path remains unavailable. The [Lean probe](../../../tools/research/TempAllocationChecks.lean)
uses the existing native allocator, not a substitute implementation. Its
separate executable leaves the mixed-load runtime fixed.

The candidate obtains 16 OS random bytes for a temporary suffix. File creation
retains its existing exclusive/no-follow native operation; a random name does
not replace that authority. DB staging now uses exclusive `mkdir` rather than
checking absence and then recursively creating or reusing a directory. Only a
successfully claimed staging directory enters the cleanup scope. Initialized
DB publication still rejects replacement and synchronizes the parent before
returning. No native C primitive, global lock or CAS is added. Open/publication
errors include their target path, and the native load harness labels save
ingress, deferred storage and publisher-exchange failures.

Native allocation checks produced exactly one winner and 79 explicit refusals
for 80 simultaneous same-target DB creations. Eighty independent creations all
succeeded; the winner stayed valid and zero staging directories remained.
The immutable-publication regression also passed 320 simultaneous equal-byte
publications, while still rejecting changed bytes and a replacement inode.
These checks exercise real filesystem IO; they do not prove native OS semantics,
randomness, multi-host failover or NAS durability.

The [plan](plan.json) fixes three repetitions per prepared/skipped-cut condition,
80 ordinary actual-MiniLM queries plus 80 saves in each, the original 28-second
hook cutoff, and the unchanged aggregate memory and disk guards. A runtime
change restarts the series. Background drain, complete numerical coverage,
original restoration and fresh-chat/restart delivery are required independently
of the immediate query results. Any failure stops the series.

All six [fixed-runtime trials](trials.json) passed: each restored 80 acknowledged
originals and delivered both frozen fields in all 80 ordinary hook requests,
excluding later originals. No save failed. These are 480 logical queries and
480 saves, not transport-RPC counts or 480 independent human users.

| Fixture | Write / read-only owners | Max hook | Max save ACK | Semantic / fallback | Later preparation drain |
| --- | ---: | ---: | ---: | ---: | ---: |
| Prepared 6 | 4 / 2 | 16,456 ms | 5,673 ms | 21 / 59 | 7,510 ms |
| Prepared 7 | 4 / 2 | 16,584 ms | 5,660 ms | 21 / 59 | 7,508 ms |
| Prepared 8 | 4 / 2 | 16,558 ms | 5,655 ms | 21 / 59 | 6,841 ms |
| Skipped cut 7 | 16 / 0 | 19,192 ms | 11,548 ms | 6 / 74 | 19,283 ms |
| Skipped cut 8 | 16 / 0 | 19,355 ms | 12,042 ms | 6 / 74 | 19,502 ms |
| Skipped cut 9 | 16 / 0 | 19,262 ms | 12,100 ms | 6 / 74 | 19,921 ms |

The current numerical census was 327 windows per prepared fixture and 344 per
skipped-cut fixture, with missing/invalid both zero. Fresh-chat delivery of the
newly saved original took 2,157–2,925 ms; after actual service restart it took
2,613–3,399 ms, with identical body SHA per fixture. Cancellation, expiry, valid
empty output, worker reuse and invalid save-path rejection also passed. Full
body examples are retained for the first trial of each condition; every logical
query's measured body SHA and latency remain in the trial records.

The [resource records](resources.json) include failed diagnostic builds and all
native attempts. Sampled aggregate peak was 2,920,944 KiB, with no guard trigger
or owned survivors. The 3.5 GiB stop, 4 GiB ceiling and 2 GiB free-space floor
were unchanged. Ordinary ContractAudit compiled and the [eight kernel laws](laws.txt)
used only standard Lean axioms; they do not prove randomness or concurrent IO.

Apply [candidate.patch](candidate.patch) after the parent's candidate patch.
Only `FileSystem.lean` and `DB/PageMap.lean` change in the production candidate;
the sixteen [preserved source hashes](identity.json) cover original graph,
project access, input boundaries, selection, provider and authority code. The
[setup](setup.lean), [probe setup](probe-setup.lean) and [records controller](records.lean)
record reproduction and deletion boundaries. Finished fixture DBs, caches, raw
logs and the separate allocator executable are deleted after evidence extraction,
without archives. Current build inputs, its build receipt and protected originals
remain. [Cleanup](cleanup.json).

This is not an 80-person/eight-hour capacity result. Large growing databases,
stable backlog under the declared arrival rate, multi-PC authentication,
SMB/NFS operation, practical 98% necessary-evidence delivery, p99 latency and
matched total-token/quality improvement remain separate gates. The earlier
failed repetition remains a failure. Answering-model calls and matched paid
comparisons remain zero; no product, README benchmark or release adoption follows.
