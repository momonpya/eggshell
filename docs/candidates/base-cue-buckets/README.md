# Narrow base-cue lookup without changing the problem

Isolated Lean prototype, not connected to a native runtime or adopted. No
performance, capacity, answer-quality or inclusive-token benefit is claimed.

The [actual sequential measurements](../selection-preparation/sequential-phases.json)
place `problemFromView` at 133.903 / 180.191 / 182.389 ms. Its base-offer lookup
uses family-only postings and applies the exact range predicate separately for
each unit. Existing bucketed lookup is used elsewhere for bonus pieces; this
prototype addresses the remaining base lookup, without changing cue value.

[BaseCueBuckets](../../../tools/research/BaseCueBuckets.lean) uses the existing
512-character point buckets, followed by the unchanged exact predicate. Every
accepted cue's first point must belong to one of the unit's ranges. Degenerate
cue intervals have a separate family posting, so arbitrary old inputs also keep
their original behavior. This is a necessary-condition index, not a tool-name,
path, language or benchmark-specific filter.

Three generic Lean theorems prove nomination completeness, the entire ordered
lookup including duplicates, and **equality of the complete constructed
Problem** with `problemFromView`. Costs, weights, offer order, closures, cue IDs,
fixed charge, limits and failure results are therefore unchanged. The
[axiom output](axioms.txt) contains only the usual Lean axioms; no `sorry`,
`native_decide`, Z3 or new axiom is accepted. Earlier rejected proof attempts are
recorded in [plan](plan.json); no failed declaration was linked into a runtime.

Next measure the native implementation against family lookup, including wide,
overlapping, empty and degenerate ranges, before connecting a runtime. A narrow
index can still be slower on wide spans. This prototype has no `csimp` attribute
and changes no product caller. It is not a demonstrated remedy for the remaining
80-client RSS limit. Adoption still requires the complete matched token/quality
gate in AGENTS.md.
