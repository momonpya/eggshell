# Breaking redesign around evidence delivery

2026-10-24: the user permits breaking every compatibility constraint except
the core: use equivalence structure, vectors and synaptic relations to deliver
needed persisted records across multiple DBs and concurrent shared-DB use.
Those two usage modes are central requirements, not optional follow-ups.
Product adoption still follows the matched total-token,
quality and deadline requirements in AGENTS.md. This does not complete Phases 0–6.

The user's latest refinement is to derive a smaller design from Eggshell's core,
not accumulate mechanisms from other databases. The target is one original
identity/reference model, one durable source-change feed and independent
recommendation/authority views. Cluster routing, filters and layout policies
serve that model; they are not additional stores or services to install.

The [recent DB research decisions](db-research-decisions.md) map verified
Databricks, Snowflake, Redshift, DynamoDB and arXiv mechanisms to the execution
plan. Immutable stored extents and explicit source-change coverage precede
clustered recommendation and deferred original loading. A bounded source-change
consumer now drives numerical background preparation in isolation; routed-query
compensation and unified maintenance of all views remain design targets.

The [incremental projection component](incremental-projections.md) now implements
the first storage step using immutable appended extents and existing COW roots,
without another segment-catalog engine. It removes full projection reproduction.
The [source-delta preparation candidate](source-delta-warm.md) now passes only
verified changed-owner windows to numerical preparation and keeps deadline-only
events from invalidating readiness. Explicit full verification, routed query
compensation, compaction and owner-loading replacement remain separate costs.
The complete-read regression remains recorded.

The [Work-only inference component](work-only-inference.md) now factors the
actual Matcher primitives and proves complete single-pass Union equality before
result grounding. A fixed 10k diagnostic identifies 9,968 inert owners under its
one-nomination/parent context. This supplies a semantic boundary for deferred
Outcome reads, not permission to drop their Work roots or later scheduler
consequences. The [deferred discovery integration](deferred-work-discovery.md)
now retains those roots and validated Union generators. Actual 10k owner reads
fall to nine, but elapsed time does not improve: complete Work reconstruction
and numerical row acquisition remain. Full fixpoint/indexed recognition and
shared/federated qualification remain unfinished.

The [admission-policy index](admission-policy-index.md) now makes already admitted
judgment lookup exact without repeated list scans. This is request-local
bookkeeping, not yet the canonical Work/affected-parent index. Its profiled
remaining bottleneck is graph projection's repeated membership scan and list
append; replace that before layering another cache or placement mechanism over it.

The [stable projection replacement](projection-fold.md) now preserves the complete
projected graph while removing those scans/copies. Controlled disabled-Union
time falls, but normal discovery remains near 9.2 seconds. The next structural
step is still complete canonical Work/affected-parent access and routed original
reads; the projection result does not establish large-scale readiness.

## Judgment

The core is defensible. The current execution architecture is not ready for
growing shared history. Treating an index open as success while materializing
every owner later preserves the dominant cost. Requiring the recommender's whole
ranking to remain identical has also constrained changes that could avoid scans.
Neither requirement is inherent to the separation of recommendation and authority.

The [latest actual 50k pair](lexical-witness.md) delivers original evidence on
the first request, but the numerical lane still times out and continuation
converts a valid empty lexical reply into an incomplete notice. The earlier
resource-stopped run remains recorded. No million-window capacity or token
improvement is established. Do not generate larger DBs on the same unqualified
architecture.

## Simplify around Eggshell's actual unit of reuse

The useful unit is an original observation with its identity and witnesses,
not a complete hydrated Outcome. Distinguish three identities rather than
making them three copies of every payload:

- Verified content identifies shareable bytes within an allowed storage scope.
  An embedding is reusable only for identical actual embedding input and encoder
  contract, including any context that was encoded. Same text without that
  context is not enough. This is sharing, not an equivalence proof.
- A scoped observation retains operation, source fingerprint, original range/item
  and acquisition/provenance. Different occurrences/revisions can point to shared
  content without losing their Exact footprints or freshness obligations.
