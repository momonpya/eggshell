import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
import Std.Data.HashMap

open Lean

private def check (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun raw => IO.ofExcept (Json.parse raw)

private def sha (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  check (result.exitCode == 0) "cannot hash integrated input"
  return (result.stdout.splitOn " ").headD ""

private def artifact (path : System.FilePath) : IO Json := do
  return Json.mkObj [("path",toJson path.toString),("sha256",toJson (← sha path)),
    ("bytes",toJson (← path.metadata).byteSize)]

private partial def retire (path : System.FilePath) : IO Nat := do
  let metadata ← path.symlinkMetadata
  if metadata.type == .dir then
    let mut bytes := 0
    for entry in ← path.readDir do bytes := bytes+(← retire entry.path)
    IO.FS.removeDir path
    return bytes
  check (metadata.type == .file || metadata.type == .symlink) "fixture contains a special file"
  IO.FS.removeFile path
  return metadata.byteSize.toNat

private def collect (project root : System.FilePath) (cleanup : Bool) : IO Unit := do
  let resumed ← (root / "integrated-cli-resume.guard.json").pathExists
  let base := if resumed then "integrated-cli-resume" else "integrated-cli-run"
  let mut label := base
  let mut attempt := 2
  while ← (root / (base ++ toString attempt ++ ".guard.json")).pathExists do
    label := base ++ toString attempt
    attempt := attempt+1
  let guard ← read (root / (label ++ ".guard.json"))
  check (guard.getObjValD "state" == toJson "finished") "integrated fixture is still running"
  let fixture := root / (if resumed then "integrated-cli-run-fixture" else label ++ "-fixture")
  let output := project / "docs/candidates/integrated-cli" / label
  let protection ← read (project / "docs/candidates/delivery-ack/manifest.json")
  let protectedInputs : Array (String × String) ← IO.ofExcept (protection.getObjValAs? _ "currentProtectedInputs")
  let sealedInputs : Array Json ← IO.ofExcept (protection.getObjValAs? _ "sealedInputs")
  let verify := do
    for (path,digest) in protectedInputs do check ((← sha (.mk path)) == digest) "protected source changed"
    for row in sealedInputs do
      let path ← IO.ofExcept (row.getObjValAs? String "path")
      check (toJson (← sha (.mk path)) == row.getObjValD "sha256") "sealed comparison input changed"
  verify
  if cleanup then
    check (← (output / "manifest.json").pathExists) "capture integrated evidence before cleanup"
    check (!(← (output / "cleanup.json").pathExists)) "preserve the cleanup record"
    let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
    check (processes.exitCode == 0 && !(processes.stdout.splitOn "\n").any (fun row =>
      row.startsWith (root / "integrated-cli-runtime-build/StudyMain").toString ||
      row.startsWith (root / "integrated-cli-prefix/libexec/eggshell").toString ||
      row.startsWith (root / "integrated-cli-driver-build/StudyMain").toString ||
      (row.splitOn "StudyBuildMain.lean").length > 1)) "integrated product or builder is still live"
    let mut removed := #[]
    if ← fixture.pathExists then removed := removed.push (fixture.toString,← retire fixture)
    let driver := root / "integrated-cli-driver-build/StudyMain"
    if ← driver.pathExists then removed := removed.push (driver.toString,← retire driver)
    let mut logs := 0
    let mut logBytes := 0
    for directory in [root,root / "integrated-cli-runtime-build",root / "integrated-cli-driver-build"] do
      for entry in ← directory.readDir do
        if directory == root && !entry.fileName.startsWith "integrated-cli-" then continue
        if entry.fileName.endsWith ".stdout" || entry.fileName.endsWith ".stderr" then
          logBytes := logBytes+(← retire entry.path)
          logs := logs+1
    verify
    IO.FS.writeFile (output / "cleanup.json") (Json.mkObj [("removed",toJson removed),
      ("removedCompilerAndRunLogs",toJson logs),("removedLogBytes",toJson logBytes),
      ("currentRuntimeAndLinkInputsRetained",toJson true),("protectedInputsUnchanged",toJson true),
      ("archiveCreated",toJson false)]).pretty
    IO.println "Retired integrated fixture, ended driver and raw logs; current product retained."
    return
  check (!(← (output / "manifest.json").pathExists)) "preserve integrated evidence"
  IO.FS.createDirAll output
  let mut resources := #[]
  for entry in ← root.readDir do
    if entry.fileName.startsWith "integrated-cli-" && entry.fileName.endsWith ".guard.json" then
      let record ← read entry.path
      check (record.getObjValD "state" == toJson "finished") "an integrated attempt is still active"
      resources := resources.push record
  IO.FS.writeFile (output / "resources.json") (toJson resources).pretty
  for filename in ["result.json","recovery.json","recall-audit.json","recall-body.txt",
      "recall-required-before-delivery.json","shutdown.json","publisher-shutdown.json",
      "recall-shutdown.json","recall-publisher-shutdown.json","retained-source-audit.json","resume-complete.json"] do
    if ← (fixture / filename).pathExists then IO.FS.writeFile (output / filename) (← IO.FS.readFile (fixture / filename))
  for stage in ["final-warm","recover-warm","recall-warm","recall-hook"] do
    for name in ["stdout","record.json","stderr"] do
      let path := fixture / stage / name
      if ← path.pathExists then IO.FS.writeFile (output / (stage ++ "-" ++ name)) (← IO.FS.readFile path)
  for name in ["warm-after-stop","doctor"] do
    for suffix in ["stdout","stderr","guard.json"] do
      let path := root / ("integrated-cli-" ++ name ++ "." ++ suffix)
      if ← path.pathExists then IO.FS.writeFile (output / (name ++ "." ++ suffix)) (← IO.FS.readFile path)
  let mut timings := #[]
  if ← fixture.pathExists then
    for entry in ← fixture.readDir do
      let record := entry.path / "record.json"
      if (← entry.path.isDir) && (← record.pathExists) then
        timings := timings.push ((← read record).setObjVal! "stage" (toJson entry.fileName))
  IO.FS.writeFile (output / "commands.json") (toJson timings).pretty
  let mut latency := #[]
  for category in ["Pre","Post","Prompt"] do
    let samples := timings.filterMap fun row =>
      let stage := (row.getObjValAs? String "stage").toOption.getD ""
      let selected := if category == "Prompt" then stage == "UserPromptSubmit" || stage == "recall-hook"
        else stage.endsWith ("-" ++ category)
      if selected then (row.getObjValAs? Nat "elapsedMs").toOption else none
    let samples := samples.qsort (· < ·)
    let percentile := fun p : Nat => (samples[(samples.size*p+99)/100-1]?).getD 0
    latency := latency.push (Json.mkObj [("kind",toJson category),("samples",toJson samples.size),
      ("p50Ms",toJson (percentile 50)),("p95Ms",toJson (percentile 95)),
      ("p99Ms",toJson (percentile 99)),("maximumMs",toJson (percentile 100)),
      ("deadlineExceeded",toJson (samples.filter (· ≥ 30000)).size)])
  IO.FS.writeFile (output / "latency.json") (Json.mkObj [("nativeCliCommandWallTime",toJson latency),
    ("sustained80PersonWorkloadValidated",toJson false)]).pretty
  if ← (root / "integrated-cli-negative-builds.json").pathExists then
    IO.FS.writeFile (output / "negative-builds.json") (← IO.FS.readFile (root / "integrated-cli-negative-builds.json"))
  let failure := root / (label ++ ".stderr")
  if ← failure.pathExists then IO.FS.writeFile (output / "run-stderr.txt") (← IO.FS.readFile failure)
  let mut binaries := #[]
  for name in ["runtime","driver"] do
    let build := root / ("integrated-cli-" ++ name ++ "-build")
    let mut objects := #[]
    for line in (← IO.FS.readFile (build / "runtime.rsp")).splitOn "\n" do
      if line.trimAscii.isEmpty then continue
      let path ← IO.ofExcept (Json.parse line >>= Json.getStr?)
      let path := System.FilePath.mk path
      if path.extension != some "o" then continue
      let mut stamps := #[]
      for suffix in ["source","dependencies"] do
        if ← (path.withExtension suffix).pathExists then stamps := stamps.push (← artifact (path.withExtension suffix))
      objects := objects.push ((← artifact path).setObjVal! "inputStamps" (toJson stamps))
    IO.FS.writeFile (output / (name ++ "-inputs.json")) (Json.mkObj [("objects",toJson objects),
      ("build",← read (build / "build.json")),("response",toJson (← IO.FS.readFile (build / "runtime.rsp")))]).pretty
    binaries := binaries.push (← artifact (build / "StudyMain"))
  IO.FS.writeFile (output / "manifest.json") (Json.mkObj [("executables",toJson binaries),
    ("run",guard),("currentProtectedInputs",toJson protectedInputs),("sealedInputs",toJson sealedInputs),
    ("protectedInputsUnchanged",toJson true),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
  verify
  IO.println s!"Captured integrated evidence: {label}"

private def imports (source : String) : Array String :=
  (source.splitOn "\n").toArray.filterMap fun line =>
    let line := line.trimAscii.toString
    let introducer := if line.startsWith "public import " then "public import " else "import "
    if !line.startsWith introducer then none else
      (line.drop introducer.length |>.toString.splitOn " ").find? (! ·.isEmpty)

private partial def copyResearch (project core : System.FilePath) (name : String)
    (seen : IO.Ref (Std.HashSet String)) : IO Unit := do
  unless name.startsWith "tools.research." && !(← seen.get).contains name do return
  seen.modify (·.insert name)
  let relative := name.replace "." "/" ++ ".lean"
  let source ← IO.FS.readFile (project / relative)
  for dependency in imports source do copyResearch project core dependency seen
  let target := core / relative
  IO.FS.createDirAll target.parent.get!
  if ← target.pathExists then
    if (← target.symlinkMetadata).type == .symlink then IO.FS.removeFile target
  IO.FS.writeFile target source

private partial def modules (root path : System.FilePath)
    (found : Std.HashMap String String := {}) : IO (Std.HashMap String String) := do
  let mut found := found
  for entry in ← path.readDir do
    if [".lake",".git","docs","runtime"].contains entry.fileName then continue
    if ← entry.path.isDir then found ← modules root entry.path found
    else if entry.fileName.endsWith ".lean" then
      let relative := ((entry.path.toString.drop (root.toString.length+1)).dropEnd 5).copy
      let name := relative.replace "/" "."
      let key := name.replace "." "_"
      if let some old := found[key]? then check (old == name) "ambiguous native module"
      found := found.insert key name
  return found

private def variant (project root : System.FilePath) (mode family : String) : IO Unit := do
  check (family == "empty-routing" && ["runtime","driver","checks","study","run","checks-run","capture","cleanup"].contains mode)
    "unknown isolated variant action"
  let output := project / "docs/candidates" / family
  let report := root / "integrated-cli-run-fixture" / (family ++ "-recall")
  if mode == "capture" || mode == "cleanup" then
    let protection ← read (project / "docs/candidates/delivery-ack/manifest.json")
    let protectedInputs : Array (String × String) ← IO.ofExcept (protection.getObjValAs? _ "currentProtectedInputs")
    let sealedInputs : Array Json ← IO.ofExcept (protection.getObjValAs? _ "sealedInputs")
    let verify := do
      for (path,digest) in protectedInputs do check ((← sha (.mk path)) == digest) "protected source changed"
      for row in sealedInputs do
        let path ← IO.ofExcept (row.getObjValAs? String "path")
        check (toJson (← sha (.mk path)) == row.getObjValD "sha256") "sealed comparison input changed"
    verify
    let process ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
    check (process.exitCode == 0 && !(process.stdout.splitOn "\n").any (fun row =>
      row.startsWith (root / (family ++ "-runtime-build/StudyMain")).toString ||
      row.startsWith (root / (family ++ "-prefix/libexec/eggshell")).toString ||
      row.startsWith (root / (family ++ "-driver-build/StudyMain")).toString ||
      row.startsWith (root / (family ++ "-checks-build/StudyMain")).toString ||
      (row.splitOn "StudyBuildMain.lean").length > 1)) "variant work is still active"
    if mode == "cleanup" then
      check (← (output / "manifest.json").pathExists) "capture the completed variant first"
      check (!(← (output / "cleanup.json").pathExists)) "preserve the cleanup record"
      let mut removed := #[]
      for relative in [family ++ "-checks-run-data",family ++ "-run-data",
          "integrated-cli-run-fixture","integrated-cli-prefix","integrated-cli-runtime-build/StudyMain",
          "integrated-cli-driver-build/StudyMain",family ++ "-driver-build/StudyMain",family ++ "-checks-build/StudyMain"] do
        let path := root / relative
        if ← path.pathExists then removed := removed.push (path.toString,← retire path)
      let mut logs := 0
      let mut bytes := 0
      for directory in [root,root / "integrated-cli-runtime-build",root / "integrated-cli-driver-build",
          root / (family ++ "-runtime-build"),root / (family ++ "-driver-build"),root / (family ++ "-checks-build")] do
        for entry in ← directory.readDir do
          if directory == root && !entry.fileName.startsWith "integrated-cli-" && !entry.fileName.startsWith (family ++ "-") then continue
          if entry.fileName.endsWith ".stdout" || entry.fileName.endsWith ".stderr" then
            bytes := bytes+(← retire entry.path); logs := logs+1
      verify
      IO.FS.writeFile (output / "cleanup.json") (Json.mkObj [("removed",toJson removed),
        ("removedCompilerAndRunLogs",toJson logs),("removedLogBytes",toJson bytes),
        ("currentRuntimeAndLinkInputsRetained",toJson true),("protectedInputsUnchanged",toJson true),
        ("archiveCreated",toJson false)]).pretty
      IO.println "Retired ended fixtures, old product, driver/check executables and raw logs; current product retained."
      return
    check (!(← (output / "manifest.json").pathExists)) "preserve variant evidence"
    IO.FS.createDirAll output
    let mut resources := #[]
    for entry in ← root.readDir do
      if entry.fileName.startsWith (family ++ "-") && entry.fileName.endsWith ".guard.json" then
        let value ← read entry.path
        check (value.getObjValD "state" == toJson "finished") "a variant task is running"
        resources := resources.push value
    for name in ["run","checks-run"] do
      let guard ← read (root / (family ++ "-" ++ name ++ ".guard.json"))
      check (guard.getObjValD "exitCode" == toJson (0 : Nat) && guard.getObjValD "guardTriggered" == toJson false)
        "qualify successful guarded routing checks and a real hook"
    IO.FS.writeFile (output / "resources.json") (toJson resources).pretty
    IO.FS.writeFile (output / "checks.json") (← IO.FS.readFile (root / (family ++ "-checks-run-data/result.json")))
    for name in ["mechanism.json","input.json","recall-audit.json","recall-body.txt","recall-required-before-delivery.json",
        "recall-shutdown.json","recall-publisher-shutdown.json"] do
      IO.FS.writeFile (output / name) (← IO.FS.readFile (report / name))
    for stage in ["recall-warm","recall-hook"] do
      for name in ["stdout","record.json","stderr"] do
        let path := report / stage / name
        let raw ← IO.FS.readFile path
        if !raw.isEmpty then IO.FS.writeFile (output / (stage ++ "-" ++ name)) raw
    let receipts ← (report / "recall-data/receipts").readDir
    check (receipts.size == 1) "qualify one actual hook"
    let some receipt := receipts[0]? | throw (IO.userError "missing variant receipt")
    IO.FS.createDirAll (output / "receipt")
    for entry in ← receipt.path.readDir do
      if ["request.json","search.json","ack.json","keyed-coverage.json","transport.json","synaptic-delivery.json"].contains entry.fileName ||
          entry.fileName.startsWith "numerical-" then
        IO.FS.writeFile (output / "receipt" / entry.fileName) (← IO.FS.readFile entry.path)
    let delta ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","--label","a/Eggshell/SynapticTopologyStore.lean",
      "--label","b/Eggshell/SynapticTopologyStore.lean",(root / "feedback-progress-core/Eggshell/SynapticTopologyStore.lean").toString,
      (root / (family ++ "-core/Eggshell/SynapticTopologyStore.lean")).toString]}
    check (delta.exitCode == 1) "expected one isolated topology fix"
    IO.FS.writeFile (output / "candidate.patch") delta.stdout
    let mut table : Array Json := #[]
    let mut executables := #[]
    for name in ["runtime","checks","driver"] do
      let build := root / (family ++ "-" ++ name ++ "-build")
      let mut ids : Array Nat := #[]
      for line in (← IO.FS.readFile (build / "runtime.rsp")).splitOn "\n" do
        if line.trimAscii.isEmpty then continue
        let path ← IO.ofExcept (Json.parse line >>= Json.getStr?)
        let path := System.FilePath.mk path
        if path.extension != some "o" then continue
        let mut stamps := #[]
        for suffix in ["source","dependencies"] do
          if ← (path.withExtension suffix).pathExists then stamps := stamps.push (← artifact (path.withExtension suffix))
        let row := (← artifact path).setObjVal! "inputStamps" (toJson stamps)
        let id := (table.findIdx? (· == row)).getD table.size
        if id == table.size then table := table.push row
        ids := ids.push id
      executables := executables.push (Json.mkObj [("kind",toJson name),("executable",← artifact (build / "StudyMain")),
        ("objectIds",toJson ids),("build",← read (build / "build.json"))])
    IO.FS.writeFile (output / "native-inputs.json") (Json.mkObj [("objects",toJson table),("executables",toJson executables)]).pretty
    IO.FS.writeFile (output / "contract-audit.txt")
      (← IO.FS.readFile (root / (family ++ "-checks-build/Eggshell_ContractAudit-lean.stdout")))
    IO.FS.writeFile (output / "manifest.json") (Json.mkObj [("currentProtectedInputs",toJson protectedInputs),
      ("sealedInputsReference",toJson "../delivery-ack/manifest.json"),("executables",toJson (executables.map (·.getObjValD "executable"))),
      ("sourceMatchesPreviousSnapshot",toJson true),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
    verify
    IO.println "Captured empty routing persistence checks and actual semantic/synaptic delivery."
    return
  let core := root / (family ++ "-core")
  let stem := family ++ "-" ++ mode
  let mut attempt := 1
  let labelAt := fun n => stem ++ (if n == 1 then "" else toString n)
  while ← (root / (labelAt attempt ++ ".guard.json")).pathExists do
    let previous ← read (root / (labelAt attempt ++ ".guard.json"))
    check (previous.getObjValD "state" == toJson "finished") "the variant task is still active"
    attempt := attempt+1
  let label := labelAt attempt
  let command : Array String ← if mode == "run" || mode == "checks-run" then do
    let checks := mode == "checks-run"
    let build := root / (family ++ (if checks then "-checks-build" else "-driver-build"))
    let data := root / (label ++ "-data")
    check (!(← data.pathExists)) "use a new isolated private root"
    pure (#["/usr/bin/env","EGGSHELL_DATA_ROOT=" ++ data.toString,"LEAN_NUM_THREADS=1",
      (build / "StudyMain").toString] ++ if checks then
        #[(root / "integrated-cli-run-fixture/work.egg").toString,data.toString]
      else #[root.toString,(root / "integrated-cli-run-fixture").toString,"candidate",family])
  else do
    let runtime := mode == "runtime"
    let parent := if runtime then "integrated-cli-runtime" else family ++ "-runtime"
    let output := root / (stem ++ "-build")
    let entry := if runtime then "Main" else if mode == "study" then "tools.research.StudyMain"
      else if mode == "checks" then "tools.research.EmptyRoutingChecks"
      else "tools.research.IntegratedCliChecks"
    if !runtime then copyResearch project core entry (← IO.mkRef {})
    let inherited ← read (root / (parent ++ "-build.settings.json"))
    let parents : Array String ← IO.ofExcept (inherited.getObjValAs? _ "parents")
    let response := root / (parent ++ "-build/runtime.rsp")
    let known ← modules core core
    let mut mapping := []
    for line in (← IO.FS.readFile response).splitOn "\n" do
      if line.trimAscii.isEmpty then continue
      let path ← IO.ofExcept (Json.parse line >>= Json.getStr?)
      let path := System.FilePath.mk path
      if path.extension == some "o" then
        if let some name := known[path.fileStem.get!]? then mapping := (path.toString,toJson name) :: mapping
    let objectMap := root / (stem ++ "-objects.json")
    IO.FS.writeFile objectMap (Json.mkObj mapping).pretty
    let plan := inherited.setObjVal! "project" (toJson core.toString)
      |>.setObjVal! "core" (toJson core.toString) |>.setObjVal! "output" (toJson output.toString)
      |>.setObjVal! "parents" (toJson (#[ (root / (parent ++ "-build")).toString ] ++ parents))
      |>.setObjVal! "objectModules" (toJson objectMap.toString) |>.setObjVal! "mainModule" (toJson entry)
      |>.setObjVal! "baselineResponse" (toJson response.toString)
      |>.setObjVal! "baselineMain" (toJson (root / (parent ++ "-build/Main.o")).toString)
      |>.setObjVal! "baselineCore" (toJson (if runtime then root / "feedback-progress-core" else core).toString)
      |>.setObjVal! "force" (toJson (#[] : Array String))
    let settings := root / (stem ++ "-build.settings.json")
    IO.FS.writeFile settings plan.pretty
    pure #["/usr/bin/env","LEAN_NUM_THREADS=1","/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean",
      "-M1024","--run",(project / "tools/research/StudyBuildMain.lean").toString,settings.toString]
  let guard ← read (root / "delivery-ack-compile8.settings.json")
  let guard := guard.setObjVal! "record" (toJson (root / (label ++ ".guard.json")).toString)
    |>.setObjVal! "command" (toJson command)
  IO.FS.writeFile (root / (label ++ ".settings.json")) guard.pretty
  IO.println s!"Prepared {label}.settings.json"

def main (args : List String) : IO Unit := do
  if let [mode,family] := args then
    variant (.mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell")
      (.mk "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study") mode family
    return
  let [mode] := args | throw (IO.userError "runtime, driver, or run")
  check (["runtime","driver","run","resume","retire-driver","capture","cleanup","doctor","receipt","compact"].contains mode) "unknown integrated mode"
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
  if mode == "capture" || mode == "cleanup" then return ← collect project root (mode == "cleanup")
  if mode == "compact" then
    let output := project / "docs/candidates/integrated-cli"
    let first := output / "integrated-cli-run"
    let next := output / "integrated-cli-resume"
    check (!(← (output / "record-compaction.json").pathExists)) "preserve the compact record"
    check ((← IO.FS.readFile (first / "runtime-inputs.json")) == (← IO.FS.readFile (next / "runtime-inputs.json")))
      "the runtime inputs differ between phases"
    IO.FS.rename (next / "runtime-inputs.json") (output / "runtime-inputs.json")
    let mut removed := #[]
    for filename in ["runtime-inputs.json","commands.json","resources.json","negative-builds.json"] do
      let old := first / filename
      if filename != "runtime-inputs.json" then
        let older ← IO.ofExcept ((← read old).getArr?)
        let newer ← IO.ofExcept ((← read (next / filename)).getArr?)
        check (older.all newer.contains) "a previous record is not retained in the combined evidence"
      removed := removed.push (old.toString,← retire old)
    for directory in [first,next] do
      for entry in ← directory.readDir do
        if (← entry.path.metadata).type == .file && (← entry.path.metadata).byteSize == 0 then
          removed := removed.push (entry.path.toString,← retire entry.path)
      let manifest ← read (directory / "manifest.json")
      IO.FS.writeFile (directory / "manifest.json") (manifest.setObjVal! "sharedRuntimeInputs"
        (toJson "../runtime-inputs.json") |>.setObjVal! "combinedCommands"
        (toJson "../integrated-cli-resume/commands.json") |>.setObjVal! "combinedResources"
        (toJson "../integrated-cli-resume/resources.json") |>.setObjVal! "negativeBuildRecords"
        (toJson "../integrated-cli-resume/negative-builds.json")).pretty
    IO.FS.writeFile (output / "record-compaction.json") (Json.mkObj [("removed",toJson removed),
      ("identicalRuntimeInputsStoredOnce",toJson true),("allPreviousCommandAndGuardRecordsRetained",toJson true),
      ("sourceDbOrCacheModified",toJson false),("archiveCreated",toJson false)]).pretty
    IO.println "Removed duplicate and empty record files; exact phase evidence retained."
    return
  if mode == "receipt" then
    let receipts := root / "integrated-cli-run-fixture/recall-data/receipts"
    let entries ← receipts.readDir
    check (entries.size == 1) "qualify exactly one new-chat receipt"
    let some entry := entries[0]? | throw (IO.userError "missing qualified receipt")
    let directory := entry.path
    let output := project / "docs/candidates/integrated-cli/integrated-cli-resume/receipt"
    check (!(← output.pathExists)) "preserve the qualified receipt"
    IO.FS.createDirAll output
    for entry in ← directory.readDir do
      if ["request.json","search.json","ack.json","keyed-coverage.json","transport.json",
          "synaptic-delivery.json"].contains entry.fileName || entry.fileName.startsWith "numerical-" then
        IO.FS.writeFile (output / entry.fileName) (← IO.FS.readFile entry.path)
    IO.println "Captured semantic and synaptic receipt evidence separately from delivery recall."
    return
  if mode == "retire-driver" then
    let old := root / "integrated-cli-driver-build/StudyMain"
    let record := project / "docs/candidates/integrated-cli/integrated-cli-run/ended-driver.json"
    check (!(← record.pathExists)) "preserve the ended driver record"
    let process ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
    check (process.exitCode == 0 && !(process.stdout.splitOn "\n").any (·.startsWith old.toString)) "driver is still running"
    let value ← artifact old
    let _ ← retire old
    IO.FS.writeFile record value.pretty
    IO.println "Retired ended driver after capturing its exact native inputs."
    return
  if mode == "doctor" then
    let guard ← read (root / "integrated-cli-warm-after-stop.settings.json")
    let command : Array String ← IO.ofExcept (guard.getObjValAs? _ "command")
    let guard := guard.setObjVal! "record" (toJson (root / "integrated-cli-doctor.guard.json").toString)
      |>.setObjVal! "command" (toJson ((command.extract 0 (command.size-2)).push "doctor"))
    check (!(← (root / "integrated-cli-doctor.guard.json").pathExists)) "preserve the doctor result"
    IO.FS.writeFile (root / "integrated-cli-doctor.settings.json") guard.pretty
    IO.println "Prepared integrated-cli-doctor.settings.json"
    return
  let core := root / "feedback-progress-core"
  let stem := "integrated-cli-" ++ mode
  let negatives := root / "integrated-cli-negative-builds.json"
  let mut failures : Array Json := #[]
  if ← negatives.pathExists then failures ← IO.ofExcept (fromJson? (← read negatives))
  let mut attempt := 1
  let attemptName := fun n => stem ++ (if n == 1 then "" else toString n)
  while ← (root / (attemptName attempt ++ ".guard.json")).pathExists do
    let previous ← read (root / (attemptName attempt ++ ".guard.json"))
    check (previous.getObjValD "state" == toJson "finished") "the integrated task is still running"
    if previous.getObjValD "exitCode" != toJson (0 : Nat) &&
        !failures.any (fun row => row.getObjValD "attempt" == toJson (attemptName attempt)) then
      let output := root / (stem ++ "-build")
      let mut diagnostics : Array (String × String) := #[]
      if ← output.pathExists then
        for entry in ← output.readDir do
          if entry.fileName.endsWith ".stdout" || entry.fileName.endsWith ".stderr" then
            let raw ← IO.FS.readFile entry.path
            if !raw.isEmpty && (entry.fileName.endsWith ".stderr" || (raw.splitOn "error:").length > 1) then
              diagnostics := diagnostics.push (entry.fileName,raw)
      failures := failures.push (Json.mkObj [("attempt",toJson (attemptName attempt)),
        ("guard",previous),("diagnostics",toJson diagnostics)])
    attempt := attempt+1
  IO.FS.writeFile negatives (toJson failures).pretty
  let label := attemptName attempt
  let command ← if mode == "run" || mode == "resume" then do
    check (← (root / "integrated-cli-driver-build/StudyMain").pathExists) "compile the integrated driver first"
    let fixture := root / (if mode == "resume" then "integrated-cli-run-fixture" else label ++ "-fixture")
    check ((← fixture.pathExists) == (mode == "resume")) "fixture presence does not match the requested action"
    pure (#["/usr/bin/env","EGGSHELL_DATA_ROOT=" ++ (fixture / "data").toString,
      "LEAN_NUM_THREADS=1",(root / "integrated-cli-driver-build/StudyMain").toString,
      root.toString,fixture.toString] ++ if mode == "resume" then #["resume-recall"] else #[])
  else do
    let runtime := mode == "runtime"
    let parent := if runtime then "feedback-progress" else "integrated-cli-runtime"
    let output := root / (stem ++ "-build")
    let entry := if runtime then "Main" else "tools.research.IntegratedCliChecks"
    if !runtime then copyResearch project core entry (← IO.mkRef {})
    let inherited ← read (root / (if runtime then "feedback-progress-build.settings.json" else "integrated-cli-runtime-build.settings.json"))
    let parents : Array String ← IO.ofExcept (inherited.getObjValAs? _ "parents")
    let originalResponse := root / (parent ++ "-build/runtime.rsp")
    let mut lines := #[]
    let mut mapping := []
    let known ← modules core core
    let dropped := ["tools_research_FeedbackProgressChecks","tools_research_ReadRangeChecks",
      "tools_research_ReplayWorkChecks","Eggshell_ContractAudit"]
    for line in (← IO.FS.readFile originalResponse).splitOn "\n" do
      if line.trimAscii.isEmpty then continue
      let path ← IO.ofExcept (Json.parse line >>= Json.getStr?)
      let path := System.FilePath.mk path
      if runtime && dropped.contains path.fileStem.get! then continue
      lines := lines.push line
      if path.extension == some "o" then
        if let some name := known[path.fileStem.get!]? then mapping := (path.toString,toJson name) :: mapping
    let response := root / (stem ++ "-base.rsp")
    IO.FS.writeFile response ("\n".intercalate lines.toList ++ "\n")
    let objectMap := root / (stem ++ "-objects.json")
    IO.FS.writeFile objectMap (Json.mkObj mapping).pretty
    let plan := inherited.setObjVal! "project" (toJson core.toString)
      |>.setObjVal! "core" (toJson core.toString)
      |>.setObjVal! "output" (toJson output.toString)
      |>.setObjVal! "parents" (toJson (#[ (root / (parent ++ "-build")).toString ] ++ parents))
      |>.setObjVal! "objectModules" (toJson objectMap.toString)
      |>.setObjVal! "mainModule" (toJson entry)
      |>.setObjVal! "baselineResponse" (toJson response.toString)
      |>.setObjVal! "baselineMain" (toJson (root / (parent ++ "-build") /
        (if runtime then "tools_research_FeedbackProgressChecks.o" else "Main.o")).toString)
      |>.setObjVal! "baselineCore" (toJson core.toString)
      |>.setObjVal! "force" (toJson (#[] : Array String))
    let settings := root / (stem ++ "-build.settings.json")
    IO.FS.writeFile settings plan.pretty
    pure #["/usr/bin/env","LEAN_NUM_THREADS=1","/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean",
      "-M1024","--run",(project / "tools/research/StudyBuildMain.lean").toString,settings.toString]
  let guard ← read (root / "delivery-ack-compile8.settings.json")
  let guard := guard.setObjVal! "record" (toJson (root / (label ++ ".guard.json")).toString)
    |>.setObjVal! "command" (toJson command)
  IO.FS.writeFile (root / (label ++ ".settings.json")) guard.pretty
  IO.println s!"Prepared {label}.settings.json"
