# Numerical access profiling and bounded read routing

These are isolated Lean sources against the accepted-empty candidate pinned in
the review. Copy the module/helper paths into that candidate and compile/link
with its original objects. No ordinary runtime imports the new routing module.
No new Python, answering-model call or seed is used.

`MatrixAccessProbe DB MATRIX-ROOT COUNT NEW-OUTPUT.json` compares each split
read with the unchanged scalar reader and records disjoint access stages. Timed
pure work is passed as a thunk; the earlier reference pass warms the OS cache.

`VectorRouteAudit fixture NEW-OUTPUT` checks tied coordinates, quota, duplicate
input, append invalidation, malformed nodes and old pinned readers.
`VectorRouteAudit DB MATRIX-ROOT SOURCE-COUNT NEW-OUTPUT` builds over **every**
projection key in the pinned matrix, then probes source vectors from the supplied
source. Source-vector self queries are not natural-language recall tests.

`RouteQueryAudit DB MATRIX-ROOT ROUTER-ROOT REFERENCE-RUNTIME NEW-OUTPUT`
compares one frozen synthetic question using the same MiniLM and original
provider. It deliberately supplies no lexical or anchor additions to isolate
numerical routing. Only source-cache state is copied into its private data root.
The routed request filters window keys before the original provider scores them;
returned indices are mapped back to original owner IDs. This is a standalone
component comparison, not production integration or a full native hook.

`RouteScoreGap DB MATRIX-ROOT COMPARISON NEW-OUTPUT` reads the already cached
query embedding and original full vectors. Its independent Lean cosine is a
diagnostic, not a bitwise NumPy-equivalence or answer-quality claim.

The current router reads a bounded number of paged leaves. It retains every
original key in preparation, but online nominations are approximate. A changed
matrix makes it unavailable, rather than yielding a completed empty result.
Incremental routing/delta compensation, replacing existing publications,
natural-language coverage and real controller integration remain unfinished.
