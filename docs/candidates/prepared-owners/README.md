# Publication-maintained original owner view

Isolated implementation of the owner metadata part of
[prepared-owner-view](../../prepared-owner-view.md), based on current
`prepared-input-core`. **Not integrated into ordinary warm/discovery and not
adopted.** Current ordinary runtime `52e9dd63…` remains unchanged. The isolated
native checker is `98b7a651…`; exact identities are in [result.json](result.json).

The Lean [implementation](PreparedOwners.lean) maintains structural Outcome
identity, every live original `(source, node, ordinal, Work, candidate)` witness,
exact distinct Outcome/candidate counts, and original-unit lexical postings and
frequencies. A hash nominates a bucket; existing `nodesEqual` checks the entire
original DAG and streamed bytes, preserving all Exact positions. Neither a
semantic match nor a synaptic weight creates identity or completion authority.
Original Outcome bodies and search windows are not copied into this view.
The existing prepared 2-gram/vector/synapse roots are unchanged; their consumer
integration is not supplied by this component.

Bootstrap enumerates original Outcome directories outside retrieval. Subsequent
updates consume authenticated `SourceDelta` additions/retractions/affected roots.
Unchanged sources contribute no changed-owner enumeration. Global frequencies
change only when the final copy disappears or the first live copy appears.
Dead entries retain stable ids and an immutable equality witness, so reinsertion
does not reuse an unrelated id. A source's new ordinal still affects tie order.
The first live original determines representative order; the checked stride
embedding preserves the full source/root ordering without requiring dense ids
or pretending gaps are document counts.

The manifest binds source order, complete declared source heads, scope and
actual implementation/GraphStore/SourceDelta source bytes. The producer cannot
be replaced by an arbitrary caller-supplied digest. A mismatched cut is not
available; a missing/backward publication chain requires explicit recovery,
never an implicit empty result or hook-time full rebuild. The chunked manifest
avoids PageMap's single-row budget, with a 16 MiB decoding bound. Reader admission
reads metadata per source and does not enumerate Outcomes, Work structure,
documents, semantic descendants or topology.

## Native evidence

The [predeclared plan](plan.json) uses 16 physical original sources and
256/1,024/4,096 initial Outcomes. Every eighth original is identical across
sources, including its Exact dependency. The [final native cases](native.json)
compare every live owner, all ordered original witnesses, exact populations,
every original lexical term/posting and pairwise owner tie order against the
existing full `Federated.prepare`. That oracle does not use the new owner view.

| Initial raw Outcomes | Bootstrap | One add + one retract | Initial reader admission |
| ---: | ---: | ---: | ---: |
| 256 | 174 ms | 12 ms | 0 ms |
| 1,024 | 686 ms | 21 ms | 1 ms |
| 4,096 | 2,743 ms | 31 ms | 1 ms |

Times use integer-millisecond resolution; a zero is below that resolution.
Each sparse update reports exactly one publication and two changed/touched
owners. An unchanged cut takes 1 ms and publishes no new head. These are single
component observations, with source readers already supplied, not hook latency,
p99, a controlled speedup or a sustained workload result. The oracle audit time
also includes independent full checks and must not be used as a speed baseline.

Every final case checks partial duplicate removal, final-copy removal,
reinsertion with stable identity, old pinned inputs, foreign scope/producer,
source permutation and unavailable backward deltas. After these checks, each
source adds one structured-Work owner and one equal-Work/equal-result owner with
a different Exact dependency. All 32 added owners stay distinct, including all
16 owners outside the text-candidate domain. The original heads remain unchanged
across each read-only audit.

A [fresh native process](reopen.json) restores the exact original prepared head
and all 16 historical original heads after subsequent updates, then repeats the
full owner/posting checks. This demonstrates retained immutable inputs in these
files, not safety during physical extent reclamation. The two focused
[Lean proofs](audit.txt) use only `propext` and `Quot.sound`; they establish order
embedding and preservation of another original on removal, not the complete
correctness of concurrent IO or incremental maintenance.

[Negative evidence](negative-checks.json) retains initial module visibility/type
errors and the first native failure: a 16-source manifest exceeded the single
row budget. The latter is fixed by chunking the manifest before publication.
[Preliminary checks](preliminary.json) precede the final producer-bound helper
and are not substituted for the final cases. [Resources](resources.json) retain
all guarded builds/checks with the existing 3.5 GiB stop, 4 GiB hard ceiling and
2 GiB disk floor. Final processes exit with no owned survivors or guard trigger.

## Integration still required

Multiple independent original append owners per project remain mandatory.
This component serializes only its own derived-root transaction; it neither
claims a lock-free runtime nor makes original publication wait for a corpus
merge. The ordinary service must still schedule its updates from publication
differences, publish captured view references and apply admission/backpressure.
These native cases do not measure concurrent writers or derived queue capacity.

Next, ordinary federated discovery must resolve nominated owner ids/originals
through this view instead of rebuilding the global catalogue. Preserve existing
complete all-source Work-class lookup, jointly closed cross-source All/Union
reachability, full child membership and run-local Union witnesses. This module
does not implement those topology/recognition adapters. Do not switch only a
counter or restrict certification to top-K and call the integration finished.

Large LLVM evidence delivery, complete transitive read dependencies, multi-host
authorization/NAS durability, retained extents during compaction, growing
10/40/80-client combined workloads and eight-hour operation remain unverified.
Answering-model calls and matched paid comparisons remain **0/18**. No new
98% necessary-evidence, total-token, quality, product, README or release claim
is made. Keep the current runtime until the existing adoption gate passes.

To reproduce, copy `PreparedOwners.lean` into `Eggshell/PreparedOwners.lean` in
an isolated `prepared-input-core`, copy `tools/research/PreparedOwnerChecks.lean`,
and rename the imported `PreparedInputChecks.main` to `preparedInputMain`.
Build with the existing `StudyBuildMain` pipeline and unchanged aggregate guard.
Run `prepared-owners FRESH_ROOT 16`, `64`, `256`; then run
`reopen-prepared-owners ROOT` on the final 256-per-source fixture in a new process.
The Lean setup/record controllers remain beside the isolated build. Ended
fixture DBs/cache and raw logs are deleted after compact evidence is sealed,
without an archive; current required source/build/link inputs remain available.
