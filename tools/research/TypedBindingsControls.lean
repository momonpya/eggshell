import tools.research.RuntimeReadControls
open Lean Eggshell Eggshell.Plugin Eggshell.Synapses Eggshell.DB
open Eggshell.Plugin.Publication.Service
#print axioms local_bindings_uses_checked_projection
namespace TypedBindingsControls
def verify (valid : Bool) (message : String) : IO Unit := unless valid do throw (IO.userError message)
def run (root : System.FilePath) : IO Unit := do
  verify (!(← root.pathExists)) "fresh typed binding controls required"
  IO.FS.createDirAll root
  let server ← makeServer
  let held ← IO.mkRef (none : Option (String × String))
  let lease ← IO.mkRef (none : Option (String × String))
  try
    let fileReport ← fileChecks server root
    let source ← PageMap.pin (root/"file-fixture/project.egg")
    let headBefore ← IO.FS.readFile (source.directory/"head")
    let metadata ← CanonicalSource.Cache.refresh source .database
    let scope ← readSource server source.directory source.head.identity .database
    let deadline := (← IO.monoMsNow)+20000
    let prepared ← prepareRegistered server scope (some source.head) deadline (some deadline) (some metadata.metadata)
    let access ← IO.ofExcept (fromJson? prepared : Except String CanonicalSource.Shared.Access)
    let retained ← IO.ofExcept (prepared.getObjValAs? String "retained")
    held.set (some (retained,access.scope))
    let reader ← Persistence.Store.NodeReader.new source
    let entries ← Build.entries source
    let owners ← entries.mapM fun entry => do return (← Build.document reader entry.id).owner
    let requests : Array SourceViewBatch.Request := #[{access,owners,retained := some retained}]
    let palette ← readSourceViews server access.capability requests deadline
    let paletteKey := SourceViewBatch.key requests
    lease.set (some (palette.lease,paletteKey))
    let reads ← server.palettes.withView palette.lease paletteKey fun view => do
      let some original := view.sources[0]? | throw (IO.userError "binding fixture view missing")
      let mut result := #[]
      for owner in owners do
        let captured ← IO.ofExcept (original.readMetadata owner)
        let some found := PreparedPlanMetadata.reads captured.stored.descriptor |
          throw (IO.userError "binding fixture has invalid original metadata")
        result := result++found
      return result
    let wanted := (hashDistinct (reads.toList.map (·.source))).toArray
    verify (!wanted.isEmpty) "binding controls need positive original ranges"
    let allowed := Std.HashSet.ofArray owners
    let endpoint : Daemon.Endpoint := ⟨"publisher",(← IO.Process.getPID).toNat,12348,access.capability,"typed-binding-check"⟩
    let localAccess := localReadAccess server endpoint
    let reference : Publication.Client.SourceReference := ⟨endpoint,access,some retained,some localAccess⟩
    let payload := Json.mkObj [("database",toJson access.database),("scope",toJson access.scope),
      ("source",toJson access.source),("metadata",toJson access.metadata),("retained",toJson (some retained)),
      ("wanted",toJson (wanted++wanted)),("allowed",toJson allowed.toArray)]
    let wired ← sourceBindings server access.capability payload deadline
    let wire ← IO.ofExcept (fromJson? wired : Except String IndexedBindings.Projection)
    let localResult ← Publication.Client.sourceBindings reference (wanted++wanted) allowed deadline
    let mut positive := 0
    for sourceRange in wanted do
      let some (_,expected) := wire.rows.find? (·.1 == sourceRange) |
        throw (IO.userError "wire projection omitted a wanted range")
      let actual := localResult.rows[sourceRange]?.getD #[]
      verify (toJson actual == toJson expected) "typed binding rows/order differ from the wire projection"
      positive := positive+actual.size
    verify (positive > 0 && localResult.complete == wire.complete && localResult.requests == wire.requests &&
      localResult.bytes == wire.bytes && localResult.unresolved == wire.unresolved && localResult.unusable == wire.unusable)
      "typed binding metadata or positive domain differs from wire"
    verify (← rejects (Publication.Client.sourceBindings
      {reference with endpoint := {endpoint with secret := "foreign-secret"}} wanted allowed deadline))
      "local binding authority accepted a foreign secret"
    verify (← rejects (Publication.Client.sourceBindings
      {reference with access := {access with source := {access.source with identity := "foreign-database"}}}
      wanted allowed deadline)) "local binding authority accepted a foreign source head"
    verify (← rejects (Publication.Client.sourceBindings
      {reference with retained := some "missing-retained-token"} wanted allowed deadline))
      "local binding authority accepted a foreign retained view"
    verify (← rejects (Publication.Client.sourceBindings reference wanted allowed 0))
      "local binding authority accepted an expired request"
    let wrongIdentity := {localAccess with bindings := fun _ _ _ _ _ _ => pure {wire with identity := toJson "foreign"}}
    verify (← rejects (Publication.Client.sourceBindings {reference with localReads := some wrongIdentity} wanted allowed deadline))
      "typed client skipped projection identity validation"
    let missing := {localAccess with bindings := fun _ _ _ _ _ _ => pure {wire with rows := #[]}}
    verify (← rejects (Publication.Client.sourceBindings {reference with localReads := some missing} wanted allowed deadline))
      "typed client skipped complete wanted-domain validation"
    let foreignOwner := {wire with rows := wire.rows.map fun (target,rows) =>
      (target,rows.map fun row => {row with binding := {row.binding with owner := "foreign-owner"}})}
    let wrongOwner := {localAccess with bindings := fun _ _ _ _ _ _ => pure foreignOwner}
    verify (← rejects (Publication.Client.sourceBindings {reference with localReads := some wrongOwner} wanted allowed deadline))
      "typed client skipped per-row owner validation"
    let empty ← Publication.Client.sourceBindings reference wanted {} deadline
    verify (empty.complete && empty.rows.toArray.all (fun (_,rows) => rows.isEmpty))
      "local binding projection leaked an owner outside allowed domain"
    verify ((← IO.FS.readFile (source.directory/"head")) == headBefore) "binding read controls changed original head"
    IO.FS.writeFile (root/"report.json") (Json.mkObj [("allPassed",toJson true),("fileControls",fileReport),
      ("ranges",toJson wanted.size),("positiveOriginalRows",toJson positive),("sameOrderedRowsAndMetadata",toJson true),
      ("typedClientSucceededWithoutNetworkListener",toJson true),("sameEndpointSecretUsed",toJson true),
      ("wrongSecretHeadRetentionDeadlineRejected",toJson true),("clientIdentityDomainOwnerChecksRetained",toJson true),
      ("allowedDomainNotWidened",toJson true),("originalHeadUnchanged",toJson true),
      ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).compress
  finally
    if let some (token,key) ← lease.get then server.palettes.release token key
    if let some (token,scope) ← held.get then server.retained.release token scope
    server.palettes.close
    server.retained.close
    server.prepared.close
    server.operations.close
end TypedBindingsControls
def main (args : List String) : IO UInt32 := do
  match args with
  | ["typed-binding-controls",root] => TypedBindingsControls.run (.mk root); return 0
  | other => sourceRouteEngine other
