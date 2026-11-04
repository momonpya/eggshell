module
import all Eggshell.PluginHooks
import all Eggshell.OperationPool
import Lean
open Lean
partial def occurrences (wanted : Name) : Expr → Nat
  | .const name _ => if name == wanted then 1 else 0
  | .app fn arg => occurrences wanted fn+occurrences wanted arg
  | .lam _ type body _ | .forallE _ type body _ => occurrences wanted type+occurrences wanted body
  | .letE _ type value body _ => occurrences wanted type+occurrences wanted value+occurrences wanted body
  | .mdata _ body | .proj _ _ body => occurrences wanted body
  | _ => 0
run_meta do
  for (caller,required,forbidden) in [
      (``Eggshell.Plugin.OperationPool.searchOperation,#[``Eggshell.Plugin.Worker.executeUsing,``Eggshell.Plugin.Worker.exchangeLocal],#[]),
      (``Eggshell.Plugin.OperationPool.Pool.run,#[``Eggshell.Plugin.OperationPool.searchOperation],#[]),
      (``Eggshell.Plugin.Worker.run,#[``Eggshell.Plugin.Worker.search],#[]),
      (``Eggshell.Plugin.Worker.executeUsing,
        #[``Eggshell.Plugin.Worker.Search.asLexical,``Eggshell.Plugin.Worker.phaseObservation],
        #[``Eggshell.Plugin.Worker.exchange,``Eggshell.Plugin.registerIndexTarget]),
      (``Eggshell.Plugin.Worker.exchangeSlot,#[``Eggshell.Plugin.Worker.retire,``IO.wait],#[]),
      (``Eggshell.Plugin.Worker.retire,#[``Eggshell.Plugin.Worker.killGroup],#[]),
      (``Eggshell.Plugin.Worker.awaitSearch,#[``IO.checkCanceled],#[]),
      (``Eggshell.Plugin.deliverForWork,
        #[``Eggshell.Plugin.Worker.exchange,``Eggshell.Plugin.Worker.SearchReply.decode,
          ``Eggshell.Plugin.Worker.SearchDelivery.ofReply,``Eggshell.Plugin.emptySearchResult],#[])] do
    let env ← getEnv
    let actual := (Compiler.getImplementedBy? env caller).getD caller
    let some declaration := env.find? (Compiler.mkUnsafeRecName actual) <|> env.find? actual
      | throwError "missing single-search implementation: {caller}"
    let some body := declaration.value? | throwError "missing single-search body: {caller}"
    for dependency in required do
      unless body.getUsedConstants.contains dependency do throwError "{caller} lost {dependency}"
    for dependency in forbidden do
      if body.getUsedConstants.contains dependency then throwError "{caller} regained {dependency}"
    if caller == ``Eggshell.Plugin.deliverForWork then
      unless occurrences ``Eggshell.Plugin.Worker.exchange body == 1 do
        throwError "delivery does not contain exactly one operation admission"
#print axioms Eggshell.Plugin.Worker.lexical_preserves_frozen_inputs
#print axioms Eggshell.Plugin.Worker.phase_preserves_upstream
#print axioms Eggshell.Plugin.Worker.no_ready_preserves_phase
#print axioms Eggshell.Plugin.Worker.empty_handoff_is_complete
#print axioms Eggshell.Plugin.Worker.absent_transport_is_not_reply
