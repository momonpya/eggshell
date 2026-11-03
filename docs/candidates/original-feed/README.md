# Original-only journal ingress

Isolated continuation of [preparation-drain](../preparation-drain/README.md).
Not adopted. The [plan](plan.json) fixes the contracts and resource limits before
execution. Answering-model calls and matched paid comparisons remain zero.

An imported event is a private one-hop reference to its exact original journal
head. It is not another producer event. Previously, both original append and
reference import advanced the mixed journal count used by upstream discovery.
Each consumer scanned that entire sequence, skipping references. The parent
audit found 3,165 references among 4,220 eligible rows. That is redundant ingress
work, not missing original observations.

The candidate maintains a sparse original ordinal posting and its inverse in the
same transaction as the raw body, per-turn receipt and original-only frontier.
A typed storage choice distinguishes original bodies from references; callers
no longer supply an arbitrary storage callback. Reference import retains its
normal mixed-journal posting and receipt but cannot advance the original feed.
The frontier binds producer, count, last original location and a hash chain.
An import cursor holds its exact retained journal head, frontier basis and
original position. Every imported point is checked for its inverse, raw-body
location, increasing order and unchanged original append receipt.

The candidate rejects nonempty journals without this feed. It does not infer an
empty original sequence or run an old-format compatibility scan. A new frozen
runtime and seed are required for future answering-model experiments. Protected
old originals are not rewritten or reused as a completed new seed.

`OriginalEventIndex` proves that its sparse append decision and count agree with
filtering a full mixed event sequence, and that aliases preserve that sequence.
The runtime uses those posting/count decisions. These are kernel-checked pure
properties, not proofs of transactional IO, storage durability, all concurrent
execution or 80-user capacity. The native independent oracle scans mixed rows
without consulting the sparse index, compares every original ordinal and body,
and tests failure/restart boundaries.

The final focused native check passes in 7,752 ms with sampled aggregate RSS
162,096 KiB. Its upstream journal contains 152 mixed rows, of which 24 are
originals. The importer examines exactly 24, in four seven-row-bounded calls;
every location and decoded body agrees with the independent full scan. Later
alias-only changes produce zero downstream debt. Duplicate retries and an
aborted transaction preserve the head. Missing postings, alias locations,
wrong inverses, foreign/unretained heads, changed frontier bases,
out-of-basis cursors and unsupported nonempty journals
are rejected. Expired/zero-budget imports change nothing. A fresh process
resumes a partial cursor, preserving all 28 later originals in order. This
demonstrates reduced examined rows, not a controlled latency speedup.

The ordinary native lifecycle also passes: prompt/Pre/Post/Stop take
413/145/111/26 ms and the two original fixture evidence items are delivered.
All six captured source views, shared private ingress, durable ACK and normal
background imports remain checked. These are small fixture timings, not p99.
The three sparse-index theorems use only `propext`, with no added axioms,
`sorry` or `native_decide`. The standard ContractAudit compiles in this build.

The actual MiniLM mixed burst completes all 80 queries and 80 durable saves.
The two fixture evidence items reach every query, with 24 semantic replies and
56 lexical fallbacks. Median/p95/maximum delivery time is
15,518/17,570/17,752 ms. Normal preparation drains in 2,109 ms, preserving all
80 original response atoms and all 327 current numerical windows. New current
queries complete semantics in 2,094 ms and, after verified service restart,
2,498 ms with identical body hashes. The whole scenario takes 31,497 ms;
that total is not one hook's latency. Peak sampled aggregate RSS is 2,733,312 KiB.

With an idle index worker paused, 24 new originals receive durable ACKs in
1,633 ms. Service shutdown leaves real durable tickets. Normal restart recovery
drains in 16,831 ms with 75 retries, preserving every original and all 423
current numerical windows. A fresh semantic query delivers the interrupted
evidence in 2,681 ms. Reissuing those 24 saves takes 1,389 ms without advancing
original heads; recovery drains in 4,000 ms with one retry and delivers the
evidence in 2,893 ms. The two interrupted-query bodies differ because private
derived state was not frozen; both actual texts are recorded. These are recovery
checks, not matched selection or token comparisons.

The parent interruption audit recorded 22,064 ms and 142 retries. The candidate
has fewer retries in this run, but these are single observations with different
physical IDs and scheduling: they are not a controlled speedup estimate.
Remaining retries include journal/checkpoint work after the original feed has
drained. Removing alias scans neither eliminates that work nor proves sustained
preparation capacity. Projecting originals to multiple source views still has
metadata fan-out; the index removes redundant ingress scanning, not all fan-out.

The final test-helper refinement adds unretained-head and changed-basis negative
checks; product code is unchanged from the normal/MiniLM runs. Both helper hashes
are recorded. [Cleanup](cleanup.json) deletes all three ended fixture trees,
299 closed/generated files and the superseded helper: 241,339,757 apparent bytes.
It does not claim equivalent physical space reclamation. Protected source and
sealed-input hashes remain unchanged, and no archive is created.
No timing result alone adopts this candidate. Original ACKs, Work
equality, certification, selector/ranking, deadlines and numerical model remain
unchanged. Multiple-PC/NAS authorization, held prepared read roots, complete
cross-owner certification and sustained 80-person preparation throughput remain
separate gates. The resource stop stays 3,670,016 KiB, the ceiling 4 GiB and the
disk floor 2 GiB. Ended DBs/caches/raw logs are deleted without an archive after
compact evidence and actual delivery bodies are recorded.

Apply [candidate.patch](candidate.patch) with `git apply --unidiff-zero` to the
parent's `preparation-drain-core`.
Build `tools.research.OriginalFeedChecks` with the existing `StudyBuildMain`
dependency/interface selection, renaming the imported research entry point to
`preparationDrainMain`. `original-feed FRESH_ROOT` runs the independent oracle
and launches `resume-original-feed ROOT` in a fresh process. For normal service
checks, run `context-prepared-numeric FRESH_ROOT`, `drain ROOT`,
`interrupt-preparation ROOT` and `interrupt-retry ROOT` with the same private
data root. Use only one aggregate guard for this experiment prefix at a time.
The [sparse results](sparse.json), [drain](drain.json), [interruption](interruption.json),
[retry](interruption-retry.json), [actual bodies](deliveries.json),
[resources](resources.json), [negative checks](negative-checks.json) and
[producer identity](result.json) separate the evidence and remaining limits.
