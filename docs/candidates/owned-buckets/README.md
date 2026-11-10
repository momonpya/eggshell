# Updating array buckets through their owning map

Isolated component, not adopted. Its later [real-hook connection](runtime/README.md)
is recorded separately. The
[current real-hook profile](../register-rounds/runtime/profile.md) found
repeated array copying after the ready marker. `ownerReach` uses an explicit
lookup/push/insert pattern. This study tests that pattern without changing
ranking, WorkGraph/Exact, advisory synapses, pools or caches.

[OwnedBuckets](../../../tools/research/OwnedBuckets.lean) compares that original
update with `HashMap.alter`, allowing the map to consume the old bucket before
updating it. Lean's ordinary alias checks still apply. This is not proof that
every input is uniquely owned or that all calls mutate arrays in place.

Three generic theorems cover arbitrary lawful keys/hashes, values, initial
tables, rows and probes. They preserve the complete ordered **optional bucket**,
including duplicates, empty stored buckets and absent keys. Function extensionality
gives equality of the complete lookup interfaces. Internal hash-table layout
equality is not claimed. [Axiom output](axioms.txt) lists only `propext`,
`Classical.choice` and `Quot.sound`; no new axiom, solver or native decision
procedure is added.

The [native audit](native-evidence.json) checks two objects and their exact
reviewed sources. Both constructor paths are separately specialized in the
consuming module; [native symbols](consumer-symbols.txt) verify both paths and
the two distinct benchmark entries. An earlier undefined-symbol-only check
was [rejected](audit-rejection.json); a subsequent attempt refused to overwrite
the existing inspector result. [Its record](audit-evidence-rejection.json)
preserves that failure. The inspector was not weakened; the successful attempt
uses its own output name. The initial unexecuted syntax failure is also
[recorded](build-rejection.json).

[The native result](component.json) uses retained immutable inputs shared with
an owned dedicated actor. Each arm reads its input after starting the clock,
and the predeclared order is AB/BA/AB. The data is synthetic; it is not a replay
of actual `ownerReach` input and does not measure `RangeReach.prepare` sorting.

| Rows | Owners | Lookup/push/insert | Alter inside map |
| --- | ---: | ---: | ---: |
| 1,024 | 1 | 1.185–1.519 ms | 0.0375–0.0421 ms |
| 4,096 | 1 | 20.034–23.361 ms | 0.113–0.127 ms |
| 8,192 | 1 | 85.732–86.247 ms | 0.224–0.240 ms |
| 1,024 | 46 | 0.0862–0.0872 ms | 0.0474–0.0519 ms |
| 4,096 | 46 | 0.498–0.512 ms | 0.139–0.144 ms |
| 8,192 | 46 | 1.777–1.831 ms | 0.279–0.284 ms |

There are 198 native controls over prefixes, duplicates, absent/empty keys
and a retained initial table. All bucket contents and the checked native table
orders match; the initial table remains unchanged. The guard exits normally,
leaves no owned processes and peaks at 93,904 KiB. This is a combined
component peak, not an arm-specific memory improvement. Heartbeat counters
are events, not allocated bytes.

The observed growth supports the copy-on-write hypothesis for this construction
pattern. It does not establish the number of actual ranges per owner, its
fraction of hook time, whole-hook speed or the few-second sixteen-client target.
At this component stage, the product's owner-range index still needed a formal
connection and matched real-hook comparisons. Those later steps are recorded
in the runtime study. The component's generic lookup equality alone is not
presented as a theorem about the entire selector. Answering-model calls and
adoption remain zero; inclusive token/quality gates remain unpassed.

The connection must preserve the existing `RangeReach.prepare` and its ordered
input. `memberChoices` observes the index through `reach[bound.owner]?`, so a
lookup interface is the appropriate equality boundary. Lift optional-bucket
equality through preparation; do not manufacture equality of raw hash maps.
The installed Lean library provides `List.idRun_forIn_yield_eq_foldl` and
`Std.HashMap.ofList_equiv_foldl` for relating the original nested collector
and final mapping. A compiler binding must precede its same-module consumers.
Prepared base ranges belong to the published project image where possible;
query-dependent units and ordinal mappings remain explicit deltas. Faster
fresh-table construction alone is not the final eighty-user architecture.

Ended component and observer artifacts are [retired](../register-rounds/runtime/retired-observed-components.json)
without an archive after their results are collected. Current product, models,
source DB and necessary native inputs remain protected. The one-off syntax and
audit repair commands are removed; fresh named build/audit attempts preserve
their own evidence. This does not erase the failed-attempt records above.
