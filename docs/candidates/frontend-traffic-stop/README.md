# Observe the frontend after ordinary shutdown

Diagnostic only; product runtime unchanged and not adopted. The sealed client
adds a sample of the exact frontend PID/program still present after the ordinary
shutdown command. It preserves that command's original deadline. A missing or
normally exited process is recorded explicitly rather than sampled as another
process. Existing delivery checkpoints, real stdout bodies and exact shutdown
stderr remain recorded.

The one fixed32-query/16-source/two-wave cohort does not reproduce the earlier
ordinary shutdown failure: frontend and publisher exit0, no process remains,
and no guard intervention occurs. All32 semantic searches deliver both required
original fields with ACK; all32 complete stdout bodies equal the retained parent.
Latency is5,710/7,126/7,970ms minimum/median/maximum. This is a synthetic diagnostic,
not a performance improvement, p99, real98% recall or eighty-person capacity.
There is no shutdown stack from this run because the frontend exits normally.

A separate model-free Lean control then reproduces the source-level ownership
hazard: a mutable local updated to`#[7]` inside`try` is still`#[]` in its captured
`finally` action. HookFrontend used the same pattern for its task arrays. The
subsequent [frontend-finalizer candidate](../frontend-finalizer/README.md)
uses the actual frontend to establish a deterministic old/new counterfactual.
The source-level control alone is not presented as the stack or cause of every
historical shutdown failure.

The selected diagnostic closure is consistent and its non-entry product sources
are identical to the sealed client parent. The entry changes only shutdown
observation. Original source heads remain unchanged. Completed earlier client
executables are removed after recording their SHA and exact body parity; their
required native inputs remain. Ended DBs, caches and raw logs are deleted by the
finalizer study, with no archives. No answering LLM is called.

[Plan](plan.json), [client/runtime hashes](build.json),
[native closure](native-closure.json), [unchanged product sources](native-sources.json),
[capture control](finally-capture.json), [actual evidence](evidence.json),
[bodies](bodies.json), [verification](verification.json), [parity](parity.json),
[shutdown observation](shutdown-sample.json), [measurements](measurements.json),
[retired clients](retired-clients.json).
