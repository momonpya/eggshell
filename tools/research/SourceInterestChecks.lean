import Main
import Eggshell.ContractAudit

open Lean Eggshell Eggshell.DB Eggshell.Plugin Eggshell.Persistence.Store
namespace Eggshell.Research.SourceInterestChecks

def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

def append (project : ProjectStore.Project) (slot : Nat) (view : ProjectStore.View)
    (marker : String) : IO PageMap.Snapshot := do
  ProjectStore.withOwner project slot fun owner => do
    let capsule : Publication.Capsule := {
      session := s!"source-interest-{slot}",turn := marker,cwd := project.directory.toString
      work := "inspect "++marker,checkpoint := false
      tools := #[{name := "mcp__fixture__inspect",useId := marker,input := "{}",response := "original "++marker}]
      finalMessage := some ("notebook "++marker),timing := #[.unavailable]}
    let request ← IO.ofExcept (capsule.prepare project.directory owner.source.identity)
    let results ← owner.publish view #[{request with target := project.sourceDirectory slot}]
    check (results.size == 1) "original publication lost its ACK"
    project.current slot

def rejects (action : IO α) : IO Bool := do
  try let _ ← action; return false
  catch _ => return true

def idle (deadline : Nat) : IO Json := do
  repeat
    let all ← IO.ofExcept (Json.parse (← Publication.Client.control "stats"))
    let value ← IO.ofExcept (all.getObjVal? "preparation")
    if (value.getObjValAs? Nat "pending").toOption == some 0 &&
        (value.getObjValAs? Nat "active").toOption == some 0 then return value
    check ((← IO.monoMsNow) < deadline) s!"source interests did not drain: {value.compress}"
    IO.sleep 20
  throw (IO.userError "unreachable preparation wait")

def absence (root : System.FilePath) : IO Unit := do
  let raw := root/"later-created.egg"
  let pending : PendingTurn := {
    sessionId := "raw-absence",turnId := "query",cwd := root.toString,prompt := "missing source"
    profile := "work",read := [raw.toString],write := none,semanticMatcher := none
    handoffChars := 120000,projection := .automatic}
  let frozen ← ProjectContext.capture pending ((← IO.monoMsNow)+20000)
  let some encoded := frozen.inputBoundary | throw (IO.userError "absent source lost its boundary")
  let boundary ← IO.ofExcept (fromJson? (α := InputBoundary.Boundary) encoded.payload)
  check (boundary.originals == [none] && boundary.usage.isEmpty) "absence was filtered out of the input inventory"
  let _ ← PageMap.create raw "created-after-capture"
  check (← rejects (retainedSelection (pendingSelection frozen) (some [none])))
    "an unbound omitted source was accepted as captured absence"
  let request ← Worker.capturePrepared {
    pending := frozen,state := {profile := "work"},work := pending.prompt,enforce := false,deadline := (← IO.monoMsNow)+20000}
  check (request.originals == some [none] && request.prepared.any (·.isEmpty))
    "worker substituted a later raw source for captured absence"

def restore (root : System.FilePath) : IO Unit := do
  let pending ← IO.ofExcept (Json.parse (← IO.FS.readFile (root/"pending.json")) >>= fromJson? (α := PendingTurn))
  let deadline := (← IO.monoMsNow)+28000
  let request ← Worker.capturePrepared {
    pending,state := {profile := "work"},work := pending.prompt,enforce := false,deadline}
  let context ← ProjectContext.open? pending deadline
  let selection := context.map (·.physicalSelection) |>.getD (pendingSelection pending)
  let some snapshots ← Worker.originalSnapshots request selection (context.map (·.snapshots)) |
    throw (IO.userError "restored query omitted its original cut")
  let sourceContext : SourceContext := {
    workspace := root,deadline,question := pending.prompt,handoffChars := selection.handoffChars}
  let some body ← automaticHandoff selection pending.prompt [] false (sourceContext := some sourceContext)
      (publishMemo := false) (captured := some snapshots) (queryInputs := request.prepared)
      (queryOwners := request.owners) (capturedHeads := request.originals) |
    throw (IO.userError "restored query returned no body")
  check (body.text == (← IO.FS.readFile (root/"body.txt"))) "fresh process changed captured-cut delivery"
  IO.println "source/private boundaries and actual delivery restored unchanged"

def audit (root : System.FilePath) (writable : Bool) : IO Unit := do
  check (root.isAbsolute && !(← root.pathExists)) "fresh controlled fixture required"
  FileSystem.privateDirectory root
  absence root
  let project ← ProjectStore.create (root/"project") 2
  let initial ← ProjectStore.pin project ((← IO.monoMsNow)+20000)
  let a0 ← append project 0 initial "A0"
  let b0 ← append project 1 initial "B0"
  let command := [(← IO.appPath).toString,"search-provider","--mode","lexical"]
  let _ ← Warm.run a0 command
  let _ ← Warm.run b0 command
  let base ← ProjectStore.pin project ((← IO.monoMsNow)+20000)
  let a1 ← append project 0 base "A1"
  let b1 ← append project 1 base "B1"
  let privateBefore ← Synapses.UsageCache.ensure a1
  -- Model another reader with shared preparation but no private B history.
  -- Initial warm may already have created a usage classifier for B0.
  let absentUsage ← Synapses.UsageCache.directory b1
  check (absentUsage.toString.startsWith (root.toString++"/private/")) "fixture usage cleanup escaped its private root"
  if ← absentUsage.pathExists then IO.FS.removeDirAll absentUsage
  check ((← Synapses.UsageCache.open? b1).isNone) "fixture did not establish absent private usage"
  let pending : PendingTurn := {
    sessionId := "source-interest",turnId := "query",cwd := root.toString,prompt := "A1 B1"
    profile := "work",read := [project.directory.toString]
    write := if writable then some project.directory.toString else none
    semanticMatcher := none,handoffChars := 120000,projection := .automatic}
  let captured ← ProjectContext.capture pending ((← IO.monoMsNow)+20000)
  let some encoded := captured.inputBoundary | throw (IO.userError "unprepared request lost its boundary")
  let boundary ← IO.ofExcept (fromJson? (α := InputBoundary.Boundary) encoded.payload)
  check (boundary.originals == [some a1.head,some b1.head]) "readiness changed captured original heads"
  check (boundary.usage == #[some privateBefore.index.head,none]) "readiness changed the captured private boundary"
  check captured.preparedInputs.isNone "fixture did not establish unprepared original heads"
  let some images := captured.projectInputs | throw (IO.userError "project cut missing")
  let some image := images[0]? | throw (IO.userError "configured project missing")
  let atCut ← ProjectStore.openView project image.cut
  let complete ← Federated.prepare atCut.sources
  let mut originalBodies := #[]
  for (_,node) in complete.owners.toList do
    let reader ← NodeReader.new node.snapshot
    let value ← reader.outcome (← locateOutcome node.snapshot node.id)
    originalBodies := originalBodies.push (readable value.outcome)
  let required := ["original A1","original B1"]
  check (required.all originalBodies.contains) "required originals absent before observing preparation"
  let a2 ← append project 0 atCut "A2"
  let b2 ← append project 1 atCut "B2"
  let _ ← Warm.run a2 command
  let _ ← Warm.run b2 command
  let laterUsage ← Synapses.UsageCache.publish a1 {
    session := "private-after-boundary",turn := "later",source := a1.head
    view := Synapses.Index.contentKey ("after-boundary",a1.head),count := 0} #[]
  let _ ← Synapses.UsageCache.ensure b1
  check (laterUsage != privateBefore.index.head) "private usage did not actually advance"
  let target ← registerIndexTarget a1 command writable
  let interest ← PreparationRegistry.request "index" target.key (some a1.head)
  let latest ← PreparationRegistry.request "index" target.key
  let selected ← PreparationRegistry.indexTarget interest
  check (interest.key != latest.key && (← selected.pin).head == a1.head &&
    ((← PreparationRegistry.indexTarget latest).sourceHead.isNone))
    "exact interest coalesced into the latest-head job"
  check (← rejects (PreparationRegistry.request "index" target.key (some b1.head)))
    "foreign original was accepted for a registered source"
  check (← rejects (PreparationRegistry.request "index" target.key (some {a1.head with bytes := a2.head.bytes+1})))
    "unpublished source extent was accepted"
  let fabricated := {a1.head with bytes := a2.head.bytes,root := a2.head.root}
  check ((← PageMap.HistoryReader.make? a2 fabricated).isSome &&
    (← rejects (PreparationRegistry.request "index" target.key (some fabricated))))
    "extent-only retention was mistaken for an actual source publication"
  let (once,_) := PreparationPlan.notify PreparationPlan.initial interest
  let (twice,accepted) := PreparationPlan.notify once interest
  check (accepted && twice.contents.pending.size == 1 && twice.contents.coalesced == 1)
    "identical source interests did not coalesce"
  let before ← (List.finRange project.manifest.owners.size).mapM fun slot => do return (← project.current slot.val).head
  let files ← sessionFiles captured.sessionId
  writeJson files.state ({profile := "work"} : ThreadState)
  writeJson files.pending captured
  let started ← IO.monoMsNow
  let input := Json.mkObj [("_eggshell_deadline",toJson (started+28000)),
    ("_eggshell_receipt",toJson (← Receipt.fresh))]
  let some body ← deliverForWork input captured pending.prompt false |
    throw (IO.userError "ordinary hook returned no historical-cut result")
  let elapsed := (← IO.monoMsNow)-started
  let delivered := required.countP (fun marker => body.text.contains marker)
  check (body.reason != "search-incomplete" && delivered == required.length &&
    !body.text.contains "original A2" && !body.text.contains "original B2")
    "automatic source interests did not deliver the captured originals"
  let drained ← idle ((← IO.monoMsNow)+10000)
  let restored ← Worker.capturePrepared {
    pending := captured,state := {profile := "work"},work := pending.prompt,enforce := false,deadline := (← IO.monoMsNow)+20000}
  let some prepared := restored.prepared | throw (IO.userError "worker did not retain completed inputs")
  check (restored.originals == some boundary.originals && prepared.map (·.usage) == boundary.usage)
    "preparation changed original heads or requester-private usage"
  check ((← PreparedInputs.load? a2 MiniLM.model SearchProvider.encoderContract).isSome &&
    (← PreparedInputs.load? b2 MiniLM.model SearchProvider.encoderContract).isSome)
    "automatic historical preparation displaced a later input"
  let expected := if writable then Sidecar.Storage.database else .user
  check (prepared.all fun reference => reference.lexical.any (·.storage == expected))
    "read-only preparation wrote the shared DB or writable preparation changed scope"
  let operation : OperationWire.Request := {
    id := ← Receipt.fresh,session := restored.pending.sessionId,role := .search,payload := toJson restored
    cutoff := restored.deadline,identity := some restored.identity,finishReady := false}
  OperationPool.validate operation
  let changed := prepared.map fun reference => {reference with usage := none}
  let substituted := {restored with
    pending := {restored.pending with preparedInputs := none}
    prepared := some changed}
  check (← rejects (OperationPool.validate {operation with payload := toJson substituted}))
    "queue accepted a changed private boundary without a ready frame"
  check (← rejects (Worker.capturePrepared {restored with pending := {restored.pending with inputBoundary := none}}))
    "worker guessed latest after losing the original boundary"
  let after ← (List.finRange project.manifest.owners.size).mapM fun slot => do return (← project.current slot.val).head
  IO.FS.writeFile (root/"body.txt") body.text
  IO.FS.writeFile (root/"pending.json") ((toJson restored.pending).pretty++"\n")
  let report := Json.mkObj [("writable",toJson writable),("capturedSources",toJson boundary.originals),
    ("requiredBeforeReadiness",toJson required),("delivered",toJson delivered),("elapsedMs",toJson elapsed),
    ("bodySha256",toJson (Sha256.hex body.text.toUTF8)),("preparation",drained),
    ("privateUsageAdvancedButFrozen",toJson true),("rawAbsenceRetained",toJson true),
    ("foreignAndFutureRejected",toJson true),("queueRejectsPrivateSubstitution",toJson true),
    ("laterInputsRetained",toJson true),("originalHeadsBefore",toJson before),("originalHeadsAfter",toJson after),
    ("automaticPreparationDemand",toJson true),("actualMiniLM",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]
  IO.FS.writeFile (root/"report.json") (report.pretty++"\n")
  IO.println (Json.mkObj [("delivered",toJson delivered),("elapsedMs",toJson elapsed),
    ("writable",toJson writable),("preparation",drained)]).compress

end Eggshell.Research.SourceInterestChecks

def main (args : List String) : IO UInt32 := do
  match args with
  | ["source-interest-audit",root,mode] =>
    try
      Eggshell.Research.SourceInterestChecks.audit (.mk root) (mode == "write")
      pure 0
    finally
      let _ ← Eggshell.Plugin.Publication.Client.control "shutdown"
  | ["source-interest-restore",root] =>
    try
      Eggshell.Research.SourceInterestChecks.restore (.mk root)
      pure 0
    finally
      let _ ← Eggshell.Plugin.Publication.Client.control "shutdown"
  | other => sourceRouteEngine other
