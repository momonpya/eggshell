# Selected equality receipts

The development candidate pins the actual selected extraction behind a completed
handoff. A `selection-*.json` stage contains its current persistent and local
Union generators, Work comparisons and completed source-owner identities. It
contains the chosen All-parent, Outcome-owner and positive child-deduplication
comparisons. The production extraction's existing validity proof supplies the
report; the hook does not build another explicit-only partition.

Completed source owners also bind to their selected root-to-Outcome branches.
Each branch refers to positions in the shared comparison pool, so ancestors
shared by multiple branches do not duplicate Value payloads in the snapshot.
A branch includes positive All-parent and child-deduplication comparisons on
its path and its terminal completed-Outcome comparison. It excludes comparisons
inside sibling subtrees. This is the executed selection path, not a minimal
counterfactual proof of necessity.

The handoff carries a small locator with the receipt identity, unique stage,
SHA-256 of its data and surviving visible/control owner lists. A demand-memo hit
retains the original locator instead of claiming to have run a new extraction.
Source checks and final delivery reconciliation only remove owners from these
lists. A control-only handoff can carry a locator even when no new completed body
is sent. The search receipt records the final locator after reconciliation.

Inspect it outside the hook deadline, using the same `EGGSHELL_DATA_ROOT`:

```sh
eggshell inspect-equality HOOK_RECEIPT_ID
```

The inspector validates the locator, snapshot digest, retained owner membership,
Exact footprints and every positive comparison by rebuilding the current
generated equality. It classifies each comparison as literal, persistent Union,
local Union or congruence using the existing proved explicit-closure classifier.
A rejected comparison, missing snapshot or mismatched digest is an error, never
a zero-congruence result. Publication and acknowledgement records are included
separately; a missing/unreadable one is null. Recorded stdout bytes and SHA-256
are checked when available. Host/model ingestion remains unconfirmed.

`completedBranches` in the inspected result contains only branches whose source
owner survived in the locator. `ownerVisible` and `ownerControls` describe that
owner's surviving delivery lanes. They do not certify that every branch of a
multiply used owner was transported. An unbound surviving owner appears in
`untrackedCompletedOwners`; it is never assigned a literal or zero-congruence
classification. Invalid comparison positions, non-Outcome terminals and foreign
owners are rejected.

## Admission-time comparisons and original child roles

The terminal native path and the indexed discovery controller observe the
actual returned Matches. They retain the original local-generator prefix and
the source-child witness selected by the corpus membership predicate. Selected
completed admissions and proposers of actual local generators are serialized;
other observed Matches are not. A later
Match with the same production identity replaces the earlier one in discovery;
the inspector uses its latest observed construction, rather than an earlier
comparison with the same owner.

`matchAdmissions` replays whole-Work and fragment identity at the recorded
`localCount`. Both positive and negative answers must agree. Later local Unions
cannot justify an earlier comparison. The completed gate's recorded facts must
still grant a non-retrieval, locally identified, grounded or whole subwork.
Each record binds to the exact projected Outcome and admitted Demand of its
selected branches. The hook does not perform this replay or build a second
explicit closure.

For a loaded topology, the witness retains the original All relation and its
child. The sparse reader instead retains the pinned DB Head, directory, literal
child id and original checked All reference frame. This observation is made in
the existing posting validation, without another source read or sibling body
hydration. `ChildObservation.position` carries actual child membership and
`child_before` derives its backward reference bound. The existing alias lookup
still supplies the production Boolean. Offline replay checks the frame and
child position, and separately classifies both Work-to-corpus and
corpus-to-original-child equality.

`sourceChild: recorded-source-boundary` means those original source facts were
captured by the pinned IO boundary. It does not independently verify the complete
source graph or recheck the current filesystem. Source freshness and the
literal Value-to-node binding retain the existing source-IO assumptions. A
missing observation remains `untracked`; observer failure cannot grant
completion or change the lookup result.

