# Preparation completion and interrupted recovery

Investigation after `1a6630a0`, using its product code unchanged. This is a native
audit without answering-model calls, not a production optimization or token-improvement result.
The [plan](plan.json) fixes the scope and limits before execution. The existing
MiniLM numerical boundary is used; no answering-model call or new Python/Ruby
implementation is involved.

The prior mixed burst ended with numerical work still pending. This audit keeps
the service alive after the same 80-query/80-save workload. It observes the real
queue without adding preparation requests, then checks durable tickets, current
checkpoints and every numerical window. Original responses are independently
materialized and compared as exact JSON atoms, rather than inferred from ACKs.

The unchanged implementation drains in **2,011 ms** after observation begins:
three pending/one active becomes zero/zero. All 80 original JSON responses are
present; all 327 current numerical windows across four write streams are valid,
with missing/invalid/needed all zero. Original heads remain unchanged. Three
conservative `complete` probes remain false because they retain external-freshness
validation; the completed replay/checkpoint audit is a distinct `drained` check.
The audit does not disable or reinterpret those freshness probes.

A new query for a newly stored observation delivers it through completed semantic
search in **2,078 ms**. After a verified clean service exit and restart, a fresh
query delivers the same body in **2,456 ms**, with matching SHA-256. This restarts
the DB service, not the machine or the numerical keeper. The whole guarded burst,
drain, inspections and restart took 31,228 ms; the burst's maximum delivery was
17,860 ms. The whole scenario time is not a single hook's latency. Sampled peak
aggregate RSS was 2,578,304 KiB, with no guard trigger or surviving owned process.

The separate interruption check pauses only known **idle**, service-owned index
workers. Twenty-four additional observations are then durably ACKed in 1,715 ms,
while 24 real tickets and one active/four pending jobs remain. The service is
stopped without resuming that worker. Actual service/worker exit is verified;
normal manager discovery then recovers the durable work after restart. Recovery
takes **22,064 ms**, with 31 jobs and **142 retries**. All 24 exact new responses
survive, original heads are unchanged, and all 423 current numerical windows are
valid. A new native query delivers an interrupted observation via completed
semantic search in **2,724 ms**. The guarded scenario took 34,222 ms, with sampled
aggregate RSS 1,804,384 KiB and no surviving process.

Reissuing those exact 24 saves with preparation paused returns all ACKs in
1,379 ms and leaves 24 real tickets, while original heads remain unchanged.
After another verified stop, normal recovery drains in 4,131 ms (one retry);
all 423 windows remain valid, and the query delivers the interrupted observation
via semantics in 3,006 ms. Its body hash differs from the first interrupted
query: private derived state was not frozen between these checks. This is an
idempotent source/recovery check, not a controlled selection or token comparison.
The test clears retired worker IDs before later cleanup can resume a process.

These results contradict a general failure to persist or finish preparation in
this fixture. They do not justify changing backoff merely because work was still
active at the end of a foreground burst. The recovery's 142 retries need a more
specific explanation: `Journal.importFeed` walks the mixed event count in bounded
slices, then skips indirect references. `feedRequired` uses that same mixed count.
Consequently, adding projected references can create apparent ingress debt even
when the original producer has added no event. A read-only census separates raw
events from aliases under the current preparation authority; its result is
recorded independently from the timing experiment. Of 21 registered ingress
edges, 20 are eligible under the current write/private-cache authority. One old
database-storage grant belongs to a currently read-only project and is excluded
from the active-work totals. A full settled traversal of the eligible feeds has
4,220 rows: 1,055 raw events and 3,165 indirect references. The existing 32-row
bound yields 140 slices; indexing raw events alone would yield 40. These are
snapshot counts and a calculated slice bound, **not measured speedup**. No
eligible feed remains required, and the census changes no private journal head.

The next isolated implementation should maintain original-only ordinal postings
atomically with raw append, leave those postings unchanged on reference import,
and track that original position in the import cursor. It must preserve the same
one-hop references, raw body bytes, scope, retained-head and append-receipt checks.
Prove equivalence to filtering the full journal, then compare against that
independent native oracle, including interleaved references, retries, cursor holes,
forks and interruption. No ranking or retry-weight tuning is supported by this
audit. This original-only feed is planned, not implemented by this commit.

No ranking, selector, WorkGraph, Exact/Union, certification, model, original ACK,
hook deadline or service capacity changed. An optional inspection callback was
added to the research harness. Test-helper compile/layout errors and diagnostic
controller failures are retained in compact negative records. The census requires
the existing native filesystem adapter; a plain interpreter cannot load it.
The aggregate 3,670,016 KiB stop, 4 GiB ceiling and 2 GiB disk floor remain fixed.

This small fixture does not establish 80 people working for eight hours, real MCP
server/privacy policy, NAS/multiple-PC behavior, large-scale ingestion throughput,
98% required-evidence delivery or answering-model quality/token savings. Paid
matched comparisons remain **0/18** and production adoption is unchanged.

Build `tools.research.PreparationDrainChecks` against the recorded parent, with
the imported research entry point renamed to `projectExecutionMain`. Run
`context-prepared-numeric FRESH_ROOT`, `drain ROOT`, then
`interrupt-preparation ROOT` and `interrupt-retry ROOT`, keeping the private data root unchanged. Only one
aggregate guard may own this experiment prefix at a time. The census is compiled
and linked with the parent's native filesystem objects. Ended fixture DBs,
caches, raw logs and superseded executables are deleted after compact evidence
is extracted; no archive is created.
