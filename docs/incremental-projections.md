# Incremental projections in the existing authenticated store

This isolated candidate replaces the full-generation projection writer with
append-only payload chunks and copy-on-write directory paths in the existing
PageMap. It adds no storage engine, compatibility reader or manual format
version. Counts and rows commit through one atomic head, eliminating the separate
matrix readiness publication. Scope/model/encoder and actual implementation bytes
select the derived store. Original DBs and authority are unchanged.

`SearchProvider.prepareMatrix` now calls `VectorMatrix.ensureUsing`. Valid old
projections retain their original chunk references. Only missing or damaged
projection payloads invoke the producer; valid rows are not reproduced. Initial
construction retains the previous 64-row leaf buffer and bounded directory
frontier. Incremental updates flush bounded groups through existing COW paths.
An empty request is empty work. Input enumeration/sorting still scales with the
requested key list, and full-key calls still validate every requested payload.

One nonwaiting claim covers creation, checking, suffix recovery and publication
for a root/contract. Readers retain their exact head and descriptor, without
writer ownership. A failed/terminated writer cannot publish its appended suffix;
the next owner recovers only beyond the published extent. Directory corruption
is rejected, not silently converted to missing rows. A damaged payload with an
intact descriptor can be repaired independently. Cached rows can outlive source
membership: this store is numerical hints, not the current source domain.

## Evidence

The Lean source proves row/statistics codec roundtrips, the retained frontier
bound, and preservation of each old row's chunk bytes under append. The last
proof explicitly assumes append-only storage and reuses PageMap's byte equality
theorem; it does not prove arbitrary filesystem behavior. ContractAudit compiles.
The source and final native executables link successfully. Earlier compiler/test
syntax failures are retained as failed guards, not described as passing builds.

Native tests cover 1/63/64/65/1025-row initial construction, a 4096-row base,
full-key and delta-only additions, no-op publication, duplicate input, foreign
contracts, 32 KiB rows, corrupt-payload repair, independent DBs and competing
writers. A subprocess is killed after 64 unpublished additions; its exit 137 is
intentional. The parent verifies old visibility and successful suffix recovery.
The test guard exits zero, peak aggregate RSS 163,472 KiB, no owned survivors.

| Component operation | Requested | Produced | Bytes appended | Operation time |
| --- | ---: | ---: | ---: | ---: |
| Construct base | 4096 | 4096 | 13,497,294 | 1471 ms |
| Add one, passing full keys | 4097 | 1 | 31,216 | 1672 ms |
| Repeat unchanged full keys | 4097 | 0 | 0 | 1678 ms |
| Add one, passing only its key | 1 | 1 | 24,450 | 6 ms |

These are diagnostic component samples, not p99 or full-hook latency. The test
compares the complete old file prefix and all old row descriptors byte-for-byte;
it does not infer preservation from unchanged file size or timestamps.

The real 10k fixture has 19,969 discovery/focus projections. Start with 19,968
audited rows, then call the actual `SearchProvider.prepareMatrix` with all keys:
only the missing row is produced, with 36,581 appended bytes. Old prefix and
references remain unchanged. All 19,969 projected bitstrings and coverage records
equal the independent flat reference; projected data totals 61,344,768 bytes.
The repeat call produces zero rows and appends zero bytes.

The first audit failed because its fallback pointed at the flat-only clean cache
whose raw-vector directory was empty. The corrected audit explicitly names the
original read-only raw cache and resumes the validated 19,968-row base; it is not
a new cold preparation timing. Full-key addition still takes 9264 ms and the
unchanged call 9338 ms. Complete reads take 9522 ms versus flat-reference 5522 ms;
the scan regression remains. Opening takes 2 ms and four statistics-path pages.
The corrected audit guard exits zero, aggregate peak RSS 536,080 KiB, no survivors.

A separate numerical-provider run uses the saved request plus a diagnostic
receipt. Its parsed JSON, including every returned rank/window order, equals the
saved reference. The receipt confirms all 10,000 requested source windows came
through the new matrix, absent/unusable sources zero, and source/query encoding
zero. The encoder model is not loaded. Provider-stage time is 6960 ms; guard time
is 12,438 ms including setup/teardown, aggregate peak RSS 225,776 KiB, exit zero,
no survivors. This is not UserPromptSubmit or an answering-model comparison.

Original 10k/50k DB root files, reference flat files, MiniLM boundary, Handoff,
Matcher, PageMap and WindowCentroid sources are unchanged. The current private
provider cache retains one prepared copy; the identical temporary audit store
and terminal helper executables are removed with hashes recorded, without an
archive. Raw receipts, failure records, source and build inputs remain available.

## Remaining work

The measured saving is avoided projection production/writes, not model tokens.
The full `warm` caller still enumerates and validates the complete requested
window population. Connect publication changes/explicit maintenance debt to
delta keys instead of treating the 6 ms component sample as a fast full warm.
Timeout-only `Warm.invalidate`, background resource competition and per-request
owner/domain hydration also remain. No routed base/delta query, compaction,
cross-DB projection sharing, complete federated recognition or latest 50k useful
delivery is established by this component.

The candidate is unadopted; MiniLM, selector, prompts and recognition semantics
are unchanged. No answering-model calls or seeds were generated. Product adoption
still requires AGENTS.md's matched total-token improvement, quality and deadline
comparisons across all topics and both laps. Phases 0–6 remain active.
