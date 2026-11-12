module
import all Eggshell.ProjectGatewayPeer
import all Eggshell.ProjectRead
import Lean
open Lean
open Eggshell.Plugin.Publication

theorem exported_advice_had_no_completion (handoff : Eggshell.Plugin.Handoff) (result : Read.Advice)
    (accepted : Read.advice handoff = .ok result) :
    handoff.completed = 0 ∧ handoff.blocksCurrent = false ∧ handoff.localUnions = 0 := by
  by_cases safe : handoff.completed == 0 && !handoff.blocksCurrent && handoff.localUnions == 0 &&
      handoff.reason != "search-incomplete"
  · simp only [Bool.and_eq_true,beq_iff_eq] at safe
    have blocked : handoff.blocksCurrent = false := by
      cases state : handoff.blocksCurrent <;> simp_all
    exact ⟨safe.1.1.1,blocked,safe.1.2⟩
  · simp [Read.advice,safe,Functor.map] at accepted
    change (Except.error "shared advisory query did not finish without completion authority" : Except String Read.Advice) =
      Except.ok result at accepted
    cases accepted

#print axioms exported_advice_had_no_completion
#print axioms Read.advice_never_completes
#print axioms Read.image_keeps_inventory
#print axioms Read.response_keeps_inputs
#print axioms Eggshell.Synapses.Recommend.Prepared.emptyOriginal_no_tree
#print axioms Eggshell.Synapses.Routed.empty_original_collection
#print axioms Eggshell.Synapses.Routed.missing_nonempty_collection
#print axioms Eggshell.Synapses.Transport.empty_original_bindings
#print axioms Eggshell.Synapses.Transport.requested_original_bindings

run_meta do
  let environment ← getEnv
  for (caller,required) in #[
      (``Gateway.Peer.query,``Gateway.Peer.accepts),
      (``Gateway.Peer.query,``Read.Response.check),
      (``Gateway.execute,``Client.readProjectAdvice),
      (``Client.readProjectAdvice,``Read.Response.check),
      (``Read.query,``Owned.Pool.readProject),
      (``Read.query,``Eggshell.ProjectViews.Pool.acquire),
      (``Read.query,``Eggshell.PreparedReaders.Frame.capture),
      (``Read.query,``Eggshell.SearchReaders.Coordinator.borrow),
      (``Read.query,``Eggshell.Synapses.Recommend.prepareMany),
      (``Read.query,``Eggshell.Plugin.computeAutomaticHandoff),
      (``Read.query,``Read.advice)] do
    let some declaration := environment.find? caller | throwError "Missing project read caller: {caller}"
    let some body := declaration.value? | throwError "Missing project read implementation: {caller}"
    unless body.getUsedConstants.contains required do throwError "Project read bypasses its boundary: {caller}, {required}"
  for (caller,required) in #[
      (``Eggshell.Synapses.Routed.collect,``Eggshell.Synapses.Recommend.Prepared.emptyOriginal),
      (``Eggshell.Synapses.Transport.build,``Eggshell.Synapses.Transport.originalBindings)] do
    let some declaration := environment.find? caller | throwError "Missing empty-source caller: {caller}"
    let some body := declaration.value? | throwError "Missing empty-source implementation: {caller}"
    unless body.getUsedConstants.contains required do throwError "Empty-source proof is disconnected: {caller}, {required}"
  let mut pending := [``Gateway.withPeer,``Gateway.Peer.query]
  let mut visited : NameSet := {}
  let forbidden := #[``Eggshell.ProjectStore.openProject,``Eggshell.DB.PageMap.pin,
    ``IO.FS.readFile,``IO.FS.readBinFile,``Std.Mutex.atomically]
  while let caller :: rest := pending do
    pending := rest
    if visited.contains caller then continue
    visited := visited.insert caller
    if forbidden.contains caller then throwError "Remote query client reaches DB files or a mutex: {caller}"
    if let some declaration := environment.find? caller then
      if let some body := declaration.value? then pending := body.getUsedConstants.toList++pending
  logInfo m!"Project query client closure: {visited.size} declarations; no project reads or mutex atomically."
