module
public import tools.research.RealSelectionStages
public import Eggshell.PublicationService
@[expose] public section

namespace Eggshell.Research.RealSelectionObserver
open Lean Eggshell Plugin Synapses SharedRangeAdapter
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)

/-- This diagnostic borrows the same immutable sources as the real selector.
No capability, endpoint or readable token is persisted. -/
def assemble (query : ServiceQuery) (sources : Array SharedReadViews.Source) :
    Except String (Array ServiceUnit × List CuePiece × PreparedSourceView.Domain) := do
  let mut units := #[]
  let mut pieces := []
  let mut rows := #[]
  let mut headers := {}
  let families := Std.HashMap.ofArray (query.files.map fun file => (file.family,file))
  let generic := KeyPostings.prepare (fun entry : GenericUnit × Nat => entry.1.family) query.generic.zipIdx
  let genericPieces := KeyPostings.prepare (fun piece : CuePiece => piece.family) query.pieces.toArray
  for family in [:query.owners.size] do
    if let some file := families[family]? then
      let mut incoming := #[]
      let mut parts := #[]
      for entry in sources do
        if !entry.owners.contains file.owner then continue
        let ready ← entry.readMetadata file.owner
        for source in ready.stored.descriptor.files do
          if !headers.contains source then headers := headers.insert source (PreparedSourceView.fileReady source)
        for (source,extents) in ready.stored.scopes do
          let some header := headers[source]? | throw "scope has no published file header"
          headers := headers.insert source (header.addExtents extents)
        if !ready.rows.isEmpty then parts := parts.push ready
        incoming := incoming ++ ready.rows
      if incoming.isEmpty then throw "file selector has no published rows in its scoped views"
      let original ← PreparedSourceView.join incoming headers
      let prepared ← PreparedSourceView.federatedUnits file.owner parts original file.groups
      for unit in prepared do
        units := units.push {
          shape := {family,ranges := unit.ranges,coverage := unit.coverage}
          sourceKeys := unit.keys}
      pieces := pieces ++ viewPieces query.scale file original
      rows := rows ++ original
    else pieces := pieces ++ (genericPieces.lookup family).toList
    for (unit,index) in generic.lookup family do
      units := units.push {shape := {family,ranges := unit.ranges},generic := some index,contextual := unit.contextual}
    unless units.size ≤ 65536 do throw "prepared selector exceeds its unit budget"
  let originals ← PreparedSourceView.join rows headers
  let source ← PreparedSourceView.domain originals headers query.frameCosts
  return (units,pieces,source)

/-- The opaque thunk is invoked after the first clock read. Data is forced
through an IO argument before the second read, not reconstructed by a timer. -/
@[noinline, nospecialize] def measure (action : Unit → α) : IO (α × Nat) := do
  let began ← IO.monoNanosNow
  let result ← (← IO.mkRef (action ())).get
  return (result,((← IO.monoNanosNow)-began)/1000)

def profile (query : ServiceQuery) (sources : Array SharedReadViews.Source)
    (expected : ServiceChoice) : IO Json := do
  let (assembled,assemblyUs) ← measure (fun _ => assemble query sources)
  let (units,pieces,source) ← IO.ofExcept assembled
  check (expected.receipt.getObjValD "candidateUnits" == toJson units.size) "profile assembled a different candidate domain"
  let (problem,problemUs) ← measure (fun _ => problemFromView query source units pieces)
  let some p := problem | throw (IO.userError "profile problem was rejected")
  let (bundles,bundleUs) ← measure (fun _ => RealSelectionStages.bundleStage query units pieces p)
  let some bundles := bundles | throw (IO.userError "profile bundle stage was rejected")
  let (scopes,scopeUs) ← measure (fun _ => RealSelectionStages.scopeStage query units pieces source p bundles)
  let some scopes := scopes | throw (IO.userError "profile scope stage was rejected")
  let (selection,greedyUs) ← measure (fun _ => SharedCoverage.OwnedAdvance.chooseOwned scopes.problem)
  let some selection := selection | throw (IO.userError "profile greedy stage was rejected")
  let (finished,finishUs) ← measure (fun _ => scopes.finish selection)
  let some finished := finished | throw (IO.userError "profile result was rejected")
  check (toJson finished == toJson expected) "profile stages changed the actual service choice"
  return Json.mkObj [
    ("sameCompleteServiceChoice",toJson true),("units",toJson units.size),("pieces",toJson pieces.length),
    ("sourceRows",toJson source.rows.size),("owners",toJson query.owners.size),
    ("problemOffers",toJson p.offers.size),("recipes",toJson bundles.recipes.size),
    ("scopes",toJson scopes.scopes),("recognizedScopes",toJson scopes.recognized),
    ("containmentChecks",toJson scopes.containmentChecks),("conditionedOffers",toJson scopes.problem.offers.size),
    ("selected",toJson selection.selected.length),
    ("timesUs",Json.mkObj [("assembly",toJson assemblyUs),("problem",toJson problemUs),
      ("bundles",toJson bundleUs),("compileBindScopes",toJson scopeUs),
      ("greedy",toJson greedyUs),("finish",toJson finishUs)])]

