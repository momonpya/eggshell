import Main
import Eggshell.ContractAudit

open Lean Eggshell Eggshell.DB Eggshell.Plugin Eggshell.Persistence.Store
namespace Eggshell.Research.CapturedPreparationChecks

def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

def rowValue (index : Nat) : ByteArray :=
  (String.ofList (List.replicate 512 'x')++toString index).toUTF8

def branchCheck (snapshot : PageMap.Snapshot) (choice : String) (future removed : Bool) : IO Unit := do
  check ((← snapshot.get "choice") == some choice.toUTF8) "derived branch changed its chosen basis"
  check ((← snapshot.get "future").isSome == future) "future row entered an earlier logical tree"
  check ((← snapshot.get "aborted").isNone) "aborted branch became visible"
  for index in [:256] do
    let expected := if removed && index == 128 then none else some (rowValue index)
    check ((← snapshot.get s!"row:{index}") == expected) "retained branch lost an original row"

def restoreBranches (root : System.FilePath) : IO Unit := do
  let saved ← IO.ofExcept (Json.parse (← IO.FS.readFile (root/"branches.json")))
  let heads ← IO.ofExcept (saved.getObjValAs? (Array PageMap.Head) "heads")
  let current ← PageMap.pin (root/"derived.egg")
  let cases := #[("a0",false,false),("a2",true,true),("a1",false,false),("recovered",false,false)]
  check (heads.size == cases.size) "branch inventory changed"
  for (head,index) in heads.zipIdx do
    let some retained ← PageMap.HistoryReader.make? current head | throw (IO.userError "published branch was truncated")
    let some (choice,future,removed) := cases[index]? | throw (IO.userError "missing branch expectation")
    branchCheck retained.snapshot choice future removed
  IO.println "all four logical branches restored with all 256 row checks"

