# Isolated lexical point reader

These are reviewable source copies, not modules imported by the product build.
Apply `docs/candidates/lexical-reads-runtime.patch` with `git apply --unidiff-zero`
to the pinned row-matrix candidate, not directly to a different product source.
The patch adds these modules and changes two Handoff lookup constructors.

`LexicalReads.lean` batches original authenticated B-tree point paths without
loading complete metadata namespaces. `LexicalReadsAudit.lean` compares original
ordered postings, logical traces, malformed membership and bounded point reads.
The same unchanged native `HookScaleRun.lean` harness checks actual stdout and
ACK behavior. See `docs/lexical-point-batches.md` for evidence and limitations.

This candidate is unadopted. Proofs and model-free checks do not establish
token savings, p99, or million-window readiness.
