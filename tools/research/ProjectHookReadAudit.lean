module
import all Eggshell.ProjectHookRead
import all Eggshell.PluginHooks
import Lean
open Lean Eggshell.Plugin
#print axioms ProjectHookRead.restored_has_no_completion
#print axioms Publication.Read.advice_never_completes
#print axioms Publication.Read.response_keeps_inputs
#print axioms clear_forgets_delivery_projection
#print axioms clear_forgets_claims
run_meta do
  let env ← getEnv
  for (caller,required) in #[
      (``userPromptSubmit,``ProjectHookRead.capture),
      (``deliverForWork,``ProjectHookRead.exchange),
      (``deliverForWork,``Worker.SearchDelivery.ofDecoded),
      (``deliverForWork,``Handoff.reconcileDelivery),
      (``deliverForWork,``Handoff.acknowledgmentProjection),
      (``ProjectHookRead.capture,``Worker.withRemoteRequest),
      (``ProjectHookRead.capture,``Publication.Gateway.withPeer),
      (``ProjectHookRead.capture,``Publication.Gateway.Peer.pin),
      (``ProjectHookRead.exchange,``Worker.withRemoteRequest),
      (``ProjectHookRead.exchange,``Publication.Gateway.Peer.accepts),
      (``ProjectHookRead.exchange,``Publication.Gateway.Peer.query),
      (``ProjectHookRead.exchange,``ProjectHookRead.handoff),
      (``ProjectHookRead.handoff,``ProjectHookRead.restored),
      (``Worker.exchange,``Worker.withRemoteRequest)] do
    let some decl := env.find? caller | throwError "Missing remote-hook caller: {caller}"
    let some body := decl.value? | throwError "Missing remote-hook body: {caller}"
    unless body.getUsedConstants.contains required do throwError "Remote hook bypasses {required}: {caller}"
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
  logInfo m!"Remote-hook adapter: {seen.size} declarations; no local project-file reads."
