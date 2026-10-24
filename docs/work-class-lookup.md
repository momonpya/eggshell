# Original Work-class lookup

This isolated Lean component composes existing machinery: current Union
generators → complete text aliases → original Work-owner buckets → original
live Outcome frames. It adds no DB catalogue, format version or recommendation
top-K limit. Source copies are in `tools/research/work-class-lookup/`; hashes and
raw records are in [the review](candidates/work-class-lookup-review.json).

## Proven boundary

`Prepared` contains the generated closure of today's persistent and run-local
edges with **no corpus roots**, plus its inverse alias table. It reuses
`build_complete_atoms`, which covers mixed Atom/Apply and recursive edges.
Structured intermediate aliases can connect text Works; the final lookup
retains textual Works, matching the existing candidate compiler.

Ordinary Lean proves `member_iff` (exactly generated equivalence), `full_iff`
(agreement with arbitrary corpus-rooted closures), and `select_full` (the
complete original ordered owner filter, including duplicate Work owners).
Typed returned owners carry generated equality and preserve Exact footprints.
All five declarations pass an axiom audit allowing only `propext`,
`Classical.choice` and `Quot.sound`. These are class/selection proofs, not a
filesystem-IO refinement proof or unconditional permission to reuse an Outcome.
Original child membership, result grounding, freshness, scope and extraction
remain necessary.

## Original source access

`NodeReader.classOwners` resolves the class's Work values with `findNode?`, then
reads existing `searchWork` buckets through `supportDocuments`. That reader checks
indexed population, original live headers and insertion order. Only those owners
are hydrated; their original Work values must still satisfy today's quotient.
No search windows, other Work bodies or derived owner claims are read.
`NodeReaders.classOwners` queries a pinned source array and attaches each source
number. Equal local IDs and ordinals remain separate. It does not construct
`Federated.prepare`'s complete semantic-membership catalogue.

Preparation depends on generating edges/subterms, not unrelated stored Works.
Probe cost depends on class size, source count, B-tree height and returned bytes.
A class with many owners still has a large output, currently materialized by
this API. Streaming/cursor compensation remains future work. No constant total
latency or bounded cost for arbitrary generators/output is claimed.

## Fixed-source checks

Thirteen small checks cover duplicate Work owners, mixed congruence, unmentioned
positive/negative atoms, local-edge removal, removal of persistent generators,
Exact fingerprint separation, two pinned DBs, live-owner retirement and the old
snapshot's continued validity. These are generated fixtures, not new seeds.

Existing 10k/50k publications were opened read-only. A separate complete original
Work scan and corpus-rooted closure supply each oracle, outside query timing.
Each source runs 20 literal, 20 run-local-alias and 20 negative probes, all with
fresh pinned page/node readers. Positive cases return one original owner.
All 120 results agree with the ordered oracle. Original head/pages/writer hashes
agree with the preceding checkpoint.

| Source windows | Probe | Median ms | Maximum ms | Page reads | Owners |
| --- | --- | ---: | ---: | ---: | ---: |
| 10,000 | Literal | 25.546 | 29.395 | 51 | 1 |
| 10,000 | Run-local alias | 24.783 | 27.466 | 51 | 1 |
| 10,000 | Absent | 3.822 | 4.958 | 8 | 0 |
| 50,000 | Literal | 28.759 | 39.332 | 67 | 1 |
| 50,000 | Run-local alias | 28.673 | 30.604 | 67 | 1 |
| 50,000 | Absent | 5.309 | 6.637 | 11 | 0 |

Median is the lower middle of 20 observations. OS cache is not flushed; the
complete oracle ran first. These are class probes, **not end-to-end hooks, model
calls, p99 estimates or a speedup comparison**. Rootless preparation took 6/9 us
with one local generator; no large persistent closure was measured. Guarded
runs including oracle construction took 6.544/22.361 s. Maximum aggregate RSS
across builds/tests was 2,022,464 KiB, below the 3.5 GiB guard and 4 GiB ceiling.
All guards/owned children finished. An initial proof failed because an implicit
edge-list binder was not tied to `Prepared`; the corrected proof and subsequent
builds/checks passed. The failure is retained.

## Integration limit

This section records this component's original boundary. The subsequent
[structural Work candidate](structural-work.md) now connects generated identity
to normal discovery and a positive native entry, with original owner, child,
freshness and extraction checks. Broad all-Work inference and the 50k hook
failure remain unresolved.

The component executes against original DBs but is not connected to normal
discovery. That controller combines structural equality with query-dependent
partial-text Union inference and still restores broad Work postings.
`Matcher.admittedCandidates` accepts literal surface overlap or external
nomination. `findIn_no_surface_admissions` explicitly proves that no shared
surface yields no matches even when a quotient knows an alias. Adding an owner
index alone therefore cannot replace that controller.

The next structural producer must consume generated equality directly, retain
original child/freshness/extraction boundaries, and separate partial-text
inference. Do not manufacture literal `Coverage` for different spellings, mark
equality as retrieval, or silently drop query-local generators. This is a
representation boundary, not another score adjustment.

No new Python, answering models, seed calls, token measurements, product runtime
replacement, README performance claim or release adoption occurred. The prior
50k native-hook failure remains unresolved. AGENTS.md still requires matched
inclusive token improvement, quality and deadline qualification before adoption.

## Research used selectively

[Relational E-Matching (POPL 2022)](https://arxiv.org/abs/2108.02290) motivates
expressing structural matching as indexed relational joins. This executable
join is just class → Work → owner; a general join planner is unnecessary for
that relation. This is an application, not a new worst-case-optimal algorithm
or a claimed novel research result.

The [EGRAPHS 2026 Sundance report](https://pldi26.sigplan.org/details/egraphs-2026-papers/10/Relational-E-matching-in-an-SMT-solver)
reports a synthetic median speedup and a Verus median slowdown. It supports
measuring this workload instead of assuming automatic gains.
[Databricks' workload-driven clustering](https://www.databricks.com/blog/announcing-automatic-liquid-clustering)
is a later physical-layout idea; it cannot by itself remove the logical all-Work
dependency. Bloom routing, sharding and layout adaptation remain separate
decisions after exact keys and query scope are fixed.
