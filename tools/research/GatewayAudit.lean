module
import all Eggshell.ProjectGatewayPeer
import all Eggshell.ProjectPublication
import Lean
open Lean

#print axioms Eggshell.Plugin.Publication.Gateway.boundary_keeps_all_projects
#print axioms Eggshell.Plugin.Publication.Gateway.readonly_rejects_publication
#print axioms Eggshell.Plugin.Publication.Gateway.publication_keeps_target
#print axioms Eggshell.Plugin.Publication.Gateway.response_keeps_request
#print axioms Eggshell.Plugin.Publication.Owned.read_scope_uses_read_registration

run_meta do
  let environment ← getEnv
  for (caller,required) in #[
      (``Eggshell.Plugin.Publication.Gateway.execute,``Eggshell.Plugin.Publication.Gateway.writeFor),
      (``Eggshell.Plugin.Publication.Gateway.execute,``Eggshell.Plugin.Publication.Gateway.Boundary.inScope),
      (``Eggshell.Plugin.Publication.Gateway.execute,``Eggshell.Plugin.Publication.Client.submitProject),
      (``Eggshell.Plugin.Publication.Gateway.Peer.publish,``Eggshell.Plugin.Publication.Client.checkProjectReceipt),
      (``Eggshell.Plugin.Publication.Gateway.Peer.publish,``Eggshell.Plugin.Publication.Gateway.Peer.accepts),
      (``Eggshell.Plugin.Publication.Gateway.pin,``Eggshell.Plugin.Publication.Client.pinReadProject),
      (``Eggshell.Plugin.Publication.Owned.Pool.pinRead,``Eggshell.Plugin.Publication.Owned.Pool.readProject)] do
    let some declaration := environment.find? caller | throwError "Missing gateway caller: {caller}"
    let some body := declaration.value? | throwError "Gateway caller has no body: {caller}"
    unless body.getUsedConstants.contains required do
      throwError "Gateway bypasses its checked project boundary: {caller}, {required}"
  let mut pending := [``Eggshell.Plugin.Publication.Gateway.withPeer,
    ``Eggshell.Plugin.Publication.Gateway.Peer.pin,``Eggshell.Plugin.Publication.Gateway.Peer.publish]
  let mut visited : NameSet := {}
  let forbidden := #[``Eggshell.ProjectStore.openProject,``Eggshell.DB.PageMap.pin,
    ``IO.FS.readFile,``IO.FS.readBinFile,``Std.Mutex.atomically]
  while let caller :: rest := pending do
    pending := rest
    if visited.contains caller then continue
    visited := visited.insert caller
    if forbidden.contains caller then throwError "Client gateway reaches host storage or a global mutex: {caller}"
    if let some declaration := environment.find? caller then
      if let some body := declaration.value? then
        pending := body.getUsedConstants.toList ++ pending
  logInfo m!"Client-only gateway closure checked: {visited.size} declarations; no project file reads or mutex atomically."
