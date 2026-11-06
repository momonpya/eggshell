# Finalize the live frontend task owners

Isolated candidate; not adopted. This study repairs an actual missing-client
finalization defect. It does not establish that every historical shutdown
failure has this cause, and does not pass the eighty-person/real98%/token gates.

HookFrontend kept readers, clients and maintenance tasks in mutable local arrays.
The`finally` action captured their initial empty values, so it could return
without cancelling or joining a handler still running at shutdown. The prior
[capture control](../frontend-traffic-stop/finally-capture.json) reproduces this
Lean behavior without searches. The source pattern also explains why the old
cleanup code looked correct while failing to own its current tasks.

[HookFrontend.patch](HookFrontend.patch) replaces those captured locals with one
live registry owned exclusively by the frontend event loop. Tasks receive their
own inputs, never that registry. Registration and completed-task removal update
immutable ownership values through the loop's private reference. After the loop
stops,`finally` reads its current value and cancels/joins the recorded tasks.
No mutex or CAS is added. Source persistence, publication, model lifetime,
request actors, budgets and deadlines retain their existing contracts.

Six Lean laws establish that each registration contains the new task and
preserves the other ownership collections. An actual declaration audit connects
registration and finalization to the running frontend. Ordinary ContractAudit
passes. The registration laws use only`propext`; preservation needs no axioms.
These are source/kernel properties, not a formalization of OS or FFI execution.

The native counterfactual runs exactly the same control body against the
unchanged parent core and candidate. It keeps a real frontend handler active
when a real shutdown request arrives. The old core returns before that handler
is retired, triggering`frontend returned with an unjoined active client`.
Only the control's external cleanup releases it afterward. The candidate
cancels and joins it before returning, in8ms, without that external release.
Both controls end with no surviving owned processes. Neither calls a search or
answering model. The reference excludes only the candidate-specific proof
header; the native test body SHA is identical. Its complete native source
audit shows zero product changes from the parent.

The candidate changes only HookFrontend in its254-module native closure. Its
ordinary32-query/16-source/two-wave cohort then completes semantic search and
both required original fields with ACK32/32. All32 complete stdout bodies match
the immediately preceding unchanged-runtime diagnostic. Prime included,35
actual outputs are independently verified. Hook latency is5,774/7,156/9,084ms
minimum/median/maximum; this single cohort does not show a speed improvement.

Frontend shutdown is315ms/exit0/stderr empty; publisher exits0 and the guard
does not intervene. No owned process remains. Related peak RSS is2,744,416KiB.
The publication host still grows176,544→656,128→886,864KiB across prime/two
waves. That remaining memory behavior, earlier eighty-search capacity failure,
full mixed/growing-project workload and NAS/multi-host behavior remain open.
No unchanged eighty-search retry is performed. The ordinary diagnostic parent
also shuts down cleanly; the deterministic active-handler counterfactual is
the causal evidence for this specific repair.

The source catalogue, vector/synaptic ranks, full e-class certification and
delivery selection do not change. Synthetic32/32 delivery is not real98%
necessary-evidence recall, answer-quality preservation or inclusive-token
improvement. No answering LLM is called; paid comparisons remain0/18. Product,
README performance claims and release adoption remain gated by matched trials.

After actual body and counterfactual evidence is retained, all ended study DBs,
caches, private sessions and raw logs are deleted. Earlier diagnostic,
intermediate and reference executables are removed after SHA/ownership checks;
required objects, source/dependency witnesses and interfaces remain. No archives
are created and the active baseline alias is restored.

[Plan](plan.json), [build/laws](build.json), [native closure](native-closure.json),
[exact source changes](native-sources.json), [native controls](native-checks.json),
[reference body seal](reference-control-plan.json), [reference build](reference-build.json),
[reference unchanged sources](reference-native-sources.json),
[actual evidence](evidence.json), [bodies](bodies.json), [verification](verification.json),
[parity](parity.json), [summary](summary.json), [measurements](measurements.json),
[all guards](controls.json), [development failures](development.json),
[cleanup](cleanup.json).
