# Reuse verified pages across request epochs

The corrected native candidate `6bbbfc68…` preserves the selected parent's
rotating `State.insert` byte-for-byte. Its complete native/source audit and
component checks pass. Three warm primes and every measured client return the
same actual body as the independently audited final-snapshot references: 18/18
fully stored originals, 19/19 including the partially stored item. This is a
fixed-fixture result, not a general recall estimate.

The completed comparison uses the same source snapshot, questions, model
assets, preparation, launch barrier, deadlines and resource limits. The order
is parent/candidate/candidate/parent, with four then sixteen clients per arm.

| Arm | Four-client wave | Sixteen-client wave | Sampled peak RSS (KiB) |
| --- | ---: | ---: | ---: |
| Parent A1 | 6.013 s | 16.091 s | 3,847,920 |
| Candidate B1 | 5.697 s | 14.750 s | 3,973,104 |
| Candidate B2 | 5.690 s | 14.503 s | 4,331,136 |
| Parent A2, recovered | 5.992 s | 15.635 s | 3,974,320 |

All measured clients preserve body bytes, semantic completion, synaptic
completion and delivery ACK. Source files remain unchanged and all four
supervisors exit normally with no owned processes. Mean sixteen-client latency
is descriptively 7.795% lower; only two repetitions per implementation were
measured. The five-second wave target is **not met**. RSS reduction, p99,
inclusive-token improvement, quality preservation and 80-person capacity are
not established. The candidate remains isolated and **not adopted**.

The final parent attempt stopped at the unchanged disk floor during its warm
primes, before a measured wave. A startup-only recovery then refused stale
endpoints left by that forced stop. Both failed attempts are retained and
excluded from performance averages. After retiring ended capacity state,
endpoint PIDs were checked against the stopped supervisor and confirmed dead
before their files were removed. The successful replacement occupies the same
last-parent position, with unchanged inputs and limits; it adds no replicate.
See `resource-recovery.json`, `drained-recovery.json` and the stopped arm records.

Fresh evidence is in `checks-rotating.json`, `native-rotating.json`,
`sources-rotating.json`, `entry-rotating.json`, `rotating-runtime.json` and
`rotating-comparison.json`. Per-arm records were collected before deleting
duplicate sessions/receipts and are never regenerated from missing files.
`checks.json`, `runtime.json` and `core.patch` belong to the rejected prefix
candidate below; `rotating-core.patch` is the current correction.

Isolated Lean candidate over product `dd53c89b…`, not adopted. No answering-model
call, token improvement or 80-person capacity is established.
The [fixed-snapshot parent](../snapshot-scheduling/README.md) finishes 16 clients
in 15.639 s, with all bodies, frozen originals, semantic/synaptic traversal and
ACK correct. Each topic repeats 1,627–1,905 private page misses.

**The first candidate is rejected.** Native SHA `19e6b870…` passes its component
checks, but fails the first real warm prime. Parent A1 completes 4/16 clients
in 5.989/15.431 s with all bodies, semantic/synaptic traversal and ACK correct
(RSS peak 4,094,384 KiB). Candidate B1 stops before its measured 4/16 phases:
the first topic takes 15.420 s, ACK succeeds, the body differs, and synaptic
completion is false. B2 and A2 were not run; there is no completed ABBA or
candidate sixteen-client result.

The candidate's frozen-prefix private front admits no later pages once full.
It records 38,557 misses rather than the parent's roughly 1,700, despite
106,936 immutable-base hits. Full scope/descriptor checks and immutable sharing
do not make that admission policy efficient. The delivered graph owners and
excerpts differ, rather than merely a formatting suffix. Do not adopt or rerun
the same prefix policy. The next change must preserve a rotating hot front;
cache learning cannot prevent the current query from caching its working set.

`rejected-prime.json` binds the actual native stdout and body to its publication
and keeps the counters and incomplete synapse result. Its original-evidence
coverage is **not independently audited**: a separate reused CLI audit input
still referenced the parent's stdout and was rejected. No exit code, timing
record or coverage value was synthesized to make that audit pass. Source files
are unchanged; failed body equality is not reported as zero-percent delivery.

The existing cache already contains decoded, verified pages. The change pools
those values across queries instead of adding another page decoder or skipping
verification. The [corrected patch](rotating-core.patch) touches four modules:

- A reader receives one immutable page base and a private 2 MiB / 512-entry
  rotating front. Base hits do not use a cache owner. Seed pages already in the
  base do not occupy private admission slots. A full front rotates exactly as
  in the parent, admitting later hot pages. New misses use the original backing
  verifier.
- The existing public-reader coordinator consumes returned fronts. It merges
  their already verified entries into its pending cache, skipping duplicates.
  It hands out a new immutable base only after every tracked borrower has
  retired. Every concurrently live borrower therefore sees the same base.
