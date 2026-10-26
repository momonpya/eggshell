module
import all Eggshell.NativePublication
import all Eggshell.SynapseBuild
public meta import Lean
open Lean

#print axioms LiteralSearch.hit_is_requested_original
#print axioms Eggshell.Synapses.ObservedRecords.base_covers

run_meta do
  let environment ← getEnv
  for (root,required,forbidden) in #[
      (``Eggshell.Synapses.ObservationContext.quoteMatches,
        #[``LiteralSearch.first],
        #[``Eggshell.DB.PageMap.Writer.put, ``Eggshell.FileSystem.openRead]),
      (``Eggshell.Synapses.Build.refresh,
        #[``Eggshell.Synapses.ObservationContext.quoteMatches,
          ``Eggshell.Synapses.ObservedRecords.load?, ``LiteralSearch.prepare],
        #[``Eggshell.Plugin.NativePublication.stage])] do
    let mut pending := [root]
    let mut visited : Std.HashSet Name := {}
    while let name :: rest := pending do
      pending := rest
      if visited.contains name then continue
      visited := visited.insert name
      let some declaration := environment.find? name | throwError "Missing literal boundary {name}"
      if let some body := declaration.value? then
        for dependency in body.getUsedConstants do
          if dependency.toString.startsWith "Eggshell." || dependency.toString.startsWith "ContentCorrespondence." ||
              dependency.toString.startsWith "LiteralSearch." then pending := dependency :: pending
    for name in required do
      unless visited.contains name do throwError "Literal boundary {root} bypasses {name}"
    for name in forbidden do
      if visited.contains name then throwError "Literal boundary {root} reaches forbidden {name}"
    logInfo m!"Audited literal-support boundary {root}"
