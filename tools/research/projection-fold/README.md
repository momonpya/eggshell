# Isolated stable projection fold

The runtime patch applies with `git apply --unidiff-zero` to the pinned
admission-policy checkout. It adds the generic exact append helper, a proved
compiler replacement for `projectMatches`, and ContractAudit entries.
Handoff source bytes are unchanged, but the generated caller must be rebuilt.
The tested C/object and caller check are pinned in the review.

The controlled/native helpers reuse the retained unchanged source and objects.
Profiling uses the same controlled executable in a separate cohort; its times
are excluded. See `docs/projection-fold.md` for results and limits. This does
not implement persistent canonical recognition or qualify product adoption.