- The operation supervisor resolves the one-shot retirement **after joining
  the search actor and its nested search tasks**. The return contains only
  private entries, not the borrowed base or reader image. Cancellation and
  failed acquisition still retire; a failed reply write cannot strand a lease.
- The base and pending cache each retain at most 31 MiB of encoded charges.
  Together with 32 existing 2 MiB image seeds and one builder they fit the
  original 128 MiB public-page allowance. Private fronts retain the existing
  per-request bound. This is not a proof of whole-process RSS, allocator
  reclamation, OS scheduling, cryptography or network-file-system behavior.

Promotion captures a persistent cache value; it does not scan the DB or build
an arena on each query. Scope, file incarnation and complete page descriptor
still decide every hit. Unchanged append-only pages can be reused after a
publication; changed references must go through the original backing verifier.
Ranking, Exact/Match/Extract, all three advisory edges, original evidence,
deadlines, MiniLM and ACK semantics are unchanged.

The [native component checker](../../../tools/research/QuiescentPagesChecks.lean)
covers a held owner mutex, foreign scopes and descriptors, independent fronts,
pressure, live-epoch stability, quiescent promotion, cancellation/early
retirement, ordinary lookup/read-trace equality and changed publication bytes.
Its proof output and complete product closure must pass before any hook trial.
The predeclared comparison is parent/candidate/candidate/parent, 4 then 16
clients per arm, on one final snapshot with the same three reference bodies.
No 40/80 load or automatic failed-arm retry is permitted on this Mac.

The corrected native component check and its guard are in
`checks-rotating.json`; its source replaces the prefix-pressure law with the
existing encoded-byte bound. The build prints all six proof dependencies;
compiler diagnostics are not separately archived in the corrected receipt.
`native-rotating.json` inspects 324 native project objects.
`sources-rotating.json` has an exact four-module change set, one added checker
and no removed original modules, including approval of changed embedded literal
inputs. `entry-rotating.json` checks that the native entry adds only the checker
command. No product code is taken from the working checkout to fill missing
frozen dependencies.

Build attempts are separate from functional results. The first compilation
rejected a constructor/binder name collision. A subsequent build was stopped
by the unchanged 2 GiB disk floor; it is not a failed retrieval or a successful
build. Obsolete predecessor executables are removed without archives, while
their required native objects/interfaces and current product/controllers and
comparator are preserved. The old stand-alone guard executable is also retired
after verifying no selected native source invokes it.

The research admission helper previously recognized two retired guard paths,
omitting the current fixed-sequence supervisor. It now recognizes the actual
`StudyMain guard` command under this experiment root. A probe against the live
resumed build confirms refusal of another guard; the probe is counted by that
same resource supervisor. This metadata fix changes no product or model harness.

Global limits remain 5,000,000,000 bytes, 4,358,524 KiB RSS stop, 2 GiB disk floor
and the original 30 s hook deadline. Success here would still require separate
growing-project, multi-project, sustained-load, NAS, representative 98% evidence
and matched total-token/quality validation before the full goal is complete.

Cleanup removes 1,013,592,871 logical bytes in 1,757 file/link entries: two
obsolete predecessor executables, one obsolete guard executable, a completed
seed's derived cache and an unaccepted old seed DB. No archive is made. Current
product, two controllers, comparator, accepted seed original files, retained
history and active final-snapshot source hashes remain unchanged. Compiler
objects and source witnesses remain; symlink targets are not followed when
retiring directories. Actual free space differs from logical bytes because
some executables were copy-on-write clones.

Additional cleanup removes the temporary marketplace checkout (84,098,325
logical bytes), the completed isolated build's compiler interfaces (295,915,719
bytes), and ended capacity sessions/ledgers/receipts (335,728,050 bytes).
After collecting the replacement parent, its 23 clients' duplicate state and
receipts are also removed (55,882,659 bytes); actual stdout and collected
measurements remain. `retired-final-arm-state.json` records that cleanup.
The selected product, original DBs, reference bodies, project read-cache
and model assets are preserved. No archive is made. At that stage, the isolated
native executable remained while its compiler interfaces required rebuilding.
See the corresponding `retired-*.json` receipts.

The ended unadopted candidate's build/source, installation and component-check
directories have subsequently been [removed](retired-runtime.json): 1,910 file
entries and 223,232,884 logical bytes, without following symlinks. The saved
patch, proof sources, actual stdout, scalar results and native/source audits
remain; this candidate's former executable path is retired. Protected product,
controllers and comparator hashes were unchanged. Later diagnostic helpers have
their own retirement receipts and are not protected merely by an old path name.

The candidate's sixteen-client cache misses fall to 423–489 per request, but
the wall-time improvement remains about 8%. This experiment does not justify
repeating the same cache policy or claiming the remaining delay is explained.
The next investigation should follow the existing routing/codec profile and
test reuse of prepared typed work-graph data, preserving source scope, full
references, read dependencies and the three advisory edges.
