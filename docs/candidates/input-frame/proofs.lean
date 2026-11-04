module
import all Eggshell.Worker
import all Eggshell.OperationPool
import Lean
open Lean
run_meta do
  let env ← getEnv
  for (caller,required) in [
      (``Eggshell.Plugin.Worker.exchange,#[``Eggshell.Plugin.Worker.capturePrepared,``Eggshell.Plugin.Worker.Search.compactPrepared]),
      (``Eggshell.Plugin.OperationPool.validate,#[``Eggshell.Plugin.Worker.Search.referenceWellFormed,``Eggshell.PreparedInputs.acceptsBoundary]),
      (``Eggshell.Plugin.Worker.run,#[``Eggshell.Plugin.Worker.search]),
      (``Eggshell.Plugin.Worker.search,#[``Eggshell.Plugin.Worker.Search.restorePrepared,``Eggshell.Plugin.Worker.searchRestored]),
      (``Eggshell.Plugin.Worker.searchRestored,#[``Eggshell.Plugin.automaticHandoff,``Eggshell.Plugin.queueCheckpoint])] do
    let actual := (Compiler.getImplementedBy? env caller).getD caller
    let some declaration := env.find? (Compiler.mkUnsafeRecName actual) <|> env.find? actual
      | throwError "missing input-frame boundary implementation"
    let some body := declaration.value? | throwError "missing input-frame boundary body"
    for dependency in required do
      unless body.getUsedConstants.contains dependency do throwError "{caller} lost {dependency}"
#print axioms Eggshell.Plugin.Worker.Search.restore_refer
#print axioms Eggshell.Plugin.Worker.Search.refer_identity
#print axioms Eggshell.Plugin.Worker.Search.refer_asLexical
#print axioms Eggshell.Plugin.Worker.search_restoration_exact