The final inspector restricts admissions with the retained owners and branches.
`untrackedAdmissionBranches` and `untrackedSourceChildBranches` list gaps by
their selection-branch positions, including when no admission was captured.
Neither an absent record nor a literal extraction erases an unknown. In the
regression fixture, all extraction comparisons are literal, while the original
child-role comparison requires congruence.

## Local generator proposers

At Match observation, the collector also calls the production `localUnion?`
function with that immutable view and the actual Inquiry. It retains the
proposal, rather than inventing an origin from the final quotient. At capture,
one full structural key (both endpoints, scope kind and authority) locates the
earliest proposing Match for each actual local generator. Hash collisions do
not identify generators, and unselected proposals are not serialized. The
collector does not rebuild equality or inspect additional source bodies.

`Matcher.newLocalUnions_origin` proves that every generator kept by production
deduplication came from an input Match and is scoped to that Inquiry. The proof
uses the production `distinctLocalUnions` fold, including duplicate/reversed
pair handling. `ContractAudit` checks its axioms and that the collector calls
the production nomination function without another quotient build.

`localUnionOrigins` replays the recorded proposal gate: no retrieval-only hit,
a positive Work alignment or complete side, original fragment non-identity,
unchanged endpoints and Inquiry scope, and the generator's Exact footprint.
Unlike completed admission, nomination requires neither completed subwork nor
Outcome context. Whole-Work identity is an observed Match comparison; only the
fragment identity test is directly used by the proposal gate. These records
do not assert minimal causal dependencies.

Generator `i` may use only a prefix of length at most `i`. Self/future references,
duplicate origins, endpoint/scope changes and invalid gates are errors. Two
generators proposed in the same pass can share the same shorter prefix: they
must not be replayed as if the second used the first. Missing proposers remain
listed in `untrackedLocalOrigins`, including when no history was recorded.

This component covers the entire captured run before source/transport pruning,
so it does not claim that every available generator was used by a retained
owner. Scheduling now has the whole-step observations described below;
Work-pattern selection and minimal scheduling dependencies remain untracked,
as do complete continuation and final-fragment ancestry. Consequently
`localUnionAncestry` and whole-delivery ancestry remain `untracked` even when
every immediate proposer was recovered. No Phase 3 fraction is derived.

## Actual scheduling and continuation observations

The discovery controller emits a typed observation immediately after its
existing extraction and before evaluating its tasks. It includes that actual
selection's validity witness, the already generated All edges, and the exact
ordered task filter. `ScheduleObservation.task_origin` proves that each task
came from the extraction, is not the synthetic remainder, and passes the
production freshness filter. The certified terminal fast path records its
unadmitted root without another extraction.

`schedulingRecords` retain whole-step positive selection comparisons and
selected All uses. A generated use means exact structural membership in that
step's prior continuations. Offline replay checks the task filter and equality
comparisons using the original local-generator prefix. An admission or local
proposer binds to its actual pass, task and prefix; a contradictory binding is
an error, while a missing observation remains `untracked`.
`schedulingAncestry: recorded-step` describes this binding. It does not certify
the admission policy, Work-pattern selection or a minimal dependency slice.

When production `rootContinuation?` creates an All, another typed observation
retains that actual result and the root Matches supporting its non-remainder
children. `rootContinuation_child_origin` proves that each such child came
from an automatic root Match with subwork. The collector immediately joins
its original admission prefix and scheduling pass, before later observations
can replace that Match. Only Value references and selected facts survive the
callback; it does not retain a quotient or reader cache.

`continuationRecords` replay those original whole/fragment identity answers,
check the root and mandatory open remainder, and reject future prefixes,
duplicate child support or nonautomatic support. Missing support appears in
`untrackedChildren`; missing Match epochs remain null. Retrieval-only support
is permitted to generate open Work but supplies no Union or completion
authority. Its automatic gate is a captured production result, not a separate
proof of the pattern choice or original child role.

These observations cover the captured run before final owner pruning. They
do not resolve which scheduling premise or continuation was necessary for a
surviving completed leaf. `dependencySlice`, `localUnionAncestry`,
`continuationAncestry` and `deliveryAncestry` remain `untracked`. The existing
optimized/reference discovery theorem also accepts the same observer on both
sides; the new proofs pass the axiom audit without `native_decide`.

