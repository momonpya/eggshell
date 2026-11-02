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
  let bounds := args.contains "bounds"
  let prefixMode := args.contains "prefix"
  let ranges := args.contains "ranges"
  let work := args.contains "work" || bounds || prefixMode || ranges
  let args := args.filter (fun arg => arg != "work" && arg != "bounds" && arg != "prefix" && arg != "ranges")
  check (args.isEmpty || args == ["cleanup"]) "expected optional work and capture or cleanup"
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
  let stem := if ranges then "read-ranges" else if prefixMode then "replay-prefix" else if bounds then "replay-bounds" else if work then "replay-work" else "turn-replay"
  let entryPoint := if ranges then "ReadRangeMain" else if work then "ReplayWorkMain" else "TurnReplayChecks"
  let output := project / "docs/candidates" / stem
  let build := root / (stem ++ "-build")
  let parent := root / (if ranges then "replay-prefix-core" else if prefixMode then "replay-bounds-core" else if bounds then "replay-work-core" else if work then "turn-replay-core" else "delivery-ack-core")
  let core := root / (stem ++ "-core")
  let mut native := root / (stem ++ "-native")
  let mut lastChecks := root / (stem ++ "-checks.guard.json")
  let mut attempt := 2
  while ← (root / (stem ++ "-checks" ++ toString attempt ++ ".guard.json")).pathExists do
    lastChecks := root / (stem ++ "-checks" ++ toString attempt ++ ".guard.json")
    native := root / (stem ++ "-native" ++ toString attempt)
    attempt := attempt+1
  let protectedRecord ← read (project / "docs/candidates/delivery-ack/manifest.json")
  let protectedInputs : Array (String × String) ← IO.ofExcept (protectedRecord.getObjValAs? _ "currentProtectedInputs")
  let sealedInputs : Array Json ← IO.ofExcept (protectedRecord.getObjValAs? _ "sealedInputs")
  let verify := do
    for (path,digest) in protectedInputs do check ((← sha (.mk path)) == digest) "protected input changed"
    for entry in sealedInputs do
      let path ← IO.ofExcept (entry.getObjValAs? String "path")
      check (toJson (← sha (.mk path)) == entry.getObjValD "sha256") "sealed model input changed"
  verify
  if work && args.isEmpty then
    let retirement := project / "docs/candidates/delivery-ack/current-replay-build-retirement.json"
    let record ← read retirement
    if let .arr removed := record.getObjValD "removed" then
      let detailSha ← sha retirement
      let logicalBytes ← IO.ofExcept (record.getObjValAs? Nat "logicalBytesRemoved")
      IO.FS.writeFile retirement (Json.mkObj [("removedFiles",toJson removed.size),
        ("logicalBytesRemoved",toJson logicalBytes),("removedDetailSha256",toJson detailSha),
        ("currentLinkObjectsInterfacesAndStampsRetained",toJson true),
        ("sourceAndDbFilesExcluded",toJson true),("protectedInputsUnchanged",toJson true),
        ("archiveCreated",toJson false),("physicalBytesRecoveredMeasured",toJson false)]).pretty
  if args == ["cleanup"] then
    check (← (output / "manifest.json").pathExists) "capture evidence before cleanup"
    check (!(← (output / "cleanup.json").pathExists)) "preserve the cleanup record"
    let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
    check (processes.exitCode == 0 && !(processes.stdout.splitOn "\n").any (fun row =>
      row.startsWith (build / "StudyMain").toString || (row.splitOn "StudyBuildMain.lean").length > 1))
      "wait for native work to finish"
    let mut removed := #[]
    for entry in ← root.readDir do
      if entry.fileName.startsWith (stem ++ "-native") && (← entry.path.isDir) then
        removed := removed.push (entry.path.toString,← retire entry.path)
    removed := removed.push ((build / "StudyMain").toString,← retire (build / "StudyMain"))
    for entry in ← root.readDir do
      if entry.fileName.startsWith (stem ++ "-") &&
          (entry.fileName.endsWith ".stdout" || entry.fileName.endsWith ".stderr") then
        removed := removed.push (entry.path.toString,← retire entry.path)
    for entry in ← build.readDir do
      if entry.fileName.endsWith ".stdout" || entry.fileName.endsWith ".stderr" then
        removed := removed.push (entry.path.toString,← retire entry.path)
    verify
    let generatedLogs := removed.filter fun (path,_) => path.endsWith ".stdout" || path.endsWith ".stderr"
    let retainedDetails := removed.filter fun (path,_) => !path.endsWith ".stdout" && !path.endsWith ".stderr"
    IO.FS.writeFile (output / "cleanup.json") (Json.mkObj [("removed",toJson retainedDetails),
      ("removedCompilerAndRunLogs",toJson generatedLogs.size),
      ("removedLogBytes",toJson (generatedLogs.foldl (fun bytes row => bytes+row.2) 0)),
      ("protectedInputsUnchanged",toJson true),("objectsInterfacesAndInputStampsRetained",toJson true),
      ("archiveCreated",toJson false)]).pretty
    IO.println "Retired ended native fixtures, executable and compiler logs; current inputs retained."
    return
  check (!(← (output / "manifest.json").pathExists)) "preserve native evidence"
  IO.FS.createDirAll output
  let guard ← read lastChecks
  check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
    guard.getObjValD "guardTriggered" == toJson false) "native run was not successful and terminal"
  let mut modules := #[]
  let names := if ranges then ["ReadRangeIndex","SourceReadView","StoredReadLookup","SynapseJournal","ContractAudit"] else
    if prefixMode then ["SynapseJournal","ReplayPreparation","ContractAudit"] else
    if bounds then ["ReplayWork","SynapseJournal","ContractAudit"] else
    if work then ["DB/PageMap","GraphStore","TurnReplay","ReplayWork","UsageCache","SynapseJournal","ContractAudit"]
    else ["TurnReplay","SynapseIndex","UsageCache","SynapseJournal","ContractAudit"]
  for name in names do
    let relative := "Eggshell/" ++ name ++ ".lean"
    let old := parent / relative
    let present ← old.pathExists
    let old := if present then old.toString else "/dev/null"
    let result ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","--label",if present then "a/" ++ relative else "/dev/null",
      "--label","b/" ++ relative,old,(core / relative).toString]}
    check (result.exitCode == 1) "expected an isolated candidate change"
    IO.FS.writeFile (output / (name.replace "/" "_" ++ ".patch")) result.stdout
    modules := modules.push (← artifact (core / relative))
  let mut resources := #[]
  let mut negatives : Array Json := #[]
  let savedNegatives := root / (stem ++ "-negative-builds.json")
  if ← savedNegatives.pathExists then negatives ← IO.ofExcept (fromJson? (← read savedNegatives))
  for entry in ← root.readDir do
    if !entry.fileName.startsWith (stem ++ "-") || !entry.fileName.endsWith ".guard.json" then continue
    let record ← read entry.path
    check (record.getObjValD "state" == toJson "finished") "a native attempt is still running"
    resources := resources.push record
    let stderr := root / (entry.fileName.replace ".guard.json" ".stderr")
    if ← stderr.pathExists then
      let error ← IO.FS.readFile stderr
      if !error.isEmpty then negatives := negatives.push (Json.mkObj [("attempt",toJson entry.fileName),("stderr",toJson error)])
  IO.FS.writeFile (output / "resources.json") (toJson resources).pretty
  IO.FS.writeFile (output / "negative-builds.json") (toJson negatives).pretty
  IO.FS.writeFile (output / "checks.json") (← IO.FS.readFile (native / "result.json"))
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
    ("entryPointDependencies",← read (build / ("tools_research_" ++ entryPoint ++ ".dependencies"))),
    ("build",← read (build / "build.json")),("response",toJson (← IO.FS.readFile (build / "runtime.rsp")))]).pretty
  let helperAxioms ← if ranges then IO.FS.readFile (build / "tools_research_ReadRangeChecks-lean.stdout") else pure ""
  let workAxioms ← if work then IO.FS.readFile (build / "tools_research_ReplayWorkChecks-lean.stdout") else pure ""
  IO.FS.writeFile (output / "audit.json") (Json.mkObj [
    ("contractAudit",toJson (← IO.FS.readFile (build / "Eggshell_ContractAudit-lean.stdout"))),
    ("proofAxioms",toJson (← IO.FS.readFile (build / ("tools_research_" ++ entryPoint ++ "-lean.stdout")))),
    ("rangeProofAxioms",toJson helperAxioms),("replayProofAxioms",toJson workAxioms),
    ("wholeIoCorrectnessProven",toJson false)]).pretty
  IO.FS.writeFile (output / "manifest.json") (Json.mkObj [("candidateModules",toJson modules),
    ("entryPoint",← artifact (core / "tools/research" / (entryPoint ++ ".lean"))),
    ("additionalCheckModules",toJson (← if ranges then do
      pure #[← artifact (core / "tools/research/ReadRangeChecks.lean"),← artifact (core / "tools/research/ReplayWorkChecks.lean")]
      else if work then do pure #[← artifact (core / "tools/research/ReplayWorkChecks.lean")]
      else pure (#[] : Array Json))),
    ("nativeExecutable",← artifact (build / "StudyMain")),("currentProtectedInputs",toJson protectedInputs),
    ("sealedInputs",toJson sealedInputs),("protectedInputsUnchanged",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
  verify
  IO.println "Captured native turn-replay checks, exact input closure, audit, patches and resource guards."