- A canonical Work class is established by justified Unions/congruence. Indexed
  class identity carries its witness; content equality and synaptic association
  cannot create that identity.

Publish additions/retractions/justified graph changes once as typed source
changes. Derive vector coverage, lexical nominations, typed synaptic adjacency
and canonical recognition from that same feed, each with an explicit covered
boundary. Keep projections separate, not separate capture/rebuild controllers
or chat-owned copies. Compaction preserves original references. DB-only transfer
still retains original facts and can rebuild views without a central service.

At request time, look up certified reuse independently. For recommendation, rank
entry points, follow typed supporting relations toward original observations and
load only selected original ranges/items. Repeated membership of the same
observation is one logical candidate with retained witnesses, not many owners
competing for the delivery budget. Existing original-range canonicalization and
content-keyed vectors are useful foundations; this is not a claim to have just
invented them. Full owner hydration, per-DB repeated projection copies and full
rebuild scheduling still prevent those foundations from paying off at scale.

Three structural experiments distinguish this from merely changing a selector:
adding one unrelated original must not re-embed/reproduce every old vector;
adding another allowed reference to unchanged input must reuse its projection;
and a fixed query's original reads must track admitted ranges and dependency
traversal rather than every stored owner. Measure affected-parent work and
compaction separately: a Union with many affected parents or a broad query can
legitimately require broad work. Token improvement remains an empirical adoption
gate, not a deduction from this cost model or a novelty claim about these ideas.

## Confirmed implementation problems

- `CandidateDomain.open?` decodes one complete payload and creates owner,
  document and Work tables. Accepted owners are then hydrated by discovery.
- The flat `VectorMatrix.open?` decodes the complete directory and builds a
  second index; preparation retains every projected string and contiguous data.
- The reference `requestBackgroundWarm` unconditionally invalidates numerical
  readiness after an incomplete semantic result. The isolated source-delta
  candidate removes that call and entry point, records actual unavailable-input
  repair debt privately, and leaves background re-evaluation to the worker.
  Its share of total native-hook delay is not yet isolated.
- The ready-frame path can extend semantic processing to the upstream deadline.
  Remaining lexical, packing and publication work does not then have a guaranteed
  usable reserve. A transport that emits a notice in time does not solve delivery.
- The scale harness holds its prepared Snapshot/cache while measuring hooks.
  Its own RSS reaches 1,265,360 KiB in the failed run, concurrently with index,
  search and provider processes. Preparation should finish in another process.
- Provider command paths still participate in target registration. The isolated
  source-delta checkpoint now uses model/actual contracts rather than executable
  placement. Obsolete target-registry cleanup remains unfinished.

These are observed structures and control flow. They do not prove a single
exclusive cause of the complete timeout or memory failure.

## One fact store and independent derived indexes

The durable unit should be an original evidence atom: a verified source range,
a structured result item or a bounded original output span. Retain payload
reference, original operation, source/revision, scope, freshness and provenance.
An Outcome can cite many atoms without being their delivery or storage unit.
Windows are embedding views over atoms, not mandatory delivery boundaries.

Share identical verified original bytes within an allowed storage scope. Keep
resource location and historical versions separate. Equality of bytes, identical
paths, co-citation and high cosine scores do not themselves prove equivalent Work.
Canonical Exact footprints and justified Semantic classes determine e-class
membership. Retained observations remain addressable even when not recommended.

All durable capture, including journals and derived answers, must pass trusted
storage policy before writing. External/unknown origin defaults to private;
private data cannot leak through a shared embedding, synapse or receipt. This
policy boundary remains unimplemented and blocks real MCP trials.

## Recommendation: find entry points, then original evidence

Use lexical and vector indexes to find entry points without decoding the corpus.
Traverse typed synaptic relations from those points to supporting observations.
Keep consumed/support witnesses, co-citation and observed later usage distinct;
heuristic association is not an equality proof. Avoid an unconditional closure
over every weak consumption edge.

