module
import all Eggshell.HookFrontend
import Lean
open Lean
run_meta do
  for (caller,required) in [
      (``Eggshell.Plugin.HookFrontend.run,
        #[``Eggshell.Plugin.HookFrontend.Session.touch,``Eggshell.Plugin.HookFrontend.Session.finish,
          ``Eggshell.Plugin.HookFrontend.retirementIndex?,``Eggshell.Plugin.HookFrontend.Session.canRetire]),
      (``Eggshell.Plugin.HookFrontend.Session.refresh,
        #[``Eggshell.Plugin.flushDeferred,``Eggshell.Plugin.flushIndexesResult,
          ``Eggshell.Plugin.preparationWake,``Eggshell.Plugin.withSession,
          ``Eggshell.Plugin.HookFrontend.Session.closedAndDrained]),
      (``Eggshell.Plugin.HookFrontend.retirementIndex?,#[``Eggshell.Plugin.HookFrontend.Session.canRetire]),
      (``Eggshell.Plugin.HookFrontend.Session.closedAndDrained,#[``Eggshell.Plugin.readJson?])] do
    let env ← getEnv
    let actual := (Compiler.getImplementedBy? env caller).getD caller
    let some declaration := env.find? (Compiler.mkUnsafeRecName actual) <|> env.find? actual
      | throwError "missing frontend implementation: {caller}"
    let some body := declaration.value? | throwError "missing frontend body: {caller}"
    for dependency in required do
      unless body.getUsedConstants.contains dependency do throwError "{caller} lost {dependency}"
#print axioms Eggshell.Plugin.HookFrontend.Session.stale_result_ignored
#print axioms Eggshell.Plugin.HookFrontend.Session.touch_invalidates_quiet
#print axioms Eggshell.Plugin.HookFrontend.Session.active_not_retired
#print axioms Eggshell.Plugin.HookFrontend.Session.pending_not_retired
#print axioms Eggshell.Plugin.HookFrontend.Session.maintenance_not_retired
