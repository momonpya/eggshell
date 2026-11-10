import tools.research.StudyLocal
open Lean StudyLocal
def runtimeBuild := base/"current-six/stable-source-rows/build"
def directory := base/"current-six/fixed-sequence"
def reports := project/"docs/candidates/stable-source-rows/sequence"

def frozenImports : IO (Std.HashSet String) := do
  let inputs : Array (String × String) ← IO.ofExcept (fromJson? (← read
    (runtimeBuild/"tools_research_OwnedSelectionRuntime.dependencies")))
  return inputs.foldl (fun names row => names.insert row.1) {}

/-- Freeze current research code against the selected product. Product files
are never taken from the working checkout. Toolchain imports need no copies. -/
partial def controllerSources (destination : System.FilePath) (name : String)
    (seen : IO.Ref (Array String)) (fixed : Std.HashSet String) : IO Unit := do
  if (← seen.get).contains name then return
  seen.modify (·.push name)
  let relative := name.replace "." "/"++".lean"
  let target := destination/relative
  let current := project/relative
  if fixed.contains name then
    let original := runtimeBuild.parent.get!/"source"/relative
    if !(← original.pathExists) then
      check (!(← current.pathExists)) ("missing frozen project input: "++name)
      return
    IO.FS.createDirAll target.parent.get!
    IO.FS.writeFile target (← IO.FS.readFile original)
  else if name.startsWith "tools.research." then
    check (← current.pathExists) ("missing research source: "++name)
    IO.FS.createDirAll target.parent.get!
    IO.FS.writeFile target (← IO.FS.readFile current)
  if !(← target.pathExists) then
    check (!(← current.pathExists)) ("product source absent from frozen runtime: "++name)
    return
  for line in (← IO.FS.readFile target).splitOn "\n" do
    let row := line.trimAscii.toString
    let introducer := if row.startsWith "public import " then "public import " else "import "
    if row.startsWith introducer then
      for dependency in (row.drop introducer.length).toString.splitOn " " do
        if !dependency.isEmpty then controllerSources destination dependency seen fixed

/-- Move a private copy of complete object/interface pairs. Rename replaces
owned symlinks instead of writing through them into frozen parent libraries. -/
partial def mergeCache (source target : System.FilePath) : IO Unit := do
  let info := (← source.symlinkMetadata).type
  if info == .dir then
    let previous ← try pure (some (← target.symlinkMetadata).type) catch _ => pure none
    if previous == some .symlink then IO.FS.removeFile target
    IO.FS.createDirAll target
    for entry in ← source.readDir do mergeCache entry.path (target/entry.fileName)
    IO.FS.removeDir source
  else
    check (info == .file) "local cache seed contains an unexpected link"
    IO.FS.rename source target

def prepareSources : IO Unit := do
  let seen ← IO.mkRef #[]
  controllerSources (directory/"controller-source") "tools.research.StudyMain" seen (← frozenImports)
  let entry := directory/"controller-source/tools/research/StudyMain.lean"
  IO.FS.writeFile entry ("import Eggshell.ContractAudit\nimport Eggshell.Setup\n"++(← IO.FS.readFile entry))

def checkedController : IO Unit := do
  discard <| finished "fixed-sequence-controller-audit"
  let audit ← read (reports/"sources.json")
  check (audit.getObjValD "allProductCorePresent" == toJson true &&
    audit.getObjValD "commonSourcesUnchanged" == toJson true &&
    audit.getObjValD "auditorSha256" == toJson (← hash (directory/"controller-build/StudyMain")) &&
    audit.getObjValD "productSha256" == toJson (← hash (runtimeBuild/"StudyMain")))
    "current controller has no complete linker-based product-source audit"

partial def excludesLinks (root retired : System.FilePath) : IO Unit := do
  for entry in ← root.readDir do
    let kind := (← entry.path.symlinkMetadata).type
    if kind == .dir then excludesLinks entry.path retired
    else if kind == .symlink then
      let target ← IO.FS.realPath entry.path
      check (!(target.toString.startsWith (retired.toString++"/"))) "current library depends on the ended cohort"

