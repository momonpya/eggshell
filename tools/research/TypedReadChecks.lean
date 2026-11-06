import Eggshell.PublicationService
import Main
import Eggshell.ContractAudit
open Lean Eggshell Eggshell.Plugin Eggshell.Synapses
open Eggshell.Plugin.Publication.Service
open Eggshell.DB
#print axioms source_palettes_uses_typed_read
#print axioms SourceViewBatch.ReadAccess.foreign_process
#print axioms SourceViewBatch.ReadAccess.foreign_generation
#print axioms SharedReadViews.Source.geometry_is_charged

run_cmd do
  let environment ← getEnv
  let body (name : Name) := do
    let some declaration := environment.find? name | throwError "missing typed-read declaration {name}"
    let some value := declaration.value? | throwError "opaque typed-read declaration {name}"
    pure value
  for (name,required) in [(``sourcePalettes,``readSourceViews),(``localReadAccess,``readSourceViews),
      (``Publication.Client.sourcePalettes,``SourceViewBatch.ReadAccess.read),
      (``OperationPool.Pool.searchActor,``Worker.openSearchEnvironment),
      (``Worker.searchRestored,``Worker.SearchEnvironment.originalReads),
      (``automaticHandoff,``SourceContext.originalReads)] do
    unless (← body name).getUsedConstants.contains required do throwError "typed read path is disconnected {name} -> {required}"
  for name in [`Eggshell.Plugin.Publication.Client.sourceRecords,`Eggshell.Plugin.Publication.Service.sourceRecords] do
    if environment.contains name then throwError "obsolete per-source record RPC remains {name}"
  let mut pending := [``SharedReadViews.Source.readRecords,``SharedReadViews.Source.capturedBytes]
  let mut seen : Std.HashSet Name := {}
  while let some name := pending.head? do
    pending := pending.tail!
    if seen.contains name then continue
    seen := seen.insert name
    if ["Std.Mutex.","IO.Ref.","IO.Promise.","IO.asTask","IO.wait"].any (fun stem => name.toString.startsWith stem) then
      throwError "captured source read reaches shared synchronization {name}"
    if let some declaration := environment.find? name then
      if let some value := declaration.value? then pending := value.getUsedConstants.toList++pending
  logInfo m!"Actual actor/context/client/service typed path connected; {seen.size} captured-view dependencies have no shared synchronization"

def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def rejects (work : IO α) : IO Bool := try discard work; pure false catch _ => pure true
def makeServer : IO Server := do
  let originals ← CanonicalSource.Shared.Pool.new
  return ⟨← Std.Mutex.new ({} : State),← Std.Mutex.new 0,← IO.mkRef false,
    ← Std.Mutex.new #[],originals,← CanonicalSource.Leases.Pool.new originals,
    ← ObservedRecordView.Cache.new,← Std.Mutex.new 0,← Std.Mutex.new #[],
    ← SharedReadViews.Pool.new,← Publication.Owned.Pool.new,
    ← PreparationService.Pool.new,← OperationPool.Pool.new⟩
