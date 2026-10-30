module
import all Eggshell.PublicationService
public meta import Lean
open Lean

/- Dependency reachability checks integration boundaries. This is not a
proof that every possible IO trace preserves the storage transaction. -/
run_meta do
  let environment ← getEnv
  for (root,required,forbidden) in #[
      (``Eggshell.Synapses.Index.prepareBinding,
        #[``Eggshell.Synapses.Index.putImmutable,``Eggshell.Synapses.Index.touchBinding],#[]),
      (``Eggshell.Synapses.Index.erase,
        #[``Eggshell.Synapses.Index.touchBinding,``Eggshell.DB.PageMap.Writer.put],#[]),
      (``Eggshell.Plugin.Publication.Service.sourceBindings,
        #[``Eggshell.Plugin.Publication.Service.scopedSource,
          ``Eggshell.Synapses.IndexedBindings.Prepared.Pool.resolve,
          ``Eggshell.Synapses.Index.bindingChange?,``Eggshell.Synapses.IndexedBindings.checkRead?],
        #[``Eggshell.Synapses.Index.prepareBinding,``Eggshell.Synapses.Index.touchBinding,
          ``Eggshell.DB.PageMap.Writer.put,``Eggshell.Synapses.CanonicalSource.Cache.atSource?]),
      (``Eggshell.Synapses.IndexedBindings.Prepared.Pool.resolve,
        #[``Eggshell.Synapses.IndexedBindings.resolveUsing,``Eggshell.Synapses.IndexedBindings.checkRead?],
        #[``Eggshell.Synapses.Index.insert,``Eggshell.Synapses.Index.erase])] do
    let mut pending := [root]
    let mut visited : Std.HashSet Name := {}
    while let name :: tail := pending do
      pending := tail
      if visited.contains name then continue
      visited := visited.insert name
      let some declaration := environment.find? name | throwError "Missing prepared binding boundary {name}"
      if let some body := declaration.value? then
        for dependency in body.getUsedConstants do
          if dependency.toString.startsWith "Eggshell." then pending := dependency :: pending
    for name in required do
      unless visited.contains name do throwError "{root} bypasses {name}"
    for name in forbidden do
      if visited.contains name then throwError "{root} reaches forbidden query-time producer {name}"
    logInfo m!"Checked prepared binding dependency boundary: {root}"