def main (args : List String) : IO Unit := do
  if args == ["controller"] then
    idle
    check ((← hash (runtimeBuild/"StudyMain")) == "dd53c89bc450b66b58dd57d104ccbc82f32ca6345fa9666125e7feb03017000e")
      "selected product runtime changed"
    let source := directory/"controller-source"
    materialize runtimeBuild source (directory/"controller-build")
      "tools.research.StudyMain" "fixed-sequence-controller-settings.json"
    prepareSources
    for relative in #["docs/benchmarks/reseed-delivery-contract.json","docs/benchmarks/llvm-three-topics.json",
        "docs/benchmarks/readme-memory-facts.json","tools/research/StudyBuildMain.lean"] do
      IO.FS.createDirAll (source/relative).parent.get!
      IO.FS.writeFile (source/relative) (← IO.FS.readFile (project/relative))
    IO.FS.createDirAll reports
    write (reports/"plan.json") (Json.mkObj [
      ("runtimeSha256",toJson (← hash (runtimeBuild/"StudyMain"))),
      ("frozenRuntimeInputs",toJson (← frozenImports).size),("completeSequence",toJson "new seed;1,2,3;1,2,3"),
      ("model",toJson "gpt-5.6-luna"),("effort",toJson "xhigh"),
      ("beforePaidSeed",toJson "native whole-product dependency/source audit; native lifecycle/recovery; actual read-row replay; six-stage controller checks"),
      ("newProductChanges",toJson false),("adopted",toJson false)])
    guard "fixed-sequence-controller-build" #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(base/"fixed-sequence-controller-settings.json").toString]
  else if args == ["repair-controller"] then
    idle
    let closed ← read (base/"fixed-sequence-controller-build.guard.json")
    check (closed.getObjValD "state" == toJson "finished" &&
      closed.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "previous controller build is still live"
    write (reports/"product-helper-overwrite-failure.json") closed
    prepareSources
    let cache := directory/"local-cache-seed"
    copyLocalArtifacts runtimeBuild cache
    mergeCache cache (directory/"controller-build")
    guard "fixed-sequence-controller-repair" #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(base/"fixed-sequence-controller-settings.json").toString]
  else if args == ["audit"] then
    discard <| finished "fixed-sequence-controller-final"
    guard "fixed-sequence-controller-audit" #["/usr/bin/env","LEAN_PATH="++(base/"study-local-lib").toString,
      (compiler/"bin/lean").toString,"-j1","-M1536","--run",(project/"tools/research/FixedSequenceStudy.lean").toString,"audit-worker"]
  else if args == ["audit-worker"] then
    let audit := fun arguments => command (compiler/"bin/lean").toString
      (#["-j1","-M1536","--run",(project/"tools/research/StudyBuildClosureAudit.lean").toString]++arguments)
    discard <| audit #["inspect",(directory/"controller-build").toString,(reports/"native.json").toString]
    discard <| audit #["common-sources",runtimeBuild.toString,(directory/"controller-build").toString,
      (reports/"sources.json").toString]
  else if args == ["complete-controller"] then
    idle
    let closed ← read (base/"fixed-sequence-controller-repair.guard.json")
    check (closed.getObjValD "state" == toJson "finished" &&
      closed.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "previous compiler is still active"
    write (reports/"recorded-run-syntax-failure.json") closed
    prepareSources
    guard "fixed-sequence-controller-complete" #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(base/"fixed-sequence-controller-settings.json").toString]
  else if args == ["final-controller"] then
    let closed ← read (base/"fixed-sequence-controller-complete.guard.json")
    check (closed.getObjValD "state" == toJson "finished" &&
      closed.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "previous compiler remains active"
    prepareSources
    guard "fixed-sequence-controller-final" #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(base/"fixed-sequence-controller-settings.json").toString]
  else if args == ["install"] then
    idle
    checkedController
    let cohort := directory/"cohort"
    let runner := directory/"controller-build/StudyMain"
    discard <| command "/usr/bin/env" #["EGGSHELL_STUDY_AUTH_FILE=/Users/ovm/.codex/auth.json",
      runner.toString,"bootstrap","prepare",cohort.toString,base.toString,(runtimeBuild/"StudyMain").toString]
    let invoke := fun arguments => command "/usr/bin/env"
      (#["CODEX_HOME="++(cohort/"account").toString,"/Users/ovm/.nodebrew/current/bin/codex"]++arguments)
    IO.FS.writeFile (cohort/"marketplace-add.json") (← invoke #["plugin","marketplace","add",(cohort/"prefix").toString,"--json"])
    IO.FS.writeFile (cohort/"plugin-add.json") (← invoke #["plugin","add","eggshell@eggshell","--json"])
    guard "fixed-sequence-discovery" #[runner.toString,"probe",(cohort/"discovery.input.json").toString]
  else if args == ["gate"] then
    discard <| finished "fixed-sequence-discovery"
    checkedController
    let cohort := directory/"cohort"
    let runner := directory/"controller-build/StudyMain"
    let models ← IO.ofExcept ((← read (cohort/"discovery/models.json")).getObjValAs? (Array Json) "data")
    check (models.any fun row => row.getObjValD "model" == toJson "gpt-5.6-luna" &&
      ((row.getObjValD "supportedReasoningEfforts").getArr?.toOption.getD #[]).any
        (fun effort => effort.getObjValD "reasoningEffort" == toJson "xhigh")) "required model and effort are unavailable"
    discard <| command runner.toString #["bootstrap","trust-hooks",cohort.toString]
    discard <| command runner.toString #["bootstrap","seed-input",cohort.toString,"500000"]
    let input ← read (cohort/"native-gate-input.json")
    let environment : Array (String × Option String) ← IO.ofExcept (fromJson? (input.getObjValD "environment"))
    let unset := environment.filterMap fun (key,value) => if value.isNone then some key else none
    let assignments := environment.filterMap fun (key,value) => value.map (key++"="++·)
    write (cohort/"native-gate.settings.json") (Json.mkObj [
      ("command",toJson (#["/usr/bin/env"]++unset.flatMap (fun key => #["-u",key])++assignments++
        #[runner.toString,"seed-checks-generic",(cohort/"native-gate-input.json").toString,(cohort/"native-gate").toString])),
      ("cwd",toJson project.toString),("record",toJson (cohort/"native-gate.guard.json").toString),
      ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (4358524 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])
  else if args == ["controller-checks"] then
    checkedController
    let original := base/"current-six/located-study/cohort/study/seed-auth-retry"
    guard "fixed-sequence-controller-checks" #[(directory/"controller-build/StudyMain").toString,
      "stage-close-checks",(original/"rpc/exchange.jsonl").toString,original.toString,(directory/"controller-checks").toString]
  else if args == ["source-replay"] then
    checkedController
    let original := base/"current-six/located-study/cohort/study/seed-auth-retry"
    let thread ← read (original/"thread.json")
    let session ← IO.ofExcept ((thread.getObjValD "thread").getObjValAs? String "id")
    guard "fixed-sequence-source-replay" #["/usr/bin/env","EGGSHELL_DATA_ROOT="++(original/"data").toString,
      (directory/"controller-build/StudyMain").toString,"source-row-replay",(original/"work.egg").toString,
      (original/"data/sessions"/session/"checkpoints").toString,(directory/"source-replay").toString]
  else if args == ["record-and-retire"] then
    idle
    checkedController
    let checks ← finished "fixed-sequence-controller-checks"
    let replay ← finished "fixed-sequence-source-replay"
    let cohort := directory/"cohort"
    let gate ← read (cohort/"native-gate.guard.json")
    check (gate.getObjValD "state" == toJson "finished" && gate.getObjValD "exitCode" == toJson (0 : Nat) &&
      gate.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "new native lifecycle is incomplete"
    write (reports/"controller-checks.json") (← read (directory/"controller-checks/result.json"))
    write (reports/"controller-checks-guard.json") checks
    write (reports/"source-replay.json") (← read (directory/"source-replay/result.json"))
    write (reports/"source-replay-guard.json") replay
    write (reports/"native-gate.json") (← read (cohort/"native-gate/result.json"))
    write (reports/"native-gate-guard.json") gate
    write (reports/"readonly-delivery.json") (← read (cohort/"native-gate/recall-audit.json"))
    let old := base/"current-six/located-study"
    let builds := #[runtimeBuild,directory/"controller-build",base/"owned-selection-runtime-build"]
    for build in builds do
      check (!((← IO.FS.readFile (build/"runtime.rsp")).contains (old.toString++"/")))
        "current native link depends on ended cohort objects"
      excludesLinks (build/"lib") old
    let keep := #[runtimeBuild/"StudyMain",directory/"controller-build/StudyMain",
      base/"owned-selection-runtime-build/StudyMain",cohort/"native-gate/result.json"]
    let before ← keep.mapM fun path => return (path.toString,← hash path)
    let mut removed := #[]
    for path in #[old,directory/"source-replay"] do
      if ← path.pathExists then
        IO.FS.removeDirAll path
        removed := removed.push path.toString
    for path in #[base/"current-six/located-runtime-build/StudyMain",base/"controller/StudyMain"] do
      if ← path.pathExists then
        IO.FS.removeFile path
        removed := removed.push path.toString
    let after ← keep.mapM fun path => return (path.toString,← hash path)
    check (before == after) "selected runtime, controller or gate changed during cleanup"
    write (reports/"cleanup.json") (Json.mkObj [("removed",toJson removed),("protected",toJson after),
      ("archiveCreated",toJson false),("endedModelDatabaseRetainedForRecords",toJson false)])
  else if args == ["seal-seed"] then
    idle
    checkedController
    discard <| finished "fixed-sequence-controller-checks"
    discard <| finished "fixed-sequence-source-replay"
    let cohort := directory/"cohort"
    let gate ← read (cohort/"native-gate.guard.json")
    check (gate.getObjValD "state" == toJson "finished" && gate.getObjValD "exitCode" == toJson (0 : Nat) &&
      gate.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "native lifecycle has not passed"
    discard <| command (directory/"controller-build/StudyMain").toString #["bootstrap","seal-seed",cohort.toString]
    let path := cohort/"seed-1.settings.json"
    let settings ← read path
    write path (settings.setObjVal! "limitRssKiB" (toJson (4358524 : Nat))
      |>.setObjVal! "ownedPrefixes" (toJson #[base.toString]))
    let plan ← read (cohort/"seed-1.plan.json")
    write (reports/"frozen-seed.json") (Json.mkObj (["runtime","runner","model","effort","handoffChars","prompt","sourceCommit"].map
      (fun name => (name,plan.getObjValD name))++[("limits",← read (cohort/"seed-1.limits.json")),
        ("newEmptyDatabase",toJson true),("adopted",toJson false)]))
  else if args == ["align-contract"] then
    idle
    checkedController
    let cohort := directory/"cohort"
    let path := cohort/"seed-1.plan.json"
    let plan ← read path
    let output ← IO.ofExcept (plan.getObjValAs? String "output")
    check (!(← (System.FilePath.mk output).pathExists)) "contract must be fixed before generation"
    let oldDigest ← hash path
    let original ← read (project/"docs/benchmarks/reseed-delivery-contract.json")
    let entries := (← IO.ofExcept original.getObj?).toArray.toList.filter
      (fun row => row.1 != "maximumMissingRequiredMemoryAcrossAllSixStages")
    let contract := (Json.mkObj entries).setObjVal! "runtimeSha256" (toJson (← hash (runtimeBuild/"StudyMain")))
      |>.setObjVal! "aggregateMemoryCeilingBytes" (toJson (5000000000 : Nat))
      |>.setObjVal! "aggregateMemoryStopKiB" (toJson (4358524 : Nat))
      |>.setObjVal! "minimumOriginalEvidenceDeliveryPercent" (toJson (98 : Nat))
      |>.setObjVal! "localMaximumConcurrentClients" (toJson (16 : Nat))
      |>.setObjVal! "pilotRepetitionsPerCell" (toJson (1 : Nat))
      |>.setObjVal! "pilotAuthorizesAdoption" (toJson false)
    let frozen := directory/"controller-source/docs/benchmarks/reseed-delivery-contract.json"
    write (project/"docs/benchmarks/reseed-delivery-contract.json") contract
    write frozen contract
    let digest ← hash frozen
    let harness ← IO.ofExcept (plan.getObjValAs? (Array Json) "harness")
    check ((harness.filter (fun row => row.getObjValD "path" == toJson frozen.toString)).size == 1)
      "sealed contract artifact is absent or duplicated"
    let harness := harness.map fun row => if row.getObjValD "path" == toJson frozen.toString then
      row.setObjVal! "sha256" (toJson digest) else row
    write path (plan.setObjVal! "harness" (toJson harness))
    let settingsPath := cohort/"seed-1.settings.json"
    let settings ← read settingsPath
    let arguments ← IO.ofExcept (settings.getObjValAs? (Array String) "command")
    check (arguments.size == 6 && arguments[2]! == path.toString) "sealed acquisition command differs"
    write settingsPath (settings.setObjVal! "command" (toJson (arguments.set! 3 (← hash path))))
    write (reports/"contract-alignment.json") (Json.mkObj [
      ("previousPlanSha256",toJson oldDigest),("planSha256",toJson (← hash path)),
      ("contractSha256",toJson digest),("beforeGeneration",toJson true),
      ("runtimeAndControllerChanged",toJson false),("pilotAuthorizesAdoption",toJson false)])
  else if args == ["finish-seed"] then
    idle
    checkedController
    let cohort := directory/"cohort"
    let acquired := cohort/"study/seed-1"
    let monitor ← read (cohort/"seed-1.guard.json")
    let result ← read (acquired/"result.json")
    check (monitor.getObjValD "state" == toJson "finished" && monitor.getObjValD "exitCode" == toJson (0 : Nat) &&
      monitor.getObjValD "ownedPids" == toJson (#[] : Array Nat) && result.getObjValD "completed" == toJson true)
      "generation and owned cleanup must complete before source finalization"
    write (reports/"seed-generation.json") result
    write (reports/"seed-generation-guard.json") monitor
    guard "fixed-sequence-seed-finalize" #["/usr/bin/env","EGGSHELL_DATA_ROOT="++(acquired/"data").toString,
      (directory/"controller-build/StudyMain").toString,"seed-finalize",acquired.toString,(cohort/"seed-ready").toString]
  else if args == ["audit-seed"] then
    discard <| finished "fixed-sequence-seed-finalize"
    let cohort := directory/"cohort"
    let acquired := cohort/"study/seed-1"
    let definitions := reports/"task-definitions.json"
    check (!(← definitions.pathExists)) "keep the frozen task definitions"
    IO.FS.writeFile definitions (← IO.FS.readFile (base.parent.get!/"task-definitions.json"))
    guard "fixed-sequence-seed-audit" #["/usr/bin/env","EGGSHELL_DATA_ROOT="++(acquired/"data").toString,
      (directory/"controller-build/StudyMain").toString,"seed-audit",acquired.toString,definitions.toString,
      (cohort/"seed-ready/ready.egg").toString,(cohort/"seed-source-audit.json").toString]
  else if args == ["read-seed"] then
    discard <| finished "fixed-sequence-seed-audit"
    let cohort := directory/"cohort"
    let plan ← read (cohort/"seed-1.plan.json")
    let workspace ← IO.ofExcept (plan.getObjValAs? String "workspace")
    guard "fixed-sequence-seed-read" #[(directory/"controller-build/StudyMain").toString,"read-coverage",
      (cohort/"seed-ready/ready.egg").toString,workspace,(reports/"task-definitions.json").toString,
      (cohort/"seed-read-coverage.json").toString]
  else if args == ["history-seed"] then
    discard <| finished "fixed-sequence-seed-read"
    let cohort := directory/"cohort"
    guard "fixed-sequence-seed-history" #[(directory/"controller-build/StudyMain").toString,"history","freeze",
      (cohort/"study/seed-1/work.egg").toString,(cohort/"study/seed-1/data").toString,(cohort/"seed-history").toString]
  else throw (IO.userError "controller/audit required")
