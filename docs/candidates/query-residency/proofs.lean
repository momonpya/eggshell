module
import all Eggshell.PublicationService
import all Eggshell.SynapseRecommend
import all Eggshell.Handoff
import Lean
open Lean
run_meta do
  let env ← getEnv
  for (caller,required) in [
      (``Eggshell.Plugin.Publication.Service.prepareSourceBatch,#[``Eggshell.Plugin.Publication.Service.prepareSource,``Eggshell.TaskDeadline.ensureLive]),
      (``Eggshell.Plugin.Publication.Service.prepareSource,#[``Eggshell.Plugin.Publication.Service.prepareRegistered]),
      (``Eggshell.Plugin.Publication.Service.releaseRetainedSourceBatch,#[``Eggshell.Plugin.Publication.Service.releaseRetainedSource]),
      (``Eggshell.Plugin.Publication.Service.releaseRetainedSource,#[``Eggshell.Plugin.Publication.Service.scopedSource]),
      (``Eggshell.Plugin.Publication.Client.prepareSourcesUsing,#[``Eggshell.Plugin.Publication.Client.checkedSourceBatch]),
      (``Eggshell.Plugin.Publication.Client.checkedSourceBatch,#[``Eggshell.Plugin.Publication.Client.checkedSourceReference]),
      (``Eggshell.Synapses.Recommend.capturedLocal,#[``Eggshell.PreparedInputs.shared,``Eggshell.PreparedInputs.usage]),
      (``Eggshell.Synapses.Recommend.prepareMany,#[``Eggshell.Synapses.Recommend.capturedLocal,``Eggshell.Plugin.Publication.Client.retainSources]),
      (``Eggshell.Plugin.automaticHandoff,#[``Eggshell.Synapses.Recommend.prepareMany,``Eggshell.Synapses.Recommend.releaseMany])] do
    let actual := (Compiler.getImplementedBy? env caller).getD caller
    let some declaration := env.find? (Compiler.mkUnsafeRecName actual) <|> env.find? actual
      | throwError "missing source-pin implementation"
    let some body := declaration.value? | throwError "missing source-pin implementation body"
    for dependency in required do
      unless body.getUsedConstants.contains dependency do throwError "{caller} lost {dependency}"
#print axioms Eggshell.Synapses.Recommend.attach_source
#print axioms Eggshell.Synapses.Recommend.attach_private_usage
