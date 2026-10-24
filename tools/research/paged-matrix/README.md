# Isolated paged projection store

Reviewable source copies, not modules adopted into the product build. Apply
`docs/candidates/paged-matrix-runtime.patch` with `git apply --unidiff-zero` to
the pinned lexical-point candidate. Source changes are direct Lean edits.

`VectorMatrix.lean` implements paged projections and internal per-root writer
ownership. `PagedMatrixSmoke.lean` tests storage boundaries, failure/replacement,
independent DBs and concurrent readers/writers. `PagedMatrixAudit.lean` has an
independent flat-artifact reader used only for comparison with the existing
audited inputs. The candidate has no flat-format compatibility reader.

See `docs/paged-projection-store.md` for the actual full-read regression and
unqualified boundaries. Source bits agree; no token improvement or product
adoption is established.
