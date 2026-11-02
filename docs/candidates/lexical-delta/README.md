# Lexical preparation from publication deltas

2026-11-03. Isolated candidate, not adopted. No answering-model calls or token
improvement claims. The full 98% delivery / 30-second hook / 80-person sustained
use goal remains unverified.

The isolated [product patch](candidate.patch) applies to `prepared-progress-core`
with `git apply --unidiff-zero`. The [controller patch](controller.patch) adds
the normal ContractAudit import to the isolated study entry; it does not change
the product entry. [Lean probes](../../../tools/research/LexicalWarmProbe.lean)
and the [native audit/comparison](../../../tools/research/LexicalDeltaAudit.lean)
contain the complete test logic. Ended test DBs/caches were [deleted](cleanup.json),
without compressed archives; compact results remain, and replay needs new fixtures.

The parent is the completed-root candidate `621d038f`, runtime `1ba7fa06…`.
Its lexical warm still enumerated all source candidates and all indexed owners
on every source change. This candidate saves the exact completed source basis
with readiness and uses checked publication changes for ordinary updates.

`deltaPlan` reads the old and new memberships of changed owners, retracts
departed ordinals, adds new ordinals, and reuses immutable token sets on
reinsertion. Frequencies change only for affected terms. `Population` checks
the before/remove/add count before publication; `exact_balance` proves that its
checked arithmetic cannot silently lose a removal through Nat subtraction.
The native compile-time reachability audit rejects any delta plan reaching
`searchDocuments`, `directory` or `Snapshot.foldRange`.

Each batch updates membership and document count atomically. The final basis
and ready marker are committed together after validation; complete named roots
are then registered by the parent's `PreparedRoot`. Hooks still never repair
the index. Ranking, tokenization, embedding, selection and certification rules
are unchanged.

## Recovery and copied sources

An incomplete workspace records the source being prepared. It can retain its
committed prefix only when that source is verified on the requested source's
ancestry. Full reconciliation handles bootstrap and incomplete work. If no
verified origin exists, the workspace is reset and built from authoritative
originals, while previously named immutable roots remain available.

This matters for independent writable DB copies: numeric owner IDs and ordinals
may coincide after different observations are added to two copies. Reusing
token sets merely because these integers match would alias different originals.
The native fork fixture verifies rebuilding the new branch and retaining the
old branch's reader. Missing ancestry is not interpreted as an empty delta.

The native oracle covers addition, removal, ordinal-changing reinsertion,
affected-only changes, all-owner removal, empty-source revival, reuse of an
already committed partial batch, recovery of missing completion registration,
divergent copies and rejection of a wrong completed population. Postings and
frequencies match independently tokenized original Values. See
[native result](native-result.json) and [guard](native.guard.json).

## Matched update comparison

The plan fixed 64 / 1,024 / 10,000 initial owners and three repetitions before
measurement. Both arms warmed the same initial source, then received each exact
same source snapshot after one additional owner. Probe order alternated. The
control is the parent's full-catalogue path, not a published release. Both
probes were built from the same harness against their respective source cores.

| Initial owners | Control ms, all repetitions | Candidate ms, all repetitions |
| ---: | --- | --- |
| 64 | 30 / 30 / 31 | 24 / 25 / 25 |
| 1,024 | 184 / 183 / 186 | 42 / 42 / 42 |
| 10,000 | 1,792 / 2,035 / 1,780 | 64 / 65 / 68 |

All nine pairs matched original memberships for a common term, the new unique
term and an absent term. Candidate traces were complete with zero source range
reads; source page reads were 31–32 / 50 / 73 respectively. These are explicit
lexical update timings, not hooks, p99 estimates, model tokens or delivery rates.
See the sealed [plan](comparison-plan.json), [all pairs](comparison.json),
[completion](comparison-complete.json) and [resource guard](comparison.guard.json).

An initial comparison attempt was killed when a sibling guard considered its
processes leftovers: both guards shared the same broad experiment ownership
prefix. It produced no accepted timing pairs. The completed comparison ran
alone under one guard; no RSS/disk limits were relaxed. Concurrent test clients
must share one outer resource guard rather than overlapping cleanup owners.

## Remaining work

The ordinary runtime is
`66c6cf14dad23b28b41f7e0bec4f91dae4a7de411a894c14c39366a433b89271`;
its matched controller is
`5606e59269eee83d0a4698a5030b90656bf9a250f41930d821b4592ffe917dc6`.
The full [ContractAudit](contract-audit.txt) passed. The first controller link
failed because setup used an incomplete inherited object map, duplicating a
module object. The corrected setup uses the immediate baseline's complete
`object-mapping.json`; already compiled modules were retained for the successful
link. This did not change the product runtime or bypass interface checks.

[Native lifecycle](native-gate/result.json), [body audit](native-gate/recall-audit.json)
and [recovery](native-gate/recovery.json) passed: eight Pre/Post pairs, 17 journal
events, eight portable origins, consumption 1 / supports 16 / coquoted 4, final
explicit warm, source-only reconstruction and new-chat delivery. Five calls
were actual shell calls; three were MCP-shaped fixtures, not a real MCP server.
Both required fixture items were actually delivered in 4,580 ms. The numerical
provider used the unchanged MiniLM implementation. Both services exited, with
no owned process remaining; aggregate peak was 1,846,688 KiB. Runtime build
peak was 2,785,008 KiB. The aggregate 3.5 GiB stop, absolute 4 GiB ceiling and
2 GiB disk floor were unchanged. This is not a 98%/80-user benchmark.

Whole-worker numerical/synaptic progress
under continuous publication and a coherent query view across component roots
are still required. Bootstrap and full recovery still enumerate the corpus;
the fast path is proportional to changed ownership/terms plus B-tree access.
Physical compaction, bounded backlog and 80-user load are not proved here.

Keep the parent and current cohort unchanged. Adoption still requires the
prespecified repeated, matched first/history topic 1/2/3 trials with inclusive
tokens, quality and deadline checks. No paid trial is justified by this update
microbenchmark alone.