def checks (root : System.FilePath) : IO Unit := do
  check (!(← root.pathExists)) "fresh typed read check root required"
  IO.FS.createDirAll root
  let server ← makeServer
  let originalRoot : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study/frontend-quiescence-fixture-small1/work.project/owners"
  let mut requests : Array SourceViewBatch.Request := #[]
  let mut heads : Array (System.FilePath × String) := #[]
  let endpoint : Daemon.Endpoint := ⟨"publisher",(← IO.Process.getPID).toNat,12347,"", "typed-native-check"⟩
  let access := localReadAccess server endpoint
  try
    for i in [:3] do
      let source ← PageMap.pin (originalRoot/toString (i%2)/"source.egg")
      let storage : DB.Sidecar.Storage := if i < 2 then .database else .user
      heads := heads.push (source.directory/"head",← IO.FS.readFile (source.directory/"head"))
      discard <| Build.refresh source storage
      let refreshed ← CanonicalSource.Cache.refresh source storage
      let scope ← readSource server source.directory source.head.identity storage
      let deadline := (← IO.monoMsNow)+20000
      let prepared ← prepareRegistered server scope (some source.head) deadline (some deadline) (some refreshed.metadata)
      let originalAccess ← IO.ofExcept (fromJson? prepared : Except String CanonicalSource.Shared.Access)
      let retained ← IO.ofExcept (prepared.getObjValAs? String "retained")
      let reader ← Persistence.Store.NodeReader.new source
      let entries ← Build.entries source
      let owners ← (entries.extract 0 (min 4 entries.size)).mapM fun entry => do
        return (← Build.document reader entry.id).owner
      requests := requests.push ⟨originalAccess,owners.push "missing-owner",some retained⟩
    let sources := requests.map fun request =>
      (({
        endpoint := {endpoint with secret := request.access.capability}
        access := request.access
        retained := request.retained
        localReads := some access } : Publication.Client.SourceReference),request.owners)
    let deadline := (← IO.monoMsNow)+10000
    let batch ← Publication.Client.sourcePalettes sources deadline
    check (batch.localReads.isSome && batch.palette.records.size == 3) "typed client used the absent network listener"
    let key := SourceViewBatch.key requests
    let charged ← server.palettes.withView batch.palette.lease key fun view => do
      let captured := view.sources.foldl (fun bytes source => bytes+source.capturedBytes) 0
      check (view.charge == SharedReadViews.charge captured) "geometry or metadata missing from reservation"
      for (source,request) in view.sources.zip requests do
        let actual ← IO.ofExcept (source.readRecords request.owners)
        let some original := source.loaded.originals | throw (IO.userError "missing prepared original")
        let expected ← request.owners.mapM fun owner => do
          return (owner,← ObservedRecordView.geometry? original.index request.access.database owner deadline)
        check (toJson actual == toJson expected) "captured geometry differs from independent DB read"
      return view.charge
    let some first := requests[0]? | throw (IO.userError "typed read fixture has no sources")
    let wire ← sourcePalettes server first.access.capability (Json.mkObj [("sources",toJson requests)]) deadline
    let wirePalette ← IO.ofExcept (fromJson? wire : Except String SourceViewBatch.Palette)
    check (toJson wirePalette.owners == toJson batch.palette.owners &&
      toJson wirePalette.records == toJson batch.palette.records && wirePalette.identities == batch.palette.identities)
      "wire and typed reads disagree"
    access.release requests wirePalette.lease
    batch.release deadline
    let rejectedReleases ← IO.mkRef (0 : Nat)
    let malformed : SourceViewBatch.ReadAccess := {access with
      read := fun requests deadline => do
        let palette ← access.read requests deadline
        return {palette with identities := #[]}
      release := fun requests lease => do
        rejectedReleases.modify (·+1)
        access.release requests lease }
    let malformedSources := sources.map fun (reference,owners) => ({reference with localReads := some malformed},owners)
    check (← rejects (Publication.Client.sourcePalettes malformedSources deadline)) "malformed typed reply accepted"
    check ((← rejectedReleases.get) == 1 && (← server.palettes.stats).getObjValD "active" == toJson (0 : Nat))
      "client rejection leaked the typed reservation"
    for request in requests do
      let bad := {request with access := {request.access with capability := "foreign"}}
      check (← rejects (access.read #[bad] deadline)) "foreign capability accepted"
      let bad := {request with access := {request.access with scope := "foreign"}}
      check (← rejects (access.read #[bad] deadline)) "foreign scope accepted"
      let bad := {request with access := {request.access with source := {request.access.source with revision := request.access.source.revision+1}}}
      check (← rejects (access.read #[bad] deadline)) "foreign full source head accepted"
      let bad := {request with access := {request.access with metadata := {request.access.metadata with payload := String.ofList (List.replicate 64 'a')}}}
      check (← rejects (access.read #[bad] deadline)) "foreign prepared root accepted"
      let bad := {request with retained := some (String.ofList (List.replicate 64 'b'))}
      check (← rejects (access.read #[bad] deadline)) "missing retained view accepted"
    check (← rejects (access.read requests (← IO.monoMsNow))) "expired typed read accepted"
    check (!(access.accepts {endpoint with pid := endpoint.pid+1}) &&
      !(access.accepts {endpoint with generation := "foreign"}) &&
      !(access.accepts {endpoint with port := endpoint.port+1})) "foreign local endpoint accepted"
    let borrowed ← Publication.Client.sourcePalettes sources ((← IO.monoMsNow)+10000)
    let entered : IO.Promise Unit ← IO.Promise.new
    let release : IO.Promise Unit ← IO.Promise.new
    let task ← IO.asTask (server.palettes.withView borrowed.palette.lease key fun _ => do
      entered.resolve ()
      discard <| IO.wait release.result!) .dedicated
    try
      TaskDeadline.wait (Std.Async.AsyncTask.ofPurePromise entered) ((← IO.monoMsNow)+2000)
      borrowed.release deadline
      let stats ← server.palettes.stats
      check (stats.getObjValD "active" == toJson (1 : Nat) && stats.getObjValD "chargedBytes" == toJson charged)
        "release freed active reader reservation"
      check (← rejects (server.palettes.withView borrowed.palette.lease key (fun _ => pure ()))) "released lease admitted a new reader"
    finally
      release.resolve ()
      discard <| IO.wait task
    let cancelled ← Publication.Client.sourcePalettes sources ((← IO.monoMsNow)+10000)
    let cancellationEntered : IO.Promise Unit ← IO.Promise.new
    let cancelledTask ← IO.asTask (server.palettes.withView cancelled.palette.lease key fun _ => do
      cancellationEntered.resolve ()
      repeat
        if ← IO.checkCanceled then throw (IO.userError "cancelled typed borrower")
        IO.sleep 1) .dedicated
    try
      TaskDeadline.wait (Std.Async.AsyncTask.ofPurePromise cancellationEntered) ((← IO.monoMsNow)+2000)
    finally
      IO.cancel cancelledTask
      discard <| IO.wait cancelledTask
      cancelled.release ((← IO.monoMsNow)+1000)
    let final ← server.palettes.stats
    check (final.getObjValD "active" == toJson (0 : Nat) && final.getObjValD "chargedBytes" == toJson (0 : Nat)) "typed read reservation leaked"
    check ((← server.sourceReplies.atomically get) == 0) "temporary count reservation leaked"
    for (path,bytes) in heads do check ((← IO.FS.readFile path) == bytes) "typed read changed an original head"
    IO.FS.writeFile (root/"report.json") (Json.mkObj [("typedReadChecks",toJson true),
      ("typedClientSucceededWithoutNetworkListener",toJson true),("wireAndTypedGeometryMetadataEqual",toJson true),
      ("geometryIncludedInExistingQueryReservation",toJson charged),("fullScopeHeadRootCapabilityExpiryRejection",toJson true),
      ("activeBorrowSurvivesRelease",toJson true),("allReservationsReleased",toJson true),
      ("clientRejectionAndCancellationReleaseReservations",toJson true),
      ("originalHeadsUnchanged",toJson true),("final",final),("adopted",toJson false)]).compress
  finally
    for request in requests do
      if let some token := request.retained then server.retained.release token request.access.scope
    server.palettes.close
    server.retained.close
    server.prepared.close
    server.operations.close
def main (args : List String) : IO UInt32 := do
  match args with
  | ["typed-read-check",root] => checks (.mk root); return 0
  | ["front-traffic-audit",source] =>
    let result ← IO.Process.output {
      cmd := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study/metadata-ingress-candidate-build/StudyMain",
      args := #["front-traffic-audit",source]}
    IO.print result.stdout
    IO.eprint result.stderr
    return result.exitCode
  | other => sourceRouteEngine other
