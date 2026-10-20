# Isolated discovery data structures

This continues the [fixed scale diagnosis](semantic-scale-native.md). It does
not adopt a production change or report generation-model token savings.
The shared saved publication has 9,969 owners and 10,000 original windows.
The same first question, receipt, workspace and warm DB supply every standalone
inspection. Source/cache bytes remain unchanged. Each candidate must match
the entire reference Handoff, including text, packet, source records, delivery
keys, selection and completion metadata.

## Ordinal ownership

`discovery_owner_candidate.py` replaces the repeatedly sorted owner list with
one `Std.TreeMap Nat IndexedOwner`. The publication ordinal is its only key;
the row no longer duplicates that ordinal. Each value still carries the
original compiler certificate. Tree values supply the original order to the
graph and matcher, and tree membership handles repeated loads. Rejected Work
is checked again on later demands and quotient states.

`IndexedOwners.original_order` proves ordered publication keys for every
state. `DiscoveryOwnerTests.lean` checks all 720 insertion permutations of six
sparse ordinals, empty input, duplicate requests, exact body/graph/candidate
order, one hydration per retained ordinal, rejection followed by admission,
and rejection of a Work/owner disagreement. Its 722 ordering cases and four
admission cases pass in the native candidate.

## Work and child projections

`discovery_work_candidate.py` stops constructing all loaded Outcomes merely
to read `WorkGraph.subworks`, which depends on All children alone.
`sourceSubworks_exact` proves equality with the original graph projection for
arbitrary All and Outcome lists. Existing `HashDistinct.reference` preserves
the exact ordering of the Work-owner and child-demand lists. The saved and
staged membership-demand certificates remain mandatory. No source membership
check, Work comparison, candidate or evidence position is omitted.

## Retained diagnostic observations

| Standalone implementation | Full fallback | Complete reference Handoff |
| --- | ---: | --- |
| Original without instrumentation | 69,939 ms | reference |
| Original with instrumentation | 73,317 ms | equal |
| Exact depth relation set | 44,857 ms | equal |
| Depth set plus ordinal owner tree | 29,003 ms | equal |
| Depth, owner tree and Work projections | 26,274 ms | equal |

These are individual diagnostics, not balanced performance trials or a
passing hook gate. The instrumented original includes an additional native
stack observation. The candidate still exceeds the five-second goal, and a
semantic attempt consumes additional time before fallback. In the last
inspection, `loadWork` takes 5.586 seconds on the first discovery and 2.801
seconds on the second, versus 13.835/11.235 seconds in the instrumented
original. Child-membership work takes 1.527/2.043 seconds. Original loaded
owners and complete returned content are unchanged.

The owner build/inspection takes 68.486 seconds, sampled peak 2,882,176 KiB.
The combined Work inspection takes 60.151 seconds, peak 2,719,072 KiB. Neither
triggers the 3,500,000 KiB aggregate descendant guard.

A separate 24-second, 10-ms native stack observation covers the remaining
Work implementation. It retains complete reference Handoff equality. Its
recursive stack totals are not phase durations: recursive wire encoding and
grounding appear many times in one sampled stack. The exclusive sample table
and call ancestry instead identify further value comparisons, Match upsert
filtering, indexed reads and allocation work. Grouping each outermost Value
equality stack once finds 332 sampled branches under `Matcher.upsertMatch`,
versus one under the new depth membership count. These are sample counts,
not durations. `addMatches` currently filters all accumulated Matches for
each addition. Its replacement must retain the latest complete Match for
each exact `(demand, relation, currentFragment, pastFragment)` key, the same
final order and all untouched prior entries. Optimize only with that exact
sequence/authority preservation; keep the full scoring domain.

## Uninstrumented qualification

`prepare_discovery_candidate.py` reconstructs the exact candidate from the
qualified baseline and content-hashed component sources. It removes the
profiling wrappers, freezes every source file and builds the real executable,
the complete existing regression suite, owner checks and ContractAudit.
The failed first run is retained: the harness supplied an empty
`EGGSHELL_CONFIG`, which `Daemon.attachClientConfig` correctly attached over
the native fixture's own configuration. The first semantic hook therefore
returned `{}` without an offer. The unchanged ACK assertion rejected it.

The corrected harness unsets that variable for the regression subprocess so
each fixture supplies its own configuration. It reuses a completed build
only after comparing every source and still invokes Lake for all targets.
No body, ACK, timeout, ranking or ownership assertion is relaxed. The corrected
full qualification passes. All existing regression tests finish in 98.938
seconds, including native semantic-first/fallback/cold/corrupt delivery and
receipt checks. The 722 owner-order and four admission cases also pass in the
uninstrumented executable's build. ContractAudit builds successfully.

