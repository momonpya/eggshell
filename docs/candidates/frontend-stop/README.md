# Remove unrelated model ownership from frontend processes

Isolated candidate, not adopted. Answering-model calls remain0 and paid
comparisons0/18. The ordinary frontend shutdown failure remains unresolved.

The process entry point previously acquired a numerical keeper for frontend,
hook transport and administrative commands, even when they never requested a
model. Its finalizer could then wait for numerical ownership unrelated to the
command. A captured stop stack reaches `Numerical.release` and the OS lock
attempt. With the same unrelated exclusive owner guard held, the parent
shutdown command fails after10,285ms; the role-only candidate succeeds in277ms.
This control establishes the unnecessary dependency, not the cause of every
observed shutdown failure.

[Main.patch](Main.patch) keeps process-level model ownership only for the
publication service and explicit bulk warm. Numerical providers retain their
own scoped clients. Four Lean laws and a declaration audit connect the actual
entry point, role predicate and client lifetime. No lock is replaced by CAS;
the unrelated ownership operation is absent from the frontend branch.

The lifecycle control also exposed an independent child-reaping defect.
An IO expression in `samePid && (← child.tryWait).isSome` executes before the
Boolean condition, so a liveness query can reap a different child. The small
negative control records `matches=false,pollCalls=1`. [Numerical.patch](Numerical.patch)
moves the ownership test outside polling IO. Two Lean laws establish that a
foreign PID never executes the supplied poll and that an owned PID does. An
actual exited-child control confirms an unrelated child remains waitable.
The registry mutex remains because this operation changes child ownership;
it is not an immutable-data read.

The native lifetime control stops the frontend in8ms while the numerical
service remains alive under its client/publication owners, then verifies that
the last owner retires and reaps it. No model is loaded. Eighty concurrent
registrations stop in289ms with no survivors. Replaying the failed cohort's
existing private session state, without new searches, stops in295ms despite
two active and thirty pending maintenance tasks. This replay does not reproduce
the full-traffic failure and is not evidence that it is fixed. The separate
reply-disconnect control also exits normally; a disconnected shutdown reply
is not established as the cause.

The changed-runtime ordinary cohort completes32/32 semantic searches, delivers
both required original fields with ACK32/32, and preserves all32 parent stdout
bodies byte for byte. Latencies are5,710/6,897/7,812ms minimum/median/maximum.
Nevertheless the frontend shutdown command exits1 with
`eggshelld acknowledged shutdown but has not exited`; the guard reaps remaining
processes. Publication shutdown exits0. Related peak RSS is2,775,760KiB. No
unchanged eighty-search cohort was retried and no deadline or resource limit
was increased. This synthetic corpus does not measure real98% evidence recall,
answer quality, inclusive-token improvement, or eighty-person sustained use.

The extra [read-lock audit](read-lock-audit.json) checks the current native
interfaces and actual selector/service connections. It traverses1,894
dependencies of captured original/metadata/window reads, pure file metadata
and immutable page lookup, rejecting shared mutexes, IO references, promises,
tasks, waits and file-lock entry points. The page-reader specialization laws
also establish that reader lookup/insertion reaches only its private front,
without a shared owner. Ordinary ContractAudit and the laws use only standard
Lean axioms. This is a source/kernel dependency audit, not a proof of the OS,
FFI, or all concurrent IO.

The earlier file/metadata native controls complete80 independent reads while
the originating cache mutex is held. Their recorded controls are linked from
[pure-file-reads](../pure-file-reads/README.md) and
[prepared-focus](../prepared-focus/README.md). This candidate retains those
read implementations; it does not rerun or relabel them as full hooks.
Mutable admission, cache fill/eviction, active-lease accounting and numerical
pipe exchange still synchronize. They must be evaluated separately; deleting
their mutexes alone would not prove absence of races. Captured immutable reads
must continue to receive values without those mutable capabilities.

Exact native source audits limit runtime changes to Main and Numerical plus
their embedded identity inputs. Numerical implementation bytes contribute to
its service key, so the latter change creates a new service namespace. Failed
builds and the ECHILD lifecycle control remain in the evidence. Ended DBs,
caches, session data and raw logs are deleted after recording actual bodies.
Unselected obsolete objects totaling945,114,192 bytes are deleted only after
checking every retained executable's link response; required objects, source
witnesses, dependency stamps and interfaces remain. No archives are made.

[Role build/laws](build.json), [owned-poll build/laws](build-owned.json),
[role native sources](native-sources.json), [owned-poll native sources](native-owned-sources.json),
[native closure](native-owned-closure.json), [all controls](controls.json),
[model-free diagnostic controls](diagnostics.json), [actual body evidence](evidence.json),
[retained bodies](bodies.json), [independent verification](verification.json),
[parent parity](parity.json), [stage/shutdown measurements](measurements.json),
[failures](development.json), [cleanup](cleanup.json).
