# Isolated structural Work integration

Apply `docs/candidates/structural-work-runtime.patch` to the preceding
Work-class candidate checkout. That checkout already contains
`Eggshell.WorkClassLookup` and the earlier isolated runtime changes. Do not apply
the patch to the product checkout. Copy the two `tools/research` sources here
into the corresponding paths in the isolated checkout.

Compile with Lean 4.33.0, regenerate the affected public runtime modules and
their callers, then link each audit entry object instead of Main. Do not reuse
stale specialized Handoff/PluginHooks objects after changing Match. The build
record distinguishes public `l_Eggshell_` objects from retained package-private
`lp_eggshell_` objects. Run ContractAudit and its refreshed proof dependencies.

```
StructuralWorkAudit small NEW-OUTPUT
StructuralHookAudit BINARY PLUGIN FIXTURE-DB FIXTURE-WORKSPACE NEW-OUTPUT plain
StructuralHookAudit BINARY PLUGIN FIXTURE-DB FIXTURE-WORKSPACE NEW-OUTPUT known
StructuralHookAudit BINARY PLUGIN FIXTURE-DB FIXTURE-WORKSPACE NEW-OUTPUT provider
```

Use a separate private `EGGSHELL_DATA_ROOT` for each run. The API audit creates
only its own small fixtures and refuses an existing output path. Use its `one.egg`
and `workspace` for native runs. PLUGIN's `bin/eggshelld` must contain exactly
BINARY's bytes. These launchers are executables; do not read them as text.
Provider mode uses an intentionally absent executable and downloads no model.

Native runs invoke the real daemon and codex-hook protocol in fresh chats.
They verify stdout/publication SHA, current receipt ownership, accepted ACKs for
memory/control, the direct producer stage, fresh/stale control and daemon exit.
An incomplete notice has a completed ACK RPC but no accepted memory offer.
All heavy jobs run serially under the aggregate 3.5 GiB guard; require sufficient
disk space before linking. Helpers may be deleted after their terminal results
are hashed. Never delete the source DB or raw evidence.

The review in `docs/candidates/structural-work-review.json` pins the actual build
scripts, source/object/runtime hashes and raw records. The original 32-case
literal-lane comparison uses the existing DeferredWorkAudit harness; it does not
compare the intentionally new structural producer. These are model-free checks,
not an inclusive-token or scale qualification.
