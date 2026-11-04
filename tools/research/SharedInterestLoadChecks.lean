import Main
import tools.research.ConcurrentHookChecks
import tools.research.SourcePreparationChecks
import tools.research.ImmutablePublicationChecks

open Lean Eggshell Eggshell.Plugin
namespace Eggshell.Research.SharedInterestLoadChecks

def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

def natural (value : Json) (field : String) : Nat :=
  (value.getObjValAs? Nat field).toOption.getD 0

def stats : IO Json := do IO.ofExcept (Json.parse (← Publication.Client.control "stats"))

def append (project : ProjectStore.Project) (slot : Nat) (view : ProjectStore.View)
    (marker : String) : IO DB.PageMap.Snapshot :=
  ProjectStore.withOwner project slot fun owner => do
    let capsule : Publication.Capsule := {
      session := s!"cold-traffic-{slot}"
      turn := marker
      cwd := project.directory.toString
      work := "inspect "++marker
      checkpoint := false
      tools := #[{
        name := "mcp__fixture__inspect"
        useId := marker
        input := "{}"
        response := (Json.mkObj [("evidence",toJson marker)]).compress}]
      finalMessage := some ("Recorded `"++marker++"`.")
      timing := #[.unavailable]}
    let request ← IO.ofExcept (capsule.prepare project.directory owner.source.identity)
    let receipts ← owner.publish view #[{request with target := project.sourceDirectory slot}]
    check (receipts.size == 1) "cold fixture lost an original ACK"
    project.current slot

