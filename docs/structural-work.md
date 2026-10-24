# Structural Work recognition

This isolated Lean candidate connects the [original Work-class query](work-class-lookup.md)
to discovery and native PreToolUse. It reuses the source's Work-owner index,
child-membership witnesses, existing extraction, renderer and freshness checks.
It adds no catalogue, storage format, numerical model or external search engine.
The patch and helpers remain outside the product implementation.

## The representation change

`Match.work` now holds either literal `WorkAlignment` or generated whole-Work
identity. The latter carries the actual generators and an `Equivalent` proof.
It has no lexical `Coverage`, retains the original Outcome owner, and proposes
no new Union. Parent observations and retrieved nominations remain advisory.
Ordinary Lean proofs and the existing completed-authority chain cover the new
case; source IO and the truth of an observation remain explicit boundaries.

Normal indexed discovery can consume this evidence after each quotient rebuild,
including run-local generators. A separate positive native entry probes original
owner buckets across pinned DBs and checks original child membership. If an
entire operation is certified there, partial-string inference and numerical
recommendation are unnecessary. Missing positive evidence falls through to
normal discovery; it is not a complete negative answer. Current-turn staged
values still reach the existing renderer for duplicate suppression.

This is not a proof that the shortcut produces the same complete set of advice
as general discovery. It establishes a valid positive reuse path. No automatic
`cat`/`sed` equivalence rule was added: tests use explicit trusted fixture
generators. Phase 4's tool-semantics rules remain unfinished.

## Checks

The final source compiles with Lean 4.33.0. ContractAudit verifies that the native
entry reaches this producer, original class/owner lookup, extraction and selection
audit. Its transitive dependency check rejects full `searchDocuments`, full
topology restoration and `Federated.prepare` from the direct producer. Final
CorpusCache, SearchMemo, FullSearchOracle and MatcherFixtures checks also pass.
The ordinary proof audits allow only `propext`, `Classical.choice`, `Quot.sound`.
No production `native_decide` or new Python implementation is introduced.

The small API fixture checks literal and congruence-only identity, original body,
receipt replay, missing equality, parent-only ownership, cross-DB child membership,
wrong target, missing source receipt, changed file and unverified MCP output.
Fresh verified observations retain native control. Changed, unknown and external
observations retain historical data but lose completion/control.

Actual UserPromptSubmit → PreToolUse sessions use the final product executable,
its daemon and the native stdout/ACK protocol. Each output matches exactly one
new publication receipt and SHA. Memory/control publications have an accepted
manager ACK; an incomplete-search notice is not counted as memory delivery.

| Small native setup | Fresh PreToolUse ms | Changed-source PreToolUse ms |
| --- | ---: | ---: |
| Unrelated initial prompt, numerical search disabled | 440 | 371 |
| Work already delivered in initial prompt | 377 | 371 |
| Unavailable numerical provider | 403 | 393 |

All six PreToolUse receipts identify the direct class producer; its own stage is
1–6 ms and requests no semantic provider. Fresh cases deny the covered operation;
changed-source cases do not. These are one case per setup/state on a one-owner
fixture, not a scale result, p99 or comparison speedup. Daemons acknowledge stop,
exit successfully, and leave no owned process. The original fixture head stays
unchanged. The unavailable-provider initial prompts correctly emit incomplete
notices; those notices are not successful memory offers.

The independent literal-alignment lane also passes 32 fixed reference cases:
all Handoff fields and body bytes agree, including seven completed cases, five
blocking cases and a positive local-Union case. That harness deliberately omits
the new identity producer; it does not establish equivalent selection for the
intentionally changed structural lane.

Builds and checks run serially with an aggregate 3.5 GiB RSS guard below the
user's 4 GiB ceiling. Maximum observed RSS across all attempts is 2,887,568 KiB.
Compile failures, the disk-space guard stop, and initial test-verifier failures
are retained. The first native helper incorrectly demanded a memory ACK for an
empty reply; the later combined run similarly misclassified an incomplete notice.
Corrected final runs distinguish publication, ACK completion and memory acceptance.
The failed runs are not silently included as passes.

## Remaining architectural work

Broad questions still restore all Work values for partial-text inference. The
50k-window UserPromptSubmit failure is **not fixed** by this point-recognition
result. Normal federation still constructs its global catalogue. The next change
must remove those all-Work dependencies while keeping vector/synaptic nomination
separate from complete source-scoped recognition; another score adjustment or
larger fixture does not solve that dependency.

Many original owners in one class, many generators and many DBs can still cost
proportionally more. This API materializes its class owners. Streaming and
source-footprint indexing before Outcome hydration remain necessary design work.
No million-window, concurrent shared-DB, live MCP, quality or token qualification
is claimed here. Existing vectors and all three synaptic recommendation edges
remain unchanged.

Source/hash/link records, exact failure scopes and raw paths are in
[the review](candidates/structural-work-review.json). The six-file patch applies
to the preceding Work-class candidate and reverses exactly. Completed rebuildable
helpers and older runtimes/caches were removed without archives; current/reference
runtimes, original DBs, source and raw evidence remain.

No new answering-model or seed calls were made. This candidate is unadopted:
AGENTS.md requires matched inclusive-token improvement, quality and deadlines for
topics 1/2/3 in both laps with predeclared equal repetitions before product,
README-result or release adoption. Phases 0–6 remain active and unfinished.
