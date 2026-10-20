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