def coldFixtureCreated (root : System.FilePath) : IO Unit := do
  let project ← ProjectStore.create (root/"work.project") 16
  let some command ← MiniLM.command (← Paths.installRoot) | throw (IO.userError "actual MiniLM required")
  let empty ← ProjectStore.pin project ((← IO.monoMsNow)+20000)
  let a0 ← append project 0 empty "PREVIOUS_ALPHA"
  let b0 ← append project 1 empty "PREVIOUS_TAIL"
  let _ ← Warm.run a0 command
  let _ ← Warm.run b0 command
  let base ← ProjectStore.pin project ((← IO.monoMsNow)+20000)
  let a1 ← append project 0 base "OLD_ID_ALPHA"
  let b1 ← append project 1 base "OLD_ID_ALPHA_TAIL"
  let pending : PendingTurn := {
    sessionId := "cold-traffic-origin"
    turnId := "captured-old-cut"
    cwd := root.toString
    prompt := "Find OLD_ID_ALPHA and OLD_ID_ALPHA_TAIL original evidence"
    profile := "work"
    read := [project.directory.toString]
    write := some project.directory.toString
    semanticMatcher := some command
    handoffChars := 120000
    projection := .automatic}
  let captured ← ProjectContext.capture pending ((← IO.monoMsNow)+20000)
  check (captured.preparedInputs.isNone && captured.inputBoundary.isSome)
    "cold fixture already had a ready captured input frame"
  let some images := captured.projectInputs | throw (IO.userError "cold fixture omitted its project")
  let some image := images[0]? | throw (IO.userError "cold fixture omitted its source inventory")
  let view ← ProjectStore.openView project image.cut
  check (view.sources.size == 16 && view.sources[0]?.any (·.head == a1.head) &&
    view.sources[1]?.any (·.head == b1.head)) "cold fixture changed the exact original cut"
  let a2 ← append project 0 view "NEW_ID_BETA_A"
  let b2 ← append project 1 view "NEW_ID_BETA_B"
  let _ ← Warm.run a2 command
  let _ ← Warm.run b2 command
  let target ← registerIndexTarget a1 command true
  let descriptor ← PreparationRegistry.request "index" target.key (some a1.head)
  check (PreparationRegistry.matchesSourceRequest descriptor target.key a1.head &&
    !PreparationRegistry.matchesSourceRequest descriptor target.key b1.head &&
    !PreparationRegistry.matchesSourceRequest descriptor target.key {a1.head with revision := a1.head.revision+1} &&
    !PreparationRegistry.matchesSourceRequest descriptor (String.ofList (List.replicate 64 '0')) a1.head)
    "descriptor reuse did not check the complete source and registry identity"
  check ((← PreparedInputs.load? a1 MiniLM.model SearchProvider.encoderContract).isNone &&
    (← PreparedInputs.load? b1 MiniLM.model SearchProvider.encoderContract).isNone)
    "later warm unexpectedly prepared the skipped original cut"
  let files ← sessionFiles captured.sessionId
  writeJson files.state ({profile := "work"} : ThreadState)
  writeJson files.pending captured
  IO.FS.writeFile (root/"captured-turn.json") ((toJson captured).pretty++"\n")
  IO.FS.writeFile (root/"cold-fixture.json") ((Json.mkObj [
    ("originalOwners",toJson view.sources.size),("capturedA",toJson a1.head),("capturedB",toJson b1.head),
    ("laterA",toJson a2.head),("laterB",toJson b2.head),("skippedHeadsUnprepared",toJson true),
    ("requiredBeforeDelivery",toJson #["\"OLD_ID_ALPHA\"","\"OLD_ID_ALPHA_TAIL\""])]).pretty++"\n")

def coldFixture (root : System.FilePath) : IO Unit := do
  check (root.isAbsolute && !(← root.pathExists)) "fresh cold fixture required"
  FileSystem.privateDirectory root
  let _ ← Numerical.withDefaultKeeper (do coldFixtureCreated root; return 0) (drainMs := 1000)
  pure ()

def waitPrepared (root : System.FilePath) : IO Json := do
  let started ← IO.monoMsNow
  let mut samples := #[]
  let mut previous := ""
  repeat
    let state := (← stats).getObjValD "preparation"
    let stamp := (toJson (natural state "pending",natural state "active",
      natural state "finishedAttempts",natural state "retries")).compress
    if stamp != previous then
      samples := samples.push (Json.mkObj [("elapsedMs",toJson ((← IO.monoMsNow)-started)),("state",state)])
      previous := stamp
    let elapsed := (← IO.monoMsNow)-started
    let complete := natural state "pending" == 0 && natural state "active" == 0
    if complete || elapsed ≥ 120000 then
      let result := Json.mkObj [("complete",toJson complete),("elapsedMs",toJson elapsed),
        ("samples",toJson samples),("foregroundDeadlineChanged",toJson false)]
      IO.FS.writeFile (root/"drain-observation.json") (result.pretty++"\n")
      check complete "background preparation did not drain within its observation window"
      check (natural state "waiters" == 0 && natural state "claimReferences" == 0 &&
        natural state "residentBytes" == 0) "foreground preparation leaked grants or metadata"
      return result
    IO.sleep 100
  throw (IO.userError "unreachable preparation wait")

partial def hasAtom (value : Value) (bytes : ByteArray) : Bool :=
  match value with
  | .atom actual => actual == bytes
  | .apply _ children => children.toList.any (fun (_,child) => hasAtom child bytes)

def freshQuery (root : System.FilePath) (original : PendingTurn) (name : String)
    (command : List String) : IO Json := do
  let started ← IO.monoMsNow
  let draft := {original with
    sessionId := name
    turnId := "after-publication"
    projectInputs := none
    inputBoundary := none
    preparedInputs := none
    prompt := "Find the stored CONCURRENT_ORIGINAL_79 original observation."
    semanticMatcher := some command
    tools := [],inFlight := [],finalMessage := none,closed := false}
  let pending ← ProjectContext.capture draft (started+20000)
  let files ← sessionFiles name
  writeJson files.state ({profile := pending.profile} : ThreadState)
  writeJson files.pending pending
  let input := Json.mkObj [("_eggshell_deadline",toJson (started+28000)),
    ("_eggshell_receipt",toJson (← Receipt.fresh))]
  let handoff ← deliverForWork input pending pending.prompt false
  let body := handoff.map (·.text) |>.getD ""
  IO.FS.writeFile (root/(name++"-body.txt")) body
  let delivered := handoff.any fun value => value.reason != "search-incomplete" &&
    value.text.contains "\"CONCURRENT_ORIGINAL_79\""
  return Json.mkObj [("delivered",toJson delivered),("elapsedMs",toJson ((← IO.monoMsNow)-started)),
    ("trace",toJson (handoff.bind (·.search))),("bodySha256",toJson (Sha256.hex body.toUTF8))]

def inspect (root : System.FilePath) (original : PendingTurn) : IO Json := do
  let some context ← ProjectContext.open? original ((← IO.monoMsNow)+20000) |
    throw (IO.userError "mixed load lost its complete project scope")
  let some write := context.selection.write | throw (IO.userError "no selected write project")
  let before ← ProjectStore.pin write.project ((← IO.monoMsNow)+20000)
  let drained ← waitPrepared root
  let mut values := []
  for source in before.sources do
    values := values++(← Persistence.Store.materialize source).values
  for index in [:80] do
    let expected := (Json.mkObj [("evidence",toJson s!"CONCURRENT_ORIGINAL_{index}")]).compress.toUTF8
    check (values.any (hasAtom · expected)) s!"ACKed original {index} was not restored exactly"
  let some command ← MiniLM.command (← Paths.installRoot) | throw (IO.userError "actual MiniLM required")
  let owners := write.project.manifest.owners.map (·.identity)
  let targets := (← registeredIndexTargets (some owners)).filter (fun (_,target) => target.command == command)
  check (targets.length == owners.size) "numerical targets omitted an original stream"
  let mut inspections := #[]
  for (_,target) in targets do
    let source ← target.owner.pin
    let done ← PreparationRegistry.drained (← PreparationRegistry.request "index" target.key)
    let options ← Warm.options source command target.storage
    let inspected ← Warm.inspect source options
    inspections := inspections.push (Json.mkObj [("source",toJson source.head),("drained",toJson done),
      ("coverage",toJson inspected.coverage),("needed",toJson inspected.needed.length)])
    IO.FS.writeFile (root/"coverage-audit.json") ((toJson inspections).pretty++"\n")
    check (done && inspected.needed.isEmpty && inspected.coverage.missing == 0 &&
      inspected.coverage.invalid == 0) "idle preparation left missing or invalid numerical windows"
  let after ← ProjectStore.pin write.project ((← IO.monoMsNow)+20000)
  check (before.cut == after.cut) "derived preparation advanced authoritative original heads"
  let newQuery ← freshQuery root original "traffic-new-reader" command
  IO.FS.writeFile (root/"new-query.json") (newQuery.pretty++"\n")
  check (newQuery.getObjValD "delivered" == toJson true) "newly stored original was not delivered"
  let some endpoint ← Publication.Client.endpoint? | throw (IO.userError "no service to restart")
  let _ ← Publication.Client.control "shutdown"
  check (!(← Numerical.alive endpoint.pid)) "shutdown reply preceded actual service exit"
  let restarted ← freshQuery root original "traffic-restarted-reader" command
  IO.FS.writeFile (root/"restart-query.json") (restarted.pretty++"\n")
  check (restarted.getObjValD "delivered" == toJson true) "restart lost newly stored original evidence"
  let result := Json.mkObj [("restoredOriginals",toJson (80 : Nat)),("originalHeadsUnchanged",toJson true),
    ("drain",drained),("inspections",toJson inspections),("newQuery",newQuery),("restartQuery",restarted),
    ("sustainedEightHourCapacity",toJson false),("practical98PercentDelivery",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]
  IO.FS.writeFile (root/"preparation-audit.json") (result.pretty++"\n")
  return result

/-- Inspect the failed fixed cut without warming, journal replay, source writes
or starting the shared service. Keep the original failure evidence intact. -/
def diagnose (root : System.FilePath) : IO Unit := do
  let pending ← IO.ofExcept (Json.parse (← IO.FS.readFile (root/"captured-turn.json")) >>= fromJson? (α := PendingTurn))
  let some context ← ProjectContext.open? pending ((← IO.monoMsNow)+20000) |
    throw (IO.userError "diagnostic lost the captured original cut")
  let targets ← registeredIndexTargets
  let mut rows := #[]
  for source in context.reads.sources do
    let some (_,registered) := targets.find? (fun (_,target) => target.owner.database == source.head.identity) |
      throw (IO.userError "diagnostic source omitted its static target")
    let target := {registered with sourceHead := some source.head}
    let journal ← Synapses.Journal.open? source
    let row := Json.mkObj [("source",toJson source.head.identity),("revision",toJson source.head.revision),
      ("population",toJson (← Persistence.Store.getNat source.get "candidates")),
      ("framePresent",toJson (← PreparedInputs.load? source MiniLM.model SearchProvider.encoderContract).isSome),
      ("canonicalReady",toJson (← Synapses.CanonicalSource.Cache.ready source)),
      ("windowOwnersReady",toJson (← WindowOwners.openShared? source).isSome),
      ("lexicalReady",toJson (← RetrievalResearch.Index.ready source)),
      ("sharedSynapsesReady",toJson (!(← Synapses.Build.required source target.storage))),
      ("warmRequired",toJson (← Warm.required target source)),
      ("privateReplayRequired",toJson (← Synapses.Journal.required source target.storage)),
      ("privateReplayCurrent",toJson (← Synapses.Journal.checkpointCurrent source target.storage)),
      ("privateJournalEvents",toJson (← journal.mapM fun journal => Persistence.Store.getNat journal.get "count"))]
    rows := rows.push row
  IO.FS.writeFile (root/"read-only-diagnosis.json") ((toJson rows).pretty++"\n")
  IO.println (toJson rows).compress

/-- Read the failed load's authoritative originals and private ingress without
starting a service, replaying events or retrying the failed publication. -/
def diagnoseSaves (root : System.FilePath) : IO Unit := do
  let original ← IO.ofExcept (Json.parse (← IO.FS.readFile (root/"captured-turn.json")) >>= fromJson? (α := PendingTurn))
  let some context ← ProjectContext.open? original ((← IO.monoMsNow)+20000) |
    throw (IO.userError "save diagnosis lost its captured original scope")
  let some write := context.selection.write | throw (IO.userError "save diagnosis has no write project")
  let current ← ProjectStore.pin write.project ((← IO.monoMsNow)+20000)
  let mut values := []
  let mut journals := #[]
  let mut events : Array Synapses.Journal.Entry := #[]
  for source in current.sources do
    values := values++(← Persistence.Store.materialize source).values
    if let some journal ← Synapses.Journal.open? source then
      journals := journals.push journal
      let count ← Persistence.Store.getNat journal.get "count"
      for ordinal in [:count] do events := events.push (← Synapses.Journal.entry journal ordinal)
  let mut rows := #[]
  for index in [:80] do
    let session := s!"save-client-{index}"
    let related := events.filter (fun entry => entry.payload.occurrence.session == session)
    let expected := (Json.mkObj [("evidence",toJson s!"CONCURRENT_ORIGINAL_{index}")]).compress.toUTF8
    let files ← sessionFiles session
    rows := rows.push (Json.mkObj [("index",toJson index),("session",toJson session),
      ("start",toJson (related.any (fun entry => entry.payload.kind == "start"))),
      ("finish",toJson (related.any (fun entry => entry.payload.kind == "finish"))),
      ("originalPresent",toJson (values.any (hasAtom · expected))),
      ("deferredPresent",toJson (← (files.directory/"deferred/controlled-save.json").pathExists))])
  for source in current.sources do
    check ((← DB.PageMap.pin source.directory).head == source.head) "read-only diagnosis changed an original"
  for journal in journals do
    check ((← DB.PageMap.pin journal.directory).head == journal.head) "read-only diagnosis changed a journal"
  let result := Json.mkObj [("rows",toJson rows),("sourceHeadsUnchanged",toJson true),
    ("journalHeadsUnchanged",toJson true),("publicationRetried",toJson false)]
  IO.FS.writeFile (root/"save-stage-diagnosis.json") (result.pretty++"\n")
  IO.println result.compress

def clockSample (count : Nat) : IO (Array Nat) := do
  let mut stamps : Array Nat := #[]
  for _ in [:count] do
    let now ← IO.monoNanosNow
    stamps := stamps.push now
  return stamps

def clockProbe (root : System.FilePath) : IO Unit := do
  let tasks ← (List.range 80).toArray.mapM fun _ => IO.asTask (clockSample 4096) .dedicated
  let mut seen : Std.HashSet Nat := {}
  let mut repeated := 0
  for task in tasks do
    for stamp in ← IO.ofExcept (← IO.wait task) do
      if seen.contains stamp then repeated := repeated+1
      seen := seen.insert stamp
  let result := Json.mkObj [("clockReads",toJson (327680 : Nat)),("repeated",toJson repeated),
    ("unique",toJson seen.size),("publicationCalls",toJson (0 : Nat))]
  IO.FS.writeFile (root/"clock-probe.json") (result.pretty++"\n")
  IO.println result.compress

end Eggshell.Research.SharedInterestLoadChecks

def main (args : List String) : IO UInt32 := do
  match args with
  | ["traffic-fixture",root] => projectContextCommand ["context-prepared-numeric",root]
  | ["traffic-cold-fixture",root] =>
    Eggshell.Research.SharedInterestLoadChecks.coldFixture (.mk root)
    return 0
  | ["inspect-context",root] => projectContextCommand ["inspect-context",root]
  | ["traffic-diagnose",root] =>
    Eggshell.Research.SharedInterestLoadChecks.diagnose (.mk root)
    return 0
  | ["traffic-save-diagnose",root] =>
    Eggshell.Research.SharedInterestLoadChecks.diagnoseSaves (.mk root)
    return 0
  | ["traffic-clock-probe",root] =>
    Eggshell.Research.SharedInterestLoadChecks.clockProbe (.mk root)
    return 0
  | ["traffic-allocation",root] =>
    Eggshell.Research.ImmutablePublicationChecks.allocation (.mk root)
    return 0
  | ["traffic-source-only",root] =>
    Numerical.withDefaultKeeper (do
      Eggshell.Research.SourcePreparationChecks.audit (.mk root)
      return 0) (drainMs := 1000)
  | ["traffic-immutable",root] =>
    Eggshell.Research.ImmutablePublicationChecks.audit (.mk root)
    return 0
  | ["traffic-numeric",root] =>
    Numerical.withDefaultKeeper (do
      let path : System.FilePath := .mk root
      Eggshell.Research.ConcurrentHookChecks.exercise path true
        (Eggshell.Research.SharedInterestLoadChecks.inspect path)
      return 0) (drainMs := 1000)
  | other => sourceRouteEngine other
