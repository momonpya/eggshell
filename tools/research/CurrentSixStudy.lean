import tools.research.StudyLocal
open Lean StudyLocal
def study := project/"docs/candidates/current-six"
def runRoot := base/"current-six"

/-- Extend the selected product's source closure with the controller only.
Existing frozen sources always win; missing product sources are an error. -/
partial def controllerSources (destination : System.FilePath) (name : String)
    (seen : IO.Ref (Array String)) : IO Unit := do
  if (← seen.get).contains name then return
  seen.modify (·.push name)
  let relative := name.replace "." "/"++".lean"
  let target := destination/relative
  if !(← target.pathExists) then
    let available := project/relative
    unless ← available.pathExists do return
    check (name.startsWith "tools.research.") ("missing frozen product input: "++name)
    IO.FS.createDirAll target.parent.get!
    IO.FS.writeFile target (← IO.FS.readFile available)
  unless ← target.pathExists do return
  for line in (← IO.FS.readFile target).splitOn "\n" do
    let row := line.trimAscii.toString
    let introducer := if row.startsWith "public import " then "public import " else "import "
    if row.startsWith introducer then
      for dependency in (row.drop introducer.length).toString.splitOn " " do
        if !dependency.isEmpty then controllerSources destination dependency seen

partial def sizeOfTree (path : System.FilePath) : IO (Nat × Nat) := do
  let info ← path.symlinkMetadata
  if info.type != .dir then return (1,info.byteSize.toNat)
  let mut count := 0
  let mut bytes := 0
  for entry in ← path.readDir do
    let (files,length) ← sizeOfTree entry.path
    count := count+files
    bytes := bytes+length
  return (count,bytes)

def checkedController : IO Unit := do
  let actual ← hash (runRoot/"controller-build/StudyMain")
  for (tag,report) in [("current-six-controller-readiness-audit","controller-sources-readiness.json"),
      ("current-six-controller-endpoint-audit","controller-sources-final.json"),
      ("current-six-controller-core-audit","controller-sources-complete.json"),
      ("current-six-controller-audit","controller-sources.json")] do
    if !(← (base/(tag++".guard.json")).pathExists) || !(← (study/report).pathExists) then continue
    let guard ← read (base/(tag++".guard.json"))
    let sources ← read (study/report)
    if guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
        guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) &&
        sources.getObjValD "auditorSha256" == toJson actual &&
        sources.getObjValD "allProductCorePresent" == toJson true &&
        sources.getObjValD "commonSourcesUnchanged" == toJson true then return
  throw (IO.userError "current controller bytes have no complete native product-source audit")

