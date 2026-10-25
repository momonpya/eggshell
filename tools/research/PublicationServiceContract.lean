module
import all Eggshell.PublicationService
import all Eggshell.PluginCli
public meta import Lean

open Lean

/- Call-graph checks accompany the real TCP and native-hook trials. They do
not prove filesystem durability, authorization policy, or network security. -/
run_meta do
  let environment ← getEnv
  for (root,required,forbidden) in #[
      (``Eggshell.Plugin.promote,
        #[``Eggshell.Plugin.Publication.Client.submit, ``Eggshell.Plugin.Publication.Capsule.ofPrepared],
        #[``Eggshell.Plugin.NativePublication.runPrepared, ``Eggshell.Plugin.addDeliveredGraphs]),
      (``Eggshell.Plugin.Publication.Service.publish,
        #[``Eggshell.Plugin.NativePublication.runPrepared, ``Eggshell.Plugin.NativePublication.stage,
          ``Eggshell.Persistence.appendPrepared],
        #[``Eggshell.Synapses.Journal.turnEntries, ``Eggshell.Synapses.Journal.replay,
          ``Eggshell.Warm.runTarget, ``Eggshell.Persistence.Store.materialize]),
      (``Eggshell.Plugin.Publication.Capsule.pending, #[``Eggshell.Plugin.Publication.Capsule.work],
        #[``Eggshell.Synapses.Journal.Entry, ``Eggshell.Synapses.Journal.Knowledge])] do
    let mut pending := [root]
    let mut visited : Std.HashSet Name := {}
    while let name :: rest := pending do
      pending := rest
      if visited.contains name then continue
      visited := visited.insert name
      let some declaration := environment.find? name | throwError "Missing publication boundary {name}"
      if let some value := declaration.value? then
        for dependency in value.getUsedConstants do
          if dependency.toString.startsWith "Eggshell." then pending := dependency :: pending
    for name in required do
      unless visited.contains name do throwError "Publication boundary {root} no longer reaches {name}"
    for name in forbidden do
      if visited.contains name then throwError "Publication boundary {root} reaches forbidden path {name}"
    logInfo m!"Audited shared publication boundary {root}"
