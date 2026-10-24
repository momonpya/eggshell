# Bounded original-point batches

This is an isolated Lean candidate layered on the numerical row-matrix runtime,
not a product adoption or a large-corpus readiness claim. The installed study
runtime and product source remain unchanged. Source copies and the exact patch
are retained under `tools/research/lexical-reads/` and `docs/candidates/`.

## Read only requested keys

The original lexical reader checks three original values per posting entry:
the index's owner ordinal, the source member ordinal and live candidate flag.
Keep all three checks. For up to 512 posting owners, gather at most 1,024 full
source keys and 512 index keys. Group requests by the original B-tree `route`,
visit the selected paths once and build small result tables from checked leaves.
Do not fetch the complete owner/member/candidate namespaces or trust candidate
metadata in place of source membership.

Load and authenticate a page before interpreting its fences, including an
out-of-fence miss. Gap queries use the same selected child as original point
lookup. Keep page errors with each affected key until its logical lookup; a
speculative later error cannot replace an earlier membership or decoding error.
Consume results and perform membership checks in the original posting order.

Speculative reads share the pinned head, handle, bounded page cache and physical
IO counters. Their separate disabled trace cannot add superset dependencies to
a matcher memo. Consumption records the same original point observations in
their original order. A key outside the requested batch is an error, not an
invented absent result. This optimization creates no Match, Union or authority.

The leaf-table theorem proves equality to first full-key lookup, retaining
tombstones; a dependent bound limits batch request keys. There is no complete
formal IO-refinement theorem for the grouped tree traversal. Filesystem and
ordered trace behavior are additionally checked against actual original reads.
The existing ContractAudit passes without a numerical/model/prompt change.

## Actual saved-DB checks

Both 10k and 50k audits use the same pinned source and original lexical sidecar
for the reference and candidate. Twenty-four terms preserve complete ordered
postings and counts. Encoded logical trace bytes, charged size and completion
flags also agree. Common postings can exceed the existing 64 KiB trace allowance;
agreement of an incomplete trace is not a proof of a complete dependency set.

Separate multileaf checks compare 1,024 requested keys, present/deleted/absent
values and complete ordered traces. Oversize requests, unrequested keys and
corrupt roots queried outside their fences are rejected. Five invalid membership
cases preserve original rejection and trace behavior; the valid control passes.
Original source and lexical publication heads remain unchanged.

The single 50k `kernel` posting takes 1,397 ms in the reference and 1,002 ms in
the candidate; other common terms take 802–913 / 649–674 ms. These are sequential
diagnostic pairs with cache/order effects, not a repeatable speedup claim or a
full native hook. Audit peak aggregate RSS is 250,592 KiB at 50k. Runtime build
peaks at 2,858,752 KiB. These build/audit guards exit zero without owned survivors.

The actual native 50k pair on runtime `4231bb2f...` fails. First caller duration
is 31,409 ms including 2,399 ms manager startup (29,010 ms for the hook itself).
Only a 356-byte incomplete notice arrives, with no search result or success ACK.
The next request has no acknowledged history either; it is stopped at 10,319 ms
with exit 137 by the 3.5 GiB aggregate guard. The sampled peak is 3,677,136 KiB,
below the user's 4 GiB ceiling; all owned processes are reaped. This interrupted
request is not an acknowledged-history sample, a normal exit or a passed search.
Raw partial results remain; no final cohort summary exists after the guard kill.

The first receipt accounts for nine posting calls / 399,753 posting rows in
6,832 ms, with batches capped at 1,024 keys. The partial numerical receipt has
12,032 scored windows at 6,300 ms, zero source/query encoding and a query-cache
hit. These stages do not account for the whole caller duration and do not prove
a single exclusive cause. At the resource stop, the harness itself retains
1,265,360 KiB, while search provider, search worker and an index worker are also
resident. Separate preparation from the measured client and account for index
work; do not raise the memory limit or discard this failure to obtain a pass.

## Limits

Only the verification batches have bounded request size. Existing term lookup,
complete posting materialization, all-owner admission/hydration, numerical
transport, candidate-domain opening and matrix-file limits remain. Large common
postings still cost O(P); full numerical ranks still cost O(N*d). This change
does not solve the [growing shared-history problem](growing-shared-history.md).
Keep actual native incomplete/timeout outcomes as failures even if this reader
is faster. Token improvement and quality are unmeasured; no answering model or
new seed is called by these audits.