def main (args : List String) : IO Unit := do
  if args == ["catalog"] then
    idle
    check (!(← runRoot.pathExists)) "preserve an existing six-stage study"
    for folder in [runRoot,runRoot/"catalog-account",runRoot/"tmp"] do
      IO.FS.createDirAll folder
      IO.setAccessRights folder {user := {read := true,write := true,execution := true}}
    IO.FS.writeFile (runRoot/"catalog-account/config.toml")
      "model = \"gpt-5.6-luna\"\nmodel_reasoning_effort = \"xhigh\"\nproject_doc_max_bytes = 0\n[features]\nplugins = false\nhooks = false\nremote_plugin = false\nmulti_agent = false\n"
    discard <| command "/bin/ln" #["-s","/Users/ovm/.codex/auth.json",(runRoot/"catalog-account/auth.json").toString]
    let input := Json.mkObj [
      ("command",toJson #["/Users/ovm/.nodebrew/current/bin/codex","--strict-config","-c","features.remote_plugin=false","app-server","--listen","stdio://"]),
      ("cwd",toJson "/Users/ovm/Code/eggshell-benchmarks/aamas-2027/sources/llvm-project"),
      ("environment",toJson (#[ ("CODEX_HOME",some (runRoot/"catalog-account").toString),
        ("TMPDIR",some (runRoot/"tmp").toString),("CODEX_THREAD_ID",none),("CODEX_TURN_ID",none)] : Array (String × Option String))),
      ("output",toJson (runRoot/"catalog").toString),("timeoutMs",toJson (60000 : Nat)),
      ("responseBytes",toJson (33554432 : Nat)),("transcriptBytes",toJson (268435456 : Nat))]
    IO.FS.createDirAll study
    write (runRoot/"catalog-input.json") input
    write (study/"local-scope.json") (Json.mkObj [
      ("localMaximumConcurrentClients",toJson (16 : Nat)),("localTarget",toJson "a few seconds within5GB; no80-client test on this Mac"),
      ("enterpriseArchitectureGoal",toJson "80people, growing multiple project DBs remains design scope; not locally proven"),
      ("fixedSequence",toJson "new empty DB/new chat seed; topic1,2,3 then topic1,2,3 with one frozen runtime SHA"),
      ("requiredEvidence",toJson "DB-present originals frozen before delivery; every required original in actual model-visible body; inclusive total tokens vs fresh; seed separately"),
      ("poolPolicy",toJson "allowed when architecture and performance justify it; partial CPU-pool candidate showed no RSS improvement and is not adopted")])
    guard "current-six-catalog" #[(base/"controller/StudyMain").toString,"probe",(runRoot/"catalog-input.json").toString]
  else if args == ["controller"] then
    discard <| finished "current-six-catalog"
    let catalog ← read (runRoot/"catalog/models.json")
    let models ← IO.ofExcept (catalog.getObjValAs? (Array Json) "data")
    check (models.any fun row => row.getObjValD "model" == toJson "gpt-5.6-luna" &&
      ((row.getObjValAs? (Array Json) "supportedReasoningEfforts").toOption.getD #[]).any
        (fun effort => effort.getObjValD "reasoningEffort" == toJson "xhigh")) "required model/effort unavailable"
    let destination := runRoot/"controller-source"
    let build := runRoot/"controller-build"
    materialize (base/"owned-selection-runtime-build") destination build "tools.research.StudyMain" "current-six-controller-settings.json"
    let entry := destination/"tools/research/StudyMain.lean"
    IO.FS.writeFile entry ("import Eggshell.ContractAudit\nimport Eggshell.Setup\n"++(← IO.FS.readFile entry))
    let seen ← IO.mkRef #[]
    controllerSources destination "tools.research.StudyMain" seen
    let settings ← read (base/"current-six-controller-settings.json")
    let parents ← IO.ofExcept (settings.getObjValAs? (Array String) "parents")
    write (base/"current-six-controller-settings.json")
      (settings.setObjVal! "parents" (toJson (parents.push (base/"controller").toString)))
    write (study/"controller-plan.json") (Json.mkObj [
      ("productRuntimeSha256",toJson (← hash (base/"owned-selection-runtime-build/StudyMain"))),
      ("model",toJson "gpt-5.6-luna"),("effort",toJson "xhigh"),
      ("copiedControllerClosure",toJson (← seen.get)),("frozenProductSourcesOverwritten",toJson false),
      ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
    guard "current-six-controller-build" #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(base/"current-six-controller-settings.json").toString]
  else if args == ["audit"] then
    discard <| finished "current-six-controller-build"
    guard "current-six-controller-audit" #["/usr/bin/env","LEAN_PATH="++(base/"study-local-lib").toString,
      (compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/CurrentSixStudy.lean").toString,"audit-worker"]
  else if args == ["audit-worker"] then
    let audit := fun arguments => command (compiler/"bin/lean").toString
      (#["-j1","-M1536","--run",(project/"tools/research/StudyBuildClosureAudit.lean").toString]++arguments)
    discard <| audit #["inspect",(runRoot/"controller-build").toString,(study/"controller-native.json").toString]
    discard <| audit #["common-sources",(base/"owned-selection-runtime-build").toString,
      (runRoot/"controller-build").toString,(study/"controller-sources.json").toString]
  else if args == ["controller-core"] then
    idle
    let failed ← read (base/"current-six-controller-audit.guard.json")
    check (failed.getObjValD "state" == toJson "finished" && failed.getObjValD "exitCode" == toJson (1 : Nat) &&
      failed.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "preserve the initial missing-core audit"
    let destination := runRoot/"controller-source"
    let entry := destination/"tools/research/StudyMain.lean"
    let original ← IO.FS.readFile entry
    check (!original.contains "import Eggshell.ContractAudit") "controller core already added"
    IO.FS.writeFile entry ("import Eggshell.ContractAudit\nimport Eggshell.Setup\n"++original)
    let seen ← IO.mkRef #[]
    controllerSources destination "tools.research.StudyMain" seen
    write (study/"controller-core-plan.json") (Json.mkObj [
      ("reason",toJson "initial controller omitted nine unused service modules; require the complete product closure before native lifecycle audit"),
      ("initialNativeObjectsConsistent",toJson true),("initialCoreSourceComparisonPassed",toJson false),
      ("harnessEntryImportsOnly",toJson #["Eggshell.ContractAudit","Eggshell.Setup"]),
      ("productSourcesChanged",toJson false),("answeringModelCalls",toJson (0 : Nat))])
    guard "current-six-controller-core-build" #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(base/"current-six-controller-settings.json").toString]
  else if args == ["core-audit"] then
    discard <| finished "current-six-controller-core-build"
    guard "current-six-controller-core-audit" #["/usr/bin/env","LEAN_PATH="++(base/"study-local-lib").toString,
      (compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/CurrentSixStudy.lean").toString,"core-audit-worker"]
  else if args == ["core-audit-worker"] then
    let audit := fun arguments => command (compiler/"bin/lean").toString
      (#["-j1","-M1536","--run",(project/"tools/research/StudyBuildClosureAudit.lean").toString]++arguments)
    discard <| audit #["inspect",(runRoot/"controller-build").toString,(study/"controller-native-complete.json").toString]
    discard <| audit #["common-sources",(base/"owned-selection-runtime-build").toString,
      (runRoot/"controller-build").toString,(study/"controller-sources-complete.json").toString]
  else if args == ["install"] then
    checkedController
    let controller := runRoot/"controller-build/StudyMain"
    let source := runRoot/"controller-source"
    for relative in ["tools/research/StudyBuildMain.lean","docs/benchmarks/reseed-delivery-contract.json",
        "docs/benchmarks/llvm-three-topics.json","docs/benchmarks/readme-memory-facts.json"] do
      IO.FS.createDirAll (source/relative).parent.get!
      IO.FS.writeFile (source/relative) (← IO.FS.readFile (project/relative))
    let workspace := "/Users/ovm/Code/eggshell-benchmarks/aamas-2027/sources/llvm-project"
    let prompts ← IO.ofExcept ((← read (project/"docs/benchmarks/llvm-three-topics.json")).getObjValAs? (Array String) "prompts")
    check (prompts.size == 4) "seed and three topic prompts required"
    for index in [:prompts.size] do
      check ((← IO.FS.readFile (base/s!"prompts/topic-{index}.txt")) ==
        prompts[index]!.replace "<LLVM_SOURCE>" workspace) "canonical prompt changed"
    let cohort := runRoot/"cohort"
    discard <| command controller.toString #["bootstrap","prepare",cohort.toString,base.toString,
      (base/"owned-selection-runtime-prefix/libexec/eggshell").toString]
    let probe ← read (cohort/"discovery.input.json")
    let catalog ← read (runRoot/"catalog/models.json")
    let models ← IO.ofExcept (catalog.getObjValAs? (Array Json) "data")
    write (study/"model-catalog.json") (Json.mkObj [
      ("luna",toJson (models.filter fun row =>
        ((row.getObjValAs? String "model").toOption.getD "").contains "luna")),
      ("nextCursor",catalog.getObjValD "nextCursor"),("answeringModelCalls",toJson (0 : Nat))])
    guard "current-six-hooks-catalog" #[controller.toString,"probe",(cohort/"discovery.input.json").toString]
    check (probe.getObjValD "timeoutMs" == toJson (60000 : Nat)) "unexpected catalog timeout"
  else if args == ["gate"] then
    discard <| finished "current-six-hooks-registered"
    let cohort := runRoot/"cohort"
    let controller := runRoot/"controller-build/StudyMain"
    check (!(← (cohort/"initial-unregistered-catalog").pathExists)) "preserve both hook catalogs"
    IO.FS.rename (cohort/"discovery") (cohort/"initial-unregistered-catalog")
    IO.FS.rename (cohort/"registered") (cohort/"discovery")
    discard <| command controller.toString #["bootstrap","trust-hooks",cohort.toString]
    discard <| command controller.toString #["bootstrap","seed-input",cohort.toString,"500000"]
    let settings := cohort/"native-gate.settings.json"
    check (!(← settings.pathExists)) "preserve native lifecycle gate"
    idle
    let input ← read (cohort/"native-gate-input.json")
    let env : Array (String × Option String) ← IO.ofExcept (fromJson? (input.getObjValD "environment"))
    let unset := env.filterMap fun (key,value) => if value.isNone then some key else none
    let assignments := env.filterMap fun (key,value) => value.map (key++"="++·)
    write settings (Json.mkObj [("command",toJson (#["/usr/bin/env"]++unset.flatMap (fun key => #["-u",key])++assignments++
      #[controller.toString,"seed-checks-generic",(cohort/"native-gate-input.json").toString,(cohort/"native-gate").toString])),
      ("cwd",toJson project.toString),("record",toJson (cohort/"native-gate.guard.json").toString),
      ("ownedPrefixes",toJson #[base.toString]),("limitRssKiB",toJson (4358524 : Nat)),
      ("minFreeKiB",toJson (2097152 : Nat))])
  else if args == ["register-hooks"] then
    discard <| finished "current-six-hooks-catalog"
    idle
    let cohort := runRoot/"cohort"
    let invoke := fun (arguments : Array String) => command "/usr/bin/env"
      (#["CODEX_HOME="++(cohort/"account").toString,"/Users/ovm/.nodebrew/current/bin/codex"]++arguments)
    IO.FS.writeFile (cohort/"marketplace-add.json") (← invoke #["plugin","marketplace","add",(cohort/"prefix").toString,"--json"])
    IO.FS.writeFile (cohort/"plugin-add.json") (← invoke #["plugin","add","eggshell@eggshell","--json"])
    let input ← read (cohort/"discovery.input.json")
    write (cohort/"registered.input.json") (input.setObjVal! "output" (toJson (cohort/"registered").toString))
    guard "current-six-hooks-registered" #[(runRoot/"controller-build/StudyMain").toString,
      "probe",(cohort/"registered.input.json").toString]
  else if args == ["gate-environment"] then
    idle
    let cohort := runRoot/"cohort"
    let prior ← read (cohort/"native-gate.guard.json")
    check (prior.getObjValD "state" == toJson "finished" && prior.getObjValD "exitCode" == toJson (1 : Nat) &&
      prior.getObjValD "ownedPids" == toJson (#[] : Array Nat) &&
      !(← (cohort/"native-gate").pathExists)) "configuration failure must precede any DB or hook"
    write (study/"lifecycle-configuration-failure.json") prior
    let input ← read (cohort/"native-gate-input.json")
    let env : Array (String × Option String) ← IO.ofExcept (fromJson? (input.getObjValD "environment"))
    let unset := env.filterMap fun (key,value) => if value.isNone then some key else none
    let assignments := env.filterMap fun (key,value) => value.map (key++"="++·)
    let settings ← read (cohort/"native-gate.settings.json")
    let command : Array String ← IO.ofExcept (settings.getObjValAs? (Array String) "command")
    write (cohort/"native-gate-environment.settings.json") (settings.setObjVal! "command"
      (toJson (#["/usr/bin/env"]++unset.flatMap (fun key => #["-u",key])++assignments++command))
      |>.setObjVal! "record" (toJson (cohort/"native-gate-checked.guard.json").toString))
  else if args == ["seal-seed"] then
    idle
    checkedController
    let cohort := runRoot/"cohort"
    let verifiedExists ← (cohort/"native-gate-verified.guard.json").pathExists
    let finalExists ← (cohort/"native-gate-final.guard.json").pathExists
    let checkedRecord := if verifiedExists then
      cohort/"native-gate-verified.guard.json" else if finalExists then
      cohort/"native-gate-final.guard.json" else cohort/"native-gate.guard.json"
    let record ← read checkedRecord
    check (record.getObjValD "state" == toJson "finished" && record.getObjValD "exitCode" == toJson (0 : Nat) &&
      record.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "native lifecycle/recovery gate is incomplete"
    discard <| command (runRoot/"controller-build/StudyMain").toString #["bootstrap","seal-seed",cohort.toString]
    let planPath := cohort/"seed-1.plan.json"
    let plan ← read planPath
    let gate := (plan.getObjValD "gate").setObjVal! "guard" (Json.mkObj [
      ("path",toJson checkedRecord.toString),("sha256",toJson (← hash checkedRecord))])
    write planPath (plan.setObjVal! "gate" gate)
    let path := cohort/"seed-1.settings.json"
    let settings ← read path
    let arguments ← IO.ofExcept (settings.getObjValAs? (Array String) "command")
    check (arguments.size == 6 && arguments[1]! == "acquire-bounded" && arguments[2]! == planPath.toString)
      "unexpected sealed acquisition command"
    write path (settings.setObjVal! "limitRssKiB" (toJson (4358524 : Nat))
      |>.setObjVal! "command" (toJson (arguments.set! 3 (← hash planPath))))
  else if args == ["repair-endpoints"] then
    idle
    let cohort := runRoot/"cohort"
    let prior ← read (cohort/"native-gate-checked.guard.json")
    check (prior.getObjValD "state" == toJson "finished" && prior.getObjValD "exitCode" == toJson (1 : Nat) &&
      prior.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "prior lifecycle guard must be drained"
    write (study/"lifecycle-endpoint-failure.json") prior
    let source := runRoot/"controller-source"
    let mut changes := #[]
    for name in ["StudySeedChecks","StudyAcquire","StudyTrial","StudyPrepare","NativeSeedFinalize"] do
      let relative := "tools/research/"++name++".lean"
      changes := changes.push (Json.mkObj [("module",toJson name),("beforeSha256",toJson (← hash (source/relative))),
        ("afterSha256",toJson (← hash (project/relative)))])
      IO.FS.writeFile (source/relative) (← IO.FS.readFile (project/relative))
    write (study/"controller-endpoint-plan.json") (Json.mkObj [("changes",toJson changes),
      ("reason",toJson "all active acquisition/preparation/trial/recovery callers must use the shared data-root frontend endpoint required by StudyRuntime"),
      ("productRuntimeChanged",toJson false),("answeringModelCalls",toJson (0 : Nat))])
    guard "current-six-controller-endpoint-build" #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(base/"current-six-controller-settings.json").toString]
  else if args == ["endpoint-audit"] then
    discard <| finished "current-six-controller-endpoint-build"
    guard "current-six-controller-endpoint-audit" #["/usr/bin/env","LEAN_PATH="++(base/"study-local-lib").toString,
      (compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/CurrentSixStudy.lean").toString,"endpoint-audit-worker"]
  else if args == ["endpoint-audit-worker"] then
    let audit := fun arguments => command (compiler/"bin/lean").toString
      (#["-j1","-M1536","--run",(project/"tools/research/StudyBuildClosureAudit.lean").toString]++arguments)
    discard <| audit #["inspect",(runRoot/"controller-build").toString,(study/"controller-native-final.json").toString]
    discard <| audit #["common-sources",(base/"owned-selection-runtime-build").toString,
      (runRoot/"controller-build").toString,(study/"controller-sources-final.json").toString]
  else if args == ["final-gate"] then
    discard <| finished "current-six-controller-endpoint-audit"
    idle
    let cohort := runRoot/"cohort"
    let shutdown ← read (cohort/"native-gate/publisher-shutdown.json")
    check (shutdown.getObjValD "processExited" == toJson true && shutdown.getObjValD "endpointRemoved" == toJson true &&
      shutdown.getObjValD "daemonExitCode" == toJson (0 : Nat)) "failed gate publisher is not closed"
    write (study/"lifecycle-endpoint-shutdown.json") shutdown
    let (files,bytes) ← sizeOfTree (cohort/"native-gate")
    IO.FS.removeDirAll (cohort/"native-gate")
    write (study/"lifecycle-failed-cleanup.json") (Json.mkObj [("files",toJson files),("logicalBytes",toJson bytes),
      ("archiveCreated",toJson false),("answeringModelCalls",toJson (0 : Nat))])
    let settings ← read (cohort/"native-gate-environment.settings.json")
    write (cohort/"native-gate-final.settings.json") (settings.setObjVal! "record"
      (toJson (cohort/"native-gate-final.guard.json").toString))
  else if args == ["readiness-build"] then
    idle
    let cohort := runRoot/"cohort"
    let prior ← read (cohort/"native-gate-final.guard.json")
    check (prior.getObjValD "state" == toJson "finished" && prior.getObjValD "exitCode" == toJson (1 : Nat) &&
      prior.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "retain the drained report-schema failure"
    write (study/"lifecycle-report-schema-failure.json") prior
    write (study/"lifecycle-native-capture.json") (← read (cohort/"native-gate/result.json"))
    for name in ["StudyReadiness","StudyAdmission","StudySeedChecks","StudyPrepare","NativeSeedFinalize","StudyStages"] do
      let relative := "tools/research/"++name++".lean"
      IO.FS.writeFile (runRoot/"controller-source"/relative) (← IO.FS.readFile (project/relative))
    IO.FS.writeFile (runRoot/"controller-source/tools/research/StudyMain.lean")
      ("import Eggshell.ContractAudit\nimport Eggshell.Setup\n"++(← IO.FS.readFile (project/"tools/research/StudyMain.lean")))
    guard "current-six-controller-readiness-build" #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(base/"current-six-controller-settings.json").toString]
  else if args == ["readiness-audit"] then
    discard <| finished "current-six-controller-readiness-build"
    guard "current-six-controller-readiness-audit" #["/usr/bin/env","LEAN_PATH="++(base/"study-local-lib").toString,
      (compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/CurrentSixStudy.lean").toString,"readiness-audit-worker"]
  else if args == ["readiness-audit-worker"] then
    let audit := fun arguments => command (compiler/"bin/lean").toString
      (#["-j1","-M1536","--run",(project/"tools/research/StudyBuildClosureAudit.lean").toString]++arguments)
    discard <| audit #["inspect",(runRoot/"controller-build").toString,(study/"controller-native-readiness.json").toString]
    discard <| audit #["common-sources",(base/"owned-selection-runtime-build").toString,
      (runRoot/"controller-build").toString,(study/"controller-sources-readiness.json").toString]
  else if args == ["readiness-checks"] then
    checkedController
    guard "current-six-readiness-checks" #[(runRoot/"controller-build/StudyMain").toString,"readiness-checks",
      (runRoot/"cohort/native-gate/final-warm/stdout").toString,(runRoot/"cohort/native-gate/work.egg").toString,
      (study/"readiness-checks.json").toString]
  else if args == ["verified-gate"] then
    discard <| finished "current-six-readiness-checks"
    idle
    let cohort := runRoot/"cohort"
    let checkClosed := fun path => do
      let row ← read path
      check (row.getObjValD "processExited" == toJson true && row.getObjValD "endpointRemoved" == toJson true &&
        row.getObjValD "daemonExitCode" == toJson (0 : Nat)) "old fixture still has an owner"
    checkClosed (cohort/"native-gate/shutdown.json")
    checkClosed (cohort/"native-gate/publisher-shutdown.json")
    IO.FS.removeDirAll (cohort/"native-gate")
    let settings ← read (cohort/"native-gate-environment.settings.json")
    write (cohort/"native-gate-verified.settings.json") (settings.setObjVal! "record"
      (toJson (cohort/"native-gate-verified.guard.json").toString))
  else if args == ["retire-prototypes"] then
    idle
    discard <| finished "current-six-controller-build"
    let keep := #[base/"owned-selection-runtime-build/StudyMain",base/"owned-selection-runtime-prefix/libexec/eggshell",
      base/"reference-records-fixture/work.egg/head",
      base/"reference-records-fixture/work.egg/2a1ab5766ac89060c477ae3fc9683c9492574ff843d134c01b53d9697a27359e.pages"]
    let before ← keep.mapM fun path => return (path.toString,← hash path)
    let response ← IO.FS.readFile (runRoot/"controller-build/runtime.rsp")
    for retired in ["pooled-selection-build","base-cue-bench-build"] do
      check (!(response.contains retired)) "new controller depends on a retired prototype"
    let pool := project/"docs/candidates/pooled-selection"
    let mut arms := #[]
    for arm in ["parent-first","candidate-first","candidate-second","parent-second"] do
      let tag := "pooled-selection-"++arm
      let closed ← finished tag
      let report ← read (base/(tag++"-result/report.json"))
      let phases ← IO.ofExcept (report.getObjValAs? (Array Json) "phases")
      let phases := phases.map fun row => Json.mkObj (["clients","wallMs","passed","allBodiesByteEqual",
        "successes","semanticCompleted","synapsesCompleted"].map fun key => (key,row.getObjValD key))
      arms := arms.push (Json.mkObj [("arm",toJson arm),("runtimeSha256",report.getObjValD "runtimeSha256"),
        ("phases",toJson phases),("guard",closed),("allPhasesPassed",report.getObjValD "allPhasesPassed")])
    write (pool/"comparison.json") (Json.mkObj [("arms",toJson arms),("adopted",toJson false),
      ("answeringModelCalls",toJson (0 : Nat)),("historicalThreadProfileUsedAsCausalControl",toJson false)])
    write (pool/"initial-hooks.json") (← read (base/"pooled-selection-hooks-result/result.json"))
    write (project/"docs/candidates/base-cue-buckets/component-result.json") (← read (base/"base-cue-bench-result/result.json"))
    write (project/"docs/candidates/base-cue-buckets/component-guard.json") (← finished "base-cue-bench-native")
    let mut retired := #[]
    for name in ["pooled-selection-source","pooled-selection-build","pooled-selection-prefix",
        "pooled-selection-hooks-result","pooled-selection-parent-first-result","pooled-selection-candidate-first-result",
        "pooled-selection-candidate-second-result","pooled-selection-parent-second-result",
        "base-cue-bench-source","base-cue-bench-build","base-cue-bench-result",
        "reference-records-fixture/data/sessions","reference-records-fixture/data/receipts",
        "reference-records-fixture/data/confirmed-delivery"] do
      let path := base/name
      check (path.parent == some base || path.parent == some (base/"reference-records-fixture/data"))
        "cleanup escaped approved experimental directories"
      if ← path.pathExists then
        let (files,bytes) ← sizeOfTree path
        IO.FS.removeDirAll path
        retired := retired.push (Json.mkObj [("path",toJson path.toString),("files",toJson files),("logicalBytes",toJson bytes)])
    let after ← keep.mapM fun path => return (path.toString,← hash path)
    check (before == after) "protected runtime or original publication changed"
    write (pool/"cleanup.json") (Json.mkObj [("removed",toJson retired),("protected",toJson after),
      ("archiveCreated",toJson false),("physicalFreedBytesClaimed",toJson false)])
  else throw (IO.userError "catalog/controller/audit/install/gate/seal-seed/retire-prototypes required")
