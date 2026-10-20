# Exact compiled Match override and native delivery

This extends the [isolated discovery candidate](discovery-native.md). The
ordinary implementation, original fixed 60 attempts, adoption requirements
and public-main comparison remain unchanged.

## Complete sequence equivalence

`Matcher.addMatches` originally folds `upsertMatch`: prepend each new Match
and filter every older Match with the same duplicate key. Repeating that
filter scans the accumulated list for every addition. The native stack
observation identified this operation after the owner-table changes.

`tools/KeyedOverride.lean` implements the same sequence by scanning additions
backward, keeping the latest complete payload for each exact key, and
filtering prior entries once. It uses `HashSet.containsThenInsert` for one
membership/insertion probe and a tail-recursive retained-list accumulator.
The key's full equality decides collisions. Untouched prior duplicates keep
their original multiplicity and order. No distinctness premise is needed.
Hash lookup has its usual key-cost and collision behavior; the theorem proves
sequence equivalence, not a worst-case running-time bound.

`merge_exact` proves equality with the original fold for arbitrary prior and
added lists and arbitrary payload types. `sameMatch_key` proves that the
concrete key is exactly the existing four Values: demand, original relation,
current fragment and past fragment. `addMatchesFast_exact` therefore preserves
the latest complete Match, including changed grounding, judgment, flags and
spans. It does not reconstruct evidence from a key.

The reference `Matcher.addMatches` definition stays unchanged in the isolated
kernel. The `@[csimp]` equality `addMatches_compiled` allows the compiler to
call the fast implementation. Inspection of the uninstrumented generated C
finds four fast calls in Matcher and one in Handoff's specialized discovery
saturation loop. This verifies use in the actual controller, beyond merely
building an unused helper.

The three new equality theorems depend on `propext`, `Classical.choice` and
`Quot.sound`; the retained axiom report contains no `sorryAx`,
`Lean.ofReduceBool` or `Lean.trustCompiler`. This does not complete the separate
inventory/removal of the goal's existing `native_decide` cases.

## Native checks and qualification

The native generic oracle compares 7,161 prior/addition sequence pairs with
the original fold, both normally and with every key forced into one hash
bucket: 14,322 checks. A 20,000-addition case also retains the latest complete
payloads and untouched prior duplicates. Existing owner checks remain intact.

The same immutable 10,000-window DB, first question, receipt and workspace
produce a full reference-equal Handoff in 19,427 ms, versus 26,274 ms before
this component. Text, packet, graph keys, source records and certification
metadata all agree. These are individual instrumented diagnostics, not
balanced performance trials or a token-saving result. Build/inspection takes
64.579 seconds, sampled peak 2,967,600 KiB, no guard trigger.

The uninstrumented executable, complete regression suite and ContractAudit
build successfully. The complete existing regressions pass in 97.304 seconds;
owner and override checks also pass. An independent candidate daemon drains
the three retained index tickets, preserves both pre-recorded graph heads,
and exits 0 with its shutdown client. All frozen candidate/baseline sources
and the ordinary runtime remain unchanged. Qualification takes 186.543
seconds at sampled aggregate peak 3,210,208 KiB, no guard trigger.

## Representative real hooks

After qualification, a separate inspection predeclares four new hooks: the
first fixed 10,000-window question in two cache layouts, with fresh and cached
question conditions in separate chats. Both profiles are read-only and the
DB/cache trees are OS protected. Setup verifies all 10,000 original cache
entries, warm/ready doctor state and zero work on explicit warm. A newly built
native inspector checks the candidate's actual question-cache contract.
Setup and any question-only priming are separate from hook timing.

| Cache layout | Question cache | Hook elapsed | Original body / publication / ACK | Five-second semantic gate |
| --- | --- | ---: | --- | --- |
| DB-owned, read-only profile | Fresh | 24,903 ms | all confirmed | fail |
| DB-owned, read-only profile | Cached | 25,499 ms | all confirmed | fail |
| Private overlay, OS-protected DB | Fresh | 25,548 ms | all confirmed | fail |
| Private overlay, OS-protected DB | Cached | 25,299 ms | all confirmed | fail |

Every attempt records actual stdout, byte count, SHA-256, on-time flush,
accepted offer and completed ACK. Semantic search times out at 4,504–4,508 ms;
the original DB body follows through lexical search in 20,312–20,951 ms with
the unfinished status visible. This restores body delivery in these four
representative cases where the earlier fixed attempts delivered only a
notice. It does not make the search semantically complete or pass the latency
gate. Native collection takes 143.371 seconds, sampled peak 1,494,160 KiB,
no guard trigger. No source/cache byte or pinned numerical asset changes.

The last numerical receipts are still running prefixes, with 1,568–8,544
windows scored; these are not complete-discovery evidence. Numerical input
preparation/cache access and full-ranking costs remain separate from the
intrinsic Work lane. Complete focus warm coverage is also still missing in
the actual LLVM corpus. Fix those boundaries and re-run the full declared
gate before the matched quality/token pilot. Four representative hooks do
not replace the failed fixed 60 attempts, and generation-model calls remain 0.

## Local records

Under `/Users/ovm/.codex/experiments/eggshell/`:

- `keyed-override-proof-20261020/construction-1`: proof construction, retained
  failed inputs, native oracle source and successful checks.
- `discovery-match-candidate-20261020/construction-1`: composed isolated
  sources, proof/tests and whole-Handoff comparison.
- `discovery-match-qualified-20261020/construction-1`: uninstrumented build,
  complete regression and independent index recovery.
- `discovery-match-proof-audit-20261020/audit-1`: axiom report, generated-C
  call locations and pinned executable hash.
- `discovery-match-native-20261020/inspection-1`: declared four-hook check,
  setup/preconditions, raw streams, receipts and failed five-second gate.
