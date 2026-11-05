module
import all Eggshell.Handoff
import Lean
open Lean
run_meta do
  let env ← getEnv
  for (caller,required) in [
      (``Eggshell.Plugin.federatedDiscovery,#[``Eggshell.Plugin.preparedOwnerBinding,``Eggshell.Plugin.knownOwner,``Eggshell.Plugin.originalPositions]),
      (``Eggshell.Plugin.preparedOwnerBinding,#[``Eggshell.SourceOwners.Reader.originals,``Eggshell.Plugin.checkPreparedOriginals]),
      (``Eggshell.Plugin.checkPreparedOriginals,#[``Eggshell.DB.PageMap.Snapshot.get,``Eggshell.Persistence.Store.getNat])] do
    let actual := (Compiler.getImplementedBy? env caller).getD caller
    let some declaration := env.find? (Compiler.mkUnsafeRecName actual) <|> env.find? actual
      | throwError "missing prepared owner binding implementation"
    let some body := declaration.value? | throwError "missing prepared owner binding body"
    for dependency in required do
      unless body.getUsedConstants.contains dependency do throwError "{caller} lost {dependency}"
#print axioms Eggshell.Plugin.known_owner_hit
#print axioms Eggshell.Plugin.unknown_owner_fallback
#print axioms Eggshell.Plugin.original_positions_complete
