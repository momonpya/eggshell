# Source-scoped routed discovery

Isolated candidate after `eebe301`; not adopted. The product runtime, README
benchmark claims and release are unchanged. Million-window scale is the design
target, not a measured result of this milestone.

## Query path

The native single-DB controller sends a query and the closed original source
scope, not a list of every document, Work or window. The provider opens the
DB-owned routing and reverse-window indexes, chooses bounded vector regions,
joins their original window keys to original owners, and scores those full
original vectors. Lexical postings nominate additional owners. Original source
membership, Work, ordinal and window positions are checked only for selected
admission owners. The normal graph discovery, three synaptic relations and
original freshness checks then consume those nominations.

The source scope includes DB incarnation, authority and the pinned head. A
concurrent append does not move that reader to the newer head. Response sources
are positions in the caller's closed array, never new paths supplied by a
response. Equal local IDs from different DBs remain distinct. Compact scoring
positions are translated back to original window positions before admission.

Router nomination is approximate and advisory. It creates no equality, Match,
Union, freshness certificate or completed result. Complete e-class recognition
remains separate from the bounded recommendation domain. The normal discovery
controller already consumes the e-class owner index; it is not restricted to
the router's candidates. Full numerical scoring is the diagnostic reference,
not the planned million-window foreground path.

Each request shares at most 128 routing leaves across its DBs and query pieces,
and at most 8,192 physical reverse-posting rows across its DBs. Tombstones spend
the row allowance. Truncated and unvisited keys are explicit, as are lexical
window omissions. Full-vector scoring remains unchanged inside the nominated
domain; this does not imply the full corpus ranking is unchanged. In particular,
the historical fixed-question top-eight overlap of zero remains recorded. That
diagnostic has not been rerun for the new native producer and is not a token
result or a required-history recall measurement.

The lexical path still computes complete query postings and global lexical
statistics. Only its selected owners are materialized for numerical scoring.
Common postings can therefore still scale with the corpus. Separate unpublished
staged candidates use their existing bounded scorer, which can nominate up to
another top-K. That differs from the old single combined candidate pool and
requires delivery and token qualification.

The first native connection exposed a quadratic implementation mistake in
lexical rank restoration: every returned position indexed the original linked
list again. A single array directory now restores the same original owners.
`originalOwners_compiled` proves exact equality in ordinary Lean; query terms,
scores, stable order and router allowances are unchanged by this correction.

## Preparation and publication

Explicit/background Warm prepares the reverse-window index with the existing
storage policy and prepares the router after the exact vector-matrix publication.
Read-only sources use their private DB-scoped sidecars. Foreground reads never
build or repair those indexes. Empty sources do not start a provider; unavailable
indexes on nonempty sources are not successful empty results.

The routing manifest binds one exact matrix head. A matrix change makes an old
router unavailable. Explicit refresh atomically replaces both live tree and
manifest, including when a replacement has fewer nodes. Readers that pinned the
old publication retain its old complete point set. Unchanged preparation writes
zero new route bytes. No manual format version or cache-compatibility alias is
introduced.

Routing refresh currently rebuilds its complete tree and its PageMap remains
append-only. Incremental matrix/routing deltas, bounded compaction and large
preparation memory remain unresolved. The reverse-window index already uses
the original publication journal for incremental updates.

## Validation boundary

Ordinary Lean proofs check closed source positions, original reverse-posting
positions, router input permutation and checked nomination quotas. ContractAudit
checks that the actual native controller reaches the scoped client, original
validation and bounded routed scorer, and forbids the old full catalogue in the
new path. These are not proofs of semantic recall, IO-wide refinement or token
improvement.

The component fixture uses two independent DB incarnations with equal local
IDs; checks original positions, foreign sources, forged Work/windows, concurrent
suffixes, empty/unavailable separation; and checks exact-bit routing replacement
from 65 to 66 points while preserving the old pinned reader.

Native scale testing uses the existing read-only synthetic 50k source, its
existing embeddings and the fixed clock question. The owned manager, actual
stdout, publication SHA, ACK, first/continued history, router coverage and
numerical completion are recorded. No answering model, seed or source embedding
is generated. This fixture is not the topics 1–3/both-lap token experiment.

After that foreground-only correction, a fresh manager and chat start again
from the first call. The earlier full warm audits are reused only after binding
their source head and hashes and checking all current preparation contracts with
the product's `Warm.required`. The warm/index/vector implementation did not
change. Earlier elapsed warm times remain explicitly historical preparation
costs, not new foreground measurements.

## This milestone's measurements

The first native connection still timed out in the approximately 14.3-second
semantic allowance. Its first/continued calls returned in 23,297/23,001 ms by
the lexical path. These failed numerical attempts are retained.

After the exact lexical-position correction, the provider-only response is
byte-for-byte identical to that first connection's completed standalone
response. Those single provider probes took 14,296 and 6,940 ms respectively;
they are not replicated paired latency or token experiments.

A fresh actual native first/continued pair then completed semantic search in
both cases. First elapsed, including 1,173 ms of owned-manager startup, was
11,418 ms; continued elapsed was 8,162 ms. The first output contained 9,316 bytes
including original fixture observations, with confirmed stdout SHA and ACK.
Continued output was valid empty/no-new-memory, and acknowledged history stayed
at 12. Certified completed work was zero; semantic search completion is a
separate status. Both calls used an 819-byte scoped request, 128 leaves out of
4,096, 3,125 routed keys and physical reverse rows, and 3,133 nominated owners
out of 49,969. Coverage is approximate; no reverse key or lexical window was
truncated in this fixture. No original-window cache miss or source encoding
occurred.

Initial explicit preparation took 189,387 ms, including 45,039 ms to construct
the router; repeated full preparation took 143,466 ms, with router reuse in
3 ms and zero route bytes written. Source embedding and matrix append counts
were zero. The final foreground-only rerun reused those completed preparation
audits after an actual 23 ms current-contract check, retaining their hashes and
exact source head. These long full-vector preparation checks still need
incremental maintenance.

All original root and lexical hashes are unchanged. The final build,
ContractAudit and component fixture passed. All guards finished with no owned
processes; maximum sampled aggregate RSS was 2,143,744 KiB under the 4 GiB user
ceiling. Four terminal rebuildable experiment executables were hashed and
removed, with source/object/negative evidence retained and no archive created.

Federated native discovery still opens its old global catalogue. The scoped
protocol's multi-DB component fixture does not qualify that product path, shared
multi-process use, million windows, p99, required-history recall, MCP privacy,
quality or inclusive token savings. Those remain adoption obligations.
