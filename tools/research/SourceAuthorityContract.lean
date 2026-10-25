module
import all Eggshell.Warm
import all Eggshell.NativePublication
public meta import Lean
open Lean

/- Source production is a native publication. Background preparation may write
its private journal and views, but must not create or repair source origins. -/
run_meta do
  let environment ← getEnv
  let retired := Name.str (``Eggshell.Synapses.Provenance.requirePublished).getPrefix "publish"
  if environment.contains retired then throwError "Retired source backfill remains in the environment"
  for root in #[``Eggshell.Synapses.Provenance.requirePublished,
      ``Eggshell.Synapses.Journal.refresh, ``Eggshell.Warm.refreshSource] do
    let mut pending := [root]
    let mut visited : Std.HashSet Name := {}
    while let name :: rest := pending do
      pending := rest
      if visited.contains name then continue
      visited := visited.insert name
      let some declaration := environment.find? name | throwError "Missing source consumer {name}"
      if let some value := declaration.value? then
        for dependency in value.getUsedConstants do
          if dependency.toString.startsWith "Eggshell." then pending := dependency :: pending
    unless visited.contains ``Eggshell.Synapses.Provenance.requirePublished do
      throwError "Source consumer {root} does not verify its source-published native intervals"
    for forbidden in #[``Eggshell.Synapses.Provenance.appendRows, ``Eggshell.Synapses.Provenance.stage,
        ``Eggshell.Persistence.appendPrepared, ``Eggshell.Persistence.Store.Intern.root] do
      if visited.contains forbidden then throwError "Source consumer {root} reaches producer {forbidden}"
    if root == ``Eggshell.Synapses.Provenance.requirePublished then
      for forbidden in #[``Eggshell.DB.PageMap.withWriter, ``Eggshell.FileSystem.openAppend,
          ``Eggshell.FileSystem.atomicBytes, ``Eggshell.FileSystem.atomicExistingBytes] do
        if visited.contains forbidden then throwError "Original verifier reaches write {forbidden}"
    logInfo m!"Audited read-only original consumption in {root}"
