module
import all Eggshell.NativePublication
import Lean
open Lean

run_meta do
  for (caller,required) in [
      (``Eggshell.Plugin.NativePublication.runPreparedAt,
        #[``Eggshell.Plugin.NativePublication.bindMetadata,``Eggshell.Plugin.NativePublication.promotedOwners]),
      (``Eggshell.Plugin.NativePublication.promotedOwners,
        #[``Eggshell.Persistence.Store.Intern.value,``Eggshell.DB.PageMap.Writer.get])] do
    let env ← getEnv
    let actual := (Compiler.getImplementedBy? env caller).getD caller
    let some declaration := env.find? (Compiler.mkUnsafeRecName actual) <|> env.find? actual
      | throwError "missing native metadata owner: {caller}"
    let some body := declaration.value? | throwError "missing implementation: {caller}"
    for dependency in required do
      unless body.getUsedConstants.contains dependency do throwError "{caller} lost {dependency}"

#print axioms Eggshell.Plugin.NativePublication.bound_affected_exact
#print axioms Eggshell.Plugin.NativePublication.bound_owner_has_delta
#print axioms Eggshell.Persistence.Store.Change.authoritative_neutral_rejected
