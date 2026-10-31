import Lean
import Std.Data.HashSet
open Lean
private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def hash (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  check (result.exitCode == 0) "cannot hash retained artifact"
  return (result.stdout.splitOn " ").headD ""
private partial def remove (path : System.FilePath) : IO (Nat × Nat) := do
  let metadata ← path.symlinkMetadata
  if metadata.type != .dir then
    IO.FS.removeFile path
    return (1,if metadata.type == .file then metadata.byteSize.toNat else 0)
  let mut count := (0,0)
  for entry in ← path.readDir do
    let value ← remove entry.path
    count := (count.1+value.1,count.2+value.2)
  IO.FS.removeDir path
  return count

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let records := project / "docs/candidates/deferred-focus"
  check (!(← (records / "retired.json").pathExists)) "preserve completed cleanup"
  for label in ["branch-proof","runtime-build","hooks-build","describe","prepare","run"] do
    let guard ← read (records / (label ++ ".guard.json"))
    check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
      guard.getObjValD "guardTriggered" == toJson false && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat))
      "candidate job did not finish cleanly"
  let originals : Array (String × String) ← IO.ofExcept ((← read
    (project / "docs/candidates/read-signal-trace/native-seal.json")).getObjValAs? _ "verifiedOriginalFilesAndRuntimes")
  for (path,expected) in originals do check ((← hash (.mk path)) == expected) "protected source/runtime changed"
  let actual := records / "hooks/candidate/rep-0/topic-1"
  let body ← IO.FS.readFile (actual / "body.txt")
  let reference := project / "docs/candidates/source-plan/bodies/topic-1.txt"
  check (body == (← IO.FS.readFile reference)) "focus deferral changed parent body"
  let result ← read (actual / "result.json")
  let before ← read (actual / "before-gold.json")
  check (result.getObjValD "bodySha256" == toJson (← hash (actual / "body.txt")) &&
    before.getObjValD "goldRead" == toJson false) "candidate receipt differs from actual body"
  let described ← read (records / "hooks/candidate-runtime.json")
  let mut shutdowns := #[]
  for path in [actual / "shutdown.json",actual / "publisher-shutdown.json",records / "hooks/candidate/prepare-shutdown.json"] do
    let stopped ← read path
    check (["acknowledged","processExited","endpointRemoved"].all (fun key => stopped.getObjValD key == toJson true))
      "candidate service did not stop"
    shutdowns := shutdowns.push stopped
  IO.FS.writeFile (records / "shutdowns.json") (toJson shutdowns).pretty
  IO.FS.writeFile (records / "runtime.json") described.pretty
  IO.FS.writeFile (records / "result.json") ((result.setObjVal! "beforeGold" before)
    |>.setObjVal! "runtime" (described.getObjValD "runtime")
    |>.setObjVal! "bodyReference" (toJson reference.toString)
    |>.setObjVal! "sameParentBody" (toJson true)
    |>.setObjVal! "actualHookCount" (toJson (1 : Nat))
    |>.setObjVal! "latencyComparisonMeasured" (toJson false)
    |>.setObjVal! "historyRoundRun" (toJson false)
    |>.setObjVal! "tokenImprovementMeasured" (toJson false)
    |>.setObjVal! "sustained80PersonWorkloadVerified" (toJson false)).pretty
  IO.FS.writeFile (records / "preparation.json") (Json.mkObj [
    ("sourceIndex",← read (records / "hooks/candidate/prepared-source.json")),
    ("warm",← read (records / "hooks/candidate/warm/stdout")),
    ("wholeWarm",← read (records / "hooks/candidate/warm/record.json"))]).pretty
  let mut inputs : Std.HashSet String := {}
  for name in ["deferred-focus-runtime-build","carried-value-runtime-build","project-metadata-runtime-build","prepared-view-runtime-build",
      "published-plan-runtime-build","service-plan-runtime-build","source-plan-runtime-build","owner-palette-runtime-build",
      "owner-palette-build","receipt-reconciliation-runtime-build","query-cache-baseline-build"] do
    let directory := root / name
    let binaryDigest ← hash (directory / "StudyMain")
    check (!binaryDigest.isEmpty) "retained runtime is missing"
    for line in (← IO.FS.readFile (directory / "runtime.rsp")).splitOn "\n" do
      if line.trimAscii.isEmpty then continue
      let path ← IO.ofExcept (Json.parse line >>= Json.getStr?)
      check (!path.contains "deferred-focus-hook-" && !path.contains "deferred-focus-proof.")
        "retained runtime borrows an ended helper"
      check (← System.FilePath.pathExists path) "native runtime input is missing"
      inputs := inputs.insert path
  for (name,output) in [("deferred-focus-runtime-build","runtime-closure.json"),
      ("deferred-focus-hook-candidate-build","helper-closure.json")] do
    let audited ← IO.Process.output {
      cmd := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean"
      args := #["-M2048","--run",(project / "tools/research/StudyBuildClosureAudit.lean").toString,
        "inspect",(root / name).toString,(records / output).toString]}
    check (audited.exitCode == 0) "native dependency closure is inconsistent"
  let mut events := #[]
  for entry in ← (root / "deferred-focus-trial/candidate/data/receipts").readDir do
    let path := entry.path / "request.json"
    if !(← path.pathExists) then continue
    if ((← read path).getObjValD "data").getObjValD "event" != toJson "UserPromptSubmit" then continue
    for name in ["request","keyed-request","keyed-nominations","canonical-source-input","delivery-domain",
        "selection-plan","synaptic-delivery","search","dispatch","transport","published"] do
      let stage := entry.path / (name ++ ".json")
      if ← stage.pathExists then
        events := events.push (Json.mkObj [("stage",toJson name),("observedMs",(← read stage).getObjValD "observedMs")])
    for item in ← entry.path.readDir do
      if item.fileName.startsWith "numerical-" && item.fileName.endsWith ".json" then
        IO.FS.writeFile (records / item.fileName) (← IO.FS.readFile item.path)
  IO.FS.writeFile (records / "receipt-timeline.json") (toJson events).pretty
  let mut total := (0,0)
  for path in [root / "deferred-focus-trial",root / "deferred-focus-hook-candidate-build",records / "hooks"] do
    let count ← remove path
    total := (total.1+count.1,total.2+count.2)
  for entry in ← root.readDir do
    if entry.fileName.startsWith "deferred-focus-proof." ||
        (entry.fileName.startsWith "deferred-focus-" && entry.fileName.endsWith ".settings.json") then
      let count ← remove entry.path
      total := (total.1+count.1,total.2+count.2)
  for (path,expected) in originals do check ((← hash (.mk path)) == expected) "cleanup changed protected input"
  for path in inputs do check (← System.FilePath.pathExists path) "cleanup removed a retained native input"
  IO.FS.writeFile (records / "retired.json") (Json.mkObj [("files",toJson total.1),("logicalBytes",toJson total.2),
    ("protectedHashesBeforeAndAfter",toJson true),("retainedNativeLinkInputs",toJson inputs.size),
    ("archiveCreated",toJson false)]).pretty
  IO.println s!"Retired ended deferral DB/cache/helper: {total.2} logical bytes"
