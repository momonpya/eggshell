# Original-window reverse nominations

This is an isolated Lean candidate after `ab59573`. It is not integrated into
Warm, the numerical wire protocol, or the native delivery hook, and is not
adopted. The active product runtime and README benchmark claims are unchanged.

The core suggests a narrower design than copying a distributed database:
e-classes establish reuse authority, vectors nominate where to look, and the
three synaptic relations carry evidence dependencies. Original records are read
when those nominations are consumed. Physical placement and negative filters
can be added where measured costs justify them; they cannot provide missing
semantic relationships or reuse authority.

The previous router returned window digests but still filtered an entire
document catalogue to find their owners. `WindowOwners` removes that dependency
with one DB-owned PageMap reverse index. Each posting retains the original owner,
Work, membership ordinal and window position. It contains no copied source text,
chat identity, equality certificate, Union or completed result. Repeated content
shares a window key while retaining each distinct original occurrence.

## Preparation and updates

Explicit preparation enumerates original checked `searchWindows` directories
once, sorts postings and bulk-builds bounded pages. The manifest and postings
publish under one atomic PageMap head. The tested read-only source uses the
private sidecar keyed by DB incarnation. Storage selection is explicit; its
Warm caller still needs the existing profile-based destination policy. The
original graph and its lexical indexes are not written.

Later preparation replays the existing authenticated source-publication chain.
For each changed owner it reads the old windows at the saved source head and
the live windows at the new head, retracts the former and inserts the latter.
This needs no second owner-to-window directory and no catalogue scan for an
available delta. Neutral publications update only the coverage basis. A missing,
divergent or bounded-out journal requires explicit full preparation; it does not
mean there were no changes. Query-time reads never rebuild this index.

Opening checks the source stamp. A different head with the same stamp must also
have a checked neutral publication chain. Missing or changed coverage is
unavailable, distinct from a completed empty lookup. Existing descriptor locks
serialize writers per DB; readers keep their pinned head and do not acquire that
writer claim.

## Bounded recommendation work

Lookup accepts at most 4,096 distinct window keys and 8,192 physical posting
rows. Traversal stops at the allowance rather than scanning the remaining
fanout. Tombstones also spend that allowance. Unvisited or truncated keys are
reported in `partialKeys`, never silently certified absent. There is currently
no continuation API for the truncated fanout.

The optional original resolver checks live owner membership, Work, original
ordinal and the digest at each original window position. It does not assert
external-file freshness or original-text delivery: those remain obligations of
the delivery producer. A native producer should defer these original checks to
the owners actually consumed, rather than eagerly validate every numerical hint.
The benchmark below intentionally validates all 3,125 nominated owners.

Normal Lean proofs cover posting soundness/completeness for every original
position, preservation of distinct positions sharing content, codec roundtrip,
the actual leaf operation's physical-row accounting, and the checked total
lookup bound. They are not an IO refinement proof of the complete persisted
index. The complete original enumeration is therefore also checked against the
stored index.

## Evidence

The existing read-only 50k fixture has 49,969 owners and 50,000 discovery-window
occurrences. Preparation took 14,221 ms and wrote 4,568,129 bytes; the committed
index extent is 4,568,144 bytes. Immediate preparation again took 4 ms, wrote
zero bytes and generated no source embeddings.

An offline audit queried all 50,000 occurrences in 25 bounded batches and
matched every original owner, Work, ordinal and position. The sorted original
and indexed occurrence digests both are
`cb995bd6fc1b2ddfc0bec98496f35f8265e54ed2ec46159410270ed6ef5f3941`.
Its lookup phase took 1,021 ms after original enumeration; this is an offline
audit with warmed caches, not foreground latency.

The fixed 3,125 discovery keys from the preceding router diagnostic were used
for three declared repetitions in fresh processes. No answering model, seed,
query embedding, source embedding or numerical scoring ran in this milestone.
OS caches were not flushed.

| Repetition | Index open | Reverse lookup | Original validation | Total |
| --- | ---: | ---: | ---: | ---: |
| 1 | 11 ms | 580 ms | 2,437 ms | 3,028 ms |
| 2 | 9 ms | 583 ms | 2,347 ms | 2,939 ms |
| 3 | 7 ms | 521 ms | 1,972 ms | 2,500 ms |

Every run retained all 3,125 original owners. No original candidate directory
was scanned. The product's normal 64 KiB memo-read trace overflows on this many
owners; it was not enlarged or treated as complete. A separate, untimed audit
checked the actual resolver for each of the 3,125 owners. Every segment was
complete, contained no original range scan and used at most 547 encoded bytes.
That audit took 0.8–0.9 seconds per run and is excluded from the table.

The 70-owner fixture checks a full original oracle, neutral/add/remove updates,
unavailable versus absent, invalid/duplicate/excess requests, invented positions,
withdrawn owners, malformed postings, old pinned readers, writer contention and
separate DBs with equal local IDs. A one-row lookup into the shared high-fanout
key reads only two uncached index pages and reports partial coverage. A new DB
can prepare while the other DB's writer claim is held. These are component
checks, not shared multi-process native delivery qualification.

All final guards finished with no owned processes left. Maximum sampled
aggregate RSS across this milestone's guards was 1,443,392 KiB under the
3,670,016 KiB guard and 4 GiB user ceiling. Original root and lexical file hashes
are unchanged. Earlier compiler failures, the first overflowing trace audit,
and a mistakenly dispatched fixture using the older helper are retained and
excluded from final evidence. The terminal helper executable is removed after
hashing; no archive is created.

## Remaining work

This index is the missing reverse-address relation, not a claim that the current
approximate router finds needed evidence. Its previous diagnostic top-eight
overlap of zero remains unchanged and explicit. Neither ranking overlap nor
this address-index audit substitutes for required-original delivery or token
qualification.

Next connect a closed DB-scoped keyed request to the numerical provider and
native producer, remove the full document catalogue from that path, and retain
lexical and synaptic nominations, complete e-class recognition, original
membership and freshness checks. Integrate incremental preparation, matrix
delta compensation and routing replacement before growing/shared use. Initial
index sorting still uses O(N) preparation memory; journal limits and a complete
rebuild path remain. Million-scale, p99, MCP privacy, native lifecycle, all-topic
and both-lap matched total-token/quality comparisons are unqualified.

Sources and exact local artifacts are bound by
`docs/candidates/window-owner-review.json`; its checker is recorded beside it.
