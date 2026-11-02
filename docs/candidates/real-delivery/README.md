# Retained LLVM source: full-hook diagnosis

Isolated, model-free diagnostic. [Plan](plan.json),
[reference ranges](references.json),
[Lean driver](../../../tools/research/RealDeliveryProbe.lean).
The runtime remains `e100a32c…`; its product sources and numerical model are
unchanged. The retained interrupted acquisition is not an accepted seed.

Before opening any hook body, freeze DB-backed obligations for all three
development topics from source-only read-only copies. Then explicitly warm,
check a second warm encodes no source windows, and run two independent native
chats per topic. These are initial-hook diagnostics, not first/history model
cycles. Actual stdout must match its publication receipt, and the immutable
source files and pre-delivery denominator must remain unchanged.

No answering model is called. The same fixed 500,000-character budget is used
throughout; no reference requirement is passed to recommendation or selection.
This is not a held-out generalization test, token comparison, or adoption gate.

## Audit metric

`RequiredDelivery` still had the retired 95% threshold while the newer
`AvailableDelivery` used 98%. The former now uses exact `49 * required <=
50 * delivered` arithmetic; the latter delegates to the same function.
Zero obligations do not pass. The one-miss boundary is 50 obligations.
The [native checks](metric-checks/result.json) cover 49/50/100 boundaries,
mixed immutable subjects, duplicates/overlaps, frozen denominators and real
JSON body attribution. Earlier records are not rewritten.

## Source audit

The first freeze stopped before any hook or numerical warm because the
independent source check rejected a saved file alias. Its [error](attempts/first-freeze/error.txt)
and [guard](attempts/first-freeze/guard.json) are retained. Neither delivery
nor a successful seed is claimed. The [follow-up](attempts/first-freeze/alias-diagnostic.txt)
identified a JSON-escaped empty line at Driver.cpp:224: its original interval
contains `\n`, while the independently loaded file line is empty. The oracle
had retained the line separator after JSON decoding. The stored content was
not wrong in this case.

The audit now decodes according to the recorded literal representation. A
zero-character alias may match only an empty reference line, and a separator
is accepted only for a line projection. A nonempty alias must decode exactly
to the reference bytes and preserve its character count. A Lean theorem rules
out a zero-character alias matching nonempty source. Native checks cover raw,
JSON, empty strings, separators, escaped backslashes/tabs, modified text and
wrong character counts. No matcher, stored coordinate or requirement is
replaced, and a mismatch still stops the audit.

The first driver build also failed on Lean syntax; the corrected native build
passed. [Build failure](attempts/driver-build.txt). Product runtime changes,
answering-model calls and paid comparisons remain zero.

## Native result

[Result](native-result.json), [resource guard](native.guard.json),
[frozen denominator](frozen/sealed.json), [missing-evidence trace](missing-evidence-trace.json).

| Topic | Required evidence, chat 0 / chat 1 | Hook milliseconds, chat 0 / chat 1 |
| --- | --- | --- |
| 1 | 4/4 / 4/4 | 15,975 / 14,746 |
| 2 | 6/7 / 6/7 | 16,420 / 15,449 |
| 3 | 5/5 / 5/5 | 15,019 / 15,098 |

The 98% gate fails for topic 2. Its four-line `dumpmachine` reference lost
Driver.cpp:2573, the closing brace; lines 2570–2572 were actually delivered.
All three supporting owners were hydrated, synaptic exploration completed,
and their focus-owner positions were 13 / 14 / 9. The selected packet has
the three preceding file lines and lacks line 2573. This narrows the failure
to preparation/selection of the complete range after owner discovery; it does
not yet distinguish a missing candidate atom from an unselected atom. No
weight, budget, source coordinate or reference was changed after observation.

Each topic's two actual bodies are byte-identical. The unique bodies are
retained in `bodies/topic-{1,2,3}.txt`; each cell's audit, stdout hash, hook
record, bounded stage summary and service shutdown are under `cells/`.
Large raw receipts are fingerprinted before retirement. The compact summaries
omit payload arrays and very large numeric values and are not replay inputs.

Semantic search and synaptic exploration completed in all six cells. Initial
construction requested all 1,977 unique windows and took 156,433 ms;
all windows were valid afterward. Repeat warm requested zero, hydrated zero
original owners and took 451 ms, including process overhead. These are
explicit preparation times, not hook times. The source-only DB remained
byte-identical. No concurrent source publication was driven by this read-only
scenario; publication overlap evidence remains the separate worker test.

The [background log](background-warnings.txt) has eleven session `state.guard`
wait warnings from queued-work reconciliation. They are not source-head
invalidation, and normal shutdown does not make them disappear as a finding.
`flushDeferred` waits for session metadata through `reconcileToolReceipts` and
`withSession`; foreground offer reconciliation/persistence also uses that
lock. The critical section causing each wait has not been instrumented, so
neither a save-throughput bound nor a root cause is claimed from this log.

The publisher and six session services exited normally; the guard found no
surviving owned process. Aggregate RSS peaked at 2,657,200 KiB, below the
unchanged 3.5 GiB stop. This is six sequential local diagnostic chats with a
retained interrupted seed, not an 80-person workload, p99 sample, fresh token
comparison or two model cycles. The runtime remains unadopted.

Next, trace candidate coverage for the missing interval and instrument the
session critical sections. Do not repeat weight tuning on these development
questions or weaken the frozen requirement after seeing its missing brace.
