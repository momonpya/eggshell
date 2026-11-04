module
import all Eggshell.Handoff
import Lean
open Lean
run_meta do
  let env ← getEnv
  let caller := ``Eggshell.Plugin.indexedDiscoveryUsing
  let actual := (Compiler.getImplementedBy? env caller).getD caller
  let some declaration := env.find? (Compiler.mkUnsafeRecName actual) <|> env.find? actual
    | throwError "missing indexed query implementation"
  let some body := declaration.value? | throwError "missing indexed query body"
  for required in [``Eggshell.Plugin.citationReach,``Eggshell.Plugin.citedParents] do
    unless body.getUsedConstants.contains required do throwError "query lost {required}"
#print axioms Eggshell.Plugin.citedParents_exact
