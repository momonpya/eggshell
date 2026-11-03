# Project publication with independently owned streams

Design direction under formal investigation, not an implemented replacement
of original publication. The first isolated [prepared-index candidate](candidates/owned-ready/README.md)
now separates independent derived writer regions and removes their mutable
ready-root catalogue. The isolated [original-stream prototype](candidates/owned-project-streams/README.md)
also publishes through separate physical owners and pins complete dependency-closed
views. Ordinary hooks and service routing still use serialized per-project
publication; the prototype is not their replacement yet.
The project remains one logical shared DB. No one-owner-per-user DB layout or
one global owner for every project is required. The target remains 80 users,
30-second hooks and 98% of necessary original evidence actually delivered;
the existing matched total-token/quality/deadline adoption gate still applies.

The current native observation found a 279–348 ms common-session guard hold
during offer publication, exceeding background save's 100 ms admission. The
[observation](candidates/session-lock-profile/README.md) preserves six identical
parent bodies and the measurement limits. Increasing the lock timeout does
not address ownership or remove repeated work.

## Ownership instead of a competing shared head

Writers own disjoint append streams inside a project namespace. Original
observations and their receipts are immutable entries. Preparing one stream
does not mutate another stream's head. Publication, lexical/synapse/vector
preparation and source-payload work can run in parallel across independent
regions. Queries pin immutable completed views.

A reader combines published frontiers by their pointwise maximum, after
checking project/authority, complete stream inventory and dependency closure.
There is no competing assignment of an entire shared head by independently
prepared writers. A whole-state replacement would lose updates, even when the
logical stream IDs differ. The executable storage representation must preserve
this distinction; a shared `IO.Ref` of the whole map would not implement it.

The [Lean model](../tools/research/OwnedPublicationModel.lean) uses actual
`PageMap.Head` values, registered physical identities distinct from the logical
project, and actual native `RequestStamp` freshness checks. It
proves independent append commutation, per-owner ordering, retained old views,
and commutative/associative/idempotent joining of dependency-closed views.
With a complete stream inventory, every referenced original enters the
assembled input. It also rejects a frontier missing a cross-stream dependency
and exhibits the stale-whole-state replacement loss. The final checks use only
standard Lean axioms, with no `sorry`, `native_decide` or new axioms.

## Required runtime refinement

The model is not a proof of concurrent IO, exclusive runtime ownership,
storage durability, e-graph completeness or response-time bounds. The next
implementation must establish the following, rather than assume them:

- Each physical append location has one live writer. Owner handover cannot let
  an old writer overwrite its successor. New immutable stream locations can
  isolate old writers; ownership admission and failover still need a checked
  protocol. Atomic storage publication and durable ACKs remain obligations.
- The finite manifest names every nonempty stream. Cross-stream dependencies
  enter the actual assembled graph, not merely a location elsewhere in storage.
- Derived lexical, vector, synapse and certification roots identify the exact
  original cut they cover. Advancing one component must not silently advance
  the others or hide outstanding preparation debt. Preparation consumes deltas
  outside hooks; readers retain prepared payloads and metadata. The requested
  original boundary is frozen independently of derived readiness. An older or
  empty closed view cannot replace it; `QueryView.exactBoundary` and
  `lagging_view_is_not_requested` express that requirement. Omitting an
  unprepared stream must not shrink the evidence-evaluation denominator.
- Exact and e-class certification operate on the complete authorized graph at
  that cut. Causal closure of a storage view does not prove that a partitioned
  congruence index is complete. Recommendation pruning must not remove facts
  needed for certification. Existing authority checks and refinement obligations
  remain intact.
- Delivery preparation produces immutable bounded payloads. The native context
  owner validates turn, epoch and the original absolute deadline before
  accepting them; ACKs record the body actually inserted. Immutable source
  publication alone cannot acknowledge delivery or complete Work.

This removes a shared mutable data location from the design instead of merely
replacing its lock with CAS. It does not claim an implementation free of all
OS/library synchronization or a formal lock-free progress guarantee. In
particular, Lean 4.33's `Std.Channel` uses `Std.Sync.Mutex`; introducing a
channel would not by itself establish that guarantee.

Runtime validation must combine concurrent publication, background indexing
and queries, including crash/retry and source changes. It must measure backlog,
memory, actual delivered evidence and 80-user sustained throughput. A pure
commutation theorem, an idle read burst or a single successful hook cannot
substitute for those checks. Product adoption remains conditional on the
prespecified matched token, quality and deadline comparisons.
