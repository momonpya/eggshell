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
#print axioms PreparedSourceView.file_ready_stored
#print axioms PreparedSourceView.file_ready_unique
#print axioms PreparedSourceView.file_ready_scopes
#print axioms PreparedSourceView.scoped_file_valid

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
      (``automaticHandoff,``SourceContext.originalReads),
      (``sourcePlan,``SharedReadViews.Source.readMetadata),
      (``PreparedSourceView.decodeOwner,``OwnerPalette.Descriptor.inScope)] do
    unless (← body name).getUsedConstants.contains required do throwError "typed read path is disconnected {name} -> {required}"
  for name in [`Eggshell.Plugin.Publication.Client.sourceRecords,`Eggshell.Plugin.Publication.Service.sourceRecords] do
    if environment.contains name then throwError "obsolete per-source record RPC remains {name}"
  for name in [`Eggshell.Synapses.CanonicalSource.Shared.Loaded.withFile,
      `Eggshell.Synapses.CanonicalSource.Shared.FileCache,
      `Eggshell.Synapses.CanonicalSource.Shared.fileCapacity,
      `Eggshell.Synapses.PreparedSourceView.readFile,
      `Eggshell.Synapses.PreparedSourceView.publishFile,
      `Eggshell.Synapses.PreparedSourceView.fileName] do
    if environment.contains name then throwError "redundant file-header storage/cache remains {name}"
  unless (← body ``sourcePlan).getUsedConstants.contains ``PreparedSourceView.fileReady do
    throwError "actual selector is disconnected from the pure file header"
  let mut pending := [``SharedReadViews.Source.readRecords,``SharedReadViews.Source.readMetadata,
    ``SharedReadViews.Source.capturedBytes,``PreparedSourceView.fileReady,``PreparedSourceView.FileReady.addExtents]
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

