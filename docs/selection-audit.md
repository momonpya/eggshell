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
the source-child witness selected by the corpus membership predicate. Only
records corresponding to completed selected Matches are serialized. A later
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
