import Eggshell.PublicationClient
import Eggshell.PublicationService

open Lean Eggshell Eggshell.Plugin Eggshell.Synapses
open CanonicalSource

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def read (path : System.FilePath) : IO Json := do
  IO.ofExcept (Json.parse (← IO.FS.readFile path))

private def emit (path : System.FilePath) (value : Json) : IO Unit := do
  IO.FS.writeFile path value.pretty
  IO.println value.compress
  (← IO.getStdout).flush

structure Fixture where
  source : DB.PageMap.Snapshot
  storage : DB.Sidecar.Storage
  ready : Cache.Ready
  owners : Array String
  expected : Std.HashMap String (Array StoredRow)
  bindings : Std.HashMap Range (Array Read)

private def fixtureFrom (source : DB.PageMap.Snapshot) (storage : DB.Sidecar.Storage) : IO Fixture := do
  let _ ← Build.refresh source storage
  let _ ← Cache.refresh source storage
  let some ready ← Cache.open? source storage | throw (IO.userError "source cache did not prepare")
  let owners := (Shared.allOwners ready.registry).toArray.map Prod.snd |>.qsort (· < ·)
  let owners := (hashDistinct owners.toList).toArray
  check (!owners.isEmpty) "fixture contains no original file rows"
  let mut expected := {}
  for owner in owners do
    let allowed := ({} : Std.HashSet (String × String)).insert (source.head.identity,owner)
    let selected := Delivery.byOwner ready.registry allowed
    let rows ← IO.ofExcept (Delivery.merge (selected[owner]?.getD #[]))
    expected := expected.insert owner rows
  let some reader ← Index.open? source storage .shared | throw (IO.userError "binding fixture is cold")
  let facts ← Index.allFacts reader.index
  let sources := hashDistinct (facts.toList.filterMap fun fact =>
    (Index.bindingCandidate? fact).map (·.source))
  let allowed := Std.HashSet.ofArray owners
  let mut bindings := {}
  -- Independent former fact/posting path; it cannot read compiled bindings.
  for range in sources do
    let found ← reader.lookup (.source range) 32768 ((← IO.monoMsNow)+10000)
    check found.complete "independent binding oracle did not finish"
    let rows := found.checked.filterMap fun checked =>
      let read := match checked.fact with
        | .read saved => some {saved with quotations := #[]}
        | .supports support => some {
            occurrence := support.read.occurrence
            source := support.source
            binding := support.binding
            quotations := #[]}
        | _ => none
      read.filter fun read => read.valid && read.source == range &&
        read.binding.database == source.head.identity && allowed.contains read.binding.owner
    bindings := bindings.insert range (hashDistinct rows.toList).toArray
  return ⟨source,storage,ready,owners,expected,bindings⟩

private def publish (source : DB.PageMap.Snapshot) (values : List Value) : IO DB.PageMap.Snapshot := do
  let _ ← DB.PageMap.withWriter source fun writer => do
    let intern : Persistence.Store.Intern := ⟨writer,← IO.mkRef {}⟩
    let ids ← values.mapM intern.root
    Persistence.Store.writeChange writer {added := ids,removed := [],unionsChanged := false}
  DB.PageMap.pin source.directory

private def observation (workspace : System.FilePath) (tag : String) (first last : Nat) : IO (List Value) := do
  -- This tests the existing file-coordinate cache, whose supported input is
  -- still the literal numbered-read domain. General original records remain
  -- a separate domain; unsupported Read syntax is not called missing memory.
  let command := s!"nl -ba source.cpp | sed -n '{first},{last}p'"
  let input := Json.mkObj [("command",toJson command)]
  let captured ← SourceEvidence.capture workspace input ((← IO.monoMsNow)+10000)
  check captured.record.valid "fixture did not capture its actual input fingerprint"
  let observed ← IO.Process.output {cmd := "/bin/sh",args := #["-c",command],cwd := workspace.toString}
  check (observed.exitCode == 0) "fixture's actual numbered file read failed"
  let text := observed.stdout
  let work := Value.text ("shell\n" ++ input.compress)
  let output := Value.text text
  let event := Value.applyList .occurrence [Ref.semantic output,Ref.semantic work,
    Ref.exact (.text "source-service-fixture"),Ref.exact (.text "turn"),Ref.exact (.text tag)]
  let owner := OutcomeEdge.make work output [event] (by simp) (by simp [maxOutcomeObservations])
  let receipt := SourceEvidence.receipt (.text "source-service-fixture") (.text "turn")
    (.text tag) owner.relation captured.record
  return [owner.relation,receipt]

private def makeFixture (root : System.FilePath) (project : Nat) : IO Fixture := do
  let path := root / s!"project-{project}"
  IO.FS.createDir path
  let text := "\n".intercalate ((List.range 1024).map fun line =>
    s!"project_{project}_line_{line}(); // immutable original support record") ++ "\n"
  IO.FS.writeFile (path / "source.cpp") text
  let source ← DB.PageMap.create (path / "source.egg")
    (Persistence.valueToJson (.text s!"prepared-source-project-{project}")).compress
  let a ← observation path "first" 1 768
  let b ← observation path "second" 257 1024
  fixtureFrom (← publish source (a++b)) .database

private def startService (binary : String) : IO (IO.Process.Child {stdin := .null,stdout := .null,stderr := .piped} × Daemon.Endpoint) := do
  let child ← IO.Process.spawn {
    cmd := binary
    args := #["codex-publication-daemon"]
    stdin := .null
    stdout := .null
    stderr := .piped
    setsid := true}
  let deadline := (← IO.monoMsNow)+10000
  repeat
    check (← child.tryWait).isNone "data-side service stopped during startup"
    if let some endpoint ← Publication.Client.endpoint? then
      check (endpoint.pid == child.pid.toNat) "another service owns the audit endpoint"
      let _ ← Daemon.exchange endpoint "ping" (budget := 1000)
      return (child,endpoint)
    check ((← IO.monoMsNow) < deadline) "data-side service startup expired"
    IO.sleep 5
  throw (IO.userError "unreachable service startup")

private def stopService (child : IO.Process.Child config) (endpoint : Daemon.Endpoint)
    (reaped : IO.Ref Bool) : IO Json := do
  let started ← IO.monoMsNow
  let acknowledged ← try
    let _ ← Daemon.exchange endpoint "shutdown" (budget := 1000)
    pure true
    catch _ => pure false
  let deadline := started+5000
  repeat
    if let some code ← child.tryWait then
      reaped.set true
      check (code == 0) "data-side service did not exit successfully"
      check (← Publication.Client.endpoint?).isNone "data-side endpoint survived shutdown"
      return Json.mkObj [("acknowledged",toJson acknowledged),("exitCode",toJson code.toNat),
        ("elapsedMs",toJson ((← IO.monoMsNow)-started)),("endpointRemoved",toJson true)]
    check ((← IO.monoMsNow) < deadline) "data-side service did not stop within its bound"
    IO.sleep 5
  throw (IO.userError "unreachable service stop")

private def retireService (child : IO.Process.Child config) (reaped : IO.Ref Bool) : IO Unit := do
  unless ← reaped.get do
    if (← child.tryWait).isNone then
      child.kill
      let _ ← child.wait
      pure ()
    reaped.set true

private def stats (endpoint : Daemon.Endpoint) : IO Json := do
  IO.ofExcept (Json.parse (← Daemon.exchange endpoint "stats" (budget := 1000)))

private def normalized (rows : Array (String × Array StoredRow)) : IO (Array (String × Array StoredRow)) :=
  rows.mapM fun (owner,values) => return (owner,← IO.ofExcept (Delivery.merge values))

private def percentile (values : Array Nat) (p : Nat) : Nat :=
  (values.qsort (· < ·))[((values.size*p+99)/100)-1]!

private def concurrent (endpoint : Daemon.Endpoint) (fixtures : Array Fixture) (clients : Nat) : IO Json := do
  let released ← IO.mkRef false
  let arrived ← Std.Mutex.new (0 : Nat)
  let tasks ← (Array.range clients).mapM fun client => IO.asTask (do
    arrived.atomically (modify (·+1))
    while !(← released.get) do IO.sleep 1
    let some input := fixtures[client%fixtures.size]? | throw (IO.userError "missing source fixture")
    let owners := (Array.range (min input.owners.size (1+client%3))).map (input.owners[·]!)
    let started ← IO.monoMsNow
    let some reference ← Publication.Client.prepareSource input.source input.storage (started+28000) |
      throw (IO.userError "prepared source unavailable to a concurrent reader")
    check (reference.endpoint.pid == endpoint.pid) "a caller replaced the shared data-side owner"
    let response ← Publication.Client.sourceRows reference owners (started+28000)
    let sources := input.bindings.toArray.map Prod.fst
    let chosen := sources.extract (client%sources.size) (min sources.size (client%sources.size+3))
    let bound ← Publication.Client.sourceBindings reference chosen (Std.HashSet.ofArray input.owners) (started+28000)
    check bound.complete "prepared source bindings did not finish"
    for range in chosen do
      check (bound.rows[range]?.getD #[] == input.bindings[range]?.getD #[])
        "compiled binding differs from complete fact/posting oracle"
    let elapsed := (← IO.monoMsNow)-started
    let actual ← normalized response.rows
    let expected := owners.map fun owner => (owner,input.expected[owner]?.getD #[])
    check (actual == expected) "shared preparation differs from independent per-owner projection"
    for (owner,layout) in response.layouts do
      let rows := input.expected[owner]?.getD #[]
      check (layout == (Records.prepare rows).map Recipe.Entry.ofRecord)
        "publication-time layout differs from the independent old preparation"
    return (elapsed,reference.access.reuse,response.reuse)) .dedicated
  let barrier := (← IO.monoMsNow)+10000
  repeat
    if (← arrived.atomically get) == clients then break
    check ((← IO.monoMsNow) < barrier) "lightweight clients did not arrive at the barrier"
    IO.sleep 1
  released.set true
  let results ← tasks.mapM fun task => IO.ofExcept (task.get.mapError IO.Error.toString)
  let mut checkedBindings := 0
  for input in fixtures do
    let deadline := (← IO.monoMsNow)+28000
    let some reference ← Publication.Client.prepareSourceUsing endpoint input.source input.storage deadline |
      throw (IO.userError "all-source binding audit lost its prepared scope")
    let sources := input.bindings.toArray.map Prod.fst
    let found ← Publication.Client.sourceBindings reference sources (Std.HashSet.ofArray input.owners) deadline
    check found.complete "all-source compiled binding audit did not finish"
    for source in sources do
      check (found.rows[source]?.getD #[] == input.bindings[source]?.getD #[])
        "complete source-binding sequence differs from former fact/posting lookup"
    checkedBindings := checkedBindings+sources.size
  let state ← stats endpoint
  let pool := state.getObjValD "preparedSources"
  let expectedLoads := min clients fixtures.size
  check ((pool.getObjValAs? Nat "loads").toOption == some expectedLoads)
    "the same source was prepared more than once"
  check ((pool.getObjValAs? Bool "accountedExact").toOption == some true)
    "prepared source charge accounting differs from its resident entries"
  check ((state.getObjValAs? Nat "projects").toOption == some 0)
    "read-only preparation acquired source publication authority"
  let times := results.map (·.1)
  return Json.mkObj [("databases",toJson fixtures.size),("clients",toJson clients),
    ("allOriginalRowsEqual",toJson true),("allPublishedLayoutsEqual",toJson true),
    ("allSourceBindingSequencesEqual",toJson true),("sourceBindingsChecked",toJson checkedBindings),
    ("preparedLoads",toJson expectedLoads),
    ("clientAndServiceExecutablesDiffer",toJson true),("oneServiceOwnerPreserved",toJson true),
    ("preparedLoadedReplies",toJson (results.filter (fun r => r.2.1 == .loaded)).size),
    ("preparedJoinedReplies",toJson (results.filter (fun r => r.2.1 == .joined)).size),
    ("preparedHitReplies",toJson (results.filter (fun r => r.2.1 == .hit)).size),
    ("p50Ms",toJson (percentile times 50)),("p95Ms",toJson (percentile times 95)),
    ("sampleP99Ms",toJson (percentile times 99)),("maxMs",toJson (percentile times 100)),
    ("service",state),("actualHookMeasured",toJson false),("nasMeasured",toJson false),
    ("answeringModelCalls",toJson (0 : Nat))]

private def rejected (action : IO α) : IO Bool := do
  try let _ ← action; pure false catch _ => pure true

private def boundaries (endpoint : Daemon.Endpoint) (left right : Fixture) : IO Json := do
  let some a ← Publication.Client.prepareSourceUsing endpoint left.source left.storage ((← IO.monoMsNow)+10000) |
    throw (IO.userError "left scope unavailable")
  let some b ← Publication.Client.prepareSourceUsing endpoint right.source right.storage ((← IO.monoMsNow)+10000) |
    throw (IO.userError "right scope unavailable")
  let forged := {b with endpoint := {b.endpoint with secret := a.access.capability}}
  check (← rejected (Publication.Client.sourceRows forged right.owners ((← IO.monoMsNow)+2000)))
    "one project's capability read another project"
  check (← rejected (Daemon.exchange a.endpoint "register" (Json.mkObj [
    ("directory",toJson left.source.directory.toString),("database",toJson left.source.head.identity)]) (budget := 2000)))
    "read scope acquired write registration"
  check (← rejected (Daemon.exchange a.endpoint "shutdown" (budget := 2000)))
    "read scope stopped the service"
  let some refreshed ← a.refresh left.source.head ((← IO.monoMsNow)+5000) |
    throw (IO.userError "read-only capability could not refresh its own source")
  check (refreshed.identity == a.identity && refreshed.access.reuse == .hit)
    "unchanged read-only refresh rebuilt or changed its source"
  return Json.mkObj [("crossProjectRejected",toJson true),("writeRegistrationRejected",toJson true),
    ("serviceControlRejected",toJson true),("readOnlyRefreshExact",toJson true)]

private def poolChecks (source : DB.PageMap.Snapshot) (ready : Cache.Ready) : IO Json := do
  let path ← Cache.directory source .user
  let some recipes ← Cache.preparedAt? source path ready.metadata |
    throw (IO.userError "published recipes are unavailable")
  let loaded : Shared.Loaded := ⟨ready.metadata,recipes,none⟩
  let pool ← Shared.Pool.new
  let .start a ← pool.admit "a" (Shared.capacity/2) | throw (IO.userError "first pool admission failed")
  pool.finish "a" a 1 (.ok loaded)
  pool.release "a" a.serial
  let .start b ← pool.admit "b" (Shared.capacity/2) | throw (IO.userError "second pool admission failed")
  pool.finish "b" b 1 (.ok loaded)
  pool.release "b" b.serial
  let .start c ← pool.admit "c" (Shared.capacity/2) | throw (IO.userError "LRU did not reclaim an idle entry")
  pool.finish "c" c 1 (.ok loaded)
  pool.release "c" c.serial
  check ((← pool.state.atomically get).entries["a"]?).isNone "LRU retained its oldest idle entry"
  let .borrowed pin ← pool.admit "b" (Shared.capacity/2) | throw (IO.userError "pool did not pin a resident reader")
  let blockedAdmission ← pool.admit "large" Shared.capacity
  check (match blockedAdmission with | .busy => true | _ => false) "pool evicted a borrowed entry"
  pool.release "b" pin.serial
  let retry ← Shared.Pool.new
  let .start old ← retry.admit "same" 1 | throw (IO.userError "failure fixture admission failed")
  retry.finish "same" old 0 (.error "expected fixture failure")
  let .start newer ← retry.admit "same" 1 | throw (IO.userError "failed load was not retryable")
  retry.release "same" old.serial
  check (((← retry.state.atomically get).entries["same"]?).any (·.borrowers == 1))
    "old release corrupted a new admission"
  retry.close
  let ran ← IO.mkRef false
  retry.launch "same" newer 0 do ran.set true; return loaded
  check (!(← ran.get) && (← rejected (retry.admit "after-close" 1)))
    "closed pool restarted preparation"
  check (((← retry.stats).getObjValAs? Bool "accountedExact").toOption.getD false)
    "closed pool retains inconsistent byte charges"
  pool.close
  -- A caller owns a borrow, not the shared load. Its deadline releases that
  -- borrow while another caller can still receive the same preparation.
  let waiting ← Shared.Pool.new
  let waitingPath : System.FilePath := "/unused-hot-entry-fixture"
  let identity := Shared.key waitingPath ready.metadata
  let .start entry ← waiting.admit identity 1 | throw (IO.userError "shared wait admission failed")
  let started ← IO.monoMsNow
  let late ← IO.asTask (waiting.withReady source waitingPath ready.metadata (started+3000)
    fun _ _ => pure true) .dedicated
  let early ← IO.asTask (rejected (waiting.withReady source waitingPath ready.metadata (started+25)
    fun _ _ => pure true)) .dedicated
  let earlyExpired ← IO.ofExcept (early.get.mapError IO.Error.toString)
  check earlyExpired "a caller consumed a preparation after its deadline"
  check ((← waiting.state.atomically get).entries[identity]?).isSome
    "expired caller erased another reader's preparation"
  waiting.launch identity entry 1 (pure loaded)
  waiting.release identity entry.serial
  check (← IO.ofExcept (late.get.mapError IO.Error.toString)) "shared reader lost its preparation"
  let state ← waiting.state.atomically get
  check (state.loads == 1 && state.entries[identity]?.any (·.borrowers == 0))
    "shared wait leaked a borrow or repeated preparation"
  waiting.close
  return Json.mkObj [("idleLruReclaimed",toJson true),("borrowedEntryKept",toJson true),
    ("failedLoadRetryable",toJson true),("oldReleaseCannotUnpinNewEntry",toJson true),
    ("closeCannotSpawn",toJson true),("expiredCallerKeepsSharedPreparation",toJson true),
    ("logicalChargesAreNotPhysicalAllocation",toJson true)]

private def unchangedRows (reference : Publication.Client.SourceReference) (fixture : Fixture) : IO Unit := do
  let actual ← normalized (← Publication.Client.sourceRows reference fixture.owners ((← IO.monoMsNow)+10000)).rows
  let expected := fixture.owners.map fun owner => (owner,fixture.expected[owner]?.getD #[])
  check (actual == expected) "publication changed the original rows of an already pinned reader"

private def lifecycle (endpoint : Daemon.Endpoint) (fixture : Fixture) : IO Json := do
  let path := fixture.source.directory
  -- Private derived state is prepared before making the actual source tree
  -- non-writable. The service must only pin/read it and take no writer lease.
  let privateInput ← fixtureFrom fixture.source .user
  let headBefore ← IO.FS.readBinFile (path / "head")
  let pagesPath := path / (fixture.source.head.identity ++ ".pages")
  let pagesBefore := Sha256.hex (← IO.FS.readBinFile pagesPath)
  let mode ← IO.Process.output {cmd := "/bin/chmod",args := #["-R","a-w",path.toString]}
  check (mode.exitCode == 0) "cannot make fixture source read-only"
  let old ← try
    check (← rejected (IO.FS.writeFile (path / "must-not-write") "rejected"))
      "read-only filesystem fixture remained writable"
    let some reference ← Publication.Client.prepareSourceUsing endpoint fixture.source .user ((← IO.monoMsNow)+10000) |
      throw (IO.userError "read-only source preparation unavailable")
    unchangedRows reference privateInput
    pure reference
    finally
      let restored ← IO.Process.output {cmd := "/bin/chmod",args := #["-R","u+w",path.toString]}
      check (restored.exitCode == 0) "cannot restore fixture source permissions"
  check ((← IO.FS.readBinFile (path / "head")) == headBefore &&
    Sha256.hex (← IO.FS.readBinFile pagesPath) == pagesBefore) "read-only preparation mutated source files"
  let workspace := path.parent.getD ""
  let added ← observation workspace "after-publication" 513 1024
  let next ← publish fixture.source added
  check (next.head != fixture.source.head) "snapshot lifecycle fixture did not publish"
  let newInput ← fixtureFrom next .user
  let some fresh ← old.refresh next.head ((← IO.monoMsNow)+10000) |
    throw (IO.userError "updated source unavailable to scoped reader")
  check (fresh.identity != old.identity && fresh.access.capability == old.access.capability)
    "publication changed read authority or reused old snapshot identity"
  unchangedRows fresh newInput
  unchangedRows old privateInput
  let before ← stats endpoint
  let some again ← fresh.refresh next.head ((← IO.monoMsNow)+10000) |
    throw (IO.userError "prepared snapshot refresh unavailable")
  unchangedRows again newInput
  let after ← stats endpoint
  check ((before.getObjValD "preparedSources").getObjValD "loads" ==
    (after.getObjValD "preparedSources").getObjValD "loads") "unchanged snapshot was prepared again"
  let endpointPath := (← Publication.directory) / "endpoint.json"
  let endpointBytes ← IO.FS.readFile endpointPath
  try
    IO.FS.writeFile endpointPath (toJson {endpoint with generation := "different-implementation"}).compress
    check (← rejected Publication.Client.resolve) "client replaced an incompatible live owner"
    check (← Numerical.alive endpoint.pid) "incompatible caller killed shared readers' service"
  finally IO.FS.writeFile endpointPath endpointBytes
  let _ ← Daemon.exchange endpoint "ping" (budget := 1000)
  return Json.mkObj [("filesystemReadOnlyExact",toJson true),("sourceFilesUnchanged",toJson true),
    ("publicationGetsNewPreparation",toJson true),("oldReaderRemainsExact",toJson true),
    ("unchangedRefreshDoesNotReload",toJson true),("incompatibleClientCannotReplaceLiveOwner",toJson true)]

def main (args : List String) : IO UInt32 := do
  try
    let [binary,output] := args | throw (IO.userError "SharedPreparedServiceAudit PRODUCT NEW-DIRECTORY")
    let root := System.FilePath.mk output
    check (root.isAbsolute && !(← root.pathExists)) "keep earlier service audit"
    IO.FS.createDir root
    let actualPath := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/r0/stage1/history/source.egg"
    let actual ← DB.PageMap.pin actualPath
    let before := actual.head
    let guard ← FileSystem.openRead (actualPath / "writer").toString
    check (← FileSystem.tryReadLock guard true) "cannot hold original source writer during read-only preparation"
    let input ← try fixtureFrom actual .user finally FileSystem.unlockRead guard
    check ((← DB.PageMap.pin actualPath).head == before) "private preparation wrote the original DB"
    let pool ← poolChecks input.source input.ready
    emit (root / "pool.json") pool
    let mut reports := #[]
    for clients in [80] do
      let (child,endpoint) ← startService binary
      let reaped ← IO.mkRef false
      try
        let report ← concurrent endpoint #[input] clients
        let shutdown ← stopService child endpoint reaped
        let stderr ← child.stderr.readToEnd
        IO.FS.writeFile (root / s!"actual-{clients}.stderr") stderr
        let report := report.setObjVal! "shutdown" shutdown |>.setObjVal! "actualSeedSource" (toJson true)
        reports := reports.push report
        emit (root / s!"actual-{clients}.json") report
      finally retireService child reaped
    let fixtureRoot := root / "fixtures"
    IO.FS.createDir fixtureRoot
    let fixtures ← (Array.range 16).mapM (makeFixture fixtureRoot)
    let some first := fixtures[0]? | throw (IO.userError "missing first project")
    let some second := fixtures[1]? | throw (IO.userError "missing second project")
    for databases in [16] do
      for clients in [80] do
        let (child,endpoint) ← startService binary
        let reaped ← IO.mkRef false
        try
          let report ← concurrent endpoint (fixtures.extract 0 databases) clients
          let repeated ← concurrent endpoint (fixtures.extract 0 databases) clients
          check (((repeated.getObjValD "service").getObjValD "preparedSources").getObjValD "evictions" == toJson (0 : Nat))
            "multiple DBs evicted each other despite a warm bounded service"
          let limits ← boundaries endpoint first second
          let shutdown ← stopService child endpoint reaped
          IO.FS.writeFile (root / s!"synthetic-{databases}-{clients}.stderr") (← child.stderr.readToEnd)
          let report := report.setObjVal! "boundaries" limits |>.setObjVal! "shutdown" shutdown
            |>.setObjVal! "repeated" repeated
          reports := reports.push report
          emit (root / s!"synthetic-{databases}-{clients}.json") report
        finally retireService child reaped
    let (child,endpoint) ← startService binary
    let reaped ← IO.mkRef false
    try
      let limits ← lifecycle endpoint first
      let state ← stats endpoint
      let shutdown ← stopService child endpoint reaped
      emit (root / "lifecycle.json") (limits.setObjVal! "service" state |>.setObjVal! "shutdown" shutdown)
      IO.FS.writeFile (root / "lifecycle.stderr") (← child.stderr.readToEnd)
    finally retireService child reaped
    check ((← DB.PageMap.pin actualPath).head == before) "service readers changed the actual source"
    emit (root / "results.json") (Json.mkObj [("source",toJson before),("reports",toJson reports),
      ("answeringModelCalls",toJson (0 : Nat)),("actualHookMeasured",toJson false),
      ("nasMeasured",toJson false),("productionAdoption",toJson false)])
    return 0
  catch error => IO.eprintln error.toString; return 1
