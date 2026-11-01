import Lean
open Lean

private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= fun value => IO.ofExcept (Json.parse value)
private def hash (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  check (result.exitCode == 0) "cannot hash finished evidence"
  return (result.stdout.splitOn " ").headD ""
private def shutdown (path : System.FilePath) : IO Json := do
  let value ← read path
  check (["acknowledged","processExited","endpointRemoved"].all (fun key => value.getObjValD key == toJson true))
    "finished service did not acknowledge and exit"
  return value
private partial def remove (path : System.FilePath) : IO (Nat × Nat) := do
  let metadata ← path.symlinkMetadata
  if metadata.type != .dir then
    IO.FS.removeFile path
    return (1,if metadata.type == .file then metadata.byteSize.toNat else 0)
  let mut count := (0,0)
  for entry in ← path.readDir do
    let next ← remove entry.path
    count := (count.1+next.1,count.2+next.2)
  IO.FS.removeDir path
  return count

private def timeline (receipts actual : System.FilePath) : IO Json := do
  let session ← IO.ofExcept ((← read (actual / "UserPromptSubmit/stdin")).getObjValAs? String "session_id")
  let mut found := #[]
  for entry in ← receipts.readDir do
    let request := entry.path / "request.json"
    if !(← request.pathExists) then continue
    let request := (← read request).getObjValD "data"
    if request.getObjValD "session" != toJson session || request.getObjValD "event" != toJson "UserPromptSubmit" then continue
    let mut times := #[]
    let mut numerical := #[]
    for item in ← entry.path.readDir do
      if !item.fileName.endsWith ".json" || item.fileName.startsWith "selection-selector" ||
          item.fileName.startsWith "selection-selectionWitness" then continue
      let value ← read item.path
      let time ← IO.ofExcept (value.getObjValAs? Nat "observedMs")
      let stage ← IO.ofExcept (value.getObjValAs? String "stage")
      times := times.push (time,Json.mkObj [("observedMs",toJson time),("stage",toJson stage)])
      if stage.startsWith "numerical-" then numerical := numerical.push value
    found := found.push (Json.mkObj [("receipt",toJson entry.fileName),
      ("timeline",toJson ((times.qsort (fun a b => a.1 < b.1)).map Prod.snd)),("numerical",toJson numerical)])
  check (found.size == 1) "need one actual prompt receipt for compact evidence"
  return found[0]!

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let records := project / "docs/candidates/transport-profile"
  let trial := root / "selection-frames-trial/candidate"
  let reference := project / "docs/candidates/source-plan/bodies/topic-1.txt"
  let body ← IO.FS.readFile reference
  let bodyHash ← hash reference
  check (!(← (records / "retired.json").pathExists)) "preserve prior finished cleanup"
  for label in ["normal-1","resident","audit-1","decision-1","decision-selftest"] do
    let guard ← read (records / (label ++ ".guard.json"))
    check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
      guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "a diagnostic is still running or failed"
  let runtime := (← read (records / "hooks/candidate-runtime.json")).getObjValD "runtime"
  let binary ← IO.ofExcept (runtime.getObjValAs? String "binary")
  check (runtime.getObjValD "sha256" == toJson (← hash (.mk binary))) "profile runtime changed"
  let mut summaries := #[]
  let mut retired := #[]
  for (name,actual,resident) in [
      ("normal",records / "hooks/candidate/rep-0/topic-1",false),
      ("resident-0",records / "resident/chat-0",true),
      ("resident-1",records / "resident/chat-1",true),
      ("audit",records / "hooks/candidate/audit/topic-1",false)] do
    let result ← read (actual / "result.json")
    check (result.getObjValD "bodySha256" == toJson bodyHash) "finished body hash changed"
    if !resident then check ((← IO.FS.readFile (actual / "body.txt")) == body) "actual body differs from retained reference"
    let profiles ← if resident then pure (result.getObjValD "serviceProfiles") else read (actual / "service-profile.json")
    let before ← if resident then read (records / "resident/before.json") else read (actual / "before-gold.json")
    let sourceFiles : Array (String × String) ← IO.ofExcept (before.getObjValAs? _ "sourceFiles")
    for (name,expected) in sourceFiles do check ((← hash (trial / "work.egg" / name)) == expected) "prepared original changed"
    let row := Json.mkObj [("name",toJson name),("runtime",runtime),("before",before),
      ("elapsedMs",result.getObjValD "elapsedMs"),("bodySha256",toJson bodyHash),
      ("bodyReference",toJson reference.toString),("sameParentBody",toJson true),
      ("availableDelivery",if resident then Json.null else result.getObjValD "availableDelivery"),
      ("publisherPid",result.getObjValD "publisherPid"),("sessionPid",result.getObjValD "sessionPid"),
      ("serviceProfiles",profiles),("receipt",← timeline (trial / "data/receipts") actual),
      ("shutdown",← shutdown (actual / "shutdown.json")),
      ("modelCalls",toJson (0 : Nat)),("adopted",toJson false)]
    IO.FS.writeFile (records / (name ++ "-result.json")) row.pretty
    summaries := summaries.push (Json.mkObj [("name",toJson name),("elapsedMs",result.getObjValD "elapsedMs"),
      ("bodySha256",toJson bodyHash),("publisherPid",result.getObjValD "publisherPid"),
      ("sessionPid",result.getObjValD "sessionPid")])
    if !resident then
      let _ ← shutdown (actual / "publisher-shutdown.json")
      retired := retired.push actual
    else
      retired := retired.push (actual / "SessionStart") |>.push (actual / "UserPromptSubmit")
  let _ ← shutdown (records / "resident/publisher-shutdown.json")
  let explanation ← read (records / "topic-1/before-gold.json")
  check (explanation.getObjValD "goldRead" == toJson false &&
    explanation.getObjValD "exactChoiceReplayed" == toJson true &&
    explanation.getObjValD "decisionsSha256" == toJson (← hash (records / "topic-1/source-decisions.json")))
    "generic explanation lost its pre-gold seal"
  IO.FS.writeFile (records / "result.json") (Json.mkObj [("runs",toJson summaries),
    ("runtime",runtime),("genericSelectorAudit",explanation),("modelCalls",toJson (0 : Nat)),
    ("newSeed",toJson false),("newDb",toJson false),("sustained80PersonWorkload",toJson false),
    ("adopted",toJson false)]).pretty
  let originals : Array (String × String) ← IO.ofExcept ((← read
    (project / "docs/candidates/read-signal-trace/native-seal.json")).getObjValAs? _ "verifiedOriginalFilesAndRuntimes")
  for (path,expected) in originals do check ((← hash (.mk path)) == expected) "protected original changed before cleanup"
  let finishedBuilds := #[root / "transport-profile-decision-build",root / "transport-profile-resident-build"]
  for entry in ← root.readDir do
    if finishedBuilds.contains entry.path then continue
    let response := entry.path / "runtime.rsp"
    if !(← response.pathExists) then continue
    let contents ← IO.FS.readFile response
    for ended in finishedBuilds do
      check (!contents.contains (ended.toString ++ "/")) "live runtime borrows a finished diagnostic build"
  retired := retired ++ finishedBuilds ++ #[trial / "data/receipts",trial / "data/sessions",
    records / "hooks/candidate/warm",root / "transport-profile-receipt-selftest",
    records / "topic-1/source-decisions.json",project / "docs/candidates/selection-witness/frames/hooks"]
  let mut count := (0,0)
  for path in retired do
    if !(← path.pathExists) then continue
    let next ← remove path
    count := (count.1+next.1,count.2+next.2)
  for (path,expected) in originals do check ((← hash (.mk path)) == expected) "protected original changed after cleanup"
  IO.FS.writeFile (records / "retired.json") (Json.mkObj [("files",toJson count.1),("logicalBytes",toJson count.2),
    ("deleted",toJson (retired.map (·.toString))),("archive",toJson false),
    ("currentPreparedDbRetained",toJson (trial / "work.egg").toString),
    ("protectedFilesVerifiedBeforeAndAfter",toJson originals.size)]).pretty
