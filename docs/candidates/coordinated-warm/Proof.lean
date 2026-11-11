import Eggshell.ExplicitWarm
open Lean Eggshell

example (now requested : Nat) :
    PreparationPlan.waiterExpiry now requested Plugin.OperationWire.searchBudgetMs =
      min requested (now+Plugin.OperationWire.searchBudgetMs) :=
  PreparationPlan.waiterExpiry_query_unchanged now requested

run_elab do
  let env ← getEnv
  for (consumer,required,forbidden) in #[
      (``Plugin.ExplicitWarm.run,
        #[``Plugin.Publication.Client.openWarmPreparation,``Plugin.Publication.Client.claimPreparations],
        #[``Warm.run,``Warm.runTarget,``DB.Sidecar.withIndexClaim]),
      (``PreparedInputs.publish,#[``PreparedInputs.StoredReference.make],#[]),
      (``PreparedInputs.capture,#[``RetrievalResearch.Index.openStored?],#[``RetrievalResearch.Index.openLocated?]),
      (``OwnerViews.prepareSource,#[``OwnerViews.loadStored?],#[``OwnerViews.loadOne?])] do
    let some value := (env.find? consumer).bind (·.value?) | throwError "missing actual warm consumer"
    let calls := value.getUsedConstants
    unless required.all calls.contains && forbidden.all (!calls.contains ·) do
      throwError "warm or shared-reference producer bypassed its checked boundary"

#print axioms PreparationPlan.waiterExpiry_requested
#print axioms PreparationPlan.waiterExpiry_window
#print axioms PreparationPlan.waiterExpiry_bounded
#print axioms PreparationPlan.waiterExpiry_query_unchanged
#print axioms PreparedInputs.Reference.shared_storage
#print axioms PreparedInputs.StoredReference.shared_is_portable
