# Prepare changed evidence through the existing publication history

This isolated Lean candidate connects source publication changes to the
[incremental projection store](incremental-projections.md). It reuses the
existing authenticated DB and its change journal. There is no second change
feed, storage engine, manual format version, or answering-model dependency.
The candidate is unadopted under AGENTS.md; it changes preparation and scheduling,
not MiniLM, recommendation, recognition, packing or the handoff prompt.

## One source history, scoped derived work

A numerical checkpoint pins the exact source head, source counters, actual
encoder/focus/planner/projection implementation contracts and retained projection
incarnation. The executable's installation path is not a numerical cache
identity. Registered executable targets still exist independently; this does not
complete target-registry cleanup or cross-DB projection sharing.

Background preparation follows the source journal's actual parent heads to the
saved head. Every record, including its size descriptor, is read through that
record's own historical child head. Revision numbers and population counters
alone are insufficient. The replay is bounded to 4,096 publications, 8 MiB of
journal payload, 8,192 added/removed entries per record and 4,096 distinct owners.
An absent/foreign/discontinuous/over-limit history selects full-source numerical
planning; it never establishes that no source work changed.

Only touched, currently live owners enter the delta plan. Point reads check the
original Outcome, membership, reverse candidate directory and bounded window
directory. Discovery and focus geometry come from the same planner as full
source preparation. Removed owners leave reusable numerical hints behind; pinned
original membership still decides whether those hints can nominate live content.
Union-only changes do not alter numerical input text; they remain work for the
independent equivalence/synaptic indexes.

No-change and memo-only publications inspect zero numerical windows. An addition
passes only its discovery/focus keys to the incremental matrix. Explicit `egg
warm` still verifies the complete source, and `doctor` retains full coverage
inspection. A background result's `scope=publication-delta` counts refer only to
the selected delta, never the whole-corpus coverage denominator.

## A deadline is not a cache defect

An incomplete search still registers background re-evaluation, but registration
does not inspect the full source or erase a prepared checkpoint. The obsolete
unconditional invalidation entry point is removed. Only a numerical read that
actually observes unavailable input creates typed private repair debt.

The repair event contains DB identity, model, encoder contract, reason and count.
It contains no question, tool input/output or original path. Immutable unique IDs
allow preparation to capture a set, repair and acknowledge exactly that set;
concurrent later events survive. Observed unavailable input requests full-source
verification, so this initial debt implementation is deliberately coarse. It is
not per-key repair or general privacy enforcement. Outstanding event enumeration
can grow; capture acknowledges at most 4,096 validated records per pass.

## Evidence and limits

Native tests exercise actual `Warm.runTarget`, deadline registration and numerical
search, including unchanged sources, memo-only publications, one-owner addition,
remove/add replacement with unchanged population, a counterfeit saved head,
concurrent debt acknowledgement and a deliberately damaged raw numerical input.
The actual search refuses cold repair, records debt, and background warm repairs
the missing input and clears only captured events. A trace verifies the delta
planner does not perform catalogue range scans. Selected windows equal full
source planning restricted to the touched owners.

A separate audit uses the existing 10,000-window source and its real revision
2→3 publication, with 1,777 live changed owners. It anchors a historical checkpoint
only after checking that the prepared matrix covers that source. This is a
component audit, not a cold/full-warm timing. The selected 3,554 discovery/focus
keys equal the full plan's corresponding keys, out of 19,969 total keys. Every
selected raw input is valid, and matrix preparation produces/writes zero rows.
Raw timings, guards, runtime and build-input hashes are pinned in
[the review](candidates/source-delta-warm-review.json).

| Final diagnostic operation | Work | Time |
| --- | --- | ---: |
| 10k original full window plan | 19,969 distinct keys | 2,631 ms |
| Same source's verified revision delta | 3,554 keys / 1,777 owners | 710 ms |
| Repeated unchanged plan | zero windows | 7 ms |
| Delta projection validation | 3,554 reused / zero produced or written | 2,697 ms |

The final small native lifecycle test takes 6 ms unchanged and 8 ms for a
memo-only publication. Adding/replacing one owner requests three new raw inputs;
actual input repair requests one. These include real MiniLM preparation where
needed, not answering-model usage. Final native lifecycle/audit guards exit zero
with no owned survivors; aggregate peaks are 1,402,320/144,864 KiB. The serial
final build peaks at 2,849,568 KiB, below the 4 GiB experiment ceiling. Earlier
compiler failures and the earlier test's mistaken expectation that whole warm
could recover missing original history remain recorded as failed runs.

The ordinary Lean proofs establish lineage identity/revision monotonicity and
that acknowledging captured IDs excludes a fresh ID. They do not establish the
completeness of the journal producer, arbitrary filesystem behavior, all derived
index maintenance, recognition completeness or required-evidence recall. The
source change producer's complete added/removed record remains a premise.

The test of a missing original journal selects full numerical planning, but
whole warm is then rejected by the existing synaptic journal preparation. This
candidate does not reconstruct broken original history or silently certify it.
A later overwrite of an old journal size descriptor cannot rewrite historical
delta replay. An inconsistent live reverse-candidate directory is rejected.

Other derived refreshes still precede numerical preparation and can enumerate
the corpus. Foreground owner hydration, routed recommendation with complete
prepared additions, independent complete indexed recognition, shared/federated
concurrency, compaction, MCP storage policy and capacity control remain unfinished.
The latest native 50k useful-delivery gate remains failed; no new p99, answering
model, seed, quality or total-token comparison is established here. Phases 0–6
remain active. Do not turn these component measurements into a product claim.