Plan delivery over original ranges/items with shared provenance costs. Keep
the supporting code when admitting its interpretation, and deduplicate overlapping
ranges under the same original identity. Supply precise versioned locators for
omitted originals, with a direct persisted-byte retrieval operation. Its freshness
and scope checks must be the same as for initial delivery.

Full numerical ranking equality becomes a reference diagnostic, not a blanket
requirement of every recommendation optimization. Approximate/routed candidates
may be evaluated, followed by exact scoring on the selected candidate set. Report
rank differences and missed needed originals before and after synaptic expansion.
Do not claim exact or complete recommendation, or let approximate candidates
limit authority. New routing is unimplemented and unadopted.

SSD-oriented graph search is a relevant primary precedent, not evidence that
Eggshell meets its resource budget: [DiskANN, NeurIPS 2019](https://proceedings.nips.cc/paper_files/paper/2019/hash/09853c7fb1d3f8ee67a61b6bf4a7f8e6-Abstract.html).
Its paper's workload/hardware results are not Eggshell or a 4 GiB measurement.

## Multiple DBs and concurrent publications

Use scoped original references containing DB incarnation and local node/atom
identity. Do not create a global numeric identity table by traversing all source
DAGs on every request. Intern/compare only requested original structures against
scoped canonical indexes, retaining full Exact roles and original byte witnesses.
Federated congruence can depend on Unions from multiple sources; an on-demand
table over recommendation candidates alone cannot establish its completeness.

Pin one publication per source for a request and retain that snapshot tuple in
receipts. A replacement or compaction must not mix original generations. Readers
should not wait for maintenance/write ownership. Serialize publication per DB,
coalesce updates and use one maintenance owner per DB/storage contract, rather
than one per chat or executable path. Different DBs must not share that writer
claim. Acquire any cross-DB maintenance claims in a fixed order or avoid holding
multiple claims; foreground original reads require none.

Keep lexical/vector/synaptic generations tied to source publication and their
actual contracts. Atomically publish readiness only after complete durable data.
Retire obsolete rebuildable generations without deleting retained originals;
in-flight readers use pinned file descriptors or explicit reader leases. A
process exit releases ownership, and interrupted unpublished generations must
be reclaimable. These filesystem guarantees must be validated for the supported
shared-storage adapter; local POSIX tests do not establish distributed/NFS safety.

Across sources, bound total candidate/read work, memory and deadline, rather
than allowing every DB its own full foreground budget. Keep visibility and
private usage signals scoped before merging nominations. The memory budget is
aggregate over the test's active processes, not independently available per DB.

## Shards, buckets, immutable segments and filters

The user specifically suggested these structures. Adopt them where they solve
distinct costs, rather than treat a hash placement scheme as a semantic search.

- **Logical shards/buckets:** scope by DB/visibility, then split bounded key
  regions. Update and compact affected regions without rebuilding every source
  or matrix. A paged directory names the current immutable segments. Stable
  logical bucket identity is separate from physical location.
- **Incremental immutable segments:** append only new/changed facts, index rows
  and projections; background compaction merges bounded runs. Keep reader-pinned
  publications and original provenance intact. The current paged projection
  prototype still rebuilds all projections when one missing key appears, because
  `prepareMatrix` calls `writeUsing` with the complete key list. The later
  incremental component replaces that call with `ensureUsing`: unchanged rows
  are retained, but upstream still supplies full keys and checks their contents.
  The source-change feed and incremental query coverage remain unfinished.
- **Bloom filters:** summarize exact keys or lexical terms per immutable segment
  to avoid negative reads. Bind filters to that same segment/publication. A
  missing/invalid filter cannot establish absence. Hash collisions may add IO;
  build/update rules must not introduce false negatives. A Bloom result cannot
  certify an original observation, grant equality or select semantic neighbors.
- **Placement:** consistent hashing is useful when physical storage targets grow
  or change, with an explicit current placement map. It does not select relevant
  semantic shards, serialize writers or provide snapshot consistency. Single-node
  storage can use the same logical buckets without implementing a distributed
  replication/gossip system prematurely.
- **Semantic routing:** separately use vector/lexical entry-point indexes to
  select search regions, then traverse relevant synapses and fetch original atoms.
  Measure misses after expansion and preserve independent authority completeness.
  Hashing original window keys alone would still require searching all shards.

Keep the routing index's covered source boundary explicit. Merge its base
nominations with all eligible prepared additions through the request's pinned
publication; use lexical/synaptic access and debt for unembedded originals.
This prevents index lag from silently hiding new records, without claiming
complete ANN retrieval. Missing change coverage or a delta cutoff must remain
visible. Refresh/compaction changes physical layout without rewriting unchanged
originals; source deletion and visibility are checked against the pinned source.

Relevant primary precedents are the [Bigtable paper, sections 5.3–6](https://usenix.org/event/osdi06/tech/chang/chang.pdf)
for immutable tables, compaction and negative-read filters, and
[Dynamo, section 4.2](https://www.allthingsdistributed.com/files/amazon-dynamo-sosp2007.pdf)
for consistent-hash placement. These are precedents, not a recommendation to copy
their entire systems or consistency semantics. [Jump consistent hash](https://arxiv.org/abs/1406.2294)
also requires sequential bucket numbering; it is not an automatic choice for
arbitrary target removal. Choose a placement function from actual target churn
and capacity requirements.

## Authority: index the verified equivalence state

Lookup current Work by scoped canonical identity, preserving operator, ordered
roles, Exact references, Semantic classes, persistent Union endpoints and full
affected-parent use lists. Maintain the published congruence state incrementally;
apply local justified Unions with their generation evidence. Recommendation top-K
must not restrict those consequences. Prove the indexed result refines the full
recognition relation and retains original authority and freshness premises.

The authors' [egg explanation](https://blog.sigplan.org/2021/04/06/equality-saturation-with-egg/)
describes congruence representation and amortized invariant maintenance. It is
structural guidance; it does not supply Eggshell's Exact or IO proof obligations.

## Controller: separate deadline, debt and maintenance

Use explicit result categories for useful delivery, semantic cutoff, unavailable
index, corrupt/missing cache rows and obsolete requests. Only observed maintenance
debt may invalidate readiness. A timeout alone must not do so. Persist bounded
debt keyed by source publication and storage/encoder contract; the active runtime
is a service owner, not that contract's identity.

Reserve time for fallback, original validation, packing and publication. A
progress frame cannot consume that reserve. Foreground requests have priority;
background preparation must yield under a shared resource governor. Keep the
4 GiB aggregate limit, bounded caches and separate tool-hook cumulative costs.
Capture/maintenance never embed the whole DB inside a foreground hook.

## Work order and acceptance

1. The streaming/paged storage component has passed its bounded component checks;
   its full-read regression is recorded. Reuse appropriate pieces for immutable
   base/delta segments and incremental buckets, rather than another full-scan
   enlargement. The incremental component now passes the no-old-row-production
   check; connect upstream source changes to delta requests, not a full key scan.
2. Separate preparation from the measured caller; introduce explicit maintenance
   debt and remove timeout-based invalidation without hiding actual corruption.
3. Separate indexed authority from bounded recommendation. Replace full owner
   materialization, prototype clustered routing with delta compensation and
   evaluate synaptic evidence recall. Add conservative block pruning/selection
   reuse only where their dependencies and measured benefit justify them.
4. Close capture privacy and actual lifecycle gates, then resume all-topic,
   both-lap matched comparisons and the paper protocol.

Existing all-rank tests remain useful reference evidence; an intentional routing
change must record its differences instead of falsifying those tests. Preserve
the strong authority boundary, actual original bytes, scope and freshness.
Model-token adoption cannot be inferred from a smaller packet or successful proof.

No finite recommender can know every future reasoning need from a query alone.
The product must both measure initial evidence recall and make misses cheap to
recover from persisted originals. Synaptic links improve the signal; they are
not a theorem that every needed record was selected.
