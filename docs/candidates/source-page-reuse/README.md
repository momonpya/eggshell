# Measure source reopening before changing shared caching

Diagnostic following `ea4711e8`; **no product candidate adopted**. The retained
owner-binding runtime remains `613e3ba5…`. The diagnostic hook runtime was
`1ce842dcd0a6f76555b951bb06348c5182c998d0ec74f0043761647c33968972`.
Lean controls the native checks, profiling, recording and cleanup.

## What the original-page pool actually removes

ProjectSources.openView already accepts a bounded, scope-separated PageMap pool.
ProjectAccess.reopen does not pass one. A native read-only audit compares that
exact API with and without the existing pool, using the same sixteen original
heads. All six runs materialize identical full graphs, including authority,
revision, roots and persistent Union pairs, and capture identical complete
materialization read traces. Forks keep the exact heads with independent read
counters and traces. Shared readers retain no private decoded-page cache.

| Pair | Isolated open / materialize | Shared open / materialize |
| --- | ---: | ---: |
| 1, first shared fill | 38.00 / 128.25 ms | 25.38 / 103.42 ms |
| 2, shared first | 26.31 / 98.04 ms | 8.30 / 71.24 ms |
| 3, isolated first | 26.14 / 93.59 ms | 8.40 / 71.65 ms |

Opening uses 64 physical page reads/237,823 bytes in every isolated run and
zero in hot shared runs. Full materialization goes from 1,748 reads/1,163,526
bytes to 1,550 reads/477,723 bytes: raw blobs are not the decoded-page cache.
The pool finishes with 198 pages, 198 misses and 28,977 hits under its existing
128 MiB serialized-page allowance. This is not a total RSS bound. Cold shared
filling is separate from reuse, and this materialization oracle is not a hook.

The improvement is real but too small here to identify source reopening as the
explanation for seconds of hook time. **Do not treat this as an eighty-user fix.**

## Actual worker phases

The isolated [diagnostic patch](diagnostic.patch) records metadata/context/source
reopening, staged restoration, Handoff and dependency-checkpoint durations.
It does not change selection, source boundaries, cache behavior, rank, workers,
deadlines, certification or checkpoint contents. The checkpoint callback is
still executed before its diagnostic counter is updated.

| Route/configuration | Cold / running actual hook | Cold / running Handoff |
| --- | ---: | ---: |
| Semantic matcher disabled | 2,376 / 1,440 ms | 582.46 / 380.32 ms |
| Configured MiniLM | 6,679 / 3,907 ms | 4,900.40 / 2,817.64 ms |

Across these four hooks, context opening takes 26.41–36.05 ms. Each calls its
dependency checkpoint once, taking 7.66–8.07 ms. Thus absent checkpoint files at
shutdown do **not** imply no checkpoint work; neither this work nor original
context reopening dominates this observation. All sixteen original snapshots
have sharedPages absent in the actual worker. The lexical worker reads 878
pages/867,374 bytes; meaning reads 7,466/2,890,683. These counters include its
original snapshots only, not every independently restored derived index.

Six actual bodies, including a separate sampled lexical pair, equal retained
parent bodies byte for byte: 13,566 lexical or 88,578 meaning UTF-8 bytes. Both
frozen original fields are present in every body. These are observations of a
two-field fixture, not real98% evidence, quality or a token comparison.

## Narrow the next implementation target

A one-second native sample of the verified live search-worker child contains
OwnerViews.restore → SourceOwners.open? and Recommend.prepareMany →
capturedLocal → PreparedInputs.shared, alongside PageMap loading/decoding and
digest work. Source inspection confirms restoration of sixteen prepared owner
inputs and reopening of shared synapse roots in each query. The existing stack
summarizer misses idle pipe reads in its blocked classifier: its overall
"awake" denominator is invalid for CPU attribution here. Keep the raw sample's
digest and compact summary as diagnostic evidence; do not add overlapping
function weights, infer percentages, or treat weights as wall/CPU time. Sampling
perturbs latency and is excluded from timing comparisons.

The [next change](next-prepared-readers.md) should retain checked **public** owner
and shared-synapse images at their exact complete prepared frame. It must keep
fresh borrower accounting and private usage, rather than cache an entire
request's Prepared object. The original-page pool alone is not the next change.
No unchanged eighty-reader burst or ranking retuning was run in this diagnostic.

The [evidence](evidence.json) keeps source/runtime hashes, guards, graph/trace
comparisons and actual hook receipts. Native builds and controller attempts that
failed are retained too. Initial checker syntax/serialization errors were fixed;
the existing sample summarizer and large-trace recorder needed their Lean heap
allowance set to 1 GiB. The unchanged aggregate guard never fires; peak is
2,847,504 KiB and no owned process survives. Diagnostic source is restored to
its exact parent bytes; ended DBs, caches, builds and raw logs are deleted with
no archives. Original protected files and all sixteen heads stay unchanged.

The goal stays active: eighty-person mixed eight-hour capacity, large/multiple
projects, NAS, p99 below30s, real98% delivery, quality and total-token improvement
remain unmet or unverified. Answering calls are zero; matched paid comparisons
remain **0/18**.