## Selected All uses and their generators

Each completed branch also carries positions into a shared structural All
pool. Repeated ancestors serialize once; sibling subtrees contribute no All
positions to that branch. `completedBranches_decomposition` proves that every
recorded branch edge belongs to the actual selection. Its proof is included
in the axiom audit. This is an executed path, not a counterfactual minimal
explanation of why an Outcome was necessary.

Production discovery retains its actual `runAll` and final pass in the result.
The completed snapshot marks an All as generated by membership in that set,
not by the presence of diagnostic events. A missing generation observation
therefore cannot turn a generated All into original source structure. The
inspector exposes the shared pool as `selectedAllUses` and the branch's uses
as `decompositions`. Invalid pool references or a missing selected parent
comparison are errors. Missing branch structure is listed by comparison
position in `untrackedDecompositionComparisons`.

A generated use links by full relation equality to the first available
eligible `continuationRecords` entry. That entry retains the original root
Matches and their scheduling/equality epochs. A scheduling selection can use
only an earlier generation pass; the final extraction may also use an All
generated in its own last pass. The producer's local prefix must not exceed
the use's prefix. Future-only producers and duplicate generation steps are
errors. A missing producer or use epoch stays `origin: untracked` with a null
continuation reference. The continuation's creation step also checks its
actual root and prefix when the scheduling observation is available.

`origin: source-selection-boundary` describes the controller's original-source
lane; it does not independently prove the source graph's complete IO binding.
`origin: recorded-generation` describes an event link, not complete causal
ancestry of its Match, automatic gate or child role. Source/transport pruning
still restricts the completed branches by owner, and the shared pool remains
the entire selected extraction. Final leaf slicing and whole-delivery
ancestry remain untracked. No Phase 3 zero or fraction is inferred from gaps.

The snapshot covers the **whole selected extraction before source and transport
pruning**, alongside the owner lists that survived. It is not yet a dependency
slice for each surviving final fragment/leaf: owner retention is coarser than
fragment retention. `finalLeafSlice` remains `untracked`. Continuation ancestry
and local-Union causal ancestry also remain untracked. Selected admission and
source-child coverage are explicit per branch. Consequently the overall result is `partial`, delivery ancestry is
`untracked`, and these comparison counts cannot supply the Phase 3 fraction.

Snapshots use the existing private atomic receipt storage and 8 MiB bound. A
capture failure is reported and leaves attribution unavailable. It cannot grant
completion authority. The snapshot write is still hook work; its cost at large
DB sizes remains to be measured. Offline replay is an explicit diagnostic
command, not a second equality fold on the hook path. This adds no model calls
and establishes no LLM-token improvement or adoption claim.

## Completed branch validation (2026-10-20)

The isolated candidate passed the focused equality executable and the full
regression suite (88.53 s, aggregate descendant peak 2,793,968 KiB, 3,500,000 KiB
guard). Its three remaining DB-owned index tickets were drained by another
daemon without changing any graph head. The native fixture made 14 calls,
checked exact stdout/SHA-256 and accepted ACK, found the retained control
owner's branch, and rejected stale completion after changing the source file.
It deliberately used lexical fallback and made zero generation-model calls;
this does not measure numerical search or token savings.

The branch fixture isolates a congruence-dependent child deduplication from a
literal sibling, checks owner pruning and explicit unknowns, rejects invalid
comparison positions/terminals/owners, and retains the locator across the
existing demand-memo serialization. `ContractAudit` checks that production
snapshot capture calls the branch builder and does not rebuild explicit closure.

Sources, executables, failed and successful build logs, guard reports and native
stdout/analysis are retained under
`/Users/ovm/.codex/experiments/eggshell/selection-branches-20261020/`.
These are diagnostics on the development candidate, with no public-main
adoption or whole-delivery ancestry claim.

## Admission observation validation (2026-10-20)

