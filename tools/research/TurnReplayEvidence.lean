import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def check (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun raw => IO.ofExcept (Json.parse raw)
private def sha (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  check (result.exitCode == 0) "cannot inspect native input"
  return (result.stdout.splitOn " ").headD ""
private def artifact (path : System.FilePath) : IO Json := do
  return Json.mkObj [("path",toJson path.toString),("sha256",toJson (← sha path)),
    ("bytes",toJson (← path.metadata).byteSize)]
private partial def retire (path : System.FilePath) : IO Nat := do
  let metadata ← path.symlinkMetadata
  if metadata.type == .dir then
    let mut bytes := 0
    for entry in ← path.readDir do bytes := bytes + (← retire entry.path)
    IO.FS.removeDir path
    return bytes
  check (metadata.type == .file) "ended diagnostic contains a special file"
  IO.FS.removeFile path
  return metadata.byteSize.toNat

def main (args : List String) : IO Unit := do
  check (args.isEmpty || args == ["cleanup"]) "expected capture or cleanup"
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
  let output := project / "docs/candidates/turn-replay"
  let build := root / "turn-replay-build"
  let parent := root / "delivery-ack-core"
  let core := root / "turn-replay-core"
  let protectedRecord ← read (project / "docs/candidates/delivery-ack/manifest.json")
  let protectedInputs : Array (String × String) ← IO.ofExcept (protectedRecord.getObjValAs? _ "currentProtectedInputs")
  let sealedInputs : Array Json ← IO.ofExcept (protectedRecord.getObjValAs? _ "sealedInputs")
  let verify := do
    for (path,digest) in protectedInputs do check ((← sha (.mk path)) == digest) "protected input changed"
    for entry in sealedInputs do
      let path ← IO.ofExcept (entry.getObjValAs? String "path")
      check (toJson (← sha (.mk path)) == entry.getObjValD "sha256") "sealed model input changed"
  verify
  if args == ["cleanup"] then
    check (← (output / "manifest.json").pathExists) "capture evidence before cleanup"
    check (!(← (output / "cleanup.json").pathExists)) "preserve the cleanup record"
    let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
    check (processes.exitCode == 0 && !(processes.stdout.splitOn "\n").any (fun row =>
      row.startsWith (build / "StudyMain").toString || (row.splitOn "StudyBuildMain.lean").length > 1))
      "wait for native work to finish"
    let mut removed := #[]
    for path in [root / "turn-replay-native",root / "turn-replay-native2",build / "StudyMain"] do
      removed := removed.push (path.toString,← retire path)
    for entry in ← root.readDir do
      if entry.fileName.startsWith "turn-replay-" &&
          (entry.fileName.endsWith ".stdout" || entry.fileName.endsWith ".stderr") then
        removed := removed.push (entry.path.toString,← retire entry.path)
    for entry in ← build.readDir do
      if entry.fileName.endsWith ".stdout" || entry.fileName.endsWith ".stderr" then
        removed := removed.push (entry.path.toString,← retire entry.path)
    verify
    IO.FS.writeFile (output / "cleanup.json") (Json.mkObj [("removed",toJson removed),
      ("protectedInputsUnchanged",toJson true),("objectsInterfacesAndInputStampsRetained",toJson true),
      ("archiveCreated",toJson false)]).pretty
    IO.println "Retired ended native fixtures, executable and compiler logs; current inputs retained."
    return
  check (!(← (output / "manifest.json").pathExists)) "preserve native evidence"
  IO.FS.createDirAll output
  let guard ← read (root / "turn-replay-checks2.guard.json")
  check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
    guard.getObjValD "guardTriggered" == toJson false) "native run was not successful and terminal"
  let mut modules := #[]
  for name in ["TurnReplay","SynapseIndex","UsageCache","SynapseJournal","ContractAudit"] do
    let relative := "Eggshell/" ++ name ++ ".lean"
    let old := parent / relative
    let old := if ← old.pathExists then old.toString else "/dev/null"
    let result ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","--label","a/" ++ relative,
      "--label","b/" ++ relative,old,(core / relative).toString]}
    check (result.exitCode == 1) "expected an isolated candidate change"
    IO.FS.writeFile (output / (name ++ ".patch")) result.stdout
    modules := modules.push (← artifact (core / relative))
  let mut resources := #[]
  let mut negatives := #[]
  for name in ["compile","compile2","compile3","compile4","compile5","checks","checks2"] do
    resources := resources.push (← read (root / ("turn-replay-" ++ name ++ ".guard.json")))
    let path := root / ("turn-replay-" ++ name ++ ".stderr")
    let error ← IO.FS.readFile path
    if !error.isEmpty then negatives := negatives.push (Json.mkObj [("attempt",toJson name),("stderr",toJson error)])
  IO.FS.writeFile (output / "resources.json") (toJson resources).pretty
  IO.FS.writeFile (output / "negative-builds.json") (toJson negatives).pretty
  IO.FS.writeFile (output / "checks.json") (← IO.FS.readFile (root / "turn-replay-native2/result.json"))
  let mut objects := #[]
  for line in (← IO.FS.readFile (build / "runtime.rsp")).splitOn "\n" do
    if line.trimAscii.isEmpty then continue
    let path ← IO.ofExcept (Json.parse line >>= Json.getStr?)
    let path := System.FilePath.mk path
    if path.extension != some "o" then continue
    let mut stamps := #[]
    for extension in ["source","dependencies"] do
      let stamp := path.withExtension extension
      if ← stamp.pathExists then stamps := stamps.push (← artifact stamp)
    objects := objects.push ((← artifact path).setObjVal! "inputStamps" (toJson stamps))
  IO.FS.writeFile (output / "native-inputs.json") (Json.mkObj [("objects",toJson objects),
    ("entryPointDependencies",← read (build / "tools_research_TurnReplayChecks.dependencies")),
    ("build",← read (build / "build.json")),("response",toJson (← IO.FS.readFile (build / "runtime.rsp")))]).pretty
  IO.FS.writeFile (output / "audit.json") (Json.mkObj [
    ("contractAudit",toJson (← IO.FS.readFile (build / "Eggshell_ContractAudit-lean.stdout"))),
    ("bucketProofAxioms",toJson (← IO.FS.readFile (build / "tools_research_TurnReplayChecks-lean.stdout"))),
    ("wholeIoCorrectnessProven",toJson false)]).pretty
  IO.FS.writeFile (output / "manifest.json") (Json.mkObj [("candidateModules",toJson modules),
    ("entryPoint",← artifact (core / "tools/research/TurnReplayChecks.lean")),
    ("nativeExecutable",← artifact (build / "StudyMain")),("currentProtectedInputs",toJson protectedInputs),
    ("sealedInputs",toJson sealedInputs),("protectedInputsUnchanged",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
  verify
  IO.println "Captured native turn-replay checks, exact input closure, audit, patches and resource guards."
