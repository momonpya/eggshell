# Isolated original Work-class query

Copy `Eggshell/WorkClassLookup.lean` and the two `tools/research` files into the
projection-fold candidate checkout. Compile with Lean 4.33.0; link the audit's
entry object instead of Main, adding the module's object. Run
`WorkClassContract.lean` for the ordinary-proof axiom audit.

```
WorkClassAudit small NEW-OUTPUT
WorkClassAudit run EXISTING-DB NEW-OUTPUT
```

Existing output paths are refused. Small mode writes only its own fixtures.
Run mode pins the input DB read-only and constructs the complete original Work
oracle outside timing. Sixty class probes use fresh request-local readers.
The alias is an in-memory run-local Union, never a source mutation. No answering
model, encoder, warm or source repair runs. Heavy work runs serially under the
aggregate 3.5 GiB guard.

This is not a hook or adoption qualification. See `docs/work-class-lookup.md`
and its review for the source/link hashes, actual build script and raw records.
