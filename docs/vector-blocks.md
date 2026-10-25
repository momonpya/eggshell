# Router-aligned original vector blocks

An isolated Lean reader after `5227a18`; not adopted and not connected to the
numerical scorer, normal Warm/provider or native hook. The existing source
encoder, numerical operation, partition, ranking, authority and delivery policy
are unchanged. Product sources, README results and release are unchanged.

On the existing 50k discovery-window fixture, all **99,969 projection rows**
and their coverage metadata match the original matrix byte for byte. The new
publication has 4,096 blocks and writes 335,817,117 bytes in 152,335 ms. A separate
full original-byte audit takes 152,484 ms. Repeated explicit preparation takes
3 ms and writes zero bytes. These are maintenance/audit times, not hook times.

The frozen routed request contains 3,125 keys. Three repetitions were declared
before measurement in AB/BA/AB order. Each method reads the same original heads,
key sequence and values twice. Every returned row and coverage string is checked
against the original hexadecimal reader outside timing. OS caches are not
flushed; each repetition is a fresh process. First means the first pass on these
reader instances, not a fresh-chat/native lifecycle result.

| Repetition | Method order | Original first | Block first | Original repeat | Block resident |
| --- | --- | ---: | ---: | ---: | ---: |
| 0 | original, block | 4,234 ms | 2,727 ms | 1,884 ms | 287 ms |
| 1 | block, original | 4,039 ms | 2,793 ms | 1,921 ms | 302 ms |
| 2 | original, block | 3,343 ms | 2,756 ms | 1,916 ms | 293 ms |

Each first block pass reads/authenticates 128 blocks. Each repeated pass has
3,125 cache hits and zero block reads/hashes. Actual retained raw payload is
9,600,000 bytes in the single 64 MiB cache. This bounds retained cache payload,
not the entire process heap or all separately created cache instances. The next
native integration must pass one shared cache across DB scopes.

Ordinary Lean proves codec roundtrip, append preservation under an explicit
committed-prefix immutability premise, exact slice size and a bound on the sum
of actual retained payload bytes. The append theorem does not cover arbitrary
overwrite of a committed file. The fixture checks new basis unavailability,
atomic replacement, original bits, missing keys, oversized-block non-retention,
old pinned readers and rejection of a wrong block checksum published in a later
head. The cache scope includes the full pinned head, so that later head cannot
reuse the earlier authenticated block. These checks are not an IO refinement
proof of every writer/reader operation.

Every guard is terminal with no owned processes. Maximum aggregate RSS across
builds and measurements is 1,426,464 KiB, below the 3,670,016 KiB guard and
4 GiB user ceiling. Original source/lexical files and the original numerical
boundary are unchanged. Original matrix/router files are also bound by hashes.
The two terminal helper executables were hashed and deleted; sources, objects,
link inputs, raw evidence and the prepared matrix remain. No archive was made.

The complete evidence and file hashes are in
[the candidate record](candidates/vector-blocks-review.json), with
[its check result](candidates/vector-blocks-review.check.json).
The source and reproducibility settings are under
[`tools/research/vector-blocks`](../tools/research/vector-blocks). They depend
on the existing isolated lexical/keyed candidate and are not a product overlay.
The recorded absolute paths identify the exact measured local checkout.

No answering model, new seed or source embedding ran. There is no new inclusive
token, quality, required-history recall, native latency/p99 or million-window
qualification. The matched topics 1–3, both laps, equal repetitions and quality /
deadline adoption conditions still apply. Next connect raw block transport to
the unchanged numerical primitive and native path, then compare data-dependent
routing with frozen full-score references. Incremental segments, compaction,
bounded preparation memory, federation and concurrent shared users remain.


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
