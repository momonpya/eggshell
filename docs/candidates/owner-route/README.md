# Reject whole-tuple readiness for independent owners

**Rejected, not adopted.** The isolated continuation connected the owner view
to source warm, root capture, keyed recommendation and federated discovery.
The native counterexample below stopped all model/lifecycle/load follow-ons.
Ordinary runtime `52e9dd63…` and component checker `98b7a651…` are unchanged.

Actual `Warm.run` prepares two DBs in lexical mode, without an encoder or
answering model. The composite owner view is prepared at `(A0,B0)`. Appending
A and warming produces `(A1,B0)`; appending B and warming produces `(A1,B1)`.
The independently captured cut **`(A0,B1)` is valid**: B's addition does not
depend on A's addition. Both individual prepared records remain available and
restore the exact original heads. The complete engine finds all three owners
and delivers `original A0_MARKER` and `original B1_MARKER`. The composite cache
has never prepared this combination, so new admission refuses it and the actual
new discovery controller returns `search-incomplete`.

The [final diagnostic](independent-cuts.json), actual
[reference output](reference-output.json) and
[candidate output](candidate-output.json) retain the result. The preliminary
check reproduced it before adding the stricter original-body assertion. This
small counterexample applies already to two read DBs; independently advancing
project owners have the same composition requirement. No acknowledged original
or individual preparation was lost. Numeric inputs are absent in these lexical
cases; the MiniLM namespace label is not an executed encoder/model experiment.

Increasing the 64-name cache cannot create a never-prepared tuple. Retrying
source warm prepares current heads, while substituting latest violates the
captured read boundary. Serializing original writers abandons the required
ownership model. The replacement must compose per-source prepared roots;
whole-tuple memoization can be an optimization, never the sole readiness gate.
See the revised [owner-input design](../../prepared-owner-view.md).

The reusable [joint topology reader](FederatedDemand.lean) uses one queue across
sources. A three-source `A→B→C→D` fixture shows that independent local closures
miss downstream edges. Joint forward/bidirectional closure and global child
membership match an independently materialized DB, including duplicate All,
unrelated edges, structured fallback and Union aliases. [Topology evidence](topology.json)
is small-fixture correctness, not IO/deadline/capacity proof. Its focused fuel
lemma uses only standard Lean axioms.

ContractAudit passed after being changed to inspect the actual new entry,
requiring checked owner restoration and one shared source-reader family while
forbidding complete-catalogue construction there. The [audit](audit.txt) did
not establish availability: the native counterexample still fails. Multi-source
keyed fusion/numerical deduplication compiled but were not experimentally
validated or adopted after this failure.

[rejected.patch](rejected.patch) is a reproducible negative implementation,
not a product fallback. Apply it to `prepared-owner-core`, copy
`FederatedDemand.lean` to `Eggshell/FederatedDemand.lean`, copy the native checker
and rename imported `PreparedOwnerChecks.main` to `preparedOwnerMain`. Commands
are `owner-independent-cuts FRESH_ROOT` and `owner-topology FRESH_ROOT`.

[Negative checks](negative-checks.json) retain record/type errors. A one-use Lean
adjustment controller initially used a reserved name; one known failing build
was redundantly started after it failed. These are implementation/control
mistakes, not old-DB damage. [Resources](resources.json) retain all guarded runs
under the unchanged 3.5 GiB stop, 4 GiB ceiling and 2 GiB disk floor.

Answering-model calls and paid comparisons remain **0/18**. Ordinary lifecycle,
actual multi-source MiniLM, LLVM and 80-user/p99/98%/token follow-ons were not run.
[Result identities](result.json) bind the diagnostic to the actual helper.
[Cleanup](cleanup.json) deletes the rejected core, entire build/executable,
fixture DBs/cache and raw logs after sealing compact evidence, without an
archive. Protected originals and both retained helpers remain unchanged.
