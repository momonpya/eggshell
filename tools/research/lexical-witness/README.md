# Original lexical witnesses

This is an isolated Lean experiment, not an adopted product change. Apply
`docs/candidates/lexical-witness-runtime.patch` to the exact separated-discovery
candidate named by its review, then copy the two helpers into `tools/research/`.
Build all affected public callers, not only the changed leaf module. The review
pins source, generated code, linked objects, response files and guarded runs.

`LexicalReadsAudit DB NEW-OUTPUT` opens the original prepared lexical index.
The scalar `RetrievalResearch.Index.Reader.posting` is the independent oracle.
Results include ordered owners, counts, error strings and full ordered logical
read traces after resetting them between terms. It also compares each nominated
owner's certified ordinal with the original member getter. Small owned fixtures
cover malformed values, conflicting cached ordinals, trace reset and publication
changes. Original source and index publication files must remain unchanged.

`LexicalWitnessContract.lean` checks ordinary axioms for the original-byte
witness invariants. It does not prove filesystem IO refinement. The first
candidate decoder remains the original IO function, and all cache hits replay
its logical observations. No answering model, seed or new numerical runtime is
needed for these checks.
