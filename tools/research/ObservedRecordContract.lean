module
import all Eggshell.NativePublication
import all Eggshell.SynapseBuild
public meta import Lean
open Lean

#print axioms Eggshell.Synapses.ObservedRecords.base_covers
#print axioms Eggshell.Synapses.ObservedRecords.metadata_preserves_authority
#print axioms Eggshell.Synapses.ObservedRecords.block_preserves_authority
#print axioms Eggshell.Synapses.Extraction.layout_total

run_meta do
  let environment ← getEnv
  for (root,required,forbidden) in #[
      (``Eggshell.Plugin.NativePublication.stage,
        #[``Eggshell.Synapses.ObservedRecords.stage, ``Eggshell.Synapses.Provenance.stage],
        #[``Eggshell.DB.PageMap.withWriter, ``Eggshell.Synapses.Build.refresh]),
      (``Eggshell.Synapses.ObservedRecords.stage,
        #[``Eggshell.Synapses.ObservedRecords.prepare, ``Eggshell.Synapses.ObservedRecords.project,
          ``Eggshell.DB.PageMap.Writer.put],
        #[``Eggshell.DB.PageMap.withWriter, ``Eggshell.FileSystem.openRead,
          ``Eggshell.Synapses.Extraction.readPlans]),
      (``Eggshell.Synapses.Provenance.derive,
        #[``Eggshell.Synapses.ObservedRecords.load?, ``Eggshell.Synapses.ObservationContext.locateUsing],
        #[``Eggshell.Synapses.ObservedRecords.stage, ``Eggshell.Synapses.Provenance.appendRows]),
      (``Eggshell.Synapses.Build.Documents.catalog,
        #[``Eggshell.Synapses.ObservedRecords.load?],
        #[``Eggshell.Synapses.ObservedRecords.stage])] do
    let mut pending := [root]
    let mut visited : Std.HashSet Name := {}
    while let name :: rest := pending do
      pending := rest
      if visited.contains name then continue
      visited := visited.insert name
      let some declaration := environment.find? name | throwError "Missing record boundary {name}"
      if let some body := declaration.value? then
        for dependency in body.getUsedConstants do
          if dependency.toString.startsWith "Eggshell." || dependency.toString.startsWith "ContentCorrespondence." then
            pending := dependency :: pending
    for name in required do
      unless visited.contains name do throwError "Record boundary {root} bypasses {name}"
    for name in forbidden do
      if visited.contains name then throwError "Record boundary {root} reaches forbidden {name}"
    logInfo m!"Audited original-record boundary {root}"