Focused equality checks include an admission whose earlier negative comparison
must remain negative despite a later local Union, and a native completion where
all extraction comparisons are literal but original child membership requires
congruence. A separate real-DB regression calls the production indexed discovery
controller and requires the sparse original All frame, complete admission/child
coverage, and an unchanged read-only source head. The child-role executable
also checks congruent aliases, original positions, Exact barriers, memoized
negative reads and retired/corrected sources without hydrating its large
unrelated body.

The standard full-suite command passed in 88.68 s, aggregate peak 2,806,448 KiB.
Another daemon drained its three remaining index tickets with all heads
unchanged. The native fixture completed 14 calls, exact stdout/SHA-256 and ACK,
admission/child coverage, and source-change invalidation. Its first run wrongly
required an indexed witness even though the path had already loaded the original
topology. That failed assertion and the corrected fixture accepting both
documented representations are preserved; runtime code did not change for it.

An additional `work-first-tests` run remains **failed** at
`command semantic=true native=false union=false`. The frozen parent `f5b0218`
fails at the same first comparison. The fixture passes nominations to the
indexed controller but compares against direct `renderAutomatic` without those
presentation inputs; observed actual output was null and the expectation an
ordinary advisory handoff. The complete cause/correction remains unresolved.
This check was not weakened, removed, or counted as passing, and no delivery
policy was changed to address it. The standard full-suite command does not run
this additional executable path.

The unchanged fixed 48-hook warm diagnostic passed after admission observations
were enabled: complete discovery scoring, semantic search, original DB body,
stdout/publication and ACK, all within 5 s. Full raw and failed records,
frozen sources/executables and hash checks are under
`/Users/ovm/.codex/experiments/eggshell/admission-audit-20261020/` and
`semantic-latency-20261019-isolated/admission-audit-1/`. See the
[latency record](semantic-latency-results.md). No generation-model calls or
public-main token/quality adoption comparison were made. Large completed
snapshots, complete local/continuation ancestry and final fragment slicing
remain open.

## Local proposer validation (2026-10-20)

The real-DB regression now creates nonliteral local equality, verifies its
original negative fragment comparison, and checks that completed admission
actually uses that local Union. It rejects self/future prefixes, retrieval-only
proposals, absent alignment, foreign Inquiry scopes and duplicate origins.
Removing the proposer records leaves every generator explicitly unknown.

The real native fixture reads `probe.txt`, then requests `cat   ./probe.txt`.
Its completed control uses two local generators proposed together at prefix 0;
both original proposer records replay. Across 14 native/inspection calls, exact
stdout/SHA-256, accepted ACK, admission/child coverage and source-change
invalidation passed. Native hook maximum was 1,639 ms in this small fixture.

The standard full-suite command passed in 90.81 s, aggregate descendant peak
2,850,368 KiB. Its three remaining tickets were drained by another daemon with
all graph heads unchanged. The unchanged fixed 48-hook warm diagnostic also
passed, including all original discovery windows and stdout/publication/ACK,
under the 5 s gate. Source/executable hashes were frozen for measurement.
The known additional `work-first-tests` mismatch from the preceding milestone
was not rerun or counted as passing here.

Frozen code, executables, failed initial build, all guard logs and native
receipts are under
`/Users/ovm/.codex/experiments/eggshell/local-origin-20261020/`;
the fixed latency run is `semantic-latency-20261019-isolated/local-origin-1/`.
These checks made zero generation-model calls and do not establish public-main
token/quality adoption, large completed-snapshot cost or complete delivery
causal ancestry. The full goal remains active.

## Scheduling and continuation validation (2026-10-20)

The focused executable passed with real-DB production-controller cases for
literal completion, local generators and a generated continuation used by a
later selection. It rejects tasks absent from discovery, changed Demand/epoch
bindings, rematching synthetic children or the remainder, changed continuation
roots, future Match prefixes and nonautomatic child support. Removed schedules
or child support remain explicitly unknown. A retrieval-only case records an
open continuation without any local Union or completed use; absent Match
epochs remain null. These cases also run in the standard full-suite command.

