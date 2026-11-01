import Lean
open Lean
private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def hash (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  check (result.exitCode == 0) "cannot hash profile evidence"
  return (result.stdout.splitOn " ").headD ""
private partial def remove (path : System.FilePath) : IO (Nat × Nat) := do
  let metadata ← path.symlinkMetadata
  if metadata.type != .dir then
    IO.FS.removeFile path
    return (1,if metadata.type == .file then metadata.byteSize.toNat else 0)
  let mut total := (0,0)
  for entry in ← path.readDir do
    let count ← remove entry.path
    total := (total.1+count.1,total.2+count.2)
  IO.FS.removeDir path
  return total

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let records := project / "docs/candidates/selection-witness"
  let frames := records / "frames"
  let trial := root / "selection-frames-trial/candidate"
  let actual := frames / "hooks/candidate/rep-0/topic-1"
  check (!(← (frames / "retired-normal.json").pathExists)) "preserve finished profile cleanup"
  for label in ["normal-1","resume-run2"] do
    let guard ← read (frames / (label ++ ".guard.json"))
    check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
      guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "profile did not finish cleanly"
  let body := actual / "body.txt"
  let reference := project / "docs/candidates/source-plan/bodies/topic-1.txt"
  check ((← IO.FS.readFile body) == (← IO.FS.readFile reference)) "profile changed actual parent body"
  let before ← read (actual / "before-gold.json")
  let result ← read (actual / "result.json")
  check (before.getObjValD "goldRead" == toJson false && result.getObjValD "bodySha256" == toJson (← hash body))
    "actual profile lost its pre-gold seal"
  let mut shutdowns := #[]
  for path in [actual / "shutdown.json",actual / "publisher-shutdown.json",frames / "hooks/candidate/resume-shutdown.json"] do
    let value ← read path
    check (["acknowledged","processExited","endpointRemoved"].all (fun key => value.getObjValD key == toJson true))
      "profile service did not stop cleanly"
    shutdowns := shutdowns.push value
  IO.FS.writeFile (frames / "normal-result.json") (Json.mkObj [("runtime",(← read (frames / "hooks/candidate-runtime.json")).getObjValD "runtime"),
    ("beforeGold",before),("elapsedMs",result.getObjValD "elapsedMs"),("bodySha256",result.getObjValD "bodySha256"),
    ("bodyReference",toJson reference.toString),("sameParentBody",toJson true),
    ("availableDelivery",result.getObjValD "availableDelivery"),("serviceProfiles",← read (actual / "service-profile.json")),
    ("shutdowns",toJson shutdowns),("modelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
  let receipt := trial / "data/receipts/29a24c4c70f3ad82b9847d7406b5561c63eec0cf51590b8c0ebb3417380014a0"
  let mut times := #[]
  let mut numerical := #[]
  for entry in ← receipt.readDir do
    if !entry.fileName.endsWith ".json" then continue
    let value ← read entry.path
    let observed ← IO.ofExcept (value.getObjValAs? Nat "observedMs")
    let stage ← IO.ofExcept (value.getObjValAs? String "stage")
    times := times.push (observed,Json.mkObj [("stage",toJson stage),("observedMs",toJson observed)])
    if stage.startsWith "numerical-" then numerical := numerical.push value
  IO.FS.writeFile (frames / "normal-timeline.json") (toJson (times.qsort (fun a b => a.1 < b.1) |>.map Prod.snd)).pretty
  IO.FS.writeFile (frames / "normal-numerical.json") (toJson numerical).pretty
  IO.FS.writeFile (frames / "resumed-preparation.json") (Json.mkObj [
    ("warm",← read (frames / "hooks/candidate/resume-warm/stdout")),
    ("timing",← read (frames / "hooks/candidate/resume-warm/record.json")),
    ("resume",← read (frames / "hooks/candidate/resume.json"))]).pretty
  let old := records / "hooks/candidate/audit/topic-1"
  let oldResult ← read (old / "result.json")
  check ((← IO.FS.readFile (old / "body.txt")) == (← IO.FS.readFile reference)) "prior completed body changed"
  IO.FS.writeFile (records / "unframed-observer-result.json") (Json.mkObj [
    ("runtime",(← read (records / "hooks/candidate-runtime.json")).getObjValD "runtime"),
    ("elapsedMs",oldResult.getObjValD "elapsedMs"),("bodySha256",oldResult.getObjValD "bodySha256"),
    ("bodyReference",toJson reference.toString),("sameParentBody",toJson true),
    ("availableDelivery",oldResult.getObjValD "availableDelivery"),("selectionWitnessSaved",toJson false),
    ("actualDiagnosticSucceeded",toJson false),("modelCalls",toJson (0 : Nat))]).pretty
  let originals : Array (String × String) ← IO.ofExcept ((← read
    (project / "docs/candidates/read-signal-trace/native-seal.json")).getObjValAs? _ "verifiedOriginalFilesAndRuntimes")
  for (path,expected) in originals do check ((← hash (.mk path)) == expected) "protected original changed before cleanup"
  let retired := #[root / "selection-witness-trial",root / "selection-frames-resume-build",
    records / "hooks",frames / "hooks/candidate/rep-0",frames / "hooks/candidate/resume-warm",frames / "hooks/candidate/warm",
    trial / "data/receipts",trial / "data/sessions"]
  for entry in ← root.readDir do
    if retired.contains entry.path then continue
    let response := entry.path / "runtime.rsp"
    if !(← response.pathExists) then continue
    let value ← IO.FS.readFile response
    check (!value.contains ((root / "selection-frames-resume-build").toString ++ "/"))
      "another runtime borrows the finished resume helper"
  let mut total := (0,0)
  for path in retired do
    if !(← path.pathExists) then continue
    let removed ← remove path
    total := (total.1+removed.1,total.2+removed.2)
  for (path,expected) in originals do check ((← hash (.mk path)) == expected) "protected original changed after cleanup"
  IO.FS.writeFile (frames / "retired-normal.json") (Json.mkObj [("files",toJson total.1),("logicalBytes",toJson total.2),
    ("deleted",toJson (retired.map (·.toString))),("archive",toJson false),
    ("currentPreparedDbRetained",toJson (trial / "work.egg").toString),
    ("protectedFilesVerifiedBeforeAndAfter",toJson originals.size)]).pretty
