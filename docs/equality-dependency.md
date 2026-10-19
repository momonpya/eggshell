# Equality dependency diagnostics

Status: unadopted diagnostics in the isolated candidate. Native receipts can
pin and replay the chosen extraction component. Whole-delivery ancestry and
the Phase 3 measurement remain incomplete.

## Explicit closure and congruence

`EqualityDependency.UnionPath` contains only literal equality, current explicit
Union edges, symmetry and transitivity. There is no Apply constructor.
`DirectIndex.same_iff` proves that the existing explicit-merge partition accepts
exactly these paths. The implementation reuses the production partition and
certificate; it does not introduce another unverified equality engine.

This works for arbitrary Values and mixed Atom/Apply generators. For example,
stored edges `a ~ b`, `x ~ F(a)` and `y ~ F(b)` make the two Atoms `x` and `y`
equal only through congruence. Merely inspecting the queried Value constructors
would miss that dependency.

The comparison classifier separates these cases:

| Kind | Meaning for this comparison |
|---|---|
| `notEquivalent` | The active equality rejects the pair. |
| `literal` | The pair is structurally identical. |
| `persistentUnion` | A path using only today's persistent generators exists. |
| `localUnion` | An explicit path exists using current local generators, but no persistent-only path exists. Local causal ancestry remains unresolved. |
| `congruence` | The active equality accepts the pair, but no explicit-only path exists even with all current local generators. |

`congruence_is_necessary` requires an actual generated-equality premise. It
proves generated equivalence and the absence of *every* Union-only path. A
heuristic or merely Exact-safe quotient cannot discharge that premise by
providing a positive Boolean alone. These theorems concern the current
generators, not the semantic truth of a nominated equality or Outcome.

`DirectIndex.make` is a diagnostic reference build. It must not be added as a
second full explicit-merge fold inside a latency-sensitive hook. A runtime
integration must reuse the current index or analyze a pinned receipt outside
the hook budget.

## Selected extraction component

`SelectionDependency.report?` accepts only a selection that passes the existing
`Selection.validFor` boundary. Its comparisons include the selected All-parent
connections, Outcome-owner connections, and every positive equality used to
drop a duplicate All child. The deduplication replay preserves the complete
production child order (`dedup_output`), and all recorded comparisons are
positive under the active equality (`comparisons_positive`).

`Plugin.discoverySelectionReport` reads the actual `Matcher.extraction` result.
It does not construct another solver or substitute an arbitrary sampled plan.
`ContractAudit` checks this dependency and the new theorems' axiom dependencies.
Native receipt persistence uses the same comparisons with the production
extraction's existing validity proof, without rerunning the validity checker.
It pins current generators for offline classification rather than building
another explicit closure in the hook. Source checks and final reconciliation
restrict the surviving owner lists. A demand-memo hit retains the original
snapshot locator. See [selected equality receipts](selection-audit.md).

A literal root equality does not imply a congruence-free extraction. The
regression fixture with children `F(a), F(b)` and generator `a ~ b` completes
the selected decomposition while visiting one child. The recorded
`deduplicatedChild` comparison identifies the congruence that omitted the other
child, even though the root identity is literal. A different valid plan might
have different dependencies; this report describes the selected plan.

Completed source owners now bind to selected root-to-Outcome paths. Shared
ancestors refer to one comparison pool; sibling subtrees remain separate. A
two-branch fixture needs congruence to deduplicate children only on the left,
while the right branch remains entirely literal. Source/transport reconciliation
removes branches of discarded owners, and missing bindings stay explicitly
untracked. Owner retention does not yet resolve which final fragments of a
multiply used owner survived.

Admission observations now retain each selected completed Match's construction
epoch and original child-role evidence. Whole-Work and fragment comparisons
are replayed using that epoch's local-generator prefix, including negative
answers. Sparse child evidence comes from the already checked original All
frame and pinned Head; loaded topology evidence keeps its original relation.
An additional native fixture has only literal extraction comparisons but needs
congruence for its original child role. The admission component exposes that
dependency. Source Value-to-node binding and freshness remain IO boundaries;
the inspector does not claim an independent complete DB proof.

Local generator records now retain the actual proposing Match and its earlier
generator prefix. Offline replay checks the proposal gate without using the
generator itself or later siblings. `newLocalUnions_origin` proves that
production deduplication retains only input Match proposals, with the original
Inquiry scope. These are immediate proposer facts; Demand scheduling and
Work-pattern selection remain untracked, so local causal ancestry is not closed.

## Validation and remaining work

The focused executable runs the real kernel and native matcher selector. It
covers transitive explicit paths, Semantic congruence, Exact barriers, removed
generators, corrected saved plans, mixed Atom/Apply generators, unresolved
local ancestry, selected child deduplication, isolated completed branches,
admission epochs, original-child congruence, rejected invalid owner selections
and a native completion selection. These are deterministic regression fixtures,
not paper benchmarks. New proof code uses no `native_decide` or admitted axiom.
The focused groups run in the standard full suite as well. Retained-work
warnings are separate from equality classification.

The selection report is one required component. It does **not** establish:

- the Demand scheduling and Work-pattern choices that exposed each local
  Union proposer;
- independent verification of the source IO's complete Value-to-node binding;
- the causal ancestry of generated All continuations and local Unions;
- which final completed leaf retains a comparison after source checks and
  transport-budget reconciliation;
- source freshness, final publication or model receipt.

Consequently `localUnion` must remain unknown in a delivery-wide tally. Even
all-literal selection comparisons cannot certify a congruence-free delivery.
Admission and child coverage gaps are listed per selected branch; local causal
ancestry, continuations and final fragment slicing remain incomplete. No overall fraction
is reported, no Phase 0 completion is claimed, and no token adoption gate has
been passed. Native receipts also retain semantic status, actual cache probes
and stage durations; Phase 0 still needs the missing ancestry components and
the remaining measurements in `GOAL.md`.
