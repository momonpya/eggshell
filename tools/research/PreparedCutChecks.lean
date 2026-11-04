import Main
import Eggshell.ContractAudit

open Lean Eggshell Eggshell.DB Eggshell.Plugin Eggshell.Persistence.Store
namespace Eggshell.Research.PreparedCutChecks

def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

def append (project : ProjectStore.Project) (slot : Nat) (view : ProjectStore.View)
    (marker : String) : IO PageMap.Snapshot := do
  ProjectStore.withOwner project slot fun owner => do
    let capsule : Publication.Capsule := {
      session := s!"prepared-cut-{slot}",turn := marker,cwd := project.directory.toString
      work := "inspect "++marker,checkpoint := false
      tools := #[{name := "mcp__fixture__inspect",useId := marker,input := "{}",response := "original "++marker}]
      finalMessage := some ("notebook "++marker),timing := #[.unavailable]}
    let request ← IO.ofExcept (capsule.prepare project.directory owner.source.identity)
    let results ← owner.publish view #[{request with target := project.sourceDirectory slot}]
    check (results.size == 1) "original publication did not acknowledge its turn"
    project.current slot

def deliver (pending : PendingTurn) : IO (Option Handoff) := do
  let deadline := (← IO.monoMsNow)+28000
  let request ← Worker.capturePrepared {
    pending,state := {profile := "work"},work := pending.prompt,enforce := false,deadline}
  let context ← ProjectContext.open? pending deadline
  let selection := context.map (·.physicalSelection) |>.getD (pendingSelection pending)
  let some sources ← Worker.originalSnapshots request selection (context.map (·.snapshots)) |
    throw (IO.userError "worker lost its exact original cut")
  let sourceContext : SourceContext := {
    workspace := .mk pending.cwd,deadline,question := pending.prompt,handoffChars := selection.handoffChars}
  automaticHandoff selection pending.prompt [] false (sourceContext := some sourceContext)
    (publishMemo := false) (captured := some sources) (queryInputs := request.prepared) (queryOwners := request.owners)

def restore (root : System.FilePath) : IO Unit := do
  let pending ← IO.ofExcept (Json.parse (← IO.FS.readFile (root/"pending.json")) >>= fromJson? (α := PendingTurn))
  let expected ← IO.FS.readFile (root/"body.txt")
  let some result ← deliver pending | throw (IO.userError "restored cut returned no body")
  check (result.text == expected) "fresh process changed the captured-cut body"
  IO.println "historical prepared cut restored with identical actual delivery"

def audit (root : System.FilePath) : IO Unit := do
  check (root.isAbsolute && !(← root.pathExists)) "fresh controlled fixture required"
  FileSystem.privateDirectory root
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
  let pending : PendingTurn := {
    sessionId := "prepared-cut",turnId := "query",cwd := root.toString,prompt := "A1 B1"
    profile := "work",read := [project.directory.toString],write := none,semanticMatcher := none
    handoffChars := 120000,projection := .automatic}
  let captured ← ProjectContext.capture pending ((← IO.monoMsNow)+20000)
  let some images := captured.projectInputs | throw (IO.userError "turn lost its original project cut")
  let some image := images[0]? | throw (IO.userError "turn omitted its project")
  check (image.cut.heads == #[a1.head,b1.head]) "turn did not capture both unprepared original owners"
  let atCut ← ProjectStore.openView project image.cut
  let complete ← Federated.prepare atCut.sources
  let mut present := #[]
  for (_,node) in complete.owners.toList do
    let reader ← NodeReader.new node.snapshot
    let outcome ← reader.outcome (← locateOutcome node.snapshot node.id)
    present := present.push (readable outcome.outcome)
  let required := ["original A1","original B1"]
  check (required.all present.contains) "required originals absent before readiness inspection"
  let a2 ← append project 0 atCut "A2"
  let b2 ← append project 1 atCut "B2"
  let _ ← Warm.run a2 command
  let _ ← Warm.run b2 command
  let before ← (List.finRange project.manifest.owners.size).mapM fun slot => do
    return (← project.current slot.val).head
  check ((← PreparedInputs.load? a1 MiniLM.model SearchProvider.encoderContract).isNone &&
    (← PreparedInputs.load? b1 MiniLM.model SearchProvider.encoderContract).isNone)
    "fixture failed to skip the captured source publications"
  let repairedA ← Warm.run a1 command
  let repairedB ← Warm.run b1 command
  let some frameEnvelope ← ProjectContext.captureInputs captured (atCut.sources.toList.map some) |
    throw (IO.userError "historical source preparation did not fulfil the complete cut")
  let frame ← IO.ofExcept (fromJson? (α := PreparedInputs.Frame) frameEnvelope.payload)
  let frozen := {captured with preparedInputs := some frameEnvelope}
  check (frame.originals == [some a1.head,some b1.head] && frame.owners.isSome)
    "prepared frame substituted a later original owner"
  check ((← PreparedInputs.load? a2 MiniLM.model SearchProvider.encoderContract).isSome &&
    (← PreparedInputs.load? b2 MiniLM.model SearchProvider.encoderContract).isSome)
    "historical preparation displaced a completed later input"
  let started ← IO.monoMsNow
  let some result ← deliver frozen | throw (IO.userError "captured cut produced no Handoff")
  let elapsed := (← IO.monoMsNow)-started
  let delivered := required.countP (fun marker => result.text.contains marker)
  check (result.reason != "search-incomplete" && delivered == required.length)
    "prepared historical cut omitted required originals in actual delivery"
  check (!(result.text.contains "original A2") && !(result.text.contains "original B2"))
    "future originals entered the captured cut"
  let after ← (List.finRange project.manifest.owners.size).mapM fun slot => do
    return (← project.current slot.val).head
  check (before == after) "derived preparation changed an original source head"
  IO.FS.writeFile (root/"pending.json") ((toJson frozen).pretty++"\n")
  IO.FS.writeFile (root/"body.txt") result.text
  let report := Json.mkObj [("capturedSources",toJson frame.originals),
    ("laterSources",toJson before),("requiredBeforeReadiness",toJson required),
    ("completeOriginalOwners",toJson complete.owners.size),
    ("historicalWarmMs",toJson #[repairedA.elapsedMs,repairedB.elapsedMs]),
    ("historicalWarm",toJson #[repairedA,repairedB]),
    ("bodySha256",toJson (Sha256.hex result.text.toUTF8)),("deliveryMs",toJson elapsed),
    ("requiredDelivered",toJson delivered),("bothLaterInputsRetained",toJson true),
    ("originalHeadsUnchanged",toJson true),("automaticPreparationDemand",toJson false),
    ("actualMiniLM",toJson false),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]
  IO.FS.writeFile (root/"report.json") (report.pretty++"\n")
  IO.println report.compress

end Eggshell.Research.PreparedCutChecks

def main (args : List String) : IO UInt32 := do
  match args with
  | ["prepared-cut-audit",root] =>
    try
      Eggshell.Research.PreparedCutChecks.audit (.mk root)
      pure 0
    finally
      let _ ← Eggshell.Plugin.Publication.Client.control "shutdown"
  | ["prepared-cut-restore",root] =>
    try
      Eggshell.Research.PreparedCutChecks.restore (.mk root)
      pure 0
    finally
      let _ ← Eggshell.Plugin.Publication.Client.control "shutdown"
  | other => sourceRouteEngine other
