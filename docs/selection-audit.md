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

The snapshot covers the **whole selected extraction before source and transport
pruning**, alongside the owner lists that survived. It is not yet a dependency
slice for each surviving final fragment/leaf: owner retention is coarser than
fragment retention. `finalLeafSlice` remains `untracked`. Matcher admission, original sparse child-role
witnesses, continuation ancestry and local-Union causal ancestry remain
untracked. Consequently the overall result is `partial`, delivery ancestry is
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
