module
import all Eggshell.SynapseTransport
import Lean
open Lean
run_meta do
  let env ← getEnv
  for (caller,required) in [
      (``Eggshell.Synapses.Transport.build,#[``Eggshell.Synapses.Transport.bindingProjection,``Eggshell.Synapses.Routed.collect,
        ``Eggshell.Plugin.Publication.Client.sourceRecords,``Eggshell.Plugin.Publication.Client.sourcePalettes]),
      (``Eggshell.Synapses.Transport.bindingProjection,#[``Eggshell.Plugin.Publication.Client.sourceBindings])] do
    let actual := (Compiler.getImplementedBy? env caller).getD caller
    let some declaration := env.find? (Compiler.mkUnsafeRecName actual) <|> env.find? actual
      | throwError "missing original projection implementation"
    let some body := declaration.value? | throwError "missing projection body"
    for dependency in required do
      unless body.getUsedConstants.contains dependency do throwError "{caller} lost {dependency}"
#print axioms Eggshell.Synapses.Transport.empty_binding_projection
#print axioms Eggshell.Synapses.Transport.nonempty_binding_projection
#print axioms Eggshell.Synapses.Transport.unprepared_binding_projection
