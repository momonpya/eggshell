import Lean
open Lean
private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def hash (path : System.FilePath) : IO String := do
  let found ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  check (found.exitCode == 0) "cannot check protected input"
  return (found.stdout.splitOn " ").headD ""
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
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let records := project / "docs/candidates/published-plan"
  check (!(← (records / "retired.json").pathExists)) "preserve connection cleanup receipt"
  let guard ← read (records / "connection.guard.json")
  check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
    guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "connection is not terminal"
  let outcome ← read (records / "connection.json")
  check (["conditionedProblemExact","actualBodyExact","sourceUnchanged"].all
    (fun field => outcome.getObjValD field == toJson true)) "connection did not preserve its original contract"
  let originals : Array (String × String) ← IO.ofExcept (fromJson?
    ((← read (project / "docs/candidates/read-signal-trace/native-seal.json")).getObjValD "verifiedOriginalFilesAndRuntimes"))
  for (path,expected) in originals do check ((← hash (.mk path)) == expected) "protected source changed"
  let mut retained := #[]
  let mut binaries := #[]
  for name in ["published-plan-runtime-build","service-plan-runtime-build","source-plan-runtime-build",
      "owner-palette-runtime-build","owner-palette-build","receipt-reconciliation-runtime-build","query-cache-baseline-build"] do
    let directory := root / name
    binaries := binaries.push (directory / "StudyMain",← hash (directory / "StudyMain"))
    for line in (← IO.FS.readFile (directory / "runtime.rsp")).splitOn "\n" do
      if line.trimAscii.isEmpty then continue
      let path ← IO.ofExcept (Json.parse line >>= Json.getStr?)
      check (!(path.contains "published-plan-hook-")) "runtime borrows completed hook helper"
      if path.endsWith ".o" then
        check (← System.FilePath.pathExists path) "missing live native input"
        retained := retained.push path
  let baselineBody := records / "hooks/baseline/audit/topic-1/body.txt"
  let candidateBody := records / "hooks/candidate/audit/topic-1/body.txt"
  let body ← IO.FS.readFile baselineBody
  let sha ← hash baselineBody
  check ((← IO.FS.readFile candidateBody) == body) "actual connection bodies differ"
  let parentBody := project / "docs/candidates/source-plan/bodies/topic-1.txt"
  let bodyReference ← if (← IO.FS.readFile parentBody) == body then pure parentBody else do
    let path := records / "body.txt"
    check (!(← path.pathExists)) "preserve actual body reference"
    IO.FS.writeFile path body
    pure path
  let mut delivered := #[]
  let mut closed := #[]
  let mut preparation := #[]
  for arm in ["baseline","candidate"] do
    IO.FS.writeFile (records / ("runtime-" ++ arm ++ ".json")) (← IO.FS.readFile (records / "hooks" / (arm ++ "-runtime.json")))
    let directory := records / "hooks" / arm
    let built ← read (directory / "prepared-source.json")
    let warm ← read (directory / "warm/record.json")
    preparation := preparation.push (Json.mkObj [("arm",toJson arm),
      ("sourceIndexMs",built.getObjValD "elapsedMs"),("warm",warm),
      ("freshDiagnosticFork",toJson true),("performanceComparison",toJson false)])
    let actual ← read (directory / "audit/topic-1/result.json")
    check (actual.getObjValD "bodySha256" == toJson sha) "actual receipt differs from retained body"
    delivered := delivered.push (Json.mkObj [("arm",toJson arm),("bodySha256",toJson sha),
      ("bodyReference",toJson bodyReference.toString),("availableDelivery",actual.getObjValD "availableDelivery"),
      ("diagnosticElapsedMs",actual.getObjValD "elapsedMs"),("performanceSample",toJson false)])
    for relative in ["prepare-shutdown.json","audit/topic-1/shutdown.json","audit/topic-1/publisher-shutdown.json"] do
      let report ← read (directory / relative)
      check (["acknowledged","processExited","endpointRemoved"].all (fun field => report.getObjValD field == toJson true) &&
        report.getObjValD "daemonExitCode" == toJson (0 : Nat)) "service did not close cleanly"
      closed := closed.push (Json.mkObj [("arm",toJson arm),("stage",toJson relative),("report",report)])
  IO.FS.writeFile (records / "delivered.json") (toJson delivered).pretty
  IO.FS.writeFile (records / "shutdowns.json") (toJson closed).pretty
  IO.FS.writeFile (records / "preparation.json") (toJson preparation).pretty
  let mut deleted := #[]
  for path in [root / "published-plan-trial",records / "hooks",root / "published-plan-hook-baseline-build",root / "published-plan-hook-candidate-build"] do
    if ← path.pathExists then
      let (files,bytes) ← remove path
      deleted := deleted.push (Json.mkObj [("path",toJson path.toString),("files",toJson files),("logicalBytes",toJson bytes)])
  for name in ["service-plan-core","published-plan-core"] do
    let path := root / name / "tools/research/PublishedPlanHook.lean"
    if ← path.pathExists then IO.FS.removeFile path
  for path in retained do check (← System.FilePath.pathExists path) "cleanup removed live native input"
  for (path,expected) in binaries do check ((← hash path) == expected) "cleanup changed runtime"
  for (path,expected) in originals do check ((← hash (.mk path)) == expected) "cleanup changed original"
  IO.FS.writeFile (records / "retired.json") (Json.mkObj [("deleted",toJson deleted),
    ("retainedNativeInputs",toJson retained.size),("sourceAndRuntimesUnchanged",toJson true),
    ("compressedOrArchived",toJson false)]).pretty
  IO.println "Deleted ended connection DB/cache/helpers and duplicate logs; retained compact actual receipts and body reference"
