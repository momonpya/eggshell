# Narrow base-cue lookup without changing the problem

Isolated Lean prototype, not connected to a product caller or adopted. A native
component benchmark is complete; no runtime, capacity, answer-quality or
inclusive-token benefit is claimed.

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

The native component [plan](native-plan.json) fixes eight cases and AB/BA/AB
ordering. All 24 complete constructed Problems equal the original, including
order, duplicates and failure results. Balanced lookup improves from 45.979–46.600
ms to 5.643–5.841 ms; a single-family case improves from 177.062–178.256 ms to
2.092–2.177 ms. However, dense lookup regresses from 8.693–8.790 ms to
60.031–60.718 ms and wide lookup from 12.215–12.401 ms to 248.557–248.765 ms.
The plain index is therefore **rejected for integration**. This confirms the
need to measure exact, proved implementations rather than infer performance
from their data structure. The native guard peaked at 128,960 KiB, exited zero
and left no owned processes. Native closure and source audits passed.

This prototype has no `csimp` attribute and changes no product caller. No 80-client
capacity or token benefit follows from this component result. Adoption still
requires the complete matched token/quality gate in AGENTS.md.
