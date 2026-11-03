# Bounded reuse of complete project source images

Isolated, unadopted continuation of [owned-project-broker](../owned-project-broker/README.md).
The [plan](plan.json) preserves the 80-user/eight-hour, 30-second, 98% actual
original-evidence delivery goal and the separate matched total-token, quality
and deadline product-adoption gate. Ordinary hooks and project-wide derived
preparation are not connected to this original-publication path yet.

## What changed

The service retains a bounded catalogue of complete immutable project cuts.
Concurrent requests for the same absolute project location, immutable manifest
and exact source-head tuple share one validation promise. A ready image is never
substituted for a different requested cut. Invalid inventories, canonical-history
forks and omitted cross-owner dependencies remain errors. A failed builder is
not remembered as an empty or ready source.

`ProjectViews.Catalogue` carries proofs about the actual stored catalogue:
at most 32 resident images and 512 source-handle reservations, including builders
and images held by borrowers. Admission evicts only resolved, idle images. Each
operation receives its own ticket, so releasing an outer borrow cannot evict an
image while an admitted callback is still using it. Close rejects new admission;
existing operations drain before the retained images and pages are released.
These are catalogue bounds, not proofs of total RSS, every transient OS handle,
linear IO, NAS failover or lock-free progress.

Each borrower forks its mutable read counters, trace capture and private cache.
The underlying immutable heads and file handles remain shared. The service uses
one existing `PageMap.PagePool`, with scope, absolute source directory, physical
incarnation, authority and full checked page descriptor in its cache identity.
Its existing bound is 128 MiB of encoded page capacity; decoded heap and other
process memory are measured separately. No additional vector copy, query cache,
B-tree format, ranking rule or delivery budget was introduced.

A group whose requests use the same cut borrows that retained image directly.
Different cuts are joined using already retained readers, with an ancestry check
for every input head and dependency checks on the complete joined inventory.
This avoids opening another collection of source handles while input borrows
already occupy the budget. The original Capsule/cut digest is also computed
outside the common queue gate. Publication still atomically stores the original,
its provenance, dependency frontier and exact retry binding.

## Diagnosis and validation

The [observer](observer.json) measured 325 request-side cut openings and 111
pre-publication openings for the 50 KB fixture. Request-side validation had
118,075 aggregate overlapping ms / 726 ms maximum. Source append also remained
large: 253,145 aggregate ms / 5,528 ms maximum. These sums overlap across workers;
they are not additive wall-clock durations or proof that validation is the only
bottleneck. The common gate spent 1,808 aggregate ms computing request digests.

The [native checks](checks.json) passed:

* 80 concurrent identical requests validated one image and reused it 79 times;
* borrower counters remained independent, old source heads stayed old after
  publication, and released borrows could not be reused;
* the 32-image bound evicted idle images while retaining active ones;
* a separate 33-owner fixture retained 495 handles in 15 active images and
  refused a new 33-handle image until an existing borrower released;
* an operation retained its image even when its outer borrow was released twice;
* retained-image joins, missing/foreign/forked/dependency-omitting cuts and
  shutdown with an active borrower were checked;
* the final drain retained zero images, handles and borrowers.

The check process completed in 8,167 ms with sampled aggregate RSS 124,848 KiB,
without a resource stop or surviving owned process. The malformed-head and
missing-dependency tests intentionally account for the two failed builds in its
statistics. `expired` counts only timeouts after a borrower reservation, not all
admission refusals. Ordinary `ContractAudit` was included in the native builds.
No answering model, real MCP service, numerical preparation or delivery selector
ran in these checks.

## Why the first comparison is diagnostic

The [first twelve cells](closed-loop-comparison.json) preserved all original
observations and canonical WorkGraph digests. Their background reader loop
issued another request whenever the previous one completed. At 50 KB, the parent
therefore processed 95–111 background pins, while the candidate processed
257–359. The offered read work was unequal. The cache reduced request validation,
but its write-wave times cannot be treated as an isolated speed comparison.

A UI interruption also killed the original resource monitor while its detached
controller and workload continued. The old guard JSON is an interrupted, stale
record, not a finished guard. A later monitor was attached; direct process checks
confirmed the controller and its children finished. All twelve semantic censuses
completed, but continuous resource coverage was lost. The [interruption record](interruption.json)
keeps those limitations explicit. Neither the last fast result nor the slower
cells establish product adoption.

