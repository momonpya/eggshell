# Isolated incremental projection candidate

These are reviewable source copies, not modules adopted into the product build.
Apply `docs/candidates/incremental-projections-runtime.patch` with
`git apply --unidiff-zero` to the pinned paged-projection candidate.

VectorMatrix reuses PageMap's append-only chunks, authenticated COW directory
and atomic head. The smoke executable tests additions, original references,
concurrency, killed-writer recovery and repair. The audit has an independent
flat-reference reader and exercises the actual SearchProvider preparation path.
The flat reader is audit-only, not a compatibility path in the runtime.

See `docs/incremental-projections.md` and the candidate review for the measurements,
retained failed runs and scope. Full-key verification and full scans remain slow;
no token improvement, full-hook qualification or product adoption is established.
