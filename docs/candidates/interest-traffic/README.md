# Parallel original owners with ordinary query and save traffic

Isolated continuation of [interest-lifetime](../interest-lifetime/README.md),
parent `beeab0f0`. Not adopted. One logical project contains multiple physical
original append owners; each append location still has one writer. This is not
one writer for the entire project, and it does not create a project/vector copy
for each person. Other configured projects remain read-only inputs.

## What failed and what changed

The first prepared fixture passed 80 ordinary numerical hook requests and 80
parallel original saves. The skipped-cut fixture then failed all 80 queries
before search admission while retaining all 80 saves. Read-only inspection found
both captured source cuts had their shared canonical, window, lexical and synapse
metadata but no published input frame. Preparing a historical source was waiting
for future events in its private replay journal. Those events were outside the
captured source cut.

The candidate distinguishes explicit historical-source preparation from current
maintenance. An explicit source request prepares that exact source and returns
its actual immutable frame reference, without requesting unrelated private
replay. Current maintenance still requests replay, and unfinished requested
replay still prevents completion. A causal intervention on the failed fixture
published the two historical frames in 66/32 ms, preserving the original heads
and private journal heads and leaving private replay debt pending. This was an
intermediate candidate, not a final-runtime latency comparison. Its coverage
record describes the selected preparation delta, not a full corpus census.

The next load delivered both originals to all 80 queries but lost one of the
80 saves to an immutable-publication error. A separate deterministic native test
reproduced a false collision: removal of the winner's temporary hard link changes
the same inode's ctime. The existing strict agreement predicate then rejects
equal expected bytes. The new verifier retries at most three times through the
same held descriptor, rechecking all expected bytes and namespace identity. It
never adopts a replacement inode or weakens general source freshness checks.
The precise path of the earlier save error was not recorded, so that particular
failure is not attributed conclusively to this independently reproduced bug.

Full source inventory is retained, including empty original streams that still
need owner metadata. The candidate batches up to 32 preparation descriptions in
one transport request and reuses a descriptor already validated for the same
registry key and complete original head while that job is pending or running.
This is a transport batch size, not a retrieval or certification cap. There is
no additional persistent cache. Worker execution still checks the registry and
actual source ancestry; the same absolute waiter deadline and charge bounds
apply. Original authority, project routing, selection and provider code remain
unchanged.

## Evaluation boundary

The [predeclared plan](plan.json) requires three fresh fixtures per condition,
each with 80 ordinary `deliverForWork` requests and 80 saves, using actual local
MiniLM. Prepared fixtures include four write owners and two read-only sources.
Skipped-cut fixtures include all 16 write owners, capture unprepared A1/B1,
prepare later A2/B2 first, and freeze the two required original values before
delivery. Later values must not appear. No harness warm of the skipped cut is
performed during the load.

The final candidate's series **failed** during its second prepared repetition;
the remaining planned repetitions were not run. Successful repetitions do not
override that failure. [All attempted results](series.json), [passed trial
records](trials.json), [failed prepared trial](prepared3-failed-outcomes.json).

| Fresh fixture | Original owners | Evidence queries | Durable saves | Max hook | Max successful save ACK | Semantic / fallback |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Prepared 2 | 4 write + 2 read | 80/80 | 80/80 | 16,554 ms | 5,469 ms | 21 / 59 |
| Skipped cut 4 | 16 write | 80/80 | 80/80 | 18,583 ms | 10,805 ms | 9 / 71 |
| Skipped cut 5 | 16 write | 80/80 | 80/80 | 18,957 ms | 11,506 ms | 6 / 74 |
| Prepared 3, failed | 4 write + 2 read | 80/80 | **79/80** | 16,346 ms | 5,452 ms | 21 / 59 |

Every successful evidence query delivered both frozen values and excluded later
originals. The failed save reports only `File exists`, without a path or stage.
It is not attributed to a particular filesystem primitive from that message
alone. Trace save ingress, original publication and ACK stages before further
load. This is an unresolved concurrency failure, not a validated 80-user result.

The three fully passed repetitions restored all 80 acknowledged originals.
Ordinary preparation drained in 6,610 / 17,505 / 19,287 ms after the burst;
full current numeric censuses were 327 / 344 / 344 windows, with missing and
invalid counts both zero. Newly saved evidence reached a fresh chat in
2,149 / 2,841 / 2,932 ms, and after service restart in 2,614 / 3,356 / 3,374 ms,
with identical before/after body SHA per fixture. No such post-load completion
is claimed for the failed repetition. The [pre-fix prepared check](preliminary-prepared.json)
is kept separately, not pooled into this series. Byte-identical restart bodies
are [stored once](duplicate-bodies.json), with both measured hashes retained.

The load also checks cancellation, expiry, valid empty output, invalid save-path
rejection and worker reuse. After the burst it observes ordinary preparation
drain, materializes all 80 acknowledged originals, checks every current numeric
window, then delivers newly stored evidence to a fresh chat before and after
actual service shutdown/restart. The 120-second drain observation is separate
from the unchanged hook cutoff.

These are local synthetic bursts. They do not establish 80 people working eight
hours, stable backlog under a declared sustained arrival rate, large growing
databases, multiple PCs, SMB/NFS durability, practical 98% evidence recall or
p99 latency. Frequent semantic fallback and save latency remain visible rather
than being hidden in an aggregate pass. Latest maintenance still couples its
frame publication to private replay; this change does not claim all background
preparation is independent. Existing short scheduling mutexes and ownership
leases remain; no lock-free IO or CAS-free storage theorem is claimed.

The eight [kernel law checks](laws.txt) use only standard Lean axioms; ordinary
ContractAudit compiled with the actual runtime call connections. The [native
immutable test](immutable.json) independently demonstrates the old ctime
rejection, recovery through the same descriptor, rejection of different bytes
and replacement inodes, and 320 simultaneous identical publications without
failure. That test predates the transport batching and does not explain away
the later failed save. [Resources](resources.json) retain every guard, including
failed builds and load attempts: sampled aggregate peak 2,920,544 KiB, unchanged
3.5 GiB stop / 4 GiB ceiling / 2 GiB free-space floor, and no owned survivors.

Apply [candidate.patch](candidate.patch) to `interest-lifetime-core`, copy the
four tracked `SharedInterestLoadChecks`, `ConcurrentHookChecks`,
`SourcePreparationChecks` and `ImmutablePublicationChecks` modules into their
research paths, and build `tools.research.SharedInterestLoadChecks`. The exact
[helper and unchanged-source hashes](identity.json), [setup](setup.lean) and
[records controller](records.lean) describe the tested state. Finished fixtures,
private caches and raw logs are removed after compact evidence extraction,
without archives; the current failed prepared fixture is retained for diagnosis.
Protected originals and necessary build inputs remain. [Cleanup](cleanup.json).

At the subsequent [publication-names milestone](../publication-names/README.md),
the failed fixture was inspected without replay or publication. Its compact
diagnosis was retained and the finished DB/cache was then deleted; it is no
longer a currently retained input. See the later [deletion record](../publication-names/cleanup.json).

Answering-model calls and matched paid comparisons remain zero (0/18).
Capacity checks, Lean proofs and evidence delivery cannot satisfy the separate
matched total-token, quality and deadline adoption gate. No product source,
README benchmark or release is changed by this candidate.
