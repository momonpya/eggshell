# Architecture

[Project home](../README.md) · [User guide](codex-plugin.md)

Eggshell combines semantic retrieval with a graph of original evidence,
indexed local storage, and dependency-aware calculation reuse. This reference
describes how those parts work together and where their guarantees stop.

## Original evidence is the durable source

Eggshell records work, original tool results, their occurrences, source
observations, and final answers as a graph. Natural language, code, command
output, and documents use the same representation:

```text
Value = Atom(bytes) | Apply(operator, references)
Ref   = Semantic(value) | Exact(value)
```

The relation operators are `All`, `Outcome`, `Occurrence`, `Inquiry`, and
`Receipt`. Roles come from relation position. A parent investigation and its
observed operations remain connected; a prior answer does not replace the tool
evidence that supports it. Interrupted work can expose actual observations
without inventing a completed parent answer.

An authority is a selected memory database. An Inquiry is the current request;
Demand selects the part of its graph needed now. Inquiry-local Union and
saturation work on existing relations while preserving exact provenance.
MiniLM similarity nominates useful context. It cannot certify equality,
complete a task, suppress a tool call, or make a historical explanation
authoritative.

## Page storage and indexes

The configured `.egg` path is a database directory. Its committed `head` points
into an append-only page file. Ordered index pages route point and range reads;
immutable body chunks are at most 4 KiB. Readers pin a head and use its committed
extent, so later publication does not change the bytes they are reading.
Checksums detect corruption; checksum equality alone does not prove that two
bodies are identical.

The writer interns graph nodes and stores body chunks, relation directories,
source records, text surfaces, term indexes, and overlapping search-window
locators. Index and graph changes are published at the same committed boundary.
Normal hook search uses these directories and selected original ranges. Full
materialization remains available for explicit inspection and test oracles;
it is not the candidate-discovery path.

Snapshots have a bounded page cache. Delivery and source-hydration budgets
bound one request's work; they do not limit the number of saved records or
users. They are not a universal latency guarantee: index maintenance and
numerical inference still cost time. Actual hook measurements belong in the
benchmark record.

## Search, graph context, and delivery

1. The indexed candidate directory supplies original owners and window locators.
   Local hybrid ranking combines MiniLM and lexical rankings.
2. The graph admits supporting observations through their original relations.
   Indexed body windows are ranked against the current question **before** the
   finite body-read allowance is spent. Old commands cannot consume the allowance
   merely because they mention the same file.
3. Selected bodies retain original owners and coordinates. The checked numerical
   order can be reused with current-question lexical refinement over the hydrated
   pool. An owner absent from that observation needs an independent observation.
4. Original context ranges compete for the packet budget. Independent conditions
   and results receive coherent context; a whole Outcome need not be sent. A
   related prior explanation can carry conclusions and unavailable-test
   conditions alongside the original evidence. Reachable node count alone does
   not grow the envelope.
5. Receipts acknowledge actual publication. Previously delivered original ranges
   are suppressed without discarding new observations. Compaction changes the
   visible-context boundary so needed evidence can be restored. Associations and
   unfinished past work do not add requirements to the current task.

The fitted packet is preserved before refining its main, meaning-nominated
explanation. Refinement can replace repeated coordinate captions with a compact
form to fit missing original context, while retaining every admitted observation
and its source envelope. It is accepted only if it adds cue coverage and fills
the interior of the selected explanation span; otherwise the original packet is
returned unchanged. This does not require a full source body or alter semantic
eligibility. The complete rendered packet must still fit both byte and character
bounds. Preparing graph identifiers once avoids repeating the same work for
each fitting alternative, with a checked equivalence to the original filter.

The handoff asks the agent to cite checked evidence directly, preserve material
conditions and exceptions, obtain only necessary missing facts, and finish with
a bounded answer when validation is unavailable. A general prior explanation
must not override a conditional original observation.

The installed provider uses
`sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2` on CPU. Window
splitting, lexical scores, rank fusion, source selection, and graph rendering
run in Lean. `runtime/embedding.py` is confined to FastEmbed inference and NumPy
numerical kernels. No LLM generates summaries or organizes memory.

Indexed requests carry locators and query data. When vectors are missing, the
provider requests finite original window positions; the engine checks those
positions and supplies bounded text. Replies name original owners, rankings,
and evidence windows. Invalid replies cannot create source authority or
successful delivery. Cached vectors are disposable acceleration data; model
and text identity are checked before reuse.

`semantic_matcher = false` disables semantic retrieval. A custom executable
provider is accepted only from user-owned global configuration; a project file
cannot silently start an executable. See [the plugin guide](codex-plugin.md).

## Reuse follows actual dependencies

Page readers record point lookups, missing keys, range reads, and immutable
payload references. Negative lookups matter: adding a new matching record must
invalidate a result that previously found nothing. Dependencies reference
original bodies rather than storing another body copy.

Demand memos validate their request, candidate observations, and source
dependencies. Ranking memos retain ordered positions and certify them against
the current complete domain, including counts and frequency ordering.
Saturation memos retain shallow signatures and join instructions; the current
basis checks them again before they enter the quotient producer. Corrections
or deletions cannot import obsolete equality simply because an older memo
exists. Optional cache capacity limits affect acceleration, not saved evidence.

Only demanded computations are refreshed. This does not mean arbitrary
natural-language reasoning can be incrementally maintained or proved
equivalent to an LLM's fresh investigation.

## Source freshness and portable memory

Local file observations retain workspace-relative paths, content fingerprints,
and conditions. Eggshell checks those recorded dependencies in the current
workspace before reuse. Changed or missing files leave the old observation
as history. Confirmed new contents are separate observations; old bodies and
fingerprints are not rewritten to appear current.

An absolute checkout location is not the identity of portable evidence. A
matching file name is insufficient: a remote URL or MCP result is not certified
by checking a similarly named local file. External results retain their source
context; local checks do not prove a remote service's current state. The engine
does not hash the entire repository for each handoff.

Multiple selected authorities can be read through a federated local view with
source and snapshot ownership. Eggshell provides a local engine, not a
hosted organizational authentication, billing, or synchronization service.

## Hook ownership and proof boundaries

Each native chat has its own manager. Search and persistence run independently;
search does not hold session-state or database-writer locks. Tool receipts are
journaled before handoff work. Queue entries are acknowledged only after
successful publication, so a hook deadline does not erase progress. See
[hook lifecycle](hook-lifecycle.md).

Production Lean contracts cover original positions, bounded reads and packets,
source agreement, provenance, cache certification, and publication transitions.
ContractAudit checks the production call graph and permitted Lean axioms.
Process tests exercise interruption, replay, concurrency, and delivery.
Arbitrary LLM answer completeness, model relevance, OS scheduling, and power-loss
behavior are not established by the pure theorems. See
[verified contracts](lean-boundaries.md).

## Implementation entry points

- [Page storage and snapshots](../Eggshell/DB/PageMap.lean)
- [Certified binary codecs](../Eggshell/DB/Wire.lean)
- [Graph storage and search indexes](../Eggshell/GraphStore.lean)
- [Search, supporting graph, and handoff](../Eggshell/Handoff.lean)
- [Demand dependencies](../Eggshell/DemandMemo.lean)
- [Ranking reuse](../Eggshell/RankMemo.lean)
- [Saturation reuse](../Eggshell/SaturationMemo.lean)
- [Local source observations](../Eggshell/SourceObservation.lean)
- [Codex hook lifecycle](../Eggshell/PluginHooks.lean)
- [Executable checks](../TestMain.lean)
