# Isolated shared-project discovery and original delivery

Product `a6f2160da0215366cb16367dfec21e8093dc4330537a799de7aa9698cf8fc680`
extends the [publication gateway](../project-gateway/README.md) with read-only
discovery and original delivery. It is isolated and **unadopted**. The normal
installation and README benchmark claims are unchanged; no answering model runs.

The host validates every selected project/read capability and retains the full
owner cuts. It uses the existing project-view pool and public-reader coordinator,
forking request-local mutable readers. Existing vector nomination, e-class/work
graph discovery, synaptic traversal and source rendering run on the data side.
The client receives an answer bound to its question and complete input digest;
it receives no host DB directory or private read capability. Query text is not
published into the project DB, and private usage is removed from shared inputs.

The query uses the existing separate operations listener, leaving the source
listener available for nested original reads. It initially reserves a small
streaming reply chunk; it does not reserve the maximum 16 MiB before each long
query. Connections have separate request tasks. The client-side transitive
closure has no project-file reads or mutex `atomically` calls.

Remote advice has no completion authority. The actual export guard rejects
completed work, local unions, blocking results and incomplete searches. Current
client file freshness and certified operation reuse remain separate work.

## Native results

The [Lean fixture](../../../tools/research/ProjectReadChecks.lean) records real
source reads using the ordinary hook runtime into two project DBs, each with two
owners. There are six native observations and two final answers. The required
four original code fields are confirmed in the DB and fingerprinted **before**
delivery; the source files are then deleted.

| Workload | Result |
| --- | --- |
| ALPHA-only, BETA-only and both-project initial queries | All required original CODE rows, path and fingerprint |
| Ten simultaneous independent gateway connections | All complete in 0.503 s |
| Initial query maximum, including connection/pin/retention | 0.501 s |
| New service and ten new clients using different empty data roots | All complete in 1.988 s |
| Fresh service with source files still absent | No manual warm; actual bodies byte-identical to preceding replies |
| All 23 queries | Semantic and synaptic discovery complete; 60/60 required field appearances |
| Single-project readers | No other project's required field |
| Raw requests with changed scope, incomplete read set, changed numeric policy or empty question | Rejected |
| Original publication heads and files | Unchanged by both read phases |

The first fixture takes 22.449 s including source acquisition, one explicit warm,
queries and shutdown. The fresh-service follow-up takes 7.338 s including startup,
verification and shutdown; its ten-query gate is 1.988 s. Neither complete-fixture
time is a hook latency. The fixture uses a configured 500,000-character budget;
the largest actual body is 9,374 UTF-8 bytes. This does not establish equivalent
behavior under the public default or token savings.

All 18 acquisition callbacks and six actual source commands exit zero with empty
stderr, and no callback has the incomplete-search notice. The first successful
query fixture has empty stderr. The fresh-service follow-up retains the existing
MiniLM pooling warning; model, pooling, tokenizer and runtime files are unchanged.
Both have normally stopped services and no owned processes remaining. Sampled
related RSS peaks at 2,111,728 KiB, then 1,823,744 KiB in the
fresh-service follow-up. Neither successful resource guard triggers.

The [summary](summary.json), [actual responses](queries.json),
[fresh responses](fresh-queries.json), [frozen requirements](required-before-delivery.json),
[native calls](native-calls.json), [guards](guards.json) and
[proof audit](proofs.json) retain the evidence. There are four unique required
fields; 60 is their repeated-query appearance count, not 60 independent facts.

## Defects exposed and corrected

The first query fixture fails because this entry called the discovery engine
without the ordinary worker's search-status wrapper. The final entry records
the actual semantic-ready callback; it does not infer completion from delivered
text. The initial failed reply was not saved before its assertion. The fixture
now retains replies before checking them.

The next run confirms semantic completion and both required rows, but exposes
an existing empty-owner defect: the two untouched original trees are treated as
missing synaptic indexes. They remain in the complete read/certification cut.
A prepared source contributes the empty traversal only if its original tree,
indexes, usage and error fields are all empty. A demanded file range still goes
through the original checked binding path. Nonempty missing preparation remains
incomplete. The empty contribution and these negative cases have Lean proofs.

This failed fixture also triggers the leftover-process guard after abruptly
aborting its services. Failure cleanup now first performs normal supervised
shutdown; resource limits and leftover detection are unchanged. Both original
failures remain failures in their retained rejection records.

Nine laws use only standard axioms. The dependency audit connects real callers
to the project/cut, ACK, shared-reader, graph and export guards, including the
empty-original branches. The client-only closure checks 1,376 declarations.
The 340-object product and 317-object native observers are consistent, with all
product core and 315 common imported sources identical. Added protocol source
literals are explicitly bound to their exact file digests; the earlier strict
literal-declaration rejection is retained rather than weakening that audit.

Ended DBs, caches, duplicate observers and unused installation-helper copies
are deleted without archive: 14,415 entries and 2,636,490,671 logical bytes.
Protected originals, current native/model inputs and runtime hashes are unchanged;
the 340-object product closure passes again after deletion.

## Remaining scope

The [mixed-chat checks](../../practical-runtime/mixed-chat-lifecycle/README.md)
and [shared-owner growth checks](../../practical-runtime/shared-owner-lifecycle/README.md)
already cover two DBs with fresh/existing readers, interruption and resume,
service restart, late and duplicate Post/Stop, project switching, clear and
compaction. These use real registered hooks with scripted chat/session events,
not Codex UI chats or answering-model runs. Their successful product is
`5d37ec14…`; they have **not** been rerun as a combined lifecycle workload on
this new `a6f2160d…` shared-query entry. Its current coverage is the two read
phases above, including a fresh service and ten fresh clients on the same DBs.

This is one Mac/OS user, not another machine, authenticated deployment, SMB/NFS,
production p99 or sustained 80-user operation. New empty data roots do not mean
the OS disk cache was cold. Ordinary hooks acquire the fixture memories, but
the new query API is not yet connected as an ordinary hook's remote read target.
Remote certified Work matching, interrupted-query lifecycle tests, cross-project
transitive dependency closure, growing large DBs, MCP/dump workloads and the full
LLVM seed/first/second-pass model experiment remain outstanding. Token/quality
adoption remains zero; these small checks do not prove general 98% delivery.
