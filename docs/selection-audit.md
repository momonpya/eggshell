# Selected equality receipts

The development candidate pins the actual selected extraction behind a completed
handoff. A `selection-*.json` stage contains its current persistent and local
Union generators, Work comparisons and completed source-owner identities. It
contains the chosen All-parent, Outcome-owner and positive child-deduplication
comparisons. The production extraction's existing validity proof supplies the
report; the hook does not build another explicit-only partition.

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

The snapshot covers the **whole selected extraction before source and transport
pruning**, alongside the owner lists that survived. It is not yet a dependency
slice for each surviving leaf. Matcher admission, original sparse child-role
witnesses, continuation ancestry and local-Union causal ancestry remain
untracked. Consequently the overall result is `partial`, delivery ancestry is
`untracked`, and these comparison counts cannot supply the Phase 3 fraction.

Snapshots use the existing private atomic receipt storage and 8 MiB bound. A
capture failure is reported and leaves attribution unavailable. It cannot grant
completion authority. The snapshot write is still hook work; its cost at large
DB sizes remains to be measured. Offline replay is an explicit diagnostic
command, not a second equality fold on the hook path. This adds no model calls
and establishes no LLM-token improvement or adoption claim.
