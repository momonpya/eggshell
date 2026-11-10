import tools.research.StudyLocal
open Lean StudyLocal
def runtimeBuild := base/"current-six/stable-source-rows/build"
def directory := base/"current-six/fixed-sequence"
def reports := project/"docs/candidates/stable-source-rows/sequence"

def selectedSeed : IO String := do
  let path := directory/"cohort/selected-seed.json"
  if !(← path.pathExists) then return "seed-1"
  let selection ← read path
  let name ← IO.ofExcept (selection.getObjValAs? String "name")
  check (#["seed-2","seed-3"].contains name) "unexpected acquisition selection"
  return name

def seedPreparation : IO (System.FilePath × String) := do
  let path := directory/"cohort/selected-ready.json"
  if !(← path.pathExists) then return (directory/"cohort/seed-ready","fixed-sequence-seed-finalize")
  let selection ← read path
  let name ← IO.ofExcept (selection.getObjValAs? String "directory")
  let tag ← IO.ofExcept (selection.getObjValAs? String "guardTag")
  check (name == (directory/"cohort/seed-ready-resumed").toString &&
    tag == "fixed-sequence-seed-finalize-resumed") "unexpected seed preparation selection"
  return (.mk name,tag)

def preparationExecutor : IO String := do
  let selection := directory/"cohort/preparation-runner.json"
  if !(← selection.pathExists) then return (directory/"controller-build/StudyMain").toString
  let selected ← read selection
  let path ← IO.ofExcept (selected.getObjValAs? String "path")
  let audit ← IO.ofExcept (selected.getObjValAs? String "sourceAudit")
  check (#[directory/"preparation-build/StudyMain",directory/"preparation-history-build/StudyMain",
      directory/"preparation-closure-build/StudyMain"].any
      (fun allowed => path == allowed.toString) &&
    selected.getObjValD "sha256" == toJson (← hash (.mk path)) &&
    selected.getObjValD "sourceAuditSha256" == toJson (← hash (.mk audit))) "preparation executor changed"
  return path

def stagePreparationTag (number : Nat) : IO String := do
  if number == 2 && (← (directory/"cohort/preparation-runner.json").pathExists) then
    if #[(directory/"preparation-history-build/StudyMain").toString,
        (directory/"preparation-closure-build/StudyMain").toString].contains (← preparationExecutor) then
      return "fixed-sequence-stage-2-prepare-history"
    return "fixed-sequence-stage-2-prepare-resumed"
  return s!"fixed-sequence-stage-{number}-prepare"

def stageClosureTag (number : Nat) : IO String := do
  if number == 2 && (← preparationExecutor) == (directory/"preparation-closure-build/StudyMain").toString then
    return "fixed-sequence-stage-2-close-delegated"
  return s!"fixed-sequence-stage-{number}-close"

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

