# Isolated original-window owner index

These sources are an unadopted candidate, not modules in the active library.
Copy their `Eggshell/` and `tools/` trees into the parent isolated checkout
described in `docs/candidates/window-owner-review.json`, keeping the exact
recorded `GraphStore`, `SourceDelta`, `CandidateDomain`, `VectorMatrix` and
PageMap dependencies. `include_str` resolves against that checkout's normal
`Eggshell/` directory.

The record binds the Lean/C/link inputs, preparation, all original-occurrence
checks, three fixed-key query runs, resource guards and failed attempts. Its
recorded build and check scripts live with the local experiment. The component
does not install a runtime, alter an original DB, or qualify token savings.

See `docs/window-owner-routing.md` for the invariant, measured scope and the
remaining keyed-provider/native integration.
