import Eggshell.PreparationPlan
import Eggshell.PluginHooks
import Eggshell.PreparationService
import Lean

open Lean Eggshell Eggshell.Plugin

run_meta do
  for (name,required,forbidden) in [
      (``PreparationService.Pool.run,[``Worker.exchange,``PreparationRegistry.invocation],
        [``PreparationRegistry.workerPayload,``PreparationRegistry.complete,``DB.PageMap.pin]),
      (``drainIndexTarget,[``Publication.Client.enqueuePreparation],
        [``Worker.exchange,``Warm.required,``IndexTarget.indexes]),
      (``PreparationRegistry.workerPayload,[``PreparationRegistry.complete],
        [``PreparationRegistry.drained]),
      (``Worker.maintenance,[``Worker.indexActionWithState,``PreparationRegistry.drained],[])] do
    let info ← getConstInfo name
    let some body := info.value? | throwError "preparation boundary is not auditable: {name}"
    let used := body.getUsedConstants
    for dependency in required do
      unless used.contains dependency do throwError "preparation boundary lost {dependency}: {name}"
    for dependency in forbidden do
      if used.contains dependency then throwError "preparation boundary performs worker IO {dependency}: {name}"

theorem external_inputs_still_require_validation
    (previous : Synapses.Journal.Checkpoint) (source : DB.PageMap.Snapshot)
    (index : String) (count limit : Nat) (external : previous.external = true) :
    previous.sameInput source index count limit = pure false := by
  simp [Synapses.Journal.Checkpoint.sameInput,external]

#print axioms PreparationPlan.requests_bounded
#print axioms PreparationPlan.metadata_bounded
#print axioms PreparationPlan.active_workers_bounded
#print axioms PreparationPlan.close_is_terminal
#print axioms PreparationPlan.closed_refuses_notification
#print axioms PreparationPlan.closed_starts_no_work
#print axioms PreparationPlan.Wake.failed_is_pending
#print axioms PreparationPlan.Wake.newer_is_pending
#print axioms external_inputs_still_require_validation
