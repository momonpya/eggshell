module
import all Eggshell.PluginHooks
import all Eggshell.ContentMetadata
import all Eggshell.NativePublication
import all Eggshell.Handoff
import all Eggshell.DemandMemo
public meta import Lean
open Lean Eggshell

/-- Additional original coordinates invalidate prepared source views without
duplicating a root, changing its order, or granting a new equality. -/
theorem metadata_replay_preserves_graph (affected : List Nat)
    (roots : List Value) (unions : List UnionEdge) (resolve : Nat → Value)
    (newUnions : List UnionEdge) :
    Plugin.DemandMemo.replay
      {added := [],removed := [],unionsChanged := false,affected}
      roots unions resolve newUnions = (roots,unions) := by
  simp [Plugin.DemandMemo.replay,Persistence.Store.reviseValues]

theorem affected_is_not_neutral (affected : List Nat) (changed : affected ≠ []) :
    Persistence.Store.Change.neutral
      {added := [],removed := [],unionsChanged := false,affected} = false := by
  simp [Persistence.Store.Change.neutral,List.isEmpty_eq_false_iff,changed]

#print axioms metadata_replay_preserves_graph
#print axioms affected_is_not_neutral
#print axioms Eggshell.ContentCapture.Trie.observe_size
#print axioms Eggshell.ContentCapture.Trie.find_checked
#print axioms Eggshell.ContentMetadata.Line.original_projection
#print axioms Eggshell.ContentMetadata.Line.original_bounds
#print axioms Eggshell.Synapses.Extraction.SharedCode.original_spelling
#print axioms Eggshell.Plugin.native_receipt_ignores_correspondence
#print axioms Eggshell.Plugin.operation_owner_ignores_correspondence
#print axioms Eggshell.Persistence.Store.change_codec_roundtrip

run_meta do
  let environment ← getEnv
  for (root,required,forbidden) in #[
      (``Eggshell.Plugin.sealRecordedRead,
        #[``Eggshell.ContentCapture.finish],#[]),
      (``Eggshell.Plugin.NativePublication.stage,
        #[``Eggshell.ContentMetadata.stage,``Eggshell.Synapses.ObservedRecords.stage,
          ``Eggshell.Synapses.Provenance.stage],#[]),
      (``Eggshell.ContentMetadata.load?,#[],
        #[``Eggshell.ContentCapture.scan,``Eggshell.ContentCapture.finish,
          ``Eggshell.ContentCapture.captureInputs]),
      (``Eggshell.Synapses.CanonicalSource.addPublishedDocument,
        #[``Eggshell.ContentMetadata.load?],
        #[``Eggshell.ContentCapture.scan,``Eggshell.ContentCapture.finish]),
      (``Eggshell.Plugin.indexedDiscoveryUsing,
        #[``Eggshell.Plugin.Publication.Client.sourceRows],#[])] do
    let mut pending := [root]
    let mut visited : Std.HashSet Name := {}
    while let name :: rest := pending do
      pending := rest
      if visited.contains name then continue
      visited := visited.insert name
      let some declaration := environment.find? name | throwError "Missing capture boundary {name}"
      if let some body := declaration.value? then
        for dependency in body.getUsedConstants do
          if dependency.toString.startsWith "Eggshell." then pending := dependency :: pending
    for name in required do
      unless visited.contains name do throwError "Capture boundary {root} bypasses {name}"
    for name in forbidden do
      if visited.contains name then throwError "Capture boundary {root} reaches forbidden {name}"
    logInfo m!"Audited captured correspondence boundary {root}"
