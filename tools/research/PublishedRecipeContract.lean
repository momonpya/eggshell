module
import all Eggshell.Handoff
import all Eggshell.PublicationService
public meta import Lean
open Lean

#print axioms Eggshell.DB.PageMap.SharedPageCache.touch_bounded
#print axioms Eggshell.DB.PageMap.Snapshot.pageKey_scope
#print axioms Eggshell.Synapses.CanonicalSource.Recipe.Checked.catalogue_complete
#print axioms Eggshell.Synapses.Index.compiled_read_preserves_binding
#print axioms Eggshell.Synapses.Index.compiled_support_preserves_binding
#print axioms Eggshell.Synapses.IndexedBindings.Origin.only_admitted_owner

run_meta do
  let environment ← getEnv
  for (root,required,forbidden) in #[
      (``Eggshell.Plugin.SharedRangeAdapter.prepareCached,
        #[``Eggshell.Synapses.CanonicalSource.Recipe.check],
        #[``Eggshell.Synapses.CanonicalSource.Records.prepare]),
      (``Eggshell.Synapses.CanonicalSource.Shared.Pool.acquire,
        #[``Eggshell.Synapses.CanonicalSource.Cache.preparedAt?,``Eggshell.DB.PageMap.Snapshot.sharePages],
        #[``Eggshell.Synapses.CanonicalSource.Cache.atSource?,``Eggshell.Synapses.CanonicalSource.Recipe.compile]),
      (``Eggshell.Plugin.Publication.Service.sourceBindings,
        #[``Eggshell.Plugin.Publication.Service.scopedSource,``Eggshell.Synapses.IndexedBindings.resolve],
        #[``Eggshell.Synapses.Index.Reader.lookup,``Eggshell.Synapses.Index.prepareBinding,
          ``Eggshell.DB.PageMap.Writer.put]),
      (``Eggshell.Synapses.Transport.build,
        #[``Eggshell.Plugin.Publication.Client.sourceBindings],
        #[``Eggshell.Synapses.Index.Reader.lookup,``Eggshell.Synapses.CanonicalSource.Recipe.compile])] do
    let mut pending := [root]
    let mut visited : Std.HashSet Name := {}
    while let name :: tail := pending do
      pending := tail
      if visited.contains name then continue
      visited := visited.insert name
      let some declaration := environment.find? name | throwError "Missing prepared boundary {name}"
      if let some body := declaration.value? then
        for dependency in body.getUsedConstants do
          if dependency.toString.startsWith "Eggshell." then pending := dependency :: pending
    for name in required do
      unless visited.contains name do throwError "{root} bypasses {name}"
    for name in forbidden do
      if visited.contains name then throwError "{root} reaches forbidden query-time preparation {name}"
    logInfo m!"Checked publication/query boundary: {root}"

public def main : IO Unit := IO.println "publication/query dependency boundaries checked"