def branches (root : System.FilePath) : IO Unit := do
  check (root.isAbsolute && !(← root.pathExists)) "fresh branch fixture required"
  FileSystem.privateDirectory root
  let empty ← PageMap.create (root/"derived.egg") "derived:branch-fixture"
  let (_,a0,_) ← PageMap.withWriter empty fun writer => do
    writer.put "choice" (some "a0".toUTF8)
    for index in [:256] do writer.put s!"row:{index}" (some (rowValue index))
  let a0Snapshot ← PageMap.pin empty.directory
  let (_,a2,_) ← PageMap.withWriter a0Snapshot fun writer => do
    writer.put "choice" (some "a2".toUTF8)
    writer.put "future" (some "later".toUTF8)
    writer.put "row:128" none
  let tip ← PageMap.pin empty.directory
  let publishedPrefix := (← IO.FS.readBinFile (PageMap.dataPath tip.directory tip.head)).extract 0 tip.head.bytes
  let (_,a1,written) ← PageMap.withWriterFrom tip a0 fun writer => do
    check ((← writer.get "choice") == some "a0".toUTF8) "branch reads the physical tip instead of its logical basis"
    check ((← writer.get "future").isNone) "branch admitted a future row before applying its delta"
    writer.put "choice" (some "a1".toUTF8)
  check (a1.revision == a2.revision+1 && a2.bytes < a1.bytes && 0 < written && written < a0.bytes)
    "branch did not append a bounded delta after the published tip"
  let committed ← PageMap.pin empty.directory
  let mut aborted := false
  try
    let _ ← PageMap.withWriterFrom committed a0 fun writer => do
      writer.put "aborted" (some "must never publish".toUTF8)
      writer.flush
      (throw (IO.userError "injected branch interruption") : IO Unit)
  catch _ => aborted := true
  check (aborted && (← PageMap.pin empty.directory).head == a1) "aborted branch changed the durable head"
  let dirty ← FileSystem.readVersion committed.handle
  check (dirty.bytes > a1.bytes) "interruption did not leave an actual uncommitted tail"
  let (_,recovered,_) ← PageMap.withWriterFrom committed a0 fun writer =>
    writer.put "choice" (some "recovered".toUTF8)
  let current ← PageMap.pin empty.directory
  let mut staleRejected := false
  try let _ ← PageMap.withWriterFrom tip a0 (fun _ => pure ()); pure ()
  catch _ => staleRejected := true
  let foreign ← PageMap.create (root/"foreign.egg") "derived:foreign"
  let mut foreignRejected := false
  try let _ ← PageMap.withWriterFrom current foreign.head (fun _ => pure ()); pure ()
  catch _ => foreignRejected := true
  let mut futureRejected := false
  try let _ ← PageMap.withWriterFrom current {a0 with bytes := current.head.bytes+1} (fun _ => pure ()); pure ()
  catch _ => futureRejected := true
  let (_,unchanged,noOpBytes) ← PageMap.withWriterFrom current a0 (fun _ => pure ())
  check (staleRejected && foreignRejected && futureRejected && unchanged == a0 && noOpBytes == 0 &&
    (← PageMap.pin empty.directory).head == recovered) "branch admission or no-op changed the physical tip"
  let after := (← IO.FS.readBinFile (PageMap.dataPath current.directory current.head)).extract 0 a2.bytes
  check (publishedPrefix == after) "branch/recovery rewrote an already published physical prefix"
  IO.FS.writeFile (root/"branches.json") (Json.mkObj [("heads",toJson #[a0,a2,a1,recovered])]).pretty
  restoreBranches root
  let report := Json.mkObj [("deltaBytes",toJson written),("basisBytes",toJson a0.bytes),
    ("publishedPrefixUnchanged",toJson true),("abortAfterActualAppend",toJson true),
    ("fourRootsReadable",toJson true),("staleForeignFutureRejected",toJson true),
    ("noOpKeepsPhysicalTip",toJson true),("originalPreparationIntegrated",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]
  IO.FS.writeFile (root/"branch-report.json") (report.pretty++"\n")
  IO.println report.compress

def append (project : ProjectStore.Project) (slot : Nat) (view : ProjectStore.View)
    (marker : String) : IO PageMap.Snapshot := do
  ProjectStore.withOwner project slot fun owner => do
    let capsule : Publication.Capsule := {
      session := s!"captured-preparation-{slot}",turn := marker,cwd := project.directory.toString
      work := "inspect "++marker,checkpoint := false
      tools := #[{name := "mcp__fixture__inspect",useId := marker,input := "{}",response := "original "++marker}]
      finalMessage := some ("notebook "++marker),timing := #[.unavailable]}
    let request ← IO.ofExcept (capsule.prepare project.directory owner.source.identity)
    let _ ← owner.publish view #[{request with target := project.sourceDirectory slot}]
    project.current slot

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
  let pending : PendingTurn := {
    sessionId := "captured-preparation",turnId := "query",cwd := root.toString,prompt := "A1"
    profile := "work",read := [project.directory.toString],write := none,semanticMatcher := none
    handoffChars := 120000,projection := .automatic}
  let captured ← ProjectContext.capture pending ((← IO.monoMsNow)+20000)
  let some images := captured.projectInputs | throw (IO.userError "turn omitted its original project cut")
  let some image := images[0]? | throw (IO.userError "turn omitted its configured project")
  check (image.cut.heads[0]? == some a1.head) "turn did not capture A1"
  let atCut ← ProjectStore.openView project image.cut
  let complete ← Federated.prepare atCut.sources
  let mut necessaryPresent := false
  for (_,node) in complete.owners.toList do
    let reader ← NodeReader.new node.snapshot
    let owner ← reader.outcome (← locateOutcome node.snapshot node.id)
    if readable owner.outcome == "original A1" then necessaryPresent := true
  check necessaryPresent "required original was absent before observing delivery readiness"
  let a2 ← append project 0 atCut "A2"
  let _ ← Warm.run a2 command
  let before ← (List.finRange project.manifest.owners.size).mapM fun slot => do
    return (← project.current slot.val).head
  let oldReadyBefore ← PreparedInputs.load? a1 MiniLM.model SearchProvider.encoderContract
  let currentReady ← PreparedInputs.load? a2 MiniLM.model SearchProvider.encoderContract
  let request : Worker.Search := {
    pending := captured,state := {profile := "work"},work := pending.prompt,enforce := false
    deadline := (← IO.monoMsNow)+20000}
  let mut admission := Json.null
  try
    let restored ← Worker.capturePrepared request
    admission := Json.mkObj [("accepted",toJson true),("originals",toJson restored.originals)]
  catch error => admission := Json.mkObj [("accepted",toJson false),("error",toJson error.toString)]
  let mut historicalWarm := Json.null
  try
    let result ← Warm.run a1 command
    historicalWarm := Json.mkObj [("complete",toJson true),("elapsedMs",toJson result.elapsedMs)]
  catch error => historicalWarm := Json.mkObj [("complete",toJson false),("error",toJson error.toString)]
  let oldReadyAfter ← PreparedInputs.load? a1 MiniLM.model SearchProvider.encoderContract
  let after ← (List.finRange project.manifest.owners.size).mapM fun slot => do
    return (← project.current slot.val).head
  check (before == after) "preparation changed an original source head"
  let report := Json.mkObj [("sourceAtQuery",toJson a1.head),("laterSource",toJson a2.head),
    ("necessaryOriginalPresent",toJson necessaryPresent),("required",toJson ["original A1"]),
    ("completeOwnersAtCut",toJson complete.owners.size),
    ("capturedReadyFrame",toJson captured.preparedInputs.isSome),
    ("oldReadyBefore",toJson oldReadyBefore.isSome),("currentReady",toJson currentReady.isSome),
    ("workerAdmission",admission),("historicalWarm",historicalWarm),
    ("oldReadyAfter",toJson oldReadyAfter.isSome),("originalHeadsUnchanged",toJson (before == after)),
    ("actualDeliveryMeasured",toJson false),("answeringModelCalls",toJson (0 : Nat)),
    ("actualMiniLM",toJson false),("adopted",toJson false)]
  IO.FS.writeFile (root/"report.json") (report.pretty++"\n")
  IO.println report.compress

end Eggshell.Research.CapturedPreparationChecks

def main (args : List String) : IO UInt32 := do
  match args with
  | ["derived-branch-audit",root] =>
    Eggshell.Research.CapturedPreparationChecks.branches (.mk root)
    pure 0
  | ["derived-branch-restore",root] =>
    Eggshell.Research.CapturedPreparationChecks.restoreBranches (.mk root)
    pure 0
  | ["captured-preparation-audit",root] =>
    try
      Eggshell.Research.CapturedPreparationChecks.audit (.mk root)
      pure 0
    finally
      let _ ← Eggshell.Plugin.Publication.Client.control "shutdown"
  | other => sourceRouteEngine other
