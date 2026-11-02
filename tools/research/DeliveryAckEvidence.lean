import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson

open Lean

private def check (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def sha (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  check (result.exitCode == 0) "cannot inspect evidence input"
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
  check (metadata.type == .file) "refuse a special file in the ended fixture"
  IO.FS.removeFile path
  return metadata.byteSize.toNat

def main (args : List String) : IO Unit := do
  check (args.isEmpty || args == ["cleanup"] || args == ["patches"] ||
    args == ["summarize-retirement"]) "expected capture, cleanup, patches or summarize-retirement"
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
  let output := project / "docs/candidates/delivery-ack"
  let native := root / "delivery-ack-build"
  let old ← read (project / "docs/candidates/frozen-post/manifest.json")
  let protection ← read (output / "obsolete-runtime-retirement.json")
  let protectedInputs : Array (String × String) ← IO.ofExcept (protection.getObjValAs? _ "currentProtectedInputs")
  let sealedInputs : Array Json ← IO.ofExcept (old.getObjValAs? _ "sealedInputs")
  let verify := do
    for (path,digest) in protectedInputs do
      check ((← sha (.mk path)) == digest) "current protected source or runtime changed"
    for entry in sealedInputs do
      let path ← IO.ofExcept (entry.getObjValAs? String "path")
      check (toJson (← sha (.mk path)) == entry.getObjValD "sha256") "sealed model input changed"
  verify
  if args == ["patches"] then
    let manifest ← read (output / "manifest.json")
    let modules : Array Json ← IO.ofExcept (manifest.getObjValAs? _ "candidateModules")
    for entry in modules do
      let path ← IO.ofExcept (entry.getObjValAs? String "path")
      let path := System.FilePath.mk path
      check (toJson (← sha path) == entry.getObjValD "sha256") "tested candidate source changed"
      let name := path.fileName.get!
      let relative := "Eggshell/" ++ name
      let previous := root / "frozen-post-core" / relative
      let previous := if ← previous.pathExists then previous.toString else "/dev/null"
      let result ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0",
        "--label","a/" ++ relative,"--label","b/" ++ relative,previous,path.toString]}
      check (result.exitCode == 1) "tested module has no candidate change"
      IO.FS.writeFile (output / (path.fileStem.get! ++ ".patch")) result.stdout
    IO.println "Exported zero-context patches for the exact native-tested candidate bytes."
    return
  if args == ["summarize-retirement"] then
    for (name,detail) in [("build-page-sharing.json","files"),
        ("current-build-page-sharing.json","files"),("unreachable-build-retirement.json","removed")] do
      let path := output / name
      let original ← read path
      let entries ← IO.ofExcept ((← IO.ofExcept (original.getObjVal? detail)).getArr?)
      let fields ← IO.ofExcept original.getObj?
      let compact := Json.mkObj ((fields.toArray.filter (fun field => field.1 != detail)).toList)
      let compact := compact.setObjVal! "detailCount" (toJson entries.size)
        |>.setObjVal! "originalDetailedRecordSha256" (toJson (← sha path))
        |>.setObjVal! "detailedEntriesRetired" (toJson true)
      IO.FS.writeFile path compact.pretty
    verify
    IO.println "Retired bulky cleanup detail tables; counts, totals, invariants and original record digests retained."
    return
  if args == ["cleanup"] then
    check (← (output / "manifest.json").pathExists) "capture native evidence before cleanup"
    check (!(← (output / "cleanup.json").pathExists)) "preserve the cleanup record"
    let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
    check (processes.exitCode == 0 && !(processes.stdout.splitOn "\n").any
      (fun command => command.startsWith (native / "StudyMain").toString ||
        ((command.splitOn "StudyBuildMain.lean").length > 1))) "native work is still live"
    let mut removed := #[]
    for path in [root / "delivery-ack-native",native / "StudyMain"] do
      let bytes ← retire path
      removed := removed.push (path.toString,bytes)
    for entry in ← root.readDir do
      if entry.fileName.startsWith "delivery-ack-" &&
          (entry.fileName.endsWith ".stdout" || entry.fileName.endsWith ".stderr") then
        removed := removed.push (entry.path.toString,← retire entry.path)
    -- Compiler outputs were retained until the native run and input capture succeeded.
    for entry in ← native.readDir do
      if entry.fileName.endsWith ".stdout" || entry.fileName.endsWith ".stderr" then
        removed := removed.push (entry.path.toString,← retire entry.path)
    verify
    IO.FS.writeFile (output / "cleanup.json") (Json.mkObj [("removed",toJson removed),
      ("protectedInputsUnchanged",toJson true),("objectsInterfacesAndInputStampsRetained",toJson true),
      ("archiveCreated",toJson false)]).pretty
    IO.println "Captured native evidence retained; ended fixture, executable and compiler logs retired."
    return
  check (!(← (output / "manifest.json").pathExists)) "preserve the captured native evidence"
  let core := root / "delivery-ack-core"
  let parent := root / "frozen-post-core"
  let mut modules := #[]
  for name in ["DeliveryLedger","PluginModel","Handoff","PluginHooks","SynapseLive",
      "SynapseJournal","UsageCache","ReplayPreparation","ContractAudit"] do
    let relative := "Eggshell/" ++ name ++ ".lean"
    let previous := parent / relative
    let previous := if ← previous.pathExists then previous.toString else "/dev/null"
    let source := core / relative
    let result ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0",
      "--label","a/" ++ relative,"--label","b/" ++ relative,previous,source.toString]}
    check (result.exitCode == 1 && !result.stdout.isEmpty) "expected an isolated candidate change"
    IO.FS.writeFile (output / (name ++ ".patch")) result.stdout
    modules := modules.push (← artifact source)
  let mut objects := #[]
  for line in (← IO.FS.readFile (native / "shared-runtime.rsp")).splitOn "\n" do
    if line.trimAscii.isEmpty then continue
    let path ← IO.ofExcept (Json.parse line >>= Json.getStr?)
    if !(path.endsWith ".o") then continue
    let path := System.FilePath.mk path
    let mut inputs := #[]
    for suffix in ["source","dependencies"] do
      let input := path.withExtension suffix
      if ← input.pathExists then inputs := inputs.push (← artifact input)
    objects := objects.push ((← artifact path).setObjVal! "inputStamps" (toJson inputs))
  let mut guards := #[]
  let mut failures := #[]
  for name in ["compile","compile2","compile3","compile4","compile5","compile6","compile7","compile8","link","link2","checks"] do
    let base := "delivery-ack-" ++ name
    let guardPath := root / (base ++ ".guard.json")
    if ← guardPath.pathExists then guards := guards.push (← read guardPath)
    let errorPath := root / (base ++ ".stderr")
    if ← errorPath.pathExists then
      let error ← IO.FS.readFile errorPath
      if !error.isEmpty then failures := failures.push (Json.mkObj [("attempt",toJson name),("stderr",toJson error)])
  let checked ← read (root / "delivery-ack-checks.guard.json")
  let linked ← read (root / "delivery-ack-link2.guard.json")
  for guard in [checked,linked] do
    check (guard.getObjValD "state" == toJson "finished" &&
      guard.getObjValD "exitCode" == toJson (0 : Nat) && guard.getObjValD "guardTriggered" == toJson false)
      "capture only a successful terminal native link and run"
  IO.FS.writeFile (output / "checks.json") (← IO.FS.readFile (root / "delivery-ack-native/result.json"))
  IO.FS.writeFile (output / "resources.json") (toJson guards).pretty
  IO.FS.writeFile (output / "negative-builds.json") (toJson failures).pretty
  let audit := native / "Eggshell_ContractAudit-lean.stdout"
  let lines := (← IO.FS.readFile audit).splitOn "\n" |>.filter (! ·.isEmpty)
  check (lines.length > 800 && lines.all (·.startsWith "Audited ")) "full ContractAudit was not captured"
  IO.FS.writeFile (output / "audit.json") (Json.mkObj [("compilerOutput",← artifact audit),
    ("lines",toJson lines),("wholeIoCorrectnessProven",toJson false)]).pretty
  IO.FS.writeFile (output / "native-inputs.json") (Json.mkObj [("objects",toJson objects),
    ("entryPointDependencies",← read (native / "tools_research_DeliveryAckChecks.dependencies")),
    ("response",toJson (← IO.FS.readFile (native / "shared-runtime.rsp"))),
    ("linkSettings",← read (root / "delivery-ack-link2.settings.json"))]).pretty
  IO.FS.writeFile (output / "manifest.json") (Json.mkObj [("candidateModules",toJson modules),
    ("entryPoint",← artifact (core / "tools/research/DeliveryAckChecks.lean")),
    ("nativeExecutable",← artifact (native / "StudyMain")),("currentProtectedInputs",toJson protectedInputs),
    ("sealedInputs",toJson sealedInputs),("protectedInputsUnchanged",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
  verify
  IO.println "Captured isolated ACK implementation, native checks, source closure, audit and terminal guards."
