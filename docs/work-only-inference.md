# Separate Work inference from Outcome hydration

This isolated Lean component addresses the reason that the current indexed hook
still hydrates almost every owner on broad queries. Work surface overlap admits
a row before the complete result is read. The 10k fixture's shared vocabulary
makes all 9,969 owners pass that gate. A faster catalogue alone cannot remove
these result reads. Limiting this same gate to recommendation top-K would also
remove possible local Union generators, contrary to complete recognition.

## Factor the computation at its real dependency boundary

`WorkView.prepare` now produces complete Work alignments from Work patterns,
global population/frequencies, subwork membership and the fixed quotient. The
existing `Candidate.prepareWork` delegates to it. `WorkAlignment.localUnion?`
is the existing constructor over an alignment and its retrieved flag; the actual
`Matcher.localUnion?` delegates to that same function. No second inference rule
or guessed result payload is introduced.

`WorkInference` carries opaque source references beside Work views and prepared
alignments. Its complete admission/pass preserves order and uses the original
surface/retrieval gate. Source references contain the full DB head, original
owner, Work and result node IDs; equal local IDs in different DBs remain distinct.
The original live-owner reader supplies Work/native orientation. A derived
nomination alone is not a source witness or permission to create a Union.

Ordinary Lean proofs establish that:

- Complete Work admission and ordered local Union proposals equal the actual
  matcher's complete pass, for the same source candidate list, quotient, global
  weights and membership. This is not a top-K or previously positive-only check.
- Candidate Outcome payloads inside the corpus argument are irrelevant to this
  pass; it can run with an empty candidate list while retaining complete weights.
- A retrieved row never proposes a Union, and every proposed Union is inquiry
  scoped. Exact-footprint preservation remains in `UnionEdge`'s proof field.
- An inert comparison cannot deliver or propose a Union for **any** result
  context. This sufficient test follows existing parent/child, whole-identity
  and distinctive-anchor conditions; it introduces no relevance threshold.
  Children are retained for potentially result-grounded completion.

ContractAudit checks the actual Matcher delegation, the theorem declarations and
that `WorkInference.load` reaches the original Work reader without calling eager
`NodeReader.outcome` or `OutcomeEdge.make`. It does not forbid original byte
comparison: native occurrence endpoints with distinct but equal node IDs may
require `nodesEqual` to establish orientation. Such IO must not be removed on the
assumption that every native endpoint has an identical node number.

## Executable evidence

The native audit uses the existing read-only 10k DB, with no new seed or model.
It loads every Work through the original live membership/occurrence reader,
captures complete bounded read traces per owner and counts result-body payload
reads separately. Only after that phase does the reference hydrate Outcomes.
This tests the original reader, not a cached text/native flag substituted as
authority.

The reference is `tests/FullSearchOracle.lean`'s frozen pre-Work-gate calculation.
Only its proof's unfold list is extended for the factored helper; the reference
algorithm is unchanged. Every ordered WorkAlignment field and raw Union proposal
is compared with it, including retrieval flags, whole/fragment identity, spans,
coverage, native clause expansion and subwork membership. Small cases include
prose, native shell and MCP-shaped invocation text, independent nominations,
negative queries and evidence-present comparisons.

Build inputs, exact patch, read-only source hashes, raw results and guards are
recorded in [the candidate review](candidates/work-inference-review.json).
Failed compiler attempts are retained. This is an audit executable; its test
oracle is not linked into a product runtime.

The final audit reads all 9,969 original Works in 1,747 ms, with 30,861 physical
page reads / 7,483,322 bytes and zero result-body payload reads on this fixture.
Later full Outcome hydration takes 607 ms, reusing the same reader's Work cache;
these are not independent cold-vs-cold timings. Native orientation with distinct
endpoint aliases can still require original result bytes on other inputs.

For the broad query with one independent nomination and parent membership,
9,970 ordered alignments equal the frozen oracle and all raw Union proposals
agree. The Work pass takes 362 ms; oracle-plus-field-comparison takes 1,506 ms.
9,969 alignments, belonging exclusively to 9,968 owners, are proved inert under
the fixed quotient. The one nominated owner remains active. The negative query
retains its independent nomination. This is not the real hook's eight-nomination
configuration, a full-discovery equivalence check, or a token measurement.

Twenty small cases cover parent/child membership, native and ordinary demands,
shell/MCP invocation text, evidence-present/retrieved lanes and negative queries.
They include eight positive Union proposals, not only equality of empty lists.
The original Matcher fixtures and ContractAudit compile. Final audit/build guards
exit zero with no survivors, aggregate peaks 641,680/2,127,904 KiB. The initial
audit used child membership for every row and is retained separately; its timing
is not compared causally with the final parent-membership audit.

## The boundary that is still missing

This proves a complete **single pass**, not the full discovery fixpoint. The
existing scheduler also grounds result evidence, projects Outcomes, admits
continuations and exposes later demands. Those can change which Work is visited
on the next pass. Equality of proposals for fixed inputs does not justify dropping
all result grounding from the scheduler or replacing complete recognition with a
bounded recommendation traversal.

Inertness is also relative to the current quotient and membership. A later
justified Union can make a previously inert comparison useful. Integration must
revisit it and preserve the original Work roots/topology needed by the quotient;
discarding the whole owner from every later pass is not proved safe here.

The next integration must keep all justified Work consequences independently of
recommendation, then resolve actual original Outcomes at the dependency and
delivery boundaries. The existing `LocalUnionOrigins`/main theorem still use
actual Match generation witnesses; this component has not replaced that proof
with a bare source ID. Its original-reader IO remains a trust boundary.

Loading all Work still costs O(N); the current candidate-domain payload is also
whole-source. Published canonical Work signatures, affected-parent indexes and
on-demand evidence hydration are still needed. This component does not establish
indexed recognition completeness, removal of all-owner work from native hooks,
federated/shared concurrency, routed vector coverage, 50k useful delivery, p99,
MCP storage policy, or model-token/quality improvement. The full runtime remains
unadopted under AGENTS.md and Phases 0–6 remain active.