def waitGuard (path : System.FilePath) : IO Unit := do
  let deadline := (← IO.monoMsNow)+1200000
  repeat
    let record ← read path
    if record.getObjValD "state" == toJson "finished" then
      check (record.getObjValD "exitCode" == toJson (0 : Nat) &&
        record.getObjValD "ownedPids" == toJson (#[] : Array Nat))
        ("recorded step failed; no automatic retry: "++path.toString)
      return
    check (record.getObjValD "state" == toJson "running" && (← IO.monoMsNow) < deadline)
      "native monitor did not finish; inspect the owned process before any new step"
    IO.sleep 1000

def runGuardOnce (path : System.FilePath) : IO Unit := do
  let settings ← read path
  let record ← IO.ofExcept (settings.getObjValAs? String "record")
  if !(← (System.FilePath.mk record).pathExists) then
    discard <| command (directory/"controller-build/StudyMain").toString #["guard",path.toString]
  waitGuard (.mk record)

def receipt (path : System.FilePath) : IO Json :=
  return Json.mkObj [("path",toJson path.toString),("sha256",toJson (← hash path))]

def sealedJson (path : System.FilePath) (value : Json) : IO Unit := do
  if ← path.pathExists then check ((← read path) == value) "keep the existing continuation declaration"
  else write path value

/-- Reusing a completed fresh control does not create another independent
repetition. Only labels and output/guard destinations may differ. -/
def freshConditions (plan : Json) : Json :=
  #["label","output","guardRecord"].foldl (fun row field => row.setObjVal! field Json.null) plan

def freshArm (prepared : Json) : IO Json := do
  let rows ← IO.ofExcept (prepared.getObjValAs? (Array Json) "arms")
  let some row := rows.find? (fun row => row.getObjValD "arm" == toJson "fresh") |
    throw (IO.userError "fresh control is absent")
  return row

def checkedJsonArtifact (value : Json) : IO Json := do
  let path ← IO.ofExcept (value.getObjValAs? String "path")
  check (value.getObjValD "sha256" == toJson (← hash (.mk path))) "sealed artifact changed"
  read (.mk path)

partial def main (args : List String) : IO Unit := do
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
  else if args == ["retry-disk-stopped-seed"] then
    idle
    checkedController
    let cohort := directory/"cohort"
    let failed ← read (reports/"disk-stopped-seed.json")
    check (failed.getObjValD "accepted" == toJson false &&
      failed.getObjValD "reason" == toJson "disk-space") "account for the previous attempt first"
    discard <| read (reports/"capacity-cleanup.json")
    let fields := ((← command "/bin/df" #["-k",base.toString]).splitOn "\n")[1]!
      |>.splitOn " " |>.filter (!·.isEmpty)
    let some available := fields[3]!.toNat? | throw (IO.userError "cannot read available capacity")
    check (available ≥ 5242880) "at least 5 GiB free is required before repeating this acquisition"
    let planPath := cohort/"seed-2.plan.json"
    check (!(← planPath.pathExists) && !(← (cohort/"study/seed-2").pathExists)) "preserve the next acquisition"
    let plan := (← read (cohort/"seed-1.plan.json"))
      |>.setObjVal! "label" (toJson "new-native-seed-2")
      |>.setObjVal! "output" (toJson (cohort/"study/seed-2").toString)
      |>.setObjVal! "guardRecord" (toJson (cohort/"seed-2.guard.json").toString)
    write planPath plan
    let limits := cohort/"seed-1.limits.json"
    write (cohort/"seed-2.settings.json") (Json.mkObj [
      ("command",toJson #[(directory/"controller-build/StudyMain").toString,"acquire-bounded",
        planPath.toString,← hash planPath,limits.toString,← hash limits]),
      ("cwd",toJson cohort.toString),("record",toJson (cohort/"seed-2.guard.json").toString),
      ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (4358524 : Nat)),
      ("minFreeKiB",toJson (2097152 : Nat))])
    write (cohort/"selected-seed.json") (Json.mkObj [
      ("name",toJson "seed-2"),("failedAttempt",toJson (reports/"disk-stopped-seed.json").toString),
      ("sameRuntimeAndHarness",toJson true),("availableKiBBeforeRetry",toJson available),
      ("runtime",plan.getObjValD "runtime"),("runner",plan.getObjValD "runner"),
      ("planSha256",toJson (← hash planPath)),("adopted",toJson false)])
  else if args == ["retry-isolated-seed"] then
    idle
    checkedController
    discard <| finished "fixed-sequence-isolated-hooks"
    let cohort := directory/"cohort"
    let groups ← IO.ofExcept ((← read (cohort/"discovery-isolated/hooks.json")).getObjValAs? (Array Json) "data")
    let mut count := 0
    for group in groups do
      for hook in ← IO.ofExcept (group.getObjValAs? (Array Json) "hooks") do
        check (hook.getObjValD "pluginId" == toJson "eggshell@eggshell" &&
          hook.getObjValD "enabled" == toJson true && hook.getObjValD "trustStatus" == toJson "trusted")
          "only the selected native hooks may run"
        count := count+1
    check (count == 8) "expected eight selected hooks"
    let config := cohort/"account/config.toml"
    let correction ← read (reports/"duplicate-hook-admission.json")
    check (correction.getObjValD "generationRequests" == toJson (0 : Nat) &&
      correction.getObjValD "configurationSha256" == toJson (← hash config))
      "unsealed plugin-isolation correction"
    let planPath := cohort/"seed-3.plan.json"
    check (!(← planPath.pathExists)) "keep previous acquisition attempts"
    let plan := (← read (cohort/"seed-2.plan.json"))
      |>.setObjVal! "label" (toJson "new-native-seed-3")
      |>.setObjVal! "output" (toJson (cohort/"study/seed-3").toString)
      |>.setObjVal! "guardRecord" (toJson (cohort/"seed-3.guard.json").toString)
      |>.setObjVal! "accountConfiguration" (Json.mkObj [
        ("path",toJson config.toString),("sha256",toJson (← hash config))])
    let fields := ((← command "/bin/df" #["-k",base.toString]).splitOn "\n")[1]!
      |>.splitOn " " |>.filter (!·.isEmpty)
    let some available := fields[3]!.toNat? | throw (IO.userError "cannot read available capacity")
    check (available ≥ 5242880) "at least 5 GiB free is required before this acquisition"
    write planPath plan
    let limits := cohort/"seed-1.limits.json"
    write (cohort/"seed-3.settings.json") (Json.mkObj [
      ("command",toJson #[(directory/"controller-build/StudyMain").toString,"acquire-bounded",
        planPath.toString,← hash planPath,limits.toString,← hash limits]),
      ("cwd",toJson cohort.toString),("record",toJson (cohort/"seed-3.guard.json").toString),
      ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (4358524 : Nat)),
      ("minFreeKiB",toJson (2097152 : Nat))])
    write (reports/"selected-seed-disk-retry.json") (← read (cohort/"selected-seed.json"))
    let selection := Json.mkObj [
      ("name",toJson "seed-3"),("unselectedHooksDisabledBeforeGeneration",toJson true),
      ("modelRuntimePromptEffortLimitsUnchanged",toJson true),
      ("runtime",plan.getObjValD "runtime"),("runner",plan.getObjValD "runner"),
      ("availableKiBBeforeRetry",toJson available),("planSha256",toJson (← hash planPath)),
      ("adopted",toJson false)]
    write (cohort/"selected-seed.json") selection
    write (reports/"selected-seed.json") selection
  else if args == ["finish-seed"] then
    idle
    checkedController
    let cohort := directory/"cohort"
    let name ← selectedSeed
    let acquired := cohort/"study"/name
    let monitor ← read (cohort/(name++".guard.json"))
    let result ← read (acquired/"result.json")
    check (monitor.getObjValD "state" == toJson "finished" && monitor.getObjValD "exitCode" == toJson (0 : Nat) &&
      monitor.getObjValD "ownedPids" == toJson (#[] : Array Nat) && result.getObjValD "completed" == toJson true)
      "generation and owned cleanup must complete before source finalization"
    write (reports/"seed-generation.json") result
    write (reports/"seed-generation-guard.json") monitor
    guard "fixed-sequence-seed-finalize" #["/usr/bin/env","EGGSHELL_DATA_ROOT="++(acquired/"data").toString,
      (directory/"controller-build/StudyMain").toString,"seed-finalize",acquired.toString,(cohort/"seed-ready").toString]
  else if args == ["finish-seed-after-replay"] then
    idle
    checkedController
    let monitor ← finished "fixed-sequence-persistent-replay"
    let cohort := directory/"cohort"
    let replies := ((← IO.FS.readFile (cohort/"persistent-replay/stdout.jsonl")).splitOn "\n").filter (!·.isEmpty)
    check (replies.length == 1) "record every replay response before continuing"
    let replay ← IO.ofExcept (Json.parse replies.head!)
    check (replay.getObjValD "complete" == toJson true && replay.getObjValD "pending" == toJson (0 : Nat))
      "native replay is incomplete"
    let failed ← read (base/"fixed-sequence-seed-finalize.guard.json")
    check (failed.getObjValD "state" == toJson "finished" && failed.getObjValD "exitCode" == toJson (1 : Nat) &&
      failed.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "previous finalization is not retired"
    let previous ← IO.ofExcept (Json.parse (← IO.FS.readFile (cohort/"seed-ready/finish-replay/step-0/stdout")))
    write (reports/"native-replay-recovery.json") (Json.mkObj [
      ("previousGuard",failed),("previousReplay",previous),("replay",replay),("guard",monitor),
      ("workerRequests",toJson replies.length),("continuationResumeDemonstrated",toJson false),
      ("modelCalls",toJson (0 : Nat)),("runtimeChanged",toJson false),
      ("earlierIncompleteReplyWasNotProofOfMissingInput",toJson true)])
    let target := cohort/"seed-ready-resumed"
    write (cohort/"selected-ready.json") (Json.mkObj [
      ("directory",toJson target.toString),("guardTag",toJson "fixed-sequence-seed-finalize-resumed")])
    let acquired := cohort/"study"/(← selectedSeed)
    guard "fixed-sequence-seed-finalize-resumed" #["/usr/bin/env","EGGSHELL_DATA_ROOT="++(acquired/"data").toString,
      (directory/"controller-build/StudyMain").toString,"seed-finalize",acquired.toString,target.toString]
  else if args == ["audit-seed"] then
    let (ready,tag) ← seedPreparation
    discard <| finished tag
    let cohort := directory/"cohort"
    let acquired := cohort/"study"/(← selectedSeed)
    let definitions := reports/"task-definitions.json"
    check (!(← definitions.pathExists)) "keep the frozen task definitions"
    IO.FS.writeFile definitions (← IO.FS.readFile (base.parent.get!/"task-definitions.json"))
    guard "fixed-sequence-seed-audit" #["/usr/bin/env","EGGSHELL_DATA_ROOT="++(acquired/"data").toString,
      (directory/"controller-build/StudyMain").toString,"seed-audit",acquired.toString,definitions.toString,
      (ready/"ready.egg").toString,(cohort/"seed-source-audit.json").toString]
  else if args == ["read-seed"] then
    discard <| finished "fixed-sequence-seed-audit"
    let cohort := directory/"cohort"
    let plan ← read (cohort/((← selectedSeed)++".plan.json"))
    let workspace ← IO.ofExcept (plan.getObjValAs? String "workspace")
    let (ready,_) ← seedPreparation
    guard "fixed-sequence-seed-read" #[(directory/"controller-build/StudyMain").toString,"read-coverage",
      (ready/"ready.egg").toString,workspace,(reports/"task-definitions.json").toString,
      (cohort/"seed-read-coverage.json").toString]
  else if args == ["history-seed"] then
    discard <| finished "fixed-sequence-seed-read"
    let cohort := directory/"cohort"
    guard "fixed-sequence-seed-history" #[(directory/"controller-build/StudyMain").toString,"history","freeze",
      (cohort/"study"/(← selectedSeed)/"work.egg").toString,
      (cohort/"study"/(← selectedSeed)/"data").toString,(cohort/"seed-history").toString]
  else if args == ["record-accepted-seed"] then
    let cohort := directory/"cohort"
    let source ← read (cohort/"seed-source-audit.json")
    let coverage ← read (cohort/"seed-read-coverage.json")
    check (source.getObjValD "seedAccepted" == toJson true &&
      source.getObjValD "nativeJournalComplete" == toJson true &&
      coverage.getObjValD "publicationUnchanged" == toJson true &&
      coverage.getObjValD "conflictingCanonicalRows" == toJson (0 : Nat) &&
      coverage.getObjValD "payloadMismatches" == toJson (#[] : Array Json)) "source audit is incomplete"
    let availability ← IO.ofExcept (source.getObjValAs? (Array Json) "availability")
    let mut topics := #[]
    for row in availability do
      let frozen := row.getObjValD "frozenEvidence"
      let units ← IO.ofExcept (frozen.getObjValAs? (Array Json) "units")
      topics := topics.push (Json.mkObj [
        ("topic",row.getObjValD "topic"),("fullyStoredUnits",toJson units.size),
        ("fullRequirementNames",toJson (units.map (·.getObjValD "names"))),
        ("notFullyStored",frozen.getObjValD "initiallyUnavailable")])
    let (ready,_) ← seedPreparation
    let path := reports/"accepted-seed.json"
    check (!(← path.pathExists)) "keep the accepted-source record"
    write path (Json.mkObj [
      ("runtime",source.getObjValD "runtime"),("model",source.getObjValD "model"),
      ("effort",source.getObjValD "effort"),("provider",source.getObjValD "provider"),
      ("seedAccepted",toJson true),("sourceFiles",source.getObjValD "sourceFiles"),
      ("nativeStarts",source.getObjValD "nativeStarts"),("nativeFinishes",source.getObjValD "nativeFinishes"),
      ("originalDocuments",source.getObjValD "originalDocuments"),("originalRows",source.getObjValD "originalRows"),
      ("sourceAuditSha256",toJson (← hash (cohort/"seed-source-audit.json"))),
      ("readCoverageSha256",toJson (← hash (cohort/"seed-read-coverage.json"))),
      ("readiness",← read (ready/"view-readiness.json")),("topics",toJson topics),
      ("partialStoredEvidenceAssessedSeparatelyAtDelivery",toJson true),
      ("seedUsage",(← read (reports/"seed-generation.json")).getObjValD "usage"),
      ("sourceAuditReadHandoffBodies",source.getObjValD "handoffBodiesRead"),
      ("productionAdoption",toJson false)])
  else if args == ["template"] then
    discard <| finished "fixed-sequence-seed-history"
    let cohort := directory/"cohort"
    let target := cohort/"candidate-template.json"
    check (!(← target.pathExists)) "preserve the fixed candidate template"
    let seed ← read (cohort/((← selectedSeed)++".plan.json"))
    let mut template ← read (base/"candidate-template.json")
    for name in #["runtime","runner","accountConfiguration","pluginRoot","pluginFiles","harness",
        "model","effort","workspace","sourceCommit","cliWrapper","nativeCli","handoffChars","environment"] do
      template := template.setObjVal! name (seed.getObjValD name)
    write target (template.setObjVal! "purpose" (toJson "pilot"))
  else if args.length == 2 && args.head? == some "stage" then
    idle
    checkedController
    let some number := args[1]!.toNat? | throw (IO.userError "numeric stage required")
    check (1 ≤ number && number ≤ 6) "exactly six ordered stages are declared"
    let cohort := directory/"cohort"
    let makeArtifact := fun (path : System.FilePath) => do
      check (← path.pathExists) ("missing stage input: "++path.toString)
      pure (Json.mkObj [("path",toJson path.toString),("sha256",toJson (← hash path))])
    let initial := cohort/"seed-source-audit.json"
    let (history,sourceAudit,readCoverage,previous) ← if number == 1 then
      pure (← makeArtifact (cohort/"seed-history/history.json"),← makeArtifact initial,
        ← makeArtifact (cohort/"seed-read-coverage.json"),Json.null)
    else do
      let path := cohort/s!"stage-{number-1}/closed/closed.json"
      let completed ← read path
      check (completed.getObjValD "completed" == toJson true) "preceding stage is not closed"
      pure (completed.getObjValD "nextHistory",completed.getObjValD "sourceAudit",
        completed.getObjValD "readCoverage",← makeArtifact path)
    let input := cohort/s!"stage-{number}.input.json"
    check (!(← input.pathExists)) "do not replace an earlier stage preparation"
    let template ← makeArtifact (cohort/"candidate-template.json")
    write input (Json.mkObj [
      ("block",toJson (1 : Nat)),("stage",toJson number),("purpose",toJson "pilot"),
      ("history",history),("sourceAudit",sourceAudit),("readCoverage",readCoverage),
      ("initialSeedAudits",toJson #[← makeArtifact initial]),("definitions",← makeArtifact (reports/"task-definitions.json")),
      ("currentTemplate",template),("candidateTemplate",template),
      ("controllerSeedPlan",← makeArtifact (cohort/((← selectedSeed)++".plan.json"))),
      ("limits",← makeArtifact (cohort/"seed-1.limits.json")),("previousStage",previous),
      ("output",toJson (cohort/s!"stage-{number}").toString)])
    guard (← stagePreparationTag number) #[(← preparationExecutor),
      "stage-prepare",input.toString,← hash input]
  else if args.length == 2 && args.head? == some "close" then
    idle
    checkedController
    let some number := args[1]!.toNat? | throw (IO.userError "numeric stage required")
    check (1 ≤ number && number ≤ 6) "exactly six ordered stages are declared"
    let stage := directory/"cohort"/s!"stage-{number}"
    guard (← stageClosureTag number) #[(← preparationExecutor),
      "stage-close",(stage/"stage.json").toString,← hash (stage/"stage.json"),(stage/"closed").toString]
  else if args == ["complete-private-history"] then
    idle
    let executor ← preparationExecutor
    check (executor == (directory/"preparation-history-build/StudyMain").toString) "audited history repair required"
    let stage := directory/"cohort/stage-1"
    check ((← read (stage/"closed/closed.json")).getObjValD "completed" == toJson true) "first stage is not closed"
    let plan ← read (stage/"candidate/trial/plan.json")
    let database ← IO.ofExcept (plan.getObjValAs? String "database")
    let data ← IO.ofExcept (plan.getObjValAs? String "dataRoot")
    guard "fixed-sequence-complete-private-history" #["/usr/bin/env","EGGSHELL_DATA_ROOT="++data,
      executor,"history","freeze",database,data,(stage/"closed/history-complete").toString]
  else if args == ["check-missing-history"] || args == ["check-history-closure"] then
    discard <| finished "fixed-sequence-complete-private-history"
    let stage := directory/"cohort/stage-1"
    let original := stage/"closed/history/history.json"
    let manifest ← if args == ["check-history-closure"] then do
      let fixture := stage/"closed/history/history-missing-delivery.json"
      check (!(← fixture.pathExists)) "keep the explicitly incomplete dependency fixture"
      write fixture ((← read original).setObjVal! "confirmedDelivery" (toJson (#[] : Array Json)))
      pure fixture
      else pure original
    let plan ← read (stage/"candidate/trial/plan.json")
    let data ← IO.ofExcept (plan.getObjValAs? String "dataRoot")
    guard (if args == ["check-history-closure"] then "fixed-sequence-history-unclosed-input" else "fixed-sequence-history-missing-ledger")
      #["/usr/bin/env","EGGSHELL_DATA_ROOT="++data,
      (← preparationExecutor),"history","fork",manifest.toString,← hash manifest,
      (directory/"cohort/history-negative").toString]
  else if args == ["check-complete-history"] then
    let negative ← read (base/"fixed-sequence-history-unclosed-input.guard.json")
    check (negative.getObjValD "state" == toJson "finished" && negative.getObjValD "exitCode" == toJson (1 : Nat) &&
      negative.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "missing-history rejection did not retire"
    check ((← IO.FS.readFile (base/"fixed-sequence-history-unclosed-input.stderr")).contains
      "private history omitted or duplicated referenced delivery evidence") "negative check failed for another reason"
    check (!(← (directory/"cohort/history-negative").pathExists)) "incomplete history was forked"
    let stage := directory/"cohort/stage-1"
    let manifest := stage/"closed/history-complete/history.json"
    let plan ← read (stage/"candidate/trial/plan.json")
    let data ← IO.ofExcept (plan.getObjValAs? String "dataRoot")
    guard "fixed-sequence-history-complete-fork" #["/usr/bin/env","EGGSHELL_DATA_ROOT="++data,
      (← preparationExecutor),"history","fork",manifest.toString,← hash manifest,
      (directory/"cohort/history-positive").toString]
  else if args == ["seal-complete-history"] then
    discard <| finished "fixed-sequence-history-complete-fork"
    let stage := directory/"cohort/stage-1"
    let old ← read (stage/"closed/history/history.json")
    let manifest := stage/"closed/history-complete/history.json"
    let repaired ← read manifest
    for field in #["database","sourceFiles","privateFamilies"] do
      check (old.getObjValD field == repaired.getObjValD field) "history repair changed source or learned feedback"
    check (!(← IO.ofExcept (repaired.getObjValAs? (Array Json) "confirmedDelivery")).isEmpty)
      "historical delivery dependencies were not retained"
    let positive := directory/"cohort/history-positive"
    let receipt ← read (positive/"history-input.json")
    check (receipt.getObjValD "sessionStateCopied" == toJson false &&
      !(← (positive/"data/sessions").pathExists)) "new chat inherited live delivery state"
    let oldClosure := stage/"closed/closed.json"
    let closure := stage/"closed/closed-complete-history.json"
    check (!(← closure.pathExists)) "keep the original closure and its repair"
    let next := Json.mkObj [("path",toJson manifest.toString),("sha256",toJson (← hash manifest))]
    write closure ((← read oldClosure).setObjVal! "nextHistory" next
      |>.setObjVal! "originalClosureSha256" (toJson (← hash oldClosure)))
    write (reports/"private-history-repair.json") (Json.mkObj [
      ("sourceAndLearnedFeedbackUnchanged",toJson true),("copiedHistoricalDeliveryLedgers",repaired.getObjValD "confirmedDelivery"),
      ("missingLedgerRejected",toJson true),("sessionStateCopied",toJson false),("modelCalls",toJson (0 : Nat))])
    let input := directory/"cohort/stage-2.complete-history.input.json"
    check (!(← input.pathExists)) "preserve the repaired stage input"
    write input ((← read (directory/"cohort/stage-2.input.json")).setObjVal! "history" next
      |>.setObjVal! "previousStage" (Json.mkObj [("path",toJson closure.toString),("sha256",toJson (← hash closure))]))
    let failedStage := directory/"cohort/stage-2"
    check (!(← (failedStage/"stage.json").pathExists) && !(← (failedStage/"candidate/trial.guard.json").pathExists))
      "do not remove a prepared or charged stage"
    let monitor ← read (base/"fixed-sequence-stage-2-prepare-resumed.guard.json")
    check (monitor.getObjValD "state" == toJson "finished" && monitor.getObjValD "ownedPids" == toJson (#[] : Array Nat))
      "failed preparation still owns processes"
    let replies := failedStage/"candidate/preparation/finish-replay"
    let first ← read (replies/"step-0.json")
    let second ← read (replies/"step-1.json")
    check (second.getObjValD "error" == toJson "confirmed delivery ledger disappeared") "unexpected replay error"
    write (reports/"stage-2-missing-ledger.json") (Json.mkObj [
      ("guard",monitor),("firstReply",first),("secondReply",second),("worker",← read (replies/"worker.json")),
      ("modelAttempts",toJson (0 : Nat)),("archiveCreated",toJson false)])
    IO.FS.removeDirAll failedStage
    IO.FS.removeDirAll positive
    guard (← stagePreparationTag 2) #[(← preparationExecutor),"stage-prepare",input.toString,← hash input]
  else if args == ["resume-stage-two-preparation"] then
    idle
    checkedController
    let executor ← preparationExecutor
    check (executor != (directory/"controller-build/StudyMain").toString) "select the audited preparation repair first"
    let stage := directory/"cohort/stage-2"
    let guardRecord ← read (base/"fixed-sequence-stage-2-prepare.guard.json")
    let childRecord ← read (stage/"candidate/preparation.guard.json")
    check (guardRecord.getObjValD "state" == toJson "finished" &&
      guardRecord.getObjValD "exitCode" == toJson (1 : Nat) &&
      guardRecord.getObjValD "ownedPids" == toJson (#[] : Array Nat) &&
      childRecord.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "old preparation still owns processes"
    check ((← IO.FS.readFile (stage/"candidate/preparation.stderr")).trimAscii.toString ==
      "derived replay has unresolved input; retain durable memory without repeated model calls")
      "unexpected preparation failure"
    for arm in #["fresh","candidate"] do
      check (!(← (stage/arm/"trial.guard.json").pathExists) && !(← (stage/arm/"trial").pathExists))
        "do not discard any answering-model attempt"
    let replay ← read (stage/"candidate/preparation/finish-replay/step-0/stdout")
    check (replay.getObjValD "complete" == toJson false && replay.getObjValD "pending" == toJson (0 : Nat))
      "failure was not an incomplete bounded replay slice"
    let input := directory/"cohort/stage-2.input.json"
    let failure := Json.mkObj [
      ("guard",guardRecord),("preparationGuard",childRecord),("replay",replay),
      ("inputSha256",toJson (← hash input)),("modelAttempts",toJson (0 : Nat)),
      ("availableEvidenceSha256",toJson (← hash (stage/"candidate/preparation/available-evidence.json"))),
      ("removedIncompleteDatabaseAndCache",toJson true),("archiveCreated",toJson false)]
    IO.FS.removeDirAll stage
    check (!(← stage.pathExists)) "incomplete stage cleanup did not finish"
    write (reports/"stage-2-preparation-failure.json") failure
    guard (← stagePreparationTag 2) #[executor,"stage-prepare",input.toString,← hash input]
  else if args == ["declare-reference-round"] then
    idle
    checkedController
    let cohort := directory/"cohort"
    let failed := cohort/"stage-4/fresh/trial"
    let failure ← read (failed/"failure.json")
    let monitor ← read (cohort/"stage-4/fresh/trial.guard.json")
    check (failure.getObjValD "completed" == toJson false &&
      failure.getObjValD "runError" == toJson "observed inclusive token limit reached; retain all charged usage" &&
      monitor.getObjValD "state" == toJson "finished" && monitor.getObjValD "exitCode" == toJson (1 : Nat) &&
      monitor.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "inspect the stopped fresh control before continuation"
    let mut controls := #[]
    for topic in [1:4] do
      let stage := cohort/s!"stage-{topic}"
      check ((← read (stage/"closed/closed.json")).getObjValD "completed" == toJson true)
        "only a completed original control may be reused"
      let arm ← freshArm (← read (stage/"stage.json"))
      let plan ← checkedJsonArtifact (arm.getObjValD "plan")
      let output ← IO.ofExcept (plan.getObjValAs? String "output")
      let result ← read (.mk output/"result.json")
      check (result.getObjValD "completed" == toJson true &&
        (result.getObjValD "usage").getObjValD "unknownFinalUsage" == toJson false &&
        (result.getObjValD "usage").getObjValD "protocolPassed" == toJson true) "completed fresh usage required"
      controls := controls.push (Json.mkObj [("topic",toJson topic),("arm",arm),
        ("completedResult",← receipt (.mk output/"result.json"))])
    let failedCost := Json.mkObj [("failure",← receipt (failed/"failure.json")),
      ("usage",failure.getObjValD "usage"),("budgetStop",← receipt (failed/"budget-stop.json")),
      ("guard",← receipt (cohort/"stage-4/fresh/trial.guard.json")),
      ("finalUsageUnknown",toJson true),("notAnExactNetSaving",toJson true)]
    let declaration := Json.mkObj [("purpose",toJson "pilot with reused first-round fresh references"),
      ("stages",toJson #[4,5,6]),("controls",toJson controls),("failedAttempts",toJson #[failedCost]),
      ("automaticModelRetries",toJson (0 : Nat)),("independentPairedRepetition",toJson false),
      ("adoptionEligible",toJson false),("exactCampaignTokenTotalKnown",toJson false),
      ("productRuntimeUnchanged",toJson true),("answeringRunnerUnchanged",toJson true)]
    sealedJson (cohort/"reference-round.json") declaration
    sealedJson (reports/"reference-round.json") declaration
  else if args == ["continue-reference-round"] then
    checkedController
    let cohort := directory/"cohort"
    let protocolPath := cohort/"reference-round.json"
    let protocol ← read protocolPath
    check (protocol == (← read (reports/"reference-round.json")) &&
      protocol.getObjValD "adoptionEligible" == toJson false &&
      protocol.getObjValD "automaticModelRetries" == toJson (0 : Nat)) "explicit pilot continuation required"
    let controls ← IO.ofExcept (protocol.getObjValAs? (Array Json) "controls")
    for number in [4:7] do
      let stage := cohort/s!"stage-{number}"
      let mark := fun phase => write (reports/"sequence-progress.json") (Json.mkObj [
        ("stage",toJson number),("phase",toJson (phase : String)),
        ("freshPolicy",toJson "reused first-round control"),("comparisonCompleted",toJson false),
        ("automaticRetries",toJson (0 : Nat)),("adopted",toJson false)])
      mark "preparing"
      let settings := base/((← stagePreparationTag number)++".guard-settings.json")
      if !(← settings.pathExists) then main ["stage",toString number]
      runGuardOnce settings
      let prepared ← read (stage/"stage.json")
      let topic := (number-1)%3+1
      let some control := controls.find? (fun row => row.getObjValD "topic" == toJson topic) |
        throw (IO.userError "missing declared completed control")
      let reference := control.getObjValD "arm"
      let oldPlan ← checkedJsonArtifact (reference.getObjValD "plan")
      discard <| checkedJsonArtifact (control.getObjValD "completedResult")
      let intended ← freshArm prepared
      let newPlan ← checkedJsonArtifact (intended.getObjValD "plan")
      check (freshConditions oldPlan == freshConditions newPlan)
        "source, question, model, account, harness or environment differs from the completed fresh reference"
      let arms ← IO.ofExcept (prepared.getObjValAs? (Array Json) "arms")
      let referenced := prepared.setObjVal! "arms" (toJson (arms.map fun row =>
        if row.getObjValD "arm" == toJson "fresh" then reference else row))
      let referenced := referenced.setObjVal! "freshIsReused" (toJson true)
        |>.setObjVal! "comparisonCompleted" (toJson false)
        |>.setObjVal! "continuationProtocol" (← receipt protocolPath)
        |>.setObjVal! "derivedFrom" (← receipt (stage/"stage.json"))
      let manifest := stage/"stage-reference.json"
      sealedJson manifest referenced
      let some candidate := arms.find? (fun row => row.getObjValD "arm" == toJson "candidate") |
        throw (IO.userError "candidate arm is absent")
      mark "candidate:generation"
      let selected ← checkedJsonArtifact (candidate.getObjValD "settings")
      let path ← IO.ofExcept ((candidate.getObjValD "settings").getObjValAs? String "path")
      check (selected.getObjValD "record" == toJson (stage/"candidate/trial.guard.json").toString)
        "candidate guard destination changed"
      runGuardOnce (.mk path)
      let plan ← checkedJsonArtifact (candidate.getObjValD "plan")
      let output ← IO.ofExcept (plan.getObjValAs? String "output")
      let result ← read (.mk output/"result.json")
      check (result.getObjValD "completed" == toJson true &&
        (result.getObjValD "usage").getObjValD "unknownFinalUsage" == toJson false &&
        (result.getObjValD "usage").getObjValD "protocolPassed" == toJson true)
        "candidate generation incomplete; keep costs without retrying"
      mark "closing-source-history"
      let tag := s!"fixed-sequence-stage-{number}-close-reference"
      let closureSettings := base/(tag++".guard-settings.json")
      if !(← closureSettings.pathExists) then
        guard tag #[(← preparationExecutor),"stage-close",manifest.toString,← hash manifest,
          (stage/"reference-closure").toString]
      runGuardOnce closureSettings
      let nativePath := stage/"reference-closure/closed.json"
      let native ← read nativePath
      check (native.getObjValD "completed" == toJson true) "native source history closure failed"
      let closed := native.setObjVal! "comparisonCompleted" (toJson false)
        |>.setObjVal! "oneRecordedAttemptPerArm" (toJson false)
        |>.setObjVal! "freshIsReused" (toJson true)
        |>.setObjVal! "nativeClosure" (← receipt nativePath)
        |>.setObjVal! "continuationProtocol" (← receipt protocolPath)
        |>.setObjVal! "failedAttempts" (protocol.getObjValD "failedAttempts")
      IO.FS.createDirAll (stage/"closed")
      sealedJson (stage/"closed/closed.json") closed
      mark "history-completed-with-reference-control"
  else if args == ["run-six"] then
    checkedController
    let progress := reports/"sequence-progress.json"
    let mark := fun (number : Nat) (phase : String) => write progress (Json.mkObj [
      ("stage",toJson number),("phase",toJson phase),("model",toJson "gpt-5.6-luna"),
      ("effort",toJson "xhigh"),("automaticRetries",toJson (0 : Nat)),("adopted",toJson false)])
    for number in [1:7] do
      let stage := directory/"cohort"/s!"stage-{number}"
      mark number "preparing"
      let settings := base/((← stagePreparationTag number)++".guard-settings.json")
      if !(← settings.pathExists) then main ["stage",toString number]
      runGuardOnce settings
      let frozen ← read (stage/"stage.json")
      let order ← IO.ofExcept (frozen.getObjValAs? (Array String) "order")
      check (order == #["fresh","candidate"]) "pilot arm order changed"
      let arms ← IO.ofExcept (frozen.getObjValAs? (Array Json) "arms")
      for name in order do
        mark number (name++":generation")
        let some arm := arms.find? (fun row => row.getObjValD "arm" == toJson name) |
          throw (IO.userError "declared pilot arm is missing")
        let artifact := arm.getObjValD "settings"
        let path ← IO.ofExcept (artifact.getObjValAs? String "path")
        check (artifact.getObjValD "sha256" == toJson (← hash (.mk path))) "sealed guard settings changed"
        runGuardOnce (.mk path)
        let planArtifact := arm.getObjValD "plan"
        let planPath ← IO.ofExcept (planArtifact.getObjValAs? String "path")
        check (planArtifact.getObjValD "sha256" == toJson (← hash (.mk planPath))) "sealed model plan changed"
        let plan ← read (.mk planPath)
        let output ← IO.ofExcept (plan.getObjValAs? String "output")
        let result ← read (.mk output/"result.json")
        check (result.getObjValD "completed" == toJson true &&
          (result.getObjValD "usage").getObjValD "unknownFinalUsage" == toJson false &&
          (result.getObjValD "usage").getObjValD "protocolPassed" == toJson true)
          "model result is incomplete; preserve cost without retrying or advancing"
      mark number "closing-source-history"
      let settings := base/((← stageClosureTag number)++".guard-settings.json")
      if !(← settings.pathExists) then main ["close",toString number]
      runGuardOnce settings
      check ((← read (stage/"closed/closed.json")).getObjValD "completed" == toJson true)
        "source history closure is incomplete"
      mark number "completed"
  else throw (IO.userError "controller/audit required")
