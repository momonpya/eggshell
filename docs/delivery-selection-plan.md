# Trace the actual delivery decision

The first-topic omission is not an owner-admission failure. On the unchanged
source-only checkpoint, owner `v5413273379768701678` is nomination index 2 and
focus index 5 (third and sixth, respectively). It is hydrated and already has
recognized numbered source rows. Adding another shell-command recognizer would
not fix this case.

The isolated selection-plan candidate replaces the duplicated fitter with one
typed `SharedRangeAdapter.Plan`. The decision, actual character/byte ceiling
proof, mandatory-control prefix proof and private explanation share the same
candidate/cost arrays. The explanation does not solve the problem again and
does not enter the model prompt. `DeliveryExplain.lean` reads that recorded
decision, not the reference workspace or a rerun of retrieval. It reports the
first recorded loss and subtracts the candidate intervals with the existing
proved interval implementation. Semantic scores are explicitly unrecorded;
this is not yet a complete public `egg explain` command.

Two real native chats took 13,124 / 11,775 ms and produced exactly the baseline
stdout SHA-256 `b8b58afcb50f135e29049b022565b6c12357e685375f7b91f78267e3be8b4a20`.
Delivery remains **2/4**, with no answering-model calls or token-improvement
claim. A freshly compiled FullSearchOracle and ContractAudit passed against
this candidate; an inherited oracle was not used as acceptance evidence.

## Different losses inside the same owner

The legacy path creates 42 units for this owner and selects none.

| Frozen original-output interval | In union of all candidate units | In selected units | First recorded loss |
| --- | --- | --- | --- |
| language state `[11653,12212)` | yes | no | selector |
| trailing warning `[13394,13748)` | no | no | candidate domain |

The warning has an uncovered suffix `[13667,13748)`: **81 original-output
characters**, which can include JSON escapes. They are not necessarily 81
source-code characters. No selector weight can buy original bytes absent from
every candidate.

The prepared canonical rows were also disabled whenever the independent
500 ms synaptic walk ended incomplete. Removing only this dependency exposes
838 original rows for the owner and selects 8 of 21 units. It produces stable
stdout in 11,095 / 9,779 ms, but still delivers **2/4**. Neither frozen missing
interval is in that candidate union. Focus-centered groups are therefore not
a complete original-record catalogue, even when all stored rows are available.
This ablation is not adopted.

## Failed partial-prefix alternative

The baseline's bounded synaptic walk reports incomplete and discards all its
checked offers. A separate prototype admitted healthy, checked partial results
while leaving failure/corruption rejection and authority separation intact.
Component checks for all three relations, omission preference, private pins,
partial postings and source immutability passed.

The actual chats admitted 413 / 330 offers, took 20,496 / 21,453 ms and returned
different bytes. Both still delivered 2/4. The wall-clock cutoff exposes a
different prefix of one posting, so this prototype fails both coverage and
stable first-delivery checks. It is not a solution and is not adopted. Raising
the deadline or retuning these offers is not the next step.

A read-only audit of all **12,695 checked facts in the shared index only**
found one fact overlapping the missing language interval and none overlapping
the warning. Private usage facts were not included. This does not establish
root reachability, and missing edges do not remove stored original bytes from
the frozen denominator.

## Implementation direction

Separate the complete immutable original-record domain from query hints.
Original records, bindings, shared payload costs and optional verified file
aliases belong to preparation. Vector/focus/citation/synaptic hints rank those
records; they must not define which stored bytes exist as possible units.
Keep every real origin and Work authority separate from payload sharing.
Query-time source-file availability and Git cannot be prerequisites.

The suggestion to map arbitrary outputs to saved file contents is useful only
with an actual captured-byte witness. Current dependencies retain fingerprints
and original outputs, not every dependent file's complete content. The research
evaluator's external reference-file lookup must not be copied into the product
as a portable provenance certificate. Ambiguous or transformed output stays an
original observation unless its mapping is checked.

All variants use the same frozen C7 checkpoint for model-free diagnosis. Their
changed runtimes have not acquired a new seed or run the six answering stages.
Production/README/release adoption and total-token improvement remain false.
Ended prototype DB/cache/builds are removed after small receipts, patches and
metrics are retained, without compressed archives.

The partial-prefix and passive-plan prototypes have now been retired: 13
targets, 1,123,226,203 logical bytes. The cleanup checked terminal guards,
absence of live processes and active-candidate links before deletion, and
copied bounded JSON receipts first. This is logical file size, not a measured
APFS space-reclamation claim. The active seed, MiniLM/build dependencies and
canonical ablation remain available.
