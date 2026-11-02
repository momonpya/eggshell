# Delivery acknowledgment without blocking background saving

Isolated candidate, not adopted. No answering-model calls, token improvement,
or 80-person sustained-use claim. The [predeclared plan](plan.json) fixes three
repetitions of each metadata shape for each arm. This does not replace the
required matched first/history topic 1/2/3 token and quality comparisons.

## Two different waits

The historical `source changed before lexical warm` defect rejected preparation
of a still-readable source when a newer publication appeared. The completed-root
and lexical-delta candidates separate completed source roots from newer debt.
The ordinary [worker overlap check](../lexical-delta/worker-progress/result.json)
completed revisions 26/44/64 despite 24/19/17 overlapping later publications,
then caught up to revision 79. Its exact postings/window-owner checks and all
158 valid numerical windows are small-fixture evidence, not 80-user throughput.

The nine `state.guard` warnings in the record-boundary real-delivery run have a
different cause. `acknowledge` held the shared session lock while confirming
original ranges in the private delivery ledger. Background saving tries that
same lock with 100 ms admission. The initial synthetic native reproduction
used the actual ACK and ordinary background state-read functions. With 11,540
rows (6,231 unique), 623 synthetic bindings, nine graph keys and 500,000 body
characters, ACK took 1,052 ms and six background reads timed out. The session
JSON was 3,115,657 bytes; read/write took 26/18 ms. These are a single diagnostic
sample, not the controlled comparison. The binding count is an assumption;
the actual retained packet did not preserve its ACK binding count.

## Candidate contract

The [product patch](candidate.patch) changes only the isolated copies of
`PluginHooks.lean` and `DeliveryLedger.lean`. It applies cleanly to the
record-boundary parent core. The native session state schema, admitted body,
projection, authority, ranking, graph and numerical contracts stay unchanged.

ACKs for one session use their own serialization guard and the existing offer's
absolute deadline. Session control is locked only to capture the offer and to
compare/publish its confirmed head. The potentially large ledger update runs
outside that control lock. Before publishing, the code checks the complete
captured offer, current turn, enabled flag, epoch, deadline and preceding
accepted head. A concurrent state change can prevent confirmation without
blocking background work for the whole ledger write.

The ledger starts from that exact preceding accepted root, not the latest
physical head. A process can disappear after preparing a ledger head but before
publishing it into session state. A later ACK must not inherit rows from such
an abandoned head. Existing immutable historical pages supply the accepted
base; no whole-ledger copy is needed. The old session pointer is kept until
the new head is durable. No timeout is increased and no warning is suppressed.

The [Lean diagnostic](../../../tools/research/SessionStateProbe.lean) checks
actual ACKs and background reads, unchanged text, exact sparse source coverage
and the absence of invented gap lines. The separate
[interleaving checks](../../../tools/research/SessionAcknowledgmentChecks.lean)
exercise compaction, disable, turn changes, replacement, expiry, accepted-head
changes, simultaneous ACKs and recovery from abandoned prepared heads.

## Native comparison and safety checks

The [control](control.json) and [candidate](candidate.json) each ran the fixed
nine cases. The benchmark namespace's compiled source is identical in both
arms, SHA-256 `9bc3c2f2eae64ff6ab88bf987f58656c3b2f638b289dc8705860581eb87345d9`;
only its executable entry wrapper differs. Each arm uses its corresponding
product implementation and a new private fixture root.

| Large case | Control | Candidate |
| --- | --- | --- |
| Background admission failures | 6 / 6 / 6 | 0 / 0 / 0 |
| Successful overlapping background reads | 1 / 1 / 1 | 32 / 32 / 33 |
| ACK wall time, ms | 1075 / 1065 / 1065 | 1160 / 1152 / 1186 |
| Longest background read including JSON decode, ms | 157 / 158 / 157 | 79 / 81 / 49 |

ACK latency did not improve: it rose while background calls could make
progress. This result concerns lock exclusion, not faster ledger writes or
full-hook latency. Empty and small cases also had zero admission failures.
All 18 case runs preserved acknowledged body bytes and exact sparse source
coverage; absent lines remained absent. The
[initial one-shot reproduction](initial-diagnostic.json) is kept separately.

All nine [interleaving checks](interleavings.json) passed, including accepted
historical-head reuse after a newer physical head was abandoned. The ordinary
`ContractAudit` compiled; the two added rejection proofs use only standard
Lean axioms, as shown in the [compiler output](axioms.txt).

The entry point is
[SessionAckAudit](../../../tools/research/SessionAckAudit.lean), with
`probe OUTPUT`, `checks OUTPUT`, and `native INPUT NEW-ROOT` modes.

## Ordinary native lifecycle

The candidate product runtime is
`d33a5d3c2ad7bb4c96aac61d111c26260f47835d4233b2a0795697fd561207e3`.
The [ordinary lifecycle result](native-gate.json) started from an empty DB and
used five actual shell operations plus three MCP-shaped hook pairs, not a real
MCP server. It published eight original tool records and 17 journal events,
with one consumption witness, 16 supports and four co-quotation facts. There
were no direct relation insertions or answering-model calls.

An original-only checkpoint recovered under a new private cache root, without
changing the source publication. A new chat received both frozen fixture
requirements (2/2) in 4,336 ms. The actual [body](native-gate-body.txt) and
received output hashes are retained. All four save/session services exited
normally and removed their endpoints; no owned process remained. This small
fixture is not the retained LLVM 32/32 check, and no LLVM result is attributed
to the new runtime without rerunning it.

The [resource receipts](resources.json) retain all attempts, including two
test-harness compile failures (record-literal indentation; colliding helper
`main` declarations), followed by successful builds. Neither failure executed
product tests. Successful native diagnostics had zero guard triggers. Maximum
aggregate build RSS was 2,823,936 KiB; lifecycle RSS was 1,844,960 KiB. The
3.5 GiB stop / 4 GiB absolute ceiling and 2 GiB disk floor stayed unchanged.

These checks do not establish full-hook p99, continuous 80-user service
capacity, answer quality or total-token reduction. See [summary](summary.json).
Ended synthetic DBs, caches and helper executables are deleted, without
archives; [cleanup](cleanup.json) records the exact owned paths. The current
candidate prefix, parent, immutable source and necessary link/interface inputs
remain available. Replaying the diagnostics requires fresh fixture roots.
