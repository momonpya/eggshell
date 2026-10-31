import Lean
open Lean
private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= fun s => IO.ofExcept (Json.parse s)
private def hash (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  check (result.exitCode == 0) "cannot hash retained source/runtime"
  return (result.stdout.splitOn " ").headD ""
private partial def remove (path : System.FilePath) : IO (Nat × Nat) := do
  let info ← path.symlinkMetadata
  if info.type != .dir then
    IO.FS.removeFile path
    return (1,if info.type == .file then info.byteSize.toNat else 0)
  let mut total := (0,0)
  for entry in ← path.readDir do
    let next ← remove entry.path
    total := (total.1+next.1,total.2+next.2)
  IO.FS.removeDir path
  return total

def main : IO Unit := do
  let study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  let root := study / "shared-snapshot"
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let evidence := project / "docs/candidates/source-plan"
  let guard ← read (evidence / "suite.guard.json")
  check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat))
    "source-plan processes must terminate before cleanup"
  let result ← read (evidence / "result.json")
  check (result.getObjValD "ordinaryActualHooks" == toJson (12 : Nat)) "source-plan suite did not complete"
  check (!(← (evidence / "retired.json").pathExists)) "preserve source-plan cleanup record"
  let originals : Array (String × String) ← IO.ofExcept (fromJson?
    ((← read (project / "docs/candidates/read-signal-trace/native-seal.json")).getObjValD "verifiedOriginalFilesAndRuntimes"))
  for (path,sha) in originals do check ((← hash (.mk path)) == sha) "protected source/runtime changed before cleanup"
  let builds := #["owner-palette-runtime-build","source-plan-runtime-build","owner-palette-build",
    "receipt-reconciliation-runtime-build","query-cache-baseline-build"]
  let mut retained := #[]
  let mut runtimes := #[]
  for build in builds do
    let directory := root / build
    let binary := directory / "StudyMain"
    runtimes := runtimes.push (binary,← hash binary)
    for line in (← IO.FS.readFile (directory / "runtime.rsp")).splitOn "\n" do
      if line.trimAscii.isEmpty then continue
      let path ← IO.ofExcept (Json.parse line >>= Json.getStr?)
      check ((path.splitOn "source-plan-hook-baseline-build").length == 1 &&
        (path.splitOn "source-plan-hook-candidate-build").length == 1)
        "an active runtime still borrows a trial helper input"
      if path.endsWith ".o" then
        let file : System.FilePath := path
        check (← file.pathExists) "active native input is missing"
        retained := retained.push file
  let compact := evidence / "bodies"
  IO.FS.createDirAll compact
  let mut delivered := #[]
  let mut stopped := #[]
  let closed (label : String) (path : System.FilePath) : IO Json := do
    let report ← read path
    check (["acknowledged","processExited","endpointRemoved"].all (fun key => report.getObjValD key == toJson true) &&
      report.getObjValD "daemonExitCode" == toJson (0 : Nat)) "a source-plan service did not stop cleanly"
    return Json.mkObj [("stage",toJson label),("report",report)]
  for arm in ["baseline","candidate"] do
    IO.FS.writeFile (evidence / ("runtime-" ++ arm ++ ".json"))
      (← IO.FS.readFile (evidence / "hooks" / (arm ++ "-runtime.json")))
    stopped := stopped.push (← closed (arm ++ "-prepare") (evidence / "hooks" / arm / "prepare-shutdown.json"))
  for topic in [1,2,3] do
    let exemplar := evidence / "hooks/baseline/rep-0" / s!"topic-{topic}" / "body.txt"
    let body ← IO.FS.readFile exemplar
    let sha ← hash exemplar
    let canonical := compact / s!"topic-{topic}.txt"
    IO.FS.writeFile canonical body
    for arm in ["baseline","candidate"] do
      for repetition in [0,1] do
        let directory := evidence / "hooks" / arm / s!"rep-{repetition}" / s!"topic-{topic}"
        let actual ← IO.FS.readFile (directory / "body.txt")
        let report ← read (directory / "result.json")
        for name in ["shutdown","publisher-shutdown"] do
          stopped := stopped.push (← closed s!"{arm}-{topic}-{repetition}-{name}" (directory / (name ++ ".json")))
        check (actual == body && report.getObjValD "bodySha256" == toJson sha) "completed hook body differs from compact reference"
        delivered := delivered.push (Json.mkObj [
          ("arm",toJson arm),("topic",toJson topic),("repetition",toJson repetition),
          ("elapsedMs",report.getObjValD "elapsedMs"),("bodySha256",toJson sha),
          ("bodyReference",toJson canonical.toString),("availableDelivery",report.getObjValD "availableDelivery"),
          ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  let auditBody ← IO.FS.readFile (evidence / "hooks/candidate/audit/topic-1/body.txt")
  for name in ["shutdown","publisher-shutdown"] do
    stopped := stopped.push (← closed ("independent-audit-" ++ name)
      (evidence / "hooks/candidate/audit/topic-1" / (name ++ ".json")))
  check (auditBody == (← IO.FS.readFile (compact / "topic-1.txt"))) "independent audit body differs"
  IO.FS.writeFile (evidence / "delivered.json") (toJson delivered).pretty
  IO.FS.writeFile (evidence / "shutdowns.json") (toJson stopped).pretty
  let mut deleted := #[]
  for path in #[root / "source-plan-trial",evidence / "hooks",root / "source-plan-hook-baseline-build",
      root / "source-plan-hook-candidate-build"] do
    if !(← path.pathExists) then continue
    let (files,bytes) ← remove path
    if files == 0 then continue
    deleted := deleted.push (Json.mkObj [("path",toJson path.toString),("files",toJson files),("logicalBytes",toJson bytes)])
  for name in ["owner-palette-core","source-plan-core"] do
    let helper := root / name / "tools/research/SourcePlanHook.lean"
    if ← helper.pathExists then IO.FS.removeFile helper
  for file in retained do check (← file.pathExists) "cleanup removed an active native input"
  for (binary,sha) in runtimes do check ((← hash binary) == sha) "cleanup changed a retained runtime"
  for (path,sha) in originals do check ((← hash (.mk path)) == sha) "cleanup changed a protected source/runtime"
  IO.FS.writeFile (evidence / "retired.json") (Json.mkObj [
    ("deleted",toJson deleted),("retainedNativeInputs",toJson retained.size),
    ("sourceUnchanged",toJson true),("runtimesUnchanged",toJson true),
    ("actualBodiesRetained",toJson (3 : Nat)),("compressedOrArchived",toJson false)]).pretty
  IO.println "Removed completed source-plan DB/cache/helper builds and duplicate logs; retained exact bodies and compact evidence"
