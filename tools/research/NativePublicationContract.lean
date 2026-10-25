module

import all Eggshell.PluginHooks
import all Eggshell.PluginCli
public meta import Lean

open Lean

/- A dependency regression gate complements the native failure/retry tests.
It checks the real source path; it is not a filesystem durability theorem. -/
run_meta do
  let environment ← getEnv
  for (root,required,forbidden) in #[
      (``Eggshell.Plugin.NativePublication.run,
        #[``Eggshell.Plugin.NativePublication.plan, ``Eggshell.Plugin.NativePublication.stage,
          ``Eggshell.Persistence.appendPrepared],
        #[``Eggshell.Synapses.Journal.replay, ``Eggshell.Synapses.Build.refresh,
          ``Eggshell.Warm.runTarget, ``Eggshell.Persistence.Store.materialize]),
      (``Eggshell.Plugin.NativePublication.plan,
        #[``Eggshell.Synapses.Journal.lookup?, ``Eggshell.Synapses.Provenance.lookup?],
        #[``Eggshell.Synapses.Journal.turnEntries, ``Eggshell.Synapses.Provenance.records,
          ``Eggshell.Persistence.Store.searchDocuments]),
      (``Eggshell.Plugin.NativePublication.stage,
        #[``Eggshell.Synapses.Provenance.Binding.check?, ``Eggshell.Synapses.Provenance.stage],#[]),
      (``Eggshell.Synapses.Provenance.stage,
        #[``Eggshell.Synapses.Provenance.appendRows, ``Eggshell.Persistence.Store.Intern.value],
        #[``Eggshell.DB.PageMap.withWriter, ``Eggshell.Synapses.Provenance.publish]),
      (``Eggshell.Plugin.flushDeferred,
        #[``Eggshell.Plugin.NativePublication.SaveReply.check?],
        #[``Eggshell.Plugin.addDeliveredGraphs]),
      (``Eggshell.Plugin.control, #[``Eggshell.Plugin.promote],
        #[``Eggshell.Plugin.addDeliveredGraphs])] do
    let mut pending := [root]
    let mut visited : Std.HashSet Name := {}
    while let name :: rest := pending do
      pending := rest
      if visited.contains name then continue
      visited := visited.insert name
      let some declaration := environment.find? name | throwError "Missing source boundary {name}"
      if let some value := declaration.value? then
        for dependency in value.getUsedConstants do
          if dependency.toString.startsWith "Eggshell." then pending := dependency :: pending
    for name in required do
      unless visited.contains name do throwError "Source boundary {root} no longer reaches {name}"
    for name in forbidden do
      if visited.contains name then throwError "Source boundary {root} reaches forbidden path {name}"
    logInfo m!"Audited atomic source boundary {root}"
