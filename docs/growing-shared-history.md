# Growing shared history

50,000, 100,000 or 1,000,000 windows are measurement points, not lifetime
capacity requirements. Shared investigation of LLVM, Linux and Android across
revisions can exceed all of them. No current experiment establishes useful
delivery at one million windows. The [latest actual 50k native pair](lexical-witness.md)
delivers original evidence on the first request, but the numerical lane still
times out and continuation converts a valid empty lexical reply into an
incomplete notice. This pair is unqualified; the earlier resource-stopped failure
remains recorded separately.

## Remove a ceiling rather than raise a constant

The current isolated matrix has a 512 MiB row-file limit and a 64 MiB directory
limit. The prepared candidate domain is also a bounded single payload. Raising
these constants would increase allocation and validation cost on every open.
It would not establish a scalable search path within the 4 GiB aggregate budget.

The intended representation is an immutable, paged directory over independently
bounded data blocks. An atomic manifest binds their identities and readiness to
the pinned source and implementation bytes. Readers authenticate pages and rows
as used, keep bounded caches and never materialize the complete directory or
Work/Outcome population merely to open a DB. Publication prepares changes;
derived-only publications do not invalidate the whole original domain.

The first lexical reader experiment follows this principle: batch only the
owner/member/candidate keys named by a posting, at most 1,024 keys per batch,
along the original authenticated B-tree point paths. A full-namespace prefetch
was replaced before qualification because sparse queries must not load every
owner. Postings themselves can still be large; bounded verification does not
make a ubiquitous term's complete posting list constant in time or space.

## Share bytes without confusing versions or authority

Scope persisted node identities by DB incarnation. Separate immutable original
content and embedding keys from resource location, source revision, acquisition
time and the Work's Exact footprint. Identical verified original content can
share stored bytes and embeddings under the same encoder contract. Different
revisions or tenants must not become equal merely because a path, answer or
vector is similar. Such sharing is a storage target, not a currently measured
cross-version reduction ratio.

Shards should follow immutable storage/publication boundaries, not a permanent
maximum window count. Multi-DB queries must retain permissions, source identity,
global ranking/tie behavior and complete recognition. No per-DB top-K shortcut
may discard parents or persistent/local Union consequences needed by authority.
The existing multi-source identity-table construction remains unfinished work.

## Make the unavoidable cost explicit

Keeping today's complete numerical ranking requires scoring every relevant
window: O(N*d). Blocked scans can bound memory and reduce IO/transport overhead;
they cannot guarantee 30 seconds for arbitrarily large N on fixed hardware.
Approximate nearest-neighbor routing or excluding shards changes recommendation
behavior. Either needs an explicitly isolated comparison measuring missed
relevant originals and matched total tokens; it is not a transparent equivalent
optimization. Recognition completeness must remain independent of such routing.

At the global deadline, a warm lexical path should deliver useful originals
when semantic scoring cannot finish. That path must have its own reserved time
and measured large-posting, packing and publication costs. Merely emitting an
incomplete notice within 30 seconds fails delivery. There is no proven deadline
guarantee for arbitrary-size lexical postings either.

## Measure an operating envelope

Keep 50k as the first failing regression point. Then measure increasing scales,
including 100k, 500k, one million and larger when resources allow; report the
first actual failure rather than declare the largest attempted size a capacity
ceiling. Separate unique content, stored windows, vector rows/segments, number
of DBs/revisions, largest posting, update rate and concurrent readers/writers.
Synthetic scale alone does not qualify collaborative multi-revision usage.

Use fixed snapshots and questions, new-chat and acknowledged-history strata,
caller-side deadlines, useful-original receipts, semantic completion/fallback,
aggregate peak RSS, physical reads/bytes, preparation time and disk growth.
The predeclared p99 cohort remains unrun. Keep the 4 GiB aggregate experiment
limit; do not generate million-window DB copies before disk-growth and bounded
preparation are ready. Existing original DBs and raw evidence remain intact.

These are implementation and measurement targets. Product adoption still needs
the matched total-token, quality and deadline conditions in AGENTS.md.
