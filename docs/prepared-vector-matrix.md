# Prepared numerical matrix candidate

This candidate is isolated and unadopted. The model, tokenizer, encoding bytes,
source graph, nomination population, selector, authority and prompt are unchanged.
The existing numerical Python boundary is unchanged; the new persistence,
validation, maintenance and transport control are Lean.

## What is prepared

Explicit/background warm retains the original raw segment caches, then computes
the existing token-weighted window projection once for every distinct discovery
and focus key. A DB sidecar holds one binary64 row file, one bounded key/coverage/
offset/digest directory and atomic readiness metadata. Read-only sources use the
private DB overlay. Original questions are excluded; query hints remain private.

This first step deliberately preserves every projected binary64 bit. The current
NumPy boundary performs its existing float32 conversion and independent dot
products. Neither packed float32 storage nor mmap/native matrix scoring is
implemented here. Raw one-window cache files remain for maintenance and recovery;
the ready search path avoids opening them individually.

One checked directory and one regular-file descriptor serve the search. Each row
is bounded, checked against its digest and descriptor version, and decoded to the
same prior packed input. Coverage is retained unchanged. Absent or invalid rows
use the original hints, without repairing/encoding the DB in the hook. Readiness
is a scheduling hint, not authority. The implementation and projection source
bytes determine readiness, without a manual format version.

Scoring transport batches up to 256 windows instead of 32, preserving their exact
document/position order. This is separate from the unchanged 32-segment inference
batch and bounded cold-repair policy. NumPy still computes each original dot
product independently; batching does not introduce another reduction kernel.

The directory codec has an ordinary Lean roundtrip theorem. It is not a proof of
filesystem integrity, cryptographic collision resistance, ranking equivalence or
the correctness of external numerical IO. Those boundaries need actual checks.
The file limits are 512 MiB of row data and 64 MiB of directory data.

## Actual diagnostic results

Both providers use the same saved read-only 10k source, fixed question, existing
query cache and complete ordered document population. All 19,969 discovery/focus
keys have bit-identical projections and coverage. Complete provider JSON agrees,
including thresholds, full rank order and every returned window position.
Corrupt matrix rows and foreign model/encoder identities are rejected; unchanged
maintenance reuses the matrix. Source publication is unchanged.

| Candidate / diagnostic | Reference provider | Candidate provider |
| --- | ---: | ---: |
| Initial row matrix, 32-window transport | 6,150 ms | 7,790 ms |
| Row matrix, 256-window transport | 6,440 ms | 6,345 ms |
| 50k row matrix, 256-window transport | 28,844 ms | 19,127 ms |

These single pairs do not establish a speedup. The initial candidate's isolated
row-read/projection loop decreased from 8,886 to 5,588 ms for 19,969 keys, while
the complete provider got slower. A separate instrumented initial-provider run
used all 10,000 matrix rows, zero source/query encoding, and two directory probes;
it spent 2,921 ms in cache work and 2,689 ms in scoring transport versus 41,274 us
in the actual numerical score kernel. Microbenchmarks cannot replace the full
provider or native hook.

At 50k, all 99,969 discovery/focus keys also have identical projected bits and
coverage; the complete provider output agrees with its same-source reference.
The row file is 307,104,768 bytes and the directory 33,401,643 bytes. Total
preparation takes 69,272 ms, of which 23,580 ms is writing/packing; the latter
must not be advertised as total warm time. Revalidation/reuse takes 31,983 ms.
The full audit guard peaks at 2,703,120 KiB, exits zero and leaves no owned
process. This single provider pair remains separate from native-hook latency.

The first real native 10k diagnostic returned original bytes in 16,394 ms and
an acknowledged empty continuation in 15,542 ms. Its first body SHA remains
`5c7a5f72c607710135747e78c438e89e9eb86351fb1fbf8df43772277a8cb264`.
It also exposed unrelated old installation-wide index targets, including
read-only and retired-runtime jobs. Those warnings remain in the raw record;
this is not a clean performance comparison or a claim of healthy maintenance.

