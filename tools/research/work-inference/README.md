# Isolated Work-only inference stage

`Eggshell/WorkInference.lean` and the native audit are reviewable source copies.
The exact patch in `docs/candidates/work-inference-runtime.patch` applies with
`git apply --unidiff-zero` to the pinned source-delta candidate. It also factors
the existing Matcher primitives and extends ContractAudit and the frozen oracle's
unfold proof; product files in this Git checkout remain unchanged.

The component proves complete ordered proposal equality for one fixed pass.
It is a prerequisite for deferring Outcome hydration, not a replacement for the
complete discovery scheduler or a matched token adoption result.
See `docs/work-only-inference.md` and the candidate review for scope and evidence.
