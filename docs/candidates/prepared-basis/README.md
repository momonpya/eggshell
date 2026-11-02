# Shared originals and recommendation use one prepared basis

Isolated candidate, not adopted. Baseline `1b82d622…` is unchanged. The
candidate runtime is `e100a32c4bea9e8c694eaf26da818068d24e805e6627422c66487b1c3cc9df98`.
No answering-model or token comparison was run.

## Change

[Product diff](candidate.patch), [predeclared plan](plan.json),
[native driver](../../../tools/research/PreparedBasisTrial.lean).
Apply the diff with `git apply --unidiff-zero` to `prepared-query-core`.

Original preparation already recorded its exact shared-index root, and the
service already retained that root for original bindings. Recommendation
independently opened the latest shared index. A background index publication
could therefore give the query a different graph basis from its original data.
The original-cache readiness check also used the latest supplement stamp to
judge an older immutable prepared view.

- `Cache.boundIndex?` restores the root named by original metadata and checks
  source, implementation and retained extent. `BoundIndex.exactRoot` carries
  the root equality in Lean. Service loading and recommendation share this
  constructor; a claimed canonical view is not paired with a latest index.
- Foreground opening can retain a valid completed view during later indexing.
  Maintenance `ready`/`refresh` separately compare the captured latest basis,
  so an older usable view cannot suppress required catch-up. Preparation
  finishes its captured input; later updates remain debt.
- Resident owner, selection-metadata and file keys use the physical scope,
  database identity/authority, producer and exact owner descriptors. Descriptor
  bytes are encoded, not replaced by a hash-only identity. A new project head
  alone does not rebuild unchanged owners. Key bytes are included in admission
  accounting. `Loaded.namespace_ignores_publication` is kernel checked.
- WorkGraph, vector model/scoring, e-class identity, Union/Exact, certification,
  selection weights and delivery budget are unchanged. Private usage is still
  captured separately and does not enter the shared original cache.

## Native service evidence

[Result](service-trial/result.json), [resource guard](service-trial/native.guard.json).
Four tiny project DBs each contain four actual shell observations covering 16
original source lines. Eighty native clients each read two projects through the
actual publisher TCP/stream RPC. All six phases passed: 480 client requests and
960 project reads, with exact original rows, origins and complete binding sets.

| Phase | p99 of 80 requests |
| --- | ---: |
| Cold service preparation | 1,488 ms |
| Warm reuse | 1,301 ms |
| 48 same-source graph publications | 1,339 ms |
| Graph basis caught up | 1,294 ms |
| Four new original publications | 1,661 ms |
| New original basis caught up | 1,251 ms |

The graph publication span was 0–361 ms while requests were active through
1,340 ms. Original publication/preparation spanned 0–1,030 ms while requests
were active through 1,661 ms. These timestamps verify request overlap; they do
not measure server-side instruction-by-instruction IO interleaving.

Project preparations loaded four, then eight, then twelve immutable views.
Resident original-owner loads stayed at sixteen through graph-only advancement
and increased only to twenty for four new originals. Graph-only catch-up
hydrated zero owners. All requests stayed below 30 seconds. The whole test
took 16,240 ms, peak aggregate RSS was 462,240 KiB, and the publisher exited
normally with no surviving owned process. Original publications here use
direct durable fixture writes, not an 80-writer native save/ACK workload.

The [earlier run](attempts/uninstrumented-overlap-result.json) passed contents
and load counters, but lacked explicit overlap spans. It is retained as a
provisional functional result, not the overlap-latency evidence above.

## Native hook lifecycle

[Result](native-gate/result.json), [recovery](native-gate/recovery.json),
[body audit](native-gate/recall-audit.json), [resource guard](native-gate/native.guard.json).
The actual candidate/MiniLM completed five shell calls and three MCP-shaped
calls through ordinary Pre/Post/Stop and publication/index workers. A source-only
copy with a new private root was warmed and delivered both predeclared required
fixture items to a new chat in 4,500 ms. All session/publication services exited
normally and the guard found no surviving owned process. Peak aggregate RSS
was 1,842,736 KiB. This used no real MCP server and no answering model.

This is a small lifecycle, separate from the 80-client read test. It does not
prove their joint full-hook load, or a speed improvement over the parent.

This is one local-machine TCP run on 64 unique source lines, using no encoder
or answering model. It is not a large DB, hook p99, an eight-hour workload,
multi-host NFS/SMB behavior, real MCP/privacy validation, 98% necessary-evidence
recall, or a total-token improvement. The prescribed matched repeated token
and quality comparison is still required before product adoption.
