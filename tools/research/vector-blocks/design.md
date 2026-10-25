# Routed vector blocks before changing partitions

The active direction remains routed discovery, not an all-corpus foreground
scan. Dense reading is shared infrastructure for routed scoring and the exact
diagnostic reference. Core policy, extraction, storage and validation stay Lean.
This component introduces no Python, encoder change or source embedding.

Each routing leaf's original binary64 rows form one contiguous authenticated
block. All blocks form one dense byte region in the same PageMap publication,
followed by the key/block directories. A manifest binds the exact original
matrix and route heads. There is no file per row or per block and no manual
format version. Original numerical values and coverage metadata are preserved.

Readers validate a block once while its immutable bytes remain resident in a
shared cache. Ordinary Lean bounds actual retained bytes across DB scopes and
also limits entry count. A change in basis is unavailable until explicit atomic
replacement; older pinned readers retain their old committed regions. Cache
capacity pressure can evict resident blocks, so validation is not promised once
forever or once for every DB in a daemon's lifetime.

The current component still uses point directory lookups. Scorer transport is
not connected yet; it must consume raw rows without reintroducing hex encoding
or changing the numerical operation. Preparation currently rewrites the whole
dense region after a basis change. Incremental segments and compaction remain.

## Partition and stopping policy to evaluate later

Adopt the IVF separation of coarse routing and storage/scanning of selected
lists, rather than importing a whole database or ANN package. Faiss exposes
training independently of list storage, probe count, a visit allowance and
preassigned scanning: [official IndexIVF API](https://faiss.ai/cpp_api/file/IndexIVF_8h.html).
Training and placement are explicit preparation work. New records need checked
delta segments; an old router is not valid coverage of a new matrix.

Data-dependent partitions and safe upper bounds are separate requirements.
Tree-based maximum-inner-product branch-and-bound provides the relevant bound
framework: [Ram and Gray](https://arxiv.org/abs/1202.6101). A center/radius ball is
a simpler first bound than assuming perfectly normalized vectors in an angular
cap. The bound has to cover the values actually used by the scoring primitive.

Current scores cast stored binary64 projections to float32 and use per-row
NumPy dot products, then maximum query/window evidence and hybrid reciprocal
rank fusion. Therefore geometric real-number bounds alone do not certify the
current final owner order. Norms, rounding, same-score tie order, duplicate
window owners, multiple query windows and truncated reverse postings must all
be covered. A certificate for numerical top-K is also not automatically a
certificate for the hybrid ranking or the selected delivery body.

Until those conditions are checked, report approximate coverage and unvisited
bounds as diagnostics. A budget cutoff remains approximate. Retain exact full
scoring on frozen 10k/50k inputs to measure recall and independent bound safety.
Do not tune to the single historical question or call a high score useful
memory without checking required original evidence.

The 2025 [PSP paper](https://www.vldb.org/pvldb/vol18/p1770-ke.pdf) is an alternative
graph-based MIPS reference. It does not justify adding another graph now: first
measure the new block path and data-dependent partition against the existing
graph/vector/synapse core and matched adoption gates.

The missing million-and-beyond story is still explicit: incremental routing,
bounded preparation memory, segment placement, compaction, native federation,
shared concurrent users and measured recall/latency/resource limits. No claim
that centroid routing alone solves these is made.
