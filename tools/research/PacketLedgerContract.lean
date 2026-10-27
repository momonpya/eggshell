module
import all Eggshell.Handoff
public meta import Lean
open Lean

run_meta do
  let environment ← getEnv
  for (root,required,forbidden) in #[
      (``Eggshell.Synapses.Recommend.prepare,
        #[``Eggshell.Synapses.Recommend.readablePrepared?],
        #[``Eggshell.DB.Sidecar.destination,``Eggshell.DB.Sidecar.prepare]),
      (``Eggshell.Plugin.Handoff.deliveryReceipt,
        #[``Eggshell.Plugin.Handoff.capturedPacket?,
          ``Eggshell.Synapses.PacketReceipt.Source.piece?,``Eggshell.Synapses.PacketReceipt.shared?],
        #[``Eggshell.Synapses.Extraction.presented,``Eggshell.JsonScalars.prepare?,
          ``Eggshell.Synapses.Extraction.recordedRows,``Eggshell.Synapses.ObservationContext.prepare?,
          ``Eggshell.Synapses.Bundles.receipt]),
      (``Eggshell.Plugin.indexedDiscoveryUsing,
        #[``Eggshell.Plugin.Handoff.deliveryReceipt],
        #[``Eggshell.Synapses.Bundles.receipt,``Eggshell.Plugin.SharedRangeAdapter.Plan.fullReceipt])] do
    let mut pending := [root]
    let mut visited : Std.HashSet Name := {}
    while let name :: rest := pending do
      pending := rest
      if visited.contains name then continue
      visited := visited.insert name
      let some declaration := environment.find? name | throwError "Missing packet boundary {name}"
      if let some body := declaration.value? then
        for dependency in body.getUsedConstants do
          if dependency.toString.startsWith "Eggshell." then pending := dependency :: pending
    for name in required do
      unless visited.contains name do throwError "Packet boundary {root} bypasses {name}"
    for name in forbidden do
      if visited.contains name then throwError "Packet boundary {root} reaches full reparsing/audit {name}"
    logInfo m!"Audited selected-packet boundary {root}"