That suite passed in 90.83 s, aggregate descendant peak 2,783,136 KiB under the
3,500,000 KiB guard. Another daemon drained three remaining tickets to zero
without changing any graph head. The separate original native fixture passed
14 calls, with a maximum native hook of 1,880 ms, final completed control,
stdout/SHA-256/ACK, recorded scheduling bindings and stale-source invalidation.
It generated no continuation, so it is not evidence for that component.

Additional partial-native probes requested an uncovered second command. The
first two wrongly expected the whole call to be denied; one had already
reconciled away the body, while the other delivered it as context. A third
probe confirmed body delivery but its `inspect-equality` call failed because
final reconciliation recorded `completed=0` and no equality locator. None of
these probes is counted as a passing final-completion fixture; no runtime
policy was changed for them. Direct offline replay of the third probe's
captured production stage passed: three scheduling steps, one continuation,
two local proposers, all supporting Match bindings and a subsequent generated
All use. Published bytes/SHA-256 and accepted ACK agree with the actual stdout.
This validates the captured stage before reconciliation, not final completed
delivery ancestry.

The unchanged fixed 48-hook warm protocol passed with every original discovery
window scored, semantic completion, original DB body, independent publication
bytes/SHA-256 and accepted ACK. Maximum hook latency was 3,927 ms, below the
unchanged 5 s gate. All 16 frozen hashes remained unchanged; the read-only
profile and protected-DB private-overlay conditions are included. These are
advisory fixtures, so they do not bound large completed-snapshot cost. Full
cell results are in [the latency record](semantic-latency-results.md).

Sources and executables were frozen before the final checks. All failed
probes, corrected raw-stage replay, guard logs and native records remain under
`/Users/ovm/.codex/experiments/eggshell/discovery-trace-20261020/`.
The additional known `work-first-tests` mismatch remains unresolved and was
not rerun or counted as passing. No generation-model calls, token adoption
comparison or complete causal-ancestry result is claimed.

## Selected All generation-link validation (2026-10-20)

The focused executable passed with shared-ancestor/sibling isolation, invalid
All-pool references, missing structural references, missing generation events
and missing final epochs. A real-DB completed branch must actually use a
recorded generated All. A use from the same scheduling pass is rejected, while
the final extraction may use that pass's new All. Future-only producers are
rejected. Removing generation telemetry preserves the generated flag and
leaves its origin untracked. The new branch-edge membership theorem passed
ContractAudit with only `propext` and `Quot.sound`.

The standard full-suite command passed in 90.06 s, aggregate descendant peak
2,887,920 KiB under the 3,500,000 KiB guard. Another daemon drained all three
remaining tickets without changing graph heads. A separate final completed
native control fixture passed 14 calls, exact stdout/SHA-256/ACK, scheduling
bindings and stale-source invalidation; its hook maximum was 1,065 ms.

A separate partial-native diagnostic passed ten binary calls and direct Lean
replay of its captured stage. Its one selected All is generated, is used on
the completed owner's branch and in later scheduling, and links to continuation
0 created in pass 1 and its original root Match. No structural comparison is
missing. Published bytes/SHA-256 and accepted ACK match the actual context.
Final reconciliation still records `completed=0` and no equality locator;
this is a stage-link/context diagnostic, not final completed delivery ancestry.
Both native fixtures deliberately use lexical fallback and no generation model.

The unchanged fixed 48-hook warm protocol passed complete original-window
scoring, semantic completion, original body delivery and independently checked
stdout/publication/SHA-256/ACK. Every hook was below 5 s, with a maximum of
4,055 ms. All 17 frozen hashes were unchanged. These advisory fixtures include
read-only profiles and the OS write-protected private-overlay layout; they
do not bound large completed-snapshot cost. See the full cells in
[the latency record](semantic-latency-results.md).

Frozen sources, executables, failed initial core builds, all guard logs and
native fixtures are under
`/Users/ovm/.codex/experiments/eggshell/continuation-links-20261020/`.
The known additional `work-first-tests` mismatch is retained and was not rerun
or counted as passing. Whole causal ancestry, final leaf slices and large
completed-snapshot cost remain open; no public-main token adoption is claimed.