def reads (ordinal : IO.Ref Nat) (server : Publication.Service.Server) (endpoint : Daemon.Endpoint) :
    SourceViewBatch.ReadAccess :=
  let original := Publication.Service.localReadAccess server endpoint
  {original with select := fun requests lease query deadline => do
    let result ← original.select requests lease query deadline
    let index ← ordinal.get
    if index < 3 then
      -- The harness completes three serial prime hooks before launching its
      -- wave. Once full, every concurrent callback only reads this value.
      ordinal.set (index+1)
      let observed ← server.palettes.withView lease (SourceViewBatch.key requests) fun view =>
        profile query view.sources result.choice
      let some root ← IO.getEnv "EGGSHELL_REAL_SELECTION_PROFILE" |
        throw (IO.userError "profile output directory was not set")
      let path := System.FilePath.mk root/s!"selection-{index}.json"
      check (!(← path.pathExists)) "preserve real selection profile"
      let value := observed.setObjVal! "sourceHeads" (toJson (requests.map (·.access.source)))
        |>.setObjVal! "metadataHeads" (toJson (requests.map (·.access.metadata.recipes)))
        |>.setObjVal! "querySha256" (toJson (Sha256.hex (toJson query).compress.toUTF8))
        |>.setObjVal! "choiceSha256" (toJson (Sha256.hex (toJson result.choice).compress.toUTF8))
      IO.FS.writeFile path value.compress
    return result }

end Eggshell.Research.RealSelectionObserver