The harness now fixes background read work at four requests per wave, planned at
0/250/500/750 ms, with 16 total background requests per arm. Actual start offsets
and latencies are recorded, including lateness if a preceding request is slow.
Both original requests and completed work are fixed independently of response
speed. The complete load-window duration is retained alongside write completion.
A generic Lean launcher now places ResourceGuard itself in a separate OS session,
with a bounded-workload guard still enforcing the same 3.5 GiB stop / 2 GiB disk
floor after the launch tool exits. Launch PID and subsequent live/terminal guard
records are checked; no resource threshold was relaxed.

## Comparison with fixed offered read work

The [final comparison](comparison.json) completed all twelve arms under the
[continuously running detached guard](comparison.guard.json). Both arms used
exactly the same original manifest/head/page bytes, logical absolute path,
generated native observations and common harness. Arm order alternated across
three repetitions per output size. Each arm completed four waves of 80 source
submissions and exactly 16 scheduled background pins. All original-byte,
occurrence, logical-provenance, indexed-history, scope/deadline rejection,
idempotent-retry, graph-union and fresh-process reopen checks passed. The
canonical graph and original-observation digests matched in every pair.

| Output bytes | Parent write waves, three runs (ms) | Candidate write waves, three runs (ms) |
| --- | --- | --- |
| 5,000 | 6,845 / 6,707 / 6,244 | 3,519 / 3,326 / 3,579 |
| 50,000 | 20,649 / 19,493 / 22,060 | 18,117 / 18,197 / 19,288 |

These are sums of write-completion times for 320 submissions, excluding fixture
generation, pins between waves and derived preparation. The [summary](summary.json)
also retains complete load windows and all per-pair maxima. At 5 KB the candidate's
load windows were 3,637–3,840 ms. At 50 KB they equaled the displayed write times.
The 50 KB repetition 1 maximum individual submit **increased** from 5,922 to
6,100 ms, even though that pair's total write-wave time fell. No overall average
or best run hides this tail result. These are source-publication RPC timings,
not UserPromptSubmit/Pre/Post hook latency, p99 or eight-hour capacity.

Request-side validation reused an image 317 times per candidate arm; five valid
cuts were built and one deliberately invalid dependency cut was rejected. Peak
catalogue use was six images / 96 reserved source handles. The [stage metrics](stages.json)
show the eliminated validation/queue work separately from the remaining source
append cost. Aggregate stage milliseconds overlap between workers and are not
summed into wall time. Source append still dominates the large-output path.

The full comparison took 365,738 ms, sampled aggregate RSS peaked at
2,007,936 KiB, no guard fired and no owned process survived. At 50 KB the candidate
handled only about 16.6–17.7 observations/s within the measured write waves,
below the user's maximum assumed 22.2/s **before** numerical/index preparation.
The comparison demonstrates component progress, not sufficient sustained ingest.
It includes controlled native observations, not real MCP servers or full hooks.

The current candidate helper is
`edf1ec8bb8ef5f26e778f74cc5d207047310ad292a0f6b28180d2ec7768cb59a`.
Source/runtime seals, native build records and [patches](candidate.patch) are
retained. Apply `candidate.patch` on `owned-broker-core` with
`git apply --unidiff-zero`; `observer.patch` describes the measured control.
The shared image path uses existing local mutexes and owner leases; this is not
an implementation or proof of lock-free IO.

Ordinary project/config/Pre/Post/Stop routing, policy-approved private ingress,
one project/scope-owned canonical vector/content store, prepared-root cut
alignment, complete cross-owner certification, real MCP/NAS/remote operation,
compaction and growing mixed 80-user work remain. Actual LLVM six-stage 98%
delivery and the matched token/quality/deadline gate are also pending. Answering
model calls remain zero and matched token comparisons remain 0/18. This candidate
is not adopted into the product, README results or a release.

Ended original DBs, private caches and raw driver/compiler logs are deleted after
sealing compact records. No compressed archive is made. Current candidate source,
necessary native objects/interfaces/link responses and the current helper remain;
original/control/selector input hashes are checked before and after deletion.
The interrupted guard record is kept unchanged and explicitly classified by
`interruption.json`, rather than being fabricated into a finished guard.
