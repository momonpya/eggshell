# Context planning and actual packet allocation

These are isolated, unadopted experiments. No new answering-model calls were
made. No token-reduction or answer-quality improvement is claimed.

The original stage-3 window exports already contain the two missing current
question conditions. Their original coordinates are verified in
`shared-minima-plan-audit-20261021/source-coordinate-correction.json`; decoded
display offsets are not used as indexed coordinates.

Two incremental candidates were tested against those same saved sources:

| Candidate | Change | Actual stage-3 delivery |
| --- | --- | --- |
| `0ad0571e…` | Keep the first compatible citation, then merge remaining citation and numerical context offers by rendered UTF-8 size | Both conditions absent; body byte-identical to shared-minima control |
| `9b57a5f9…` | Additionally retain the initial question's numerical positions before adding source-only focus positions | Both conditions absent; body changed |

The first candidate completed two independent new chats in 14.380/8.880 seconds;
the second in 14.894/9.228 seconds. Each pair delivered identical bodies within
30 seconds. The executable, source, original DB, actual bodies and native
receipts are retained. Both candidates preserve the exact bytes of MiniLM,
SearchProvider, SemanticMatcher, Matcher, SourceEvidence, Worker and PluginHooks.
Existing graph ownership, freshness and completion authority are unchanged.

The offer-merge regression verifies that an affordable current condition can
coexist with its coupled citation before broad historical context, while
retaining original fragments, rejecting foreign envelopes and creating no
control authority. Existing nine checks also pass. Discovery precedence has
an additional ordering/ownership check; its preservation proofs and
ContractAudit pass. These checks do not establish practical improvement.

A compiled, model-free plan probe reconstructs each original indexed source
from its exported windows and verifies every SHA-256, overlap and Work prefix.
In its simplified per-owner envelope, initial-discovery precedence reduces the
smallest coupled excerpt containing one condition from 22,989 to 12,638
characters. Those are diagnostic plan costs, not actual packet costs: the
probe omits native trace/provenance framing and other owners' competition.
The native failures above demonstrate why this local result cannot establish
delivery success. A runtime budget audit records the actual minima,
requested levels, complete packet costs and a hypothetical entry-first fit.

That runtime diagnostic has exactly the same body SHA-256 as `9b57a5f9…`.
Its actual envelope is 120,000 characters/128,000 bytes; each entry's preferred
share is 13,333/14,222. Both needed conditions are present in requested offers:

| Original owner | Minimum characters | Requested characters | Needed condition in requested offer |
| --- | ---: | ---: | --- |
| `v16748591830955464422` | 4,553 | 12,804 | yes, level 9 |
| `v3745555973717331211` | 6,839 | 9,831 | yes, already at level 1 |

All source minima together cost 277,173 characters/281,479 bytes. The actual
fitted packet costs 118,384/122,300 and omits both conditions. The hypothetical
entry-first fit stays within the same bounds at 119,854/124,852 and includes
the first condition, but excludes the second owner entirely. This hypothetical
fit is not a new native delivery or an accepted implementation. It rules out
simply switching owner groups as a complete repair. The next allocator needs
to compare requested original-range gains and their actual incremental packet
costs, rather than treating every owner's minimum as better than any already
admitted owner's additional evidence. Whole-answer and fixed-count reservations
remain withdrawn.

Original evidence is retained under
`/Users/ovm/.codex/experiments/eggshell/scope-context-20261021/`:

- `context-offer-merge-20261022/`: construction, tests, actual source audit and
  compiled per-owner plan probe. Initial compiler/test errors remain recorded;
  final checks passed without a memory-guard interruption.
- `context-offer-merge-native-stage3-20261022/`: two actual native chats.
- `discovery-context-priority-20261022/`: construction, tests and source audit.
- `discovery-context-priority-native-stage3-20261022/`: two actual native chats.
- `context-budget-audit-20261022/`: read-only allocation diagnostic.
- `context-budget-audit-native-20261022/`: two native diagnostic chats,
  14.754/9.166 seconds, with verified body equality.

`context-ordering-candidates.patch` is the review delta from the isolated
shared-minima source to the second candidate. It is not applied to production.

All heavy work is serial under the unchanged three-GiB aggregate RSS stop,
below the user's four-GiB ceiling. Candidates stay outside production. A new
answering study must start topic 1 r0 and include all six stages and equal
replications after actual delivery qualifies; these native replays never
replace answering-model comparisons.