def fileChecks (server : Server) (root : System.FilePath) : IO Json := do
  let directory := root/"file-fixture"
  IO.FS.createDirAll directory
  let content := "int alpha = 1;\nint beta = 2;\nint gamma = 3;\n"
  IO.FS.writeFile (directory/"fixture.c") content
  let input := Json.mkObj [("command",toJson "nl -ba fixture.c | sed -n '1,3p'")]
  let deadline := (← IO.monoMsNow)+20000
  let capture ← SourceEvidence.capture directory input deadline
  let output := Json.mkObj [("output",toJson "1\tint alpha = 1;\n2\tint beta = 2;\n3\tint gamma = 3;\n")]
  let correspondence ← ContentCapture.finish directory capture output.compress deadline
  check (capture.record.valid && correspondence.complete && !correspondence.aliases.isEmpty)
    "file-header control did not capture actual content correspondence"
  let tool : ToolEvent := {
    name := "arbitrary_read"
    useId := "file"
    input := input.compress
    response := output.compress
    source := some capture
    correspondence := some correspondence }
  let source ← Persistence.ensureSnapshot (directory/"project.egg")
  let occurrence : Occurrence := ⟨"file-session","file-turn",tool.useId⟩
  let known ← Journal.knowledge source [] false
  let domain := Sha256.hex "pure file metadata check".toUTF8
  discard <| Journal.append source ⟨⟨domain,1⟩,.start occurrence (canonicalToolWork tool)
    (Sha256.hex "read fixture".toUTF8) known,none⟩
  discard <| Journal.append source ⟨⟨domain,2⟩,.finish occurrence tool.name
    (canonicalJson tool.input) (canonicalJson tool.response) (some source.directory.toString),none⟩
  let pending : PendingTurn := {
    sessionId := occurrence.session
    turnId := occurrence.turn
    cwd := directory.toString
    prompt := "read fixture"
    profile := "work"
    write := some source.directory.toString
    read := []
    semanticMatcher := none
    handoffChars := 500000
    projection := .none
    tools := [tool]
    finalMessage := none }
  let request ← NativePublication.prepare pending source.directory true
  let published ← NativePublication.runPrepared source.directory #[request]
  check (published.size == 1 && published.all (·.source.complete)) "file-header control publication did not ACK"
  let source ← PageMap.pin source.directory
  let head ← IO.FS.readFile (source.directory/"head")
  discard <| Build.refresh source .database
  let refreshed ← CanonicalSource.Cache.refresh source .database
  let scope ← readSource server source.directory source.head.identity .database
  let prepared ← prepareRegistered server scope (some source.head) deadline (some deadline) (some refreshed.metadata)
  let access ← IO.ofExcept (fromJson? prepared : Except String CanonicalSource.Shared.Access)
  let retained ← IO.ofExcept (prepared.getObjValAs? String "retained")
  let owner := (compileOperationOutcomes (.text occurrence.session) (.text occurrence.turn) tool).2
  let owners := #[valueKey owner]
  let requests : Array SourceViewBatch.Request := #[⟨access,owners,some retained⟩]
  let palette ← readSourceViews server access.capability requests deadline
  try
    let captured ← server.palettes.withView palette.lease (SourceViewBatch.key requests) fun view => do
      let some source := view.sources[0]? | throw (IO.userError "file view not captured")
      return source
    let metadata ← IO.ofExcept (captured.readMetadata owners[0]!)
    check (!metadata.rows.isEmpty && !metadata.stored.descriptor.files.isEmpty) "file fixture did not reach checked owner metadata"
    let mut files : Std.HashMap Eggshell.Synapses.File PreparedSourceView.FileReady := {}
    let invalid := {metadata.stored with descriptor := {metadata.stored.descriptor with
      files := metadata.stored.descriptor.files.map fun file => {file with fingerprint := "invalid"}}}
    check (match PreparedSourceView.decodeOwner source.head.identity owners[0]! invalid with
      | .error _ => true | .ok _ => false)
      "invalid file identity escaped checked owner metadata"
    for file in metadata.stored.descriptor.files do
      let header := PreparedSourceView.fileReady file
      check (file.valid && header.stored.file == file && header.stored.order == (toJson file).compress &&
        header.stored.stem == Index.contentKey file && header.stored.extents.isEmpty) "pure header differs from canonical publication"
      check ((← captured.loaded.recipes.get ("view-file:"++Index.contentKey file)).isNone)
        "candidate still publishes redundant file metadata"
      files := files.insert file header
    for (file,extents) in metadata.stored.scopes do
      let some header := files[file]? | throw (IO.userError "file scope lost its descriptor")
      files := files.insert file (header.addExtents extents)
    let expected ← IO.ofExcept (PreparedSourceView.join metadata.rows files)
    let expectedDomain ← IO.ofExcept (PreparedSourceView.domain expected files #[])
    let cues := (PreparedSourceView.bindings owners[0]! expected).map fun (first,last) =>
      ({priority := 0,first,last} : SharedRangeAdapter.RankedCue)
    let fileQuery : SharedRangeAdapter.FileQuery := ⟨0,owners[0]!,cues,cues,[]⟩
    let query : SharedRangeAdapter.ServiceQuery := {
      owners := owners
      works := #[(valueKey (compileOperationOutcomes (.text occurrence.session) (.text occurrence.turn) tool).1,0)]
      frameCosts := #[(0,0)]
      scale := (List.range (max owners.size cues.length)).foldl (fun value rank => Nat.lcm value (61+rank)) 1
      genericCosts := #[]
      generic := #[]
      pieces := []
      files := #[fileQuery]
      bundles := #[]
      fixed := (0,0)
      ceiling := (120000,120000) }
    let domain ← IO.ofExcept (PreparedSourceView.domain expected files query.frameCosts)
    let units ← IO.ofExcept (PreparedSourceView.federatedUnits owners[0]! #[metadata] expected [])
    let shapes : Array SharedRangeAdapter.ServiceUnit := units.map fun unit => {
      shape := {family := 0,ranges := unit.ranges,coverage := unit.coverage}
      sourceKeys := unit.keys }
    let pieces := SharedRangeAdapter.viewPieces query.scale fileQuery expected
    let some expectedChoice := SharedRangeAdapter.selectView query shapes pieces domain |
      throw (IO.userError "independent file selector failed")
    let reserved ← IO.mkRef (0 : Nat)
    let actualPlan ← try
      sourcePlan server access.capability (Json.mkObj [("sources",toJson requests),
        ("lease",toJson palette.lease),("selector",toJson query)]) deadline reserved
    finally
      let amount ← reserved.get
      server.sourceReplies.atomically (modify (·-amount))
    check (actualPlan.getObjValD "choice" == toJson expectedChoice)
      "actual file selector changed the independent selection/receipt"
    check (!expectedChoice.sourceKeys.isEmpty) "file selector fixture has no positive-value original rows"
    let before ← server.prepared.stats
    let began ← IO.monoMsNow
    -- Hold the old preparation-owner lock for the whole parallel read. Every
    -- reader receives only immutable values, never a cache/lease capability.
    server.prepared.state.atomically do
      let tasks ← (Array.range 80).mapM fun _ => IO.asTask (do
        for _ in [:128] do
          let ready ← IO.ofExcept (captured.readMetadata owners[0]!)
          let mut actual := {}
          for file in ready.stored.descriptor.files do actual := actual.insert file (PreparedSourceView.fileReady file)
          for (file,extents) in ready.stored.scopes do
            let some header := actual[file]? | throw (IO.userError "parallel file scope lost its descriptor")
            actual := actual.insert file (header.addExtents extents)
          let rows ← IO.ofExcept (PreparedSourceView.join ready.rows actual)
          let domain ← IO.ofExcept (PreparedSourceView.domain rows actual #[])
          check (rows == expected && domain.costs == expectedDomain.costs && domain.payloads == expectedDomain.payloads)
            "parallel immutable file read changed original rows/costs") .dedicated
      try
        for task in tasks do TaskDeadline.wait task ((← IO.monoMsNow)+10000)
      finally
        for task in tasks do IO.cancel task
        for task in tasks do discard <| IO.wait task
    let elapsed := (← IO.monoMsNow)-began
    check ((← server.prepared.stats) == before) "pure file read mutated shared cache bookkeeping"
    check ((← IO.FS.readFile (source.directory/"head")) == head) "file header read rewrote original publication"
    return Json.mkObj [("publishedFileOwners",toJson (1 : Nat)),("fileIdentities",toJson files.size),
      ("rows",toJson expected.size),("parallelReaders",toJson (80 : Nat)),("readsEach",toJson (128 : Nat)),
      ("lockHeldReadElapsedMs",toJson elapsed),("originalRowsCostsAndPayloadsEqual",toJson true),
      ("actualServicePlanEqualsIndependentSelection",toJson true),
      ("cacheStatsUnchanged",toJson true),("noRedundantFilePublications",toJson true),
      ("originalHeadUnchanged",toJson true)]
  finally
    server.palettes.release palette.lease (SourceViewBatch.key requests)
    server.retained.release retained access.scope
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
    let fileReport ← fileChecks server root
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
    IO.FS.writeFile (root/"report.json") (Json.mkObj [("typedReadChecks",toJson true),("fileReads",fileReport),
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
  | ["file-read-check",root] => checks (.mk root); return 0
  | ["front-traffic-audit",source] =>
    let result ← IO.Process.output {
      cmd := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study/metadata-ingress-candidate-build/StudyMain",
      args := #["front-traffic-audit",source]}
    IO.print result.stdout
    IO.eprint result.stderr
    return result.exitCode
  | other => sourceRouteEngine other
