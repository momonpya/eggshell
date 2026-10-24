# DB research applied to growing shared memory

Reviewed 2026-10-24, following the user's request to use recent database work.
These are architecture decisions for isolated implementation, not evidence of
product adoption or a completed large-scale hook. Preserve equivalence, vector
and synaptic evidence delivery, multiple DBs and concurrent shared-DB access.
Implementation and proof-bearing control remain in Lean. No additional service,
Python index engine or manual format version is introduced by this decision.

## Primary sources and selected ideas

| Source and date | Verified mechanism | Eggshell adaptation |
| --- | --- | --- |
| [Databricks: NEAREST BY Join](https://www.databricks.com/blog/nearest-join-scaling-vector-search-databricks-runtime), 2026-10-05, engineering article | IVF groups vectors by centroid; files are pruned before reading. Transactional incremental refresh has a compensation branch for additions since refresh. | Prototype clustered vector segments with a small routing directory; merge routed base candidates with every eligible prepared addition since the indexed boundary. |
| [Databricks: Automatic Liquid Clustering](https://www.databricks.com/blog/announcing-automatic-liquid-clustering), 2025-03-05, engineering article | Layout follows observed query patterns and optimization weighs benefit against cost. | Keep stable original identities while changing physical grouping. First record bytes/read amplification and update cost; defer automatic layout tuning until a fixed simple layout has a measured limitation. |
| [Snowflake: Pruning in Snowflake](https://arxiv.org/html/2504.11540v1), 2025-04-15, SIGMOD Companion paper | Partition metadata supports filter pruning and top-k pruning against a running boundary. | Scope/key/term summaries and proved score bounds skip blocks before owner or original-body loading. A centroid's similarity alone is not a conservative upper bound. |
| [Redshift: Predicate Caching](https://cdn.amazon.science/11/0e/3a9288554485b616fa0c99fe4067/predicate-caching-query-driven-secondary-indexing-for-cloud-data-warehouses.pdf), 2024, SIGMOD Companion paper, sections 4.2–4.4 | Cache qualifying row ranges, check visibility during use, scan additions after the cached boundary; physical rewrites invalidate positional entries. | Cache reusable exact-filter/adjacency selection over immutable segment identities. Recheck original membership, source freshness and visibility; handle new facts through a delta rather than invalidating all unchanged work. |
| [LSM-VEC](https://arxiv.org/html/2505.17152v1), 2025-05-22, arXiv preprint | Separates vectors from a mutable disk-based graph; LSM updates and compaction avoid global reconstruction. | Separate immutable vector payload from lexical/synaptic/routing metadata. Use bounded out-of-place updates and compaction. Keep graph ANN as a later alternative if the simpler clustered router fails measured recall/cost. |
| [DynamoDB architecture](https://assets.amazon.science/33/9d/b77f13fe49a798ece85cf3f9be6d/amazon-dynamodb-a-scalable-predictably-performant-and-fully-managed-nosql-database-service.pdf), ATC 2022, and [operating lessons](https://www.amazon.science/blog/lessons-learned-from-10-years-of-dynamodb), 2022 | Routing metadata and partition management handle growth/skew; cache misses must not create a surge of backend work. | Separate logical region identity from placement, split overloaded regions, coalesce maintenance and budget cache-miss work. Retain the reader's publication while background work proceeds. |

The final row is an older architectural foundation, not a newly published paper.
Engineering articles and preprints are identified as such. None of these sources
establishes Eggshell's latency, required-evidence recall or 4 GiB aggregate RSS.
Databricks' NEAREST BY work targets batch throughput: its GEMM batching and
distributed execution results are not measurements of a single Eggshell hook.
The selections below are our design inferences, not claims made by those papers.

## A small design with three distinct concerns

The user's subsequent instruction is to go beyond imitation and simplify around
the core. The [identity and reuse decision](breaking-architecture.md#simplify-around-eggshells-actual-unit-of-reuse)
therefore takes precedence over a list of borrowed algorithms: share original
content and identical embedding input within scope, retain original observation
witnesses, and derive all views from one source-change feed. This is our proposed
composition, not an established research novelty or a measured token improvement.
It must remove redundant work rather than just rename existing canonicalization.

**Facts and publication.** Original evidence atoms have stable, scoped identities.
A paged manifest pins immutable segments, source publication, visibility and
actual encoder/index contracts. Payload blocks hold contiguous rows; the point
directory maps original keys to block offsets. Updating graph metadata must not
rewrite unchanged vectors or original bodies. Reuse the existing authenticated
PageMap and bounded IO instead of building a second general database.
Deduplicate identical embedding input across references within an allowed scope;
different contexts/contracts remain different projections. Shared payload does
not merge Work authority, source versions or private/public storage domains.

**Recommendation.** Start with one clustered vector router, lexical postings and
typed synaptic adjacency. Read ID/score/provenance metadata first. Union those
nominations, expand relevant synapses, then fetch and validate original atoms
selected for delivery. Use one request-wide read, memory and deadline budget
across all DBs. No step should hydrate every Work/Outcome to decide which to read.
The routing directory itself must be paged/hierarchical when it grows; a complete
centroid or segment list in one JSON file would reproduce the current defect.

**Authority.** Independently index canonical Work signatures, justified Unions
and affected-parent use lists. Its completeness cannot depend on which vector
clusters or recommendation owners were visited. Synaptic associations, placement,
Bloom filters and ANN scores never introduce e-class membership or completion.

Logical key buckets bound maintenance/placement. Semantic clusters provide
locality for recommendation. They are separate indexes over the same scoped
original identities. Bloom summaries avoid negative exact-key/term IO. Consistent
hashing can map logical buckets to changing physical targets; it provides neither
semantic routing nor concurrent publication consistency. A single-host deployment
does not need DynamoDB's fleet of services to use these structures.

## Preserve additions while indexes catch up

Record the source boundary covered by each derived index. For a request pinned
at publication P, obtain both the compatible base index and the complete change
interval after its boundary through P. The target recommendation plan is:

```text
visible nominated atoms = current visibility check (
    routed base IDs
  ∪ eligible prepared delta IDs
  ∪ lexical nominations
  ∪ bounded typed synaptic expansion
)
```

Search every prepared delta vector, not only deltas in the old routed clusters.
This avoids an additional loss caused by stale routing, relative to that routed
base plan; it does not make ANN globally complete. Unembedded observations remain
available through lexical/synaptic/original access, with explicit embedding debt.
Foreground hooks do not encode the corpus. A missing change interval or exceeded
delta budget is partial coverage, not proof of no relevant history.

Compaction/refresh absorbs the delta in bounded background work and atomically
replaces the manifest. A new window must not call the producer for all old vector
rows. Publication changes that only add a receipt/memo should not change source
or encoder coverage. Deletions/retractions use the pinned source's visibility;
an old hint may nominate a now-invisible item but cannot deliver it unchecked.

Selection caches apply to deterministic filters/adjacency whose dependencies
are explicit. Natural-language similarity and a cached previous answer do not
establish such an exact predicate. Cache dependencies include scope, segment
identity and relevant synaptic/equivalence publications; compaction cannot reuse
raw row offsets from the retired file. Timeout alone creates no invalidation.

## Lean obligations and executable checks

These are required checks, not proofs already completed by the paged prototype:

1. **Delta coverage:** given a valid publication change interval, every live
   addition appears in the delta branch. Scan cutoffs are explicit partial
   results; no silent gap between the base boundary and the request's publication.
2. **Conservative pruning:** a negative summary excludes no matching key/term;
   a top-k skip has a bound below the retained boundary under the complete order,
   including ties. Missing, corrupt or mismatched summaries cannot establish
   absence. Floating-point bounds require rounding/NaN handling; plain centroid
   scores are insufficient. Approximate routing is reported separately.
3. **Compaction refinement:** every visible point lookup before/after a rewrite
   returns the same original value and authority witness. Old pinned readers
   survive replacement; interruption cannot publish a partly written index.
4. **Scope and authority:** private-derived hints never enter shared outputs;
   indexed recognition equals the specified full equivalence relation, including
   cross-DB consequences and local justified Unions.
5. **Publication consistency:** a request records its per-DB snapshot tuple.
   This is not an atomic transaction across independent DBs. A remote/shared
   adapter needs its own fencing/conditional-publication and reader-retention
   contract; local file locks alone do not prove it.

Start with failure-oriented component checks and the existing immutable inputs:
add one original, add a small batch, repeat with no changes, retract an original,
replace/compact a segment, interrupt publication, change encoder/scope, run two
writers and a pinned reader. Record original-row producer calls and bytes touched,
including unchanged bytes rewritten. A quick readiness open is not that check.
Also repeat a known observation under another allowed reference/DB: record unique
embedding inputs and actual producer executions, and preserve the distinct source
witnesses. Existing per-cache content keys do not establish cross-DB sharing.

Then remove the caller's retained preparation heap and measure complete hooks.
Compare routed nominations, synaptic expansion and actually delivered originals
against the fixed full-scan reference; include multilingual/code queries, stale
indexes, skewed clusters, multiple DBs and active updates. Freeze search knobs
before held-out evaluation. Broad queries can require broad work; no unlimited
corpus/fixed-resource deadline or zero-miss recommendation theorem is claimed.

## Implementation order and present state

1. Implement the manifest/base/delta boundary and incremental segment writes;
   replace `prepareMatrix`'s one-missing-key/full-rebuild path. Introduce typed
   maintenance debt and separate preparation from timed foreground processes.
2. Replace full owner/domain loading with indexed nominations and deferred
   original loading. Prototype the clustered router using the same MiniLM and
   existing numerical boundary, with independent indexed authority.
3. Add conservative block summaries and dependency-bound selection reuse where
   measured reads justify them. Defer learned layout, a second ANN engine,
   quantization and distributed placement machinery until evidence requires them.
4. Qualify native delivery/updates/concurrency and storage privacy, then run the
   matched model comparisons required by AGENTS.md: topics 1/2/3, both laps,
   predetermined equal replications, inclusive input+output (including cached
   input and failed trials), quality and deadline. Record seed cost separately.

Only the [paged projection component](paged-projection-store.md) has been
implemented and checked here. It has a full-read regression and is unadopted.
Incremental deltas, clustering/routing, conservative skip proofs and the complete
shared/federated hook lifecycle are not implemented by that component. The last
actual 50k native hook still fails useful delivery. No answering-model calls or
new seeds were made for this review, and no token improvement is established.
