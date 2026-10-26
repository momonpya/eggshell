module
import all Eggshell.SynapticTransport
import all Eggshell.SynapticTopologyStore
public meta import Lean
open Lean

#print axioms Eggshell.Synapses.Routing.project_carries
#print axioms Eggshell.Synapses.Routing.Store.arc_roundtrip
#print axioms Eggshell.Synapses.Index.shared_rejects_usage
#print axioms Eggshell.Synapses.Routed.Result.incomplete_not_admitted

run_meta do
  let environment ← getEnv
  for (root,required,forbidden) in #[
      (``Eggshell.Synapses.Index.publishDelta,
        #[``Eggshell.Synapses.Routing.Store.insert,``Eggshell.Synapses.Routing.Store.erase,
          ``Eggshell.Synapses.Routing.Store.finish],
        #[``Eggshell.Synapses.Index.allFacts,``Eggshell.DB.PageMap.Snapshot.foldRange]),
      (``Eggshell.Synapses.Index.replace,
        #[``Eggshell.Synapses.Routing.Store.insert,``Eggshell.Synapses.Routing.Store.erase,
          ``Eggshell.Synapses.Routing.Store.finish],#[]),
      (``Eggshell.Synapses.Routing.Store.insert,
        #[``Eggshell.Synapses.Routing.project],#[``Eggshell.DB.PageMap.Snapshot.foldRange]),
      (``Eggshell.Synapses.Routed.collect,
        #[``Eggshell.Synapses.Routing.Store.open?,``Eggshell.Synapses.Routing.Store.walk],
        #[``Eggshell.Synapses.Routing.Arena.add,``Eggshell.Synapses.Index.allFacts,
          ``Eggshell.Synapses.Routing.Store.insert,``Eggshell.DB.PageMap.withWriter]),
      (``Eggshell.Synapses.Routing.Store.open?,#[],
        #[``Eggshell.DB.PageMap.open?,``Eggshell.DB.PageMap.create,``Eggshell.DB.PageMap.withWriter])] do
    let mut pending := [root]
    let mut visited : Std.HashSet Name := {}
    while let name :: rest := pending do
      pending := rest
      if visited.contains name then continue
      visited := visited.insert name
      let some declaration := environment.find? name | throwError "Missing atomic routing boundary {name}"
      if let some body := declaration.value? then
        for dependency in body.getUsedConstants do
          if dependency.toString.startsWith "Eggshell." then pending := dependency :: pending
    for name in required do
      unless visited.contains name do throwError "Atomic routing boundary {root} bypasses {name}"
    for name in forbidden do
      if visited.contains name then throwError "Atomic routing boundary {root} reaches forbidden {name}"
    logInfo m!"Audited atomic routing boundary {root}"