The final runtime `fe42fadb...`, with no old jobs in its private root, completes
the native 10k first/continued pair in 15,955/14,872 ms. Both searches complete
semantically, the first original body has the same hash above, and continued
history retains 23 acknowledged graphs without resending them. Preparation and
repeat preparation request zero encodings, cover all 19,969 keys with zero
missing/invalid, and take 16,899/16,123 ms outside hook timing. The guard exits
zero, no owned survivors, peak aggregate RSS 1,299,232 KiB. This remains a
diagnostic pair, not the predefined p99 cohort or a matched token comparison.

A fresh private input root contains hash-checked copies of only the active
read-cache and query hints, with no sessions, receipts or registered index jobs.
It is an active experiment input, not an archive. Subsequent scale checks use
that state and retain all incomplete/timeout outcomes. No new answering-model
call, seed, token improvement or quality/adoption result follows from these
numerical checks. The required p99 cohort has not run.

Matrix readiness originally had an empty-DB scheduling bug: there are no rows
to prepare, so requiring a nonempty matrix would keep rescheduling maintenance.
The final runtime accepts a completed empty-source checkpoint. An actual empty
DB settles in 12 ms, repeats in 3 ms, requests zero encodings and reports no
further required warm work. ContractAudit passes. This empty-source correction
does not change nonempty numerical ranking; its latest full-hook results must
still be recorded separately from the preceding runtime's provider pair.

## Actual 50k native failure and boundary diagnosis

The final runtime's clean 50k first/next attempts take 29,454/29,011 ms and both
return only a 356-byte SEARCH INCOMPLETE notice. There is no original body,
current search result or successful delivery ACK. The next attempt still has
zero delivery history, so it does not qualify the acknowledged-history stratum.
Both failures remain in the cohort rather than being discarded by a receipt's
`validStratum=false`. The guard exits zero, no survivors, peak 3,228,928 KiB.
Explicit/repeated preparation takes 152,800/113,442 ms, requests zero encodings,
and validates all 99,969 keys with missing/invalid zero, outside hook timing.

The terminal dispatch records report timeout waiting for `state.guard`, while
the native transport reports an expired receive deadline. Partial numerical
receipts show only about 10k scored windows; these are not full-score timings.
The latest provider separately completes with JSON equal to the reference
(its CLI adds one framing newline). Provider completion does not establish
successful native delivery.

A separate owned live diagnostic, without the large preparation helper heap,
still fails. Its 8-second worker sample is in
`indexedSemanticNominationsUsing -> RetrievalResearch.Index.Reader.posting ->
PageMap.Snapshot.get`. The reader performs an index-owner, source-member and
source-candidate point lookup for every posting. The manager is awaiting search,
and no state-lock owner was shown at that sample point. Thus a short partial
numerical duration cannot be described as a stalled numerical kernel: expensive
lexical work precedes it. A later terminal state-lock timeout remains a separate
observation; the early sample does not identify its lock holder.

A second diagnostic samples the manager at 20 seconds. It too is waiting for
search, with no state-lock owner observed. `Persistence.acquireLockUntil` checks
expiry before trying the lock, so its terminal "timed out waiting" message alone
does not establish lock contention. This is an unresolved deadline boundary,
not proof of a lock deadlock. Both diagnostic supervisors stop their owned
managers successfully and leave no owned process.

The next change must batch the original membership/owner reads and preserve
complete ordered postings and all live-membership checks. Merely dropping those
checks, trusting nomination metadata as authority, pruning the corpus or raising
the hook deadline would not establish the required result.

## What remains

Successful native 50k delivery, complete Work admission and owner hydration,
packed numerical transport, authority-index completeness, incremental warm,
privacy before MCP capture and bounded historical-page growth remain separate
gates. A matrix file alone does not remove these costs. Only matched inclusive
token improvement with preserved quality/deadlines permits product adoption.
