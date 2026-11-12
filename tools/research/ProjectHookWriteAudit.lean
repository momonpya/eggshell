module
import all Eggshell.ProjectIngress
import all Eggshell.ProjectHookRead
import all Eggshell.PluginHooks
import all Eggshell.PublicationService
import Lean
open Lean Eggshell.Plugin
#print axioms project_target_has_no_path
#print axioms final_capture_preserves_service
#print axioms ProjectIngress.final_compiles_turn
#print axioms Publication.Gateway.captured_keeps_writer
#print axioms ProjectHookRead.native_is_not_advisory
#print axioms remote_native_delivery_has_no_effect
#print axioms Publication.Read.advice_never_completes
#print axioms ProjectHookRead.restored_has_no_completion
run_meta do
  let env ← getEnv
  for (caller,required) in #[
      (``Worker.run,``Worker.publishProject),
      (``Worker.publishProject,``ProjectIngress.writer),
      (``Worker.publishProject,``ProjectIngress.capsule),
      (``Worker.publishProject,``Publication.Gateway.Peer.publish),
      (``ProjectIngress.capsule,``ProjectIngress.observationsOnly),
      (``ProjectIngress.capsule,``NativePublication.planUsing),
      (``ProjectIngress.capsule,``Publication.Capsule.ofItems),
      (``Publication.Service.serveClient,``Publication.Service.registerProjectPreparation),
      (``Publication.Service.registerProjectPreparation,``registerIndexTarget),
      (``Publication.Service.registerProjectPreparation,``Publication.Owned.Pool.markPreparationRegistered),
      (``deliverForWork,``ProjectHookRead.advisoryEligible),
      (``deliverForWork,``ProjectHookRead.exchange)] do
    let some decl := env.find? caller | throwError "Missing project-hook caller: {caller}"
    let some body := decl.value? | throwError "Missing project-hook body: {caller}"
    unless body.getUsedConstants.contains required do throwError "Project hook bypasses {required}: {caller}"
  let mut pending := [``ProjectHookRead.capture,``ProjectHookRead.exchange]
  let mut seen : NameSet := {}
  while let name :: rest := pending do
    pending := rest
    if seen.contains name then continue
    seen := seen.insert name
    if #[``Eggshell.ProjectStore.openProject,``Eggshell.DB.PageMap.pin,
        ``Eggshell.PreparedInputs.load?,``IO.FS.readFile,``IO.FS.readBinFile].contains name then
      throwError "Remote-only adapter reaches local project reads: {name}"
    if let some decl := env.find? name then
      if let some body := decl.value? then pending := body.getUsedConstants.toList++pending
  logInfo m!"Project-hook read adapter: {seen.size} declarations; no local project-file reads."
