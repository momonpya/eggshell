# Streaming paged projections: isolated component

This candidate implements a storage component of the
[breaking architecture](breaking-architecture.md). It is unadopted. It does not
implement routed recommendation, indexed federated recognition or full shared-DB
delivery. The latest actual 50k hook failure remains unresolved.

## Representation and ownership

Replace the flat row file and fully decoded directory with a sealed PageMap
generation. A key lookup traverses authenticated B-tree pages; projected binary64
bytes live in bounded, checksummed blobs. There is no 512 MiB whole-matrix or
64 MiB whole-directory allocation limit. Individual rows remain limited to
32 KiB, and native reads to 4 KiB. The underlying filesystem extent is finite.

The producer supplies one projection at a time. A 64-row leaf buffer and a
frontier with at most 31 references per level bulk-build the tree without copying
a B-tree root path for every insertion. The normal Lean proofs cover the row
codec roundtrip and the frontier bound; they do not prove the entire filesystem
or recommendation algorithm. The input key list is still materialized/sorted;
this is not a constant-memory end-to-end warm implementation. When any required
key is missing, `prepareMatrix` currently rebuilds this entire generation. The
breaking target is incremental immutable segments within logical buckets, not
rebuilding all old projections for each added window.

Each matrix root has an internal non-waiting writer claim. Competing writers fail
before producing a row, while different roots proceed independently. Readers
take no writer claim. Publish readiness only after durable tree publication;
sealed data files are read-only. Current readers retain their immutable file
descriptors when obsolete generation paths are removed. Each row checks its
actual page/blob contents and before/after read-version agreement, permitting
stable old descriptors after unlink rather than comparing their current ctime
to the ctime captured when opened.

Failed producers cannot change readiness. Subsequent exclusive maintenance
reclaims unpublished/obsolete derived generations with the bounded native prune
primitive. No original DB, original observations or reference matrix is removed.
The publication flag lives in IO.Ref so cleanup sees its actual updated state.
No manual format version or old-format compatibility path is added to the
candidate. The flat reader exists only in the independent audit.

## Actual checks

The final native component tests check 1/63/64/65/1023/1024/1025/2049 rows, unique
per-key metadata, all returned projected bits, absent keys, duplicate keys, failed
and wrong-key producers, empty input, foreign encoder/model, corrupt bytes and
32 KiB multichunk rows. They also hold a writer open while a reader and another
DB proceed, reject a second writer before producer execution, preserve a pinned
reader across replacement and reclaim an interrupted generation. Peak aggregate
RSS is 85,712 KiB; guard exit zero, no owned survivors. These are local filesystem
component tests, not distributed storage or full federated-hook qualification.

On the existing 10k source's 19,969 discovery/focus keys, every projected bit and
coverage record agrees with the previously audited flat artifact. Open reads no
directory pages. One pair measures flat directory opening at 387 ms versus paged
opening at 1 ms, but complete reads at 5,981 ms versus 11,089 ms: a regression.
Preparation takes 14,457 ms; total audit guard duration is 37,237 ms, outside any
hook timer. Projected bytes remain 61,344,768; stored tree extent is 68,509,845.
Peak aggregate RSS is 318,560 KiB; guard exit zero, no owned survivors.

A separate numerical-provider invocation uses the saved 10k request. Its complete
JSON, including array/rank/window order, equals the saved reference result. Guard
duration is 12,681 ms including process setup and teardown, peak aggregate RSS
225,504 KiB, exit zero and no owned survivors. This is not UserPromptSubmit,
an answering-model trial, a matched provider timing pair or token improvement.

The final runtime is `376aaf6d...`. Its core build links successfully; the combined
script then fails on a reserved identifier in the new test. The corrected test
and ContractAudit compile in a separate successful guard. Keep both records;
do not describe the failed combined guard as successful.

## What this result changes

Do not advertise a full-scan speedup or enlarge the same all-scan experiment to
50k/millions. The store is a candidate for bounded random access after indexed
entry-point retrieval. Complete scans remain a reference diagnostic, and may
need a separate blocked interface if retained. Measure that interface before
claiming it is faster.

The full key enumeration, all-owner Work admission, federated identity-table
construction, deadline reserve, timeout-based warm invalidation, aggregate
maintenance scheduling and capture privacy remain unfinished. No new seed,
answering model, token-saving claim, README result or product adoption follows.