Three pending index tickets are recorded before independent recovery. The
candidate daemon drains all three; both pre-recorded graph heads remain
byte-identical, and the shutdown client and daemon both exit 0. Every frozen
candidate/baseline source and ordinary runtime hash remains unchanged. The
qualification takes 104.581 seconds with sampled aggregate peak 3,197,824 KiB;
the guard does not trigger. A verified existing build cache reduces the
unchanged build check to 0.869 seconds. This is regression evidence, not
large-DB latency or generation-model token evidence.

The fixed 60-hook failures remain authoritative. Further discovery/ranking
work and complete focus warm coverage are required before repeating that
gate. Latest-public-main matched task quality and inclusive token accounting
remain required for adoption.

## Complete focus warm closure

The actual LLVM failure has a separate cause: discovery uses original saved
windows, while focus removes the Work prefix from those same window slots.
An original-window-only warm therefore leaves some focus inputs cold. The
isolated `focus_warm_candidate.py` shares the exact suffix function between
warm and indexed focus. Warm plans the union of original and focus text keys,
deduplicates it, and encodes only the missing or invalid inputs in bounded
batches. It reads Work and only bounded original prefix windows to derive the
extra keys. Original source windows, ordinal positions, model contract and
valid vector bytes stay unchanged.

Doctor reports the unique union as its total, with separate discovery/focus
coverage denominators. Neither is a count of all original window references.
The warm scheduling checkpoint includes the actual suffix implementation's
content digest. Existing original vectors remain valid; an old scheduling
hint cannot certify the new input closure. Query vectors remain private.

Durable indexed focus no longer repairs numerical inputs in the foreground.
Staged sources retain their existing bounded repair allowance. Cold/corrupt
durable input must remain explicitly unfinished and fall back to lexical DB
body delivery. This change remains isolated pending the complete latency
gate and latest-public-main quality/inclusive-token adoption comparison.

The targeted native tests pass with synthetic vectors: original-only warm
is still cold for focus, only the difference is added, corrupt focus input
is diagnosed separately, repeated warm starts no unavailable provider, and
a durable provider pull cannot trigger foreground repair. The original
staged-repair test is unchanged. The complete existing regression suite
passes in 101.758 seconds and ContractAudit builds. Three pending index
tickets drain through a separate daemon with the pre-recorded graph heads
unchanged; the shutdown client and daemon both exit 0. Qualification takes
179.241 seconds, sampled peak 3,189,376 KiB, without triggering the guard.
The first three failed constructions are retained; their new test fixture
needed syntax/type fixes and explicit cache-directory preparation before
direct synthetic writes. Existing regression assertions were not relaxed.

The same frozen LLVM publication is copied to both cache layouts. Each
requires precisely 51 additional inputs in two batches (3,940/3,470 ms),
preserving every original vector's bytes. Repeated warm requests no work.
Original discovery has 2,081 unique inputs; focus has 2,080; their union has
2,132. All 2,081 original reference positions remain. Warm on the protected
shared DB writes only the private cache. The reference repair-enabled and
candidate cache-only focus return exactly the same complete 46-owner order
and original evidence positions in both layouts. Both perform the expected
52 bounded prefix reads and no subsequent repair reads.

All 12 fixed LLVM hooks complete discovery and focus scoring of every
original reference with zero source misses, invalid records or encoding.
This closes the missing-focus-input defect, but **the delivery gate is unmet
(0/12 pass)**: after scoring, the outer semantic attempt reaches its 4.5-second
deadline and falls back to lexical delivery. The unchanged required gold
body marker is absent in every response. Publication/stdout hashes and ACKs
agree in 12/12. The 4,831.253–4,922.529 ms response range is not successful
semantic/body delivery. Diagnose the remaining post-scoring matching and
extraction before claiming practical recovery or repeating the entire scale
gate. The old failed 60 samples remain unchanged. Native collection takes
160.706 seconds, sampled peak 1,626,368 KiB; the guard does not trigger.
Frozen DBs, source-vector bytes, model/runtime assets and ordinary sources
remain unchanged. No generation-model trial or adoption comparison ran.

## Local records

Under `/Users/ovm/.codex/experiments/eggshell/`:

- `discovery-owner-candidate-20261020/construction-1`: owner-tree proofs,
  native boundary checks and exact-Handoff timings.
- `discovery-work-candidate-20261020/construction-1`: composed projection
  proofs and exact-Handoff timings.
- `discovery-work-stack-20261020/observation-1`: whole-program native stack,
  exact target hash, raw stdout, guard and reference equality.
- `discovery-candidate-qualified-20261020/construction-1`: completed build,
  retained empty-config regression failure.
- `discovery-candidate-qualified-20261020/construction-2`: corrected harness,
  exact source/build-cache verification and uninstrumented qualification.
- `focus-warm-qualified-20261020/construction-4`: complete input closure,
  targeted tests, full regression, ContractAudit and independent recovery.
- `focus-warm-native-20261020/inspection-1`: fixed LLVM inputs, separate
  discovery/focus coverage, complete focus ranking and native delivery runs.