namespace Eggshell.Plugin.Publication.Service.RealSelectionLoop
open Lean DB Synapses Std Async TCP
def runWith (reads : Server → Daemon.Endpoint → SourceViewBatch.ReadAccess) : IO UInt32 := do
  let root ← directory
  let owner ← lease (root / "service.guard")
  let socket ← Socket.Server.mk
  socket.bind (Daemon.loopback 0)
  socket.listen maxClients.toUInt32
  socket.noDelay
  let operationSocket ← Socket.Server.mk
  operationSocket.bind (Daemon.loopback 0)
  operationSocket.listen OperationPlan.maxRequests.toUInt32
  operationSocket.noDelay
  let address ← socket.getSockName
  let endpoint : Daemon.Endpoint := {
    session := "publisher",pid := (← IO.Process.getPID).toNat,port := address.port.toNat
    secret := Blake3.hex (← IO.getRandomBytes 32),generation := ← generation }
  writeJson (root / "endpoint.json") endpoint
  let operationAddress ← operationSocket.getSockName
  writeJson (root/"operations.json") ({endpoint with
    session := "publisher-operations",port := operationAddress.port.toNat} : Daemon.Endpoint)
  let originals ← CanonicalSource.Shared.Pool.new
  let server : Server := ⟨← Std.Mutex.new ({} : State),← Std.Mutex.new 0,← IO.mkRef false,
    ← Std.Mutex.new #[],originals,← CanonicalSource.Leases.Pool.new originals,← ObservedRecordView.Cache.new,
    ← Std.Mutex.new 0,← Std.Mutex.new #[],← SharedReadViews.Pool.new,← Owned.Pool.new,← PreparationService.Pool.new,
    ← OperationPool.Pool.new⟩
  -- `finally` must read the live owners, rather than a mutable local captured
  -- when its cleanup closure was constructed.
  let clients ← IO.mkRef ([] : List (Task (Except IO.Error Unit)))
  let operationClients ← IO.mkRef ([] : List (Task (Except IO.Error Unit)))
  let publications ← IO.mkRef ([] : List (Task (Except IO.Error Unit)))
  let preparations ← IO.mkRef ([] : List (Task (Except IO.Error Unit)))
  let operations ← IO.mkRef ([] : List (Task (Except IO.Error Unit)))
  let retention ← if (← IO.getEnv "EGGSHELL_RESEARCH_RETENTION") == some "1" then
    some <$> Research.RetentionProbe.Probe.new else pure none
  let mut activity ← IO.monoMsNow
  Client.registerHosted endpoint
  try
    while !(← server.stopping.get) do
      -- Backpressure belongs before accept. Accepting and dropping a socket
      -- when handlers are full turns a bounded queue into random RPC loss.
      clients.set (← retain (← clients.get))
      if (← clients.get).length < maxClients then
        match ← socket.tryAccept with
        | none => pure ()
        | some client =>
            activity ← IO.monoMsNow
            let task ← IO.asTask (serveClient server endpoint.secret client false retention) .dedicated
            clients.modify (task :: ·)
      operationClients.set (← retain (← operationClients.get))
      if (← operationClients.get).length < OperationPlan.maxRequests then
        match ← operationSocket.tryAccept with
        | none => pure ()
        | some client =>
            activity ← IO.monoMsNow
            let task ← IO.asTask (serveClient server endpoint.secret client true retention) .dedicated
            operationClients.modify (task :: ·)
      publications.set (← retain (← publications.get))
      preparations.set (← retain (← preparations.get))
      operations.set (← retain (← operations.get))
      reapReplies server
      if let some retention := retention then retention.respond
      server.retained.reap
      while (← publications.get).length < 16 do
        if let some group ← server.owned.takeGroup then
          let task ← IO.asTask (server.owned.publish group) .dedicated
          publications.modify (task :: ·)
        else
          let some (path,identity,jobs) ← takeGroup server | break
          let task ← IO.asTask (publish server path identity jobs) .dedicated
          publications.modify (task :: ·)
      for lane in List.finRange PreparationPlan.workers do
        if let some active ← server.preparation.take lane then
          let task ← IO.asTask (server.preparation.run lane active) .dedicated
          preparations.modify (task :: ·)
      for lane in List.finRange OperationPlan.workers do
        if let some (active,job) ← server.operations.take lane then
          let task ← IO.asTask (server.operations.run lane active job) .dedicated
          operations.modify (task :: ·)
      repeat
        let some (active,job) ← server.operations.takeSearch | break
        let task ← IO.asTask (server.operations.runSearch active job (some (reads server endpoint))) .dedicated
        operations.modify (task :: ·)
      if (← clients.get).isEmpty && (← operationClients.get).isEmpty &&
          (← publications.get).isEmpty && (← preparations.get).isEmpty &&
          (← operations.get).isEmpty && (← IO.monoMsNow) > activity+300000 then
        server.stopping.set true
      IO.sleep 1
    return 0
  finally
    server.stopping.set true
    if let some retention := retention then retention.stop
    server.preparation.close
    server.operations.close
    Worker.shutdown
    server.palettes.close
    server.retained.close
    server.prepared.close
    server.owned.stop
    let projects ← close server
    let publications ← publications.get
    let clients ← clients.get
    let operationClients ← operationClients.get
    let preparations ← preparations.get
    let operations ← operations.get
    -- No derived preparation is part of this wait. Active source commits
    -- finish their bounded group; queued requests receive no source ACK.
    for task in publications do let _ ← IO.wait task; pure ()
    for task in preparations do let _ ← IO.wait task; pure ()
    for task in operations do let _ ← IO.wait task; pure ()
    -- receiveLive/awaitReply poll `stopping` every five milliseconds. Do not
    -- cancel tasks parked in async socket selectors: cancelling a selector's
    -- waiter does not guarantee that its blocking task completes.
    for task in clients do let _ ← IO.wait task; pure ()
    for task in operationClients do let _ ← IO.wait task; pure ()
    server.owned.release
    for project in projects do FileSystem.unlockRead project.lease
    if let some current ← (readJson? (root / "endpoint.json") [] : IO (Option Daemon.Endpoint)) then
      if current.secret == endpoint.secret then removeIfExists (root / "endpoint.json")
    if let some current ← (readJson? (root/"operations.json") [] : IO (Option Daemon.Endpoint)) then
      if current.secret == endpoint.secret then removeIfExists (root/"operations.json")
    FileSystem.unlockRead owner
    Client.unregisterHosted endpoint


theorem original_run : runWith localReadAccess = Eggshell.Plugin.Publication.Service.run := by rfl
#print axioms original_run

def observed : IO UInt32 := do
  let ordinal ← IO.mkRef 0
  runWith (Eggshell.Research.RealSelectionObserver.reads ordinal)
end Eggshell.Plugin.Publication.Service.RealSelectionLoop
