module
import all Eggshell.Handoff
import all Eggshell.PublicationService
public meta import Lean
open Lean

#print axioms Eggshell.Synapses.CanonicalSource.Shared.Loaded.lookup_exact
#print axioms Eggshell.Synapses.CanonicalSource.Shared.Loaded.requested_domain
#print axioms Eggshell.Synapses.CanonicalSource.Shared.Budget.reserved_within
#print axioms Eggshell.Synapses.CanonicalSource.Shared.Access.capability_not_identity

run_meta do
  let environment ← getEnv
  for (root,required,forbidden) in #[
      (``Eggshell.Plugin.indexedDiscoveryUsing,
        #[``Eggshell.Plugin.Publication.Client.sourceRows],#[]),
      (``Eggshell.Synapses.Recommend.prepare,
        #[``Eggshell.Plugin.Publication.Client.prepareSource],
        #[``Eggshell.Synapses.CanonicalSource.Cache.open?]),
      (``Eggshell.Plugin.Publication.Service.prepareRegistered,
        #[``Eggshell.Synapses.CanonicalSource.Shared.Pool.withReady,
          ``Eggshell.Synapses.CanonicalSource.Cache.atSource?],
        #[``Eggshell.Synapses.CanonicalSource.Cache.refresh,
          ``Eggshell.DB.PageMap.Writer.put]),
      (``Eggshell.Plugin.Publication.Service.sourceRows,
        #[``Eggshell.Plugin.Publication.Service.scopedSource,
          ``Eggshell.Synapses.CanonicalSource.Shared.Loaded.rows,
          ``Eggshell.Synapses.CanonicalSource.Shared.Pool.withReady],
        #[``Eggshell.Synapses.CanonicalSource.Cache.refresh,
          ``Eggshell.DB.PageMap.Writer.put])] do
    let mut pending := [root]
    let mut visited : Std.HashSet Name := {}
    while let name :: rest := pending do
      pending := rest
      if visited.contains name then continue
      visited := visited.insert name
      let some declaration := environment.find? name | throwError "Missing prepared-state boundary {name}"
      if let some body := declaration.value? then
        for dependency in body.getUsedConstants do
          if dependency.toString.startsWith "Eggshell." then pending := dependency :: pending
    for name in required do
      unless visited.contains name do throwError "Prepared-state boundary {root} bypasses {name}"
    for name in forbidden do
      if visited.contains name then throwError "Prepared-state boundary {root} reaches forbidden {name}"
    logInfo m!"Audited shared prepared-state boundary {root}"
