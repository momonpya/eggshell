# Numerical scoring is not the seconds-long semantic operation

Model-free diagnostic over the same retained sixteen-source project, fixed
focus-locator executable `b887fdbf`, unchanged MiniLM and native hook/ACK path.
Three prime requests and two sixteen-request waves deliver both original fields
in all35 actual outputs. They exactly match already retained bodies; the record
links to those exact body entries instead of copying them. Source heads remain
unchanged. This is not a speed comparison or eighty-request semantic pass.

The request phase includes graph discovery, original hydration, focus,
selection and rendering. Its median is2,132 ms, range1,746–4,399 ms. Calling
that entire duration "vector search time" would misidentify the bottleneck.

| Observation,35 each | Numerical backend score median | Caller score interval median | Entire numerical call median |
| --- | ---: | ---: | ---: |
| keyed discovery,1,205 windows |613 microseconds |138 ms |165 ms |
| focus,1,200 windows |626 microseconds |146 ms |237 ms |

The backend score field does not include query embedding, data preparation,
transport or graph processing. The caller/entire-call intervals include additional
work and waits and must not be conflated with a raw dot-product cost. These
observations support investigating our execution/representation overhead; they
do not establish a universal latency for all vector DBs or workloads.

The existing rendering stage profiles report prepare median26 ms and
service/finish median33 ms. The local selector itself reports median1 ms.
Global time-window profiles are nested and can overlap; their medians must not
be added/subtracted to derive an unexplained remainder. The full70 numerical
counter records and2,583 existing stage observations are retained in the
[evidence](evidence.json). The first aggregation omitted an unexpected purpose
label; deriving labels from the observed records retains both groups. No native
trial was repeated for that recorder correction.

A two-second sample explicitly targets an actual persistent search worker,
not the more CPU-heavy frontend. It reaches federated graph discovery, focus,
source-document restoration, tokenization and source/numerical waits. The
[top-of-stack excerpt](sample-top.txt), original sample digest and sample target
are retained. Thread stack samples include idle event loops and blocking waits;
they are not per-function CPU percentages or complete-request attribution.

The80-way failure recorded earlier still matters:68 requests skip the semantic
phase before execution because the ingress-time semantic cutoff has expired
while queued. The fixed three whole-query pipes hold their lanes across work
and waits. The user's new direction is independently progressing lightweight
workers per active chat over shared public preparation, with the4 GiB ceiling
and original deadlines retained. Do not reset the deadline or increase a fixed
process count to relabel the existing failure.

The [plan](plan.json), [runtime/client identity](identity-before.json),
[guards](guards.json), [native client](../../../tools/research/WorkerCpuProfile.lean)
and [recorder](records.lean) retain diagnostic scope. The diagnostic helper and
ended private data/logs are removed with the
[reader-component cleanup](../session-readers/cleanup.json), without archives.
The parent source is restored; the fixed observed executable is unchanged.
Answering-model calls0; paid comparisons0/18; no product adoption.

For context only, the FAISS maintainers document concurrent CPU-index searches
and batching as supported execution patterns; their different hardware/data
benchmarks are not our measured performance:
[Threads and asynchronous calls](https://github.com/facebookresearch/faiss/wiki/Threads-and-asynchronous-calls).
