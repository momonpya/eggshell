# Independently owned prepared indexes

Isolated candidate, not adopted. The logical DB is still per project. This is
the first runtime step toward the [owned-stream design](../../owned-project-publication.md),
not parallel original publication or an 80-user capacity result.

The parent used a DB-wide `index.guard` for independent derived workspaces.
The candidate requires an explicit canonical, lexical, windows, semantic or
synaptic region. Writers that can touch the same workspace remain in one
region. Descriptor-based ownership admission and lifecycle coordination remain;
this is not a lock-free IO claim. The region names are injective in Lean.
The complete region inventory is also checked in Lean. Private-cache admission
keeps the registration fence until its region lease is acquired; index computation
then releases that fence. Retirement holds every extant region through rename.
An active region blocks retirement, including a region whose source disappears.

Prepared-root registration no longer maintains a separate mutable catalogue
B-tree and head. Each component publishes canonical, checksummed, scope-bound
records in 64 named slots plus `latest`. The source and historical index roots
must still validate. A retry repairs `latest` even when the named record already
exists; ancestry authorizes promotion, never revision numbers alone. Readers
retain pinned original/index snapshots. The two record replacements are not
one transaction, and neither partial publication can certify unfinished work.

Warm prepares lexical and window-owner indexes concurrently. Each task reopens
its own reader of the same exact original head, avoiding shared mutable reader
caches and traces. Both task lifetimes are joined on success and failure.
Canonical and numerical preparation retain their existing ordering.

The [plan](plan.json) was written before execution. Native [checks](checks.json)
cover independent regions overlapping and one-region exclusion, both between
threads and between processes; exact and neutral-source roots; old readers;
partial-publication recovery; no backwards promotion; rejection of bad checksum,
scope, authority, lineage, size and encoding; bounded slot rollover; fresh-process
reopen; and independent original tokenization/window census. All five region
leases, registration/admission fencing, release before retirement and refusal to
resurrect a deleted owner are exercised. Ordinary
`ContractAudit` was included in the native build. These tests use local files,
not SMB/NFS, and do not prove concurrent IO or ownership handover.

The [comparison](comparison.json) uses the same original snapshot per size,
three repetitions, alternating arm order and fresh private derived directories.
Times include the complete lexical/window preparation and ready publication:

| Original owners | Serial parent (ms) | Parallel candidate (ms) |
| --- | --- | --- |
| 64 | 72 / 73 / 72 | 56 / 54 / 53 |
| 1,024 | 1,356 / 1,354 / 1,349 | 1,265 / 1,295 / 1,285 |

All twelve runs matched independently scanned original postings and window
occurrences. Original head/pages digests were unchanged. This is a small
component comparison, not hook latency, p99, necessary-evidence recall,
statistical throughput, token reduction or an adoption result. Answering-model
calls are zero and matched token comparisons remain 0/18.

The [initial comparison](initial-comparison.json) preceded the retirement fix;
it is not pooled with the final comparison. The [initial native capture](failed-native.json)
saved all eight tool observations, but failed final warm: its experimental prefix
omitted the existing MiniLM support link. The staged probe passed journal,
canonical, window, lexical and parallel preparation before failing in the numeric
remainder. This failed run is retained as a setup failure, not relabeled successful.
The Lean fixture now checks numerical support before creating a DB or calling
hooks. The old common-guard assumption in retirement was found separately in
review and fixed before repeating the full component comparison.

The final installed runtime is
`74b7a224ec8765374bbbb5550432b8632a998bf9ca68ce6e4e32c2efc3f36f62`.
Its [native lifecycle](native/result.json) passed five real shell operations and
three MCP-shaped hook pairs, eight saved origins, seventeen journal events,
source-only recovery into a new private root and a fresh-chat read-only recall.
No real MCP server or answering model was used. All sixteen Pre/Post calls
succeeded; the maximum was 2,044 ms. The tiny frozen recall set was
[2/2](native/recall-audit.json), with the [actual body](native/recall-body.txt)
inserted in 4,515 ms. This does not establish LLVM coverage or general 98% recall.
Four managed services exited normally; the guard ended with no owned survivors.
Sampled aggregate RSS for the lifecycle was 1,854,192 KiB. The missing-support
[negative preflight](preflight-rejection.json) rejected the incomplete prefix
before a DB or any hook was started.

The full [resource record](resources.json) retains failed build/setup attempts
alongside the completed checks. The parent runtime and embedding boundary
remained unchanged; the boundary SHA-256 was
`1417508ca8aee8ee45bff632925ff6a23447d0d1a766d1c7411b775bc10a83f4`
in both arms. Apply [candidate.patch](candidate.patch) to the frozen parent core
with `git apply --unidiff-zero`; [benchmark-wrapper.patch](benchmark-wrapper.patch)
changes only the benchmark entry from serial preparation to the real warm helper.
Ended fixture DBs, caches, duplicate executables and raw compiler logs were
[deleted](cleanup.json), without an archive. The current candidate, parent
control, protected original/selector input and necessary native link inputs
were retained with unchanged digests. Deleted fixture DBs cannot now be reopened;
their synthetic construction, results and actual delivered body remain recorded.

The original PageMap writer is still serialized per project. Removing that
constraint requires separately owned physical append locations, complete owner
inventory, dependency-closed original cuts, durable ACKs, safe owner handover
and a complete cross-region certification index. The common-session guard
observed in the previous profile is also not removed by this candidate.
Concurrent original publication, indexing and queries under sustained 80-user
load, actual LLVM delivery and matched token/quality comparisons remain gates.
