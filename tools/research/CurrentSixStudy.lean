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

partial def excludesLinks (directory : System.FilePath) (retired : Array System.FilePath) : IO Unit := do
  for entry in ← directory.readDir do
    let info ← entry.path.symlinkMetadata
    if info.type == .dir then excludesLinks entry.path retired
    else if info.type == .symlink then
      let actual ← IO.FS.realPath entry.path
      check (!(retired.any fun root => actual.toString.startsWith (root.toString++"/")))
        "active interfaces depend on a retired study"

def checkedController (runRoot study : System.FilePath) (label : String → String) : IO Unit := do
  let actual ← hash (runRoot/"controller-build/StudyMain")
  for (tag,report) in [("current-six-controller-scope-audit","controller-sources-scope.json"),
      ("current-six-controller-journal-audit","controller-sources-journal.json"),
      ("current-six-controller-readiness-audit","controller-sources-readiness.json"),
      ("current-six-controller-endpoint-audit","controller-sources-final.json"),
      ("current-six-controller-core-audit","controller-sources-complete.json"),
      ("current-six-controller-audit","controller-sources.json")] do
    if !(← (base/(label tag++".guard.json")).pathExists) || !(← (study/report).pathExists) then continue
    let guard ← read (base/(label tag++".guard.json"))
    let sources ← read (study/report)
    if guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
        guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) &&
        sources.getObjValD "auditorSha256" == toJson actual &&
        sources.getObjValD "allProductCorePresent" == toJson true &&
        sources.getObjValD "commonSourcesUnchanged" == toJson true then return
  throw (IO.userError "current controller bytes have no complete native product-source audit")

def main (args : List String) : IO Unit := do
  let located := args.head? == some "located"
  let args := if located then args.drop 1 else args
  let runRoot := if located then base/"current-six/located-study" else runRoot
  let study := if located then project/"docs/candidates/located-lexical-input/cohort" else study
  let productBuild := if located then base/"current-six/located-runtime-build" else base/"owned-selection-runtime-build"
  let productRuntime := if located then productBuild/"StudyMain" else base/"owned-selection-runtime-prefix/libexec/eggshell"
  let label := fun (tag : String) => if located then tag.replace "current-six" "current-six-located" else tag
  let guard := fun tag arguments => StudyLocal.guard (label tag) arguments
  let finished := fun tag => StudyLocal.finished (label tag)
  let checkedController := checkedController runRoot study label
  let controllerSettings := label "current-six-controller-settings"++".json"
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
    materialize productBuild destination build "tools.research.StudyMain" controllerSettings
    let entry := destination/"tools/research/StudyMain.lean"
    IO.FS.writeFile entry ("import Eggshell.ContractAudit\nimport Eggshell.Setup\n"++(← IO.FS.readFile entry))
    let seen ← IO.mkRef #[]
    controllerSources destination "tools.research.StudyMain" seen
    let settings ← read (base/controllerSettings)
    let parents ← IO.ofExcept (settings.getObjValAs? (Array String) "parents")
    write (base/controllerSettings)
      (settings.setObjVal! "parents" (toJson (parents.push (base/"controller").toString)))
    write (study/"controller-plan.json") (Json.mkObj [
      ("productRuntimeSha256",toJson (← hash (productBuild/"StudyMain"))),
      ("model",toJson "gpt-5.6-luna"),("effort",toJson "xhigh"),
      ("copiedControllerClosure",toJson (← seen.get)),("frozenProductSourcesOverwritten",toJson false),
      ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
    guard "current-six-controller-build" #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(base/controllerSettings).toString]
  else if args == ["audit"] then
    discard <| finished "current-six-controller-build"
    guard "current-six-controller-audit" (#["/usr/bin/env","LEAN_PATH="++(base/"study-local-lib").toString,
      (compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/CurrentSixStudy.lean").toString]++(if located then #["located"] else #[])++#["audit-worker"])
  else if args == ["audit-worker"] then
    let audit := fun arguments => command (compiler/"bin/lean").toString
      (#["-j1","-M1536","--run",(project/"tools/research/StudyBuildClosureAudit.lean").toString]++arguments)
    discard <| audit #["inspect",(runRoot/"controller-build").toString,(study/"controller-native.json").toString]
    discard <| audit #["common-sources",productBuild.toString,
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
    discard <| command "/usr/bin/env" #["EGGSHELL_STUDY_AUTH_FILE=/Users/ovm/.codex/auth.json",
      controller.toString,"bootstrap","prepare",cohort.toString,base.toString,productRuntime.toString]
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
    let acceptedExists ← (cohort/"native-gate-accepted.guard.json").pathExists
    let scopedExists ← (cohort/"native-gate-scoped.guard.json").pathExists
    let checkedRecord := if scopedExists then cohort/"native-gate-scoped.guard.json" else if acceptedExists then cohort/"native-gate-accepted.guard.json" else if verifiedExists then
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
      |>.setObjVal! "ownedPrefixes" (toJson #[base.toString])
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
  else if args == ["readiness-build"] || args == ["journal-build"] then
    idle
    let cohort := runRoot/"cohort"
    let journal := args == ["journal-build"]
    if journal then
      let closed ← finished "current-six-journal-advance"
      let reply ← IO.FS.readFile (base/"current-six-journal-advance.stdout") >>= (IO.ofExcept ∘ Json.parse)
      check (reply == toJson true) "actual sealed worker did not complete off-hook preparation"
      write (study/"journal-offhook.json") (Json.mkObj [("guard",closed),("reply",reply),
        ("productRuntimeChanged",toJson false),("answeringModelCalls",toJson (0 : Nat))])
    let prior ← read (cohort/(if journal then "native-gate-verified.guard.json" else "native-gate-final.guard.json"))
    check (prior.getObjValD "state" == toJson "finished" && prior.getObjValD "exitCode" == toJson (1 : Nat) &&
      prior.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "retain the drained report-schema failure"
    write (study/(if journal then "lifecycle-derived-preparation-failure.json" else "lifecycle-report-schema-failure.json")) prior
    write (study/"lifecycle-native-capture.json") (← read (cohort/"native-gate/result.json"))
    for name in ["StudyReadiness","StudyAdmission","StudySeedChecks","StudyPrepare","NativeSeedFinalize","StudyStages"] do
      let relative := "tools/research/"++name++".lean"
      IO.FS.writeFile (runRoot/"controller-source"/relative) (← IO.FS.readFile (project/relative))
    IO.FS.writeFile (runRoot/"controller-source/tools/research/StudyMain.lean")
      ("import Eggshell.ContractAudit\nimport Eggshell.Setup\n"++(← IO.FS.readFile (project/"tools/research/StudyMain.lean")))
    guard (if journal then "current-six-controller-journal-build" else "current-six-controller-readiness-build") #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(base/"current-six-controller-settings.json").toString]
  else if args == ["readiness-audit"] || args == ["journal-audit"] then
    let kind := if args == ["journal-audit"] then "journal" else "readiness"
    discard <| finished ("current-six-controller-"++kind++"-build")
    guard ("current-six-controller-"++kind++"-audit") #["/usr/bin/env","LEAN_PATH="++(base/"study-local-lib").toString,
      (compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/CurrentSixStudy.lean").toString,kind++"-audit-worker"]
  else if args == ["readiness-audit-worker"] || args == ["journal-audit-worker"] then
    let kind := if args == ["journal-audit-worker"] then "journal" else "readiness"
    let audit := fun arguments => command (compiler/"bin/lean").toString
      (#["-j1","-M1536","--run",(project/"tools/research/StudyBuildClosureAudit.lean").toString]++arguments)
    discard <| audit #["inspect",(runRoot/"controller-build").toString,(study/("controller-native-"++kind++".json")).toString]
    discard <| audit #["common-sources",(base/"owned-selection-runtime-build").toString,
      (runRoot/"controller-build").toString,(study/("controller-sources-"++kind++".json")).toString]
  else if args == ["readiness-checks"] || args == ["journal-checks"] then
    checkedController
    let journal := args == ["journal-checks"]
    guard (if journal then "current-six-journal-checks" else "current-six-readiness-checks") #[(runRoot/"controller-build/StudyMain").toString,"readiness-checks",
      (runRoot/"cohort/native-gate/final-warm/stdout").toString,(runRoot/"cohort/native-gate/work.egg").toString,
      (study/(if journal then "readiness-checks-final.json" else "readiness-checks.json")).toString]
  else if args == ["verified-gate"] || args == ["journal-gate"] then
    let journal := args == ["journal-gate"]
    discard <| finished (if journal then "current-six-journal-checks" else "current-six-readiness-checks")
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
    let name := if journal then "native-gate-accepted" else "native-gate-verified"
    write (cohort/(name++".settings.json")) (settings.setObjVal! "record"
      (toJson (cohort/(name++".guard.json")).toString))
  else if args == ["journal-advance"] then
    idle
    let cohort := runRoot/"cohort"
    let prior ← read (cohort/"native-gate-verified.guard.json")
    check (prior.getObjValD "state" == toJson "finished" && prior.getObjValD "ownedPids" == toJson (#[] : Array Nat))
      "close the native lifecycle before off-hook preparation"
    let targets ← (cohort/"native-gate/data/synaptic-targets").readDir
    let targets := targets.filter fun entry => entry.fileName.endsWith ".json"
    check (targets.size == 1) "one actual native target required"
    let some target := targets[0]? | throw (IO.userError "missing native target")
    let key := target.fileName.dropEnd 5 |>.toString
    let request := cohort/"journal-maintenance-input.json"
    write request (Json.mkObj [("kind",toJson "maintenance"),("registryKind",toJson "synapses"),
      ("key",toJson key),("sourceHead",Json.null)])
    let input ← read (cohort/"native-gate-input.json")
    let env : Array (String × Option String) ← IO.ofExcept (fromJson? (input.getObjValD "environment"))
    let unset := env.filterMap fun (key,value) => if value.isNone then some key else none
    let assignments := env.filterMap fun (key,value) => value.map (key++"="++·)
    let runtime ← IO.ofExcept ((input.getObjValD "runtime").getObjValAs? String "path")
    guard "current-six-journal-advance" (#["/usr/bin/env"]++unset.flatMap (fun key => #["-u",key])++assignments++
      #["/bin/sh","-c","exec \"$1\" codex-worker index < \"$2\"","eggshell-native-index",runtime,request.toString])
  else if args == ["readonly-probe-build"] then
    idle
    let cohort := runRoot/"cohort"
    let prior ← read (cohort/"native-gate-accepted.guard.json")
    check (prior.getObjValD "state" == toJson "finished" && prior.getObjValD "ownedPids" == toJson (#[] : Array Nat))
      "readonly failure must be drained"
    write (study/"lifecycle-readonly-failure.json") prior
    write (study/"source-only-recovery.json") (← read (cohort/"native-gate/recovery.json"))
    materialize (runRoot/"controller-build") (runRoot/"readonly-probe-source") (runRoot/"readonly-probe-build")
      "tools.research.ReadOnlyWarmProbe" "current-six-readonly-probe-settings.json"
    guard "current-six-readonly-probe-build" #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(base/"current-six-readonly-probe-settings.json").toString]
  else if args == ["readonly-probe"] then
    discard <| finished "current-six-readonly-probe-build"
    guard "current-six-readonly-probe" #["/usr/bin/env","LEAN_PATH="++(base/"study-local-lib").toString,
      (compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/CurrentSixStudy.lean").toString,"readonly-probe-worker"]
  else if args == ["readonly-probe-worker"] then
    let probeBuild := runRoot/"readonly-probe-build"
    let invoke := fun arguments => command (compiler/"bin/lean").toString
      (#["-j1","-M1536","--run",(project/"tools/research/StudyBuildClosureAudit.lean").toString]++arguments)
    discard <| invoke #["inspect",probeBuild.toString,(study/"readonly-probe-native.json").toString]
    discard <| invoke #["component-sources",(runRoot/"controller-build").toString,probeBuild.toString,
      (study/"readonly-probe-sources.json").toString,"Eggshell.Warm","Eggshell.OwnerViews","Eggshell.PreparedInputs"]
    let cohort := runRoot/"cohort"
    let input ← read (cohort/"native-gate-input.json")
    let original : Array (String × Option String) ← IO.ofExcept (fromJson? (input.getObjValD "environment"))
    let env := original.map fun (key,value) => (key,if key == "EGGSHELL_DATA_ROOT" then some (cohort/"native-gate/recall-data").toString
      else if key == "EGGSHELL_CONFIG" then some (cohort/"native-gate/recall-config.toml").toString else value)
    let env := env.push ("EGGSHELL_CONFIG",some (cohort/"native-gate/recall-config.toml").toString)
    let unset := env.filterMap fun (key,value) => if value.isNone then some key else none
    let assignments := env.filterMap fun (key,value) => value.map (key++"="++·)
    let runtime ← IO.ofExcept ((input.getObjValD "runtime").getObjValAs? String "path")
    discard <| command "/usr/bin/env" (unset.flatMap (fun key => #["-u",key])++assignments++
      #[(probeBuild/"StudyMain").toString,(cohort/"native-gate/output.egg").toString,runtime,(study/"readonly-probe.json").toString])
  else if args == ["scope-build"] then
    idle
    let cohort := runRoot/"cohort"
    let prior ← read (cohort/"native-gate.guard.json")
    let warm ← read (cohort/"native-gate/recall-warm/record.json")
    check (prior.getObjValD "state" == toJson "finished" && prior.getObjValD "ownedPids" == toJson (#[] : Array Nat) &&
      warm.getObjValD "exitCode" == toJson (0 : Nat)) "retain successful product readonly warm before correcting the observer"
    write (study/"observer-scope-failure.json") prior
    let report ← read (cohort/"native-gate/recall-warm/stdout")
    let rows := ((report.getObjValD "databases").getArr?.toOption.getD #[]).flatMap fun row =>
      (row.getObjValD "sources").getArr?.toOption.getD #[]
    write (study/"readonly-warm.json") (Json.mkObj [("timing",warm),("sources",toJson (rows.map fun row =>
      Json.mkObj [("missing",(row.getObjValD "after").getObjValD "missing"),
        ("invalid",(row.getObjValD "after").getObjValD "invalid"),
        ("windows",(row.getObjValD "after").getObjValD "windows"),
        ("lexicalStorage",((row.getObjValD "prepared").getObjValD "lexical").getObjValD "storage"),
        ("numericStorage",((row.getObjValD "prepared").getObjValD "numeric").getObjValD "storage")]))])
    for name in ["StudyReadiness","StudySeedChecks"] do
      let relative := "tools/research/"++name++".lean"
      IO.FS.writeFile (runRoot/"controller-source"/relative) (← IO.FS.readFile (project/relative))
    guard "current-six-controller-scope-build" #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(base/controllerSettings).toString]
  else if args == ["scope-audit"] then
    discard <| finished "current-six-controller-scope-build"
    guard "current-six-controller-scope-audit" (#["/usr/bin/env","LEAN_PATH="++(base/"study-local-lib").toString,
      (compiler/"bin/lean").toString,"-j1","-M1536","--run",(project/"tools/research/CurrentSixStudy.lean").toString]++
      (if located then #["located"] else #[])++#["scope-audit-worker"])
  else if args == ["scope-audit-worker"] then
    let invoke := fun arguments => command (compiler/"bin/lean").toString
      (#["-j1","-M1536","--run",(project/"tools/research/StudyBuildClosureAudit.lean").toString]++arguments)
    discard <| invoke #["inspect",(runRoot/"controller-build").toString,(study/"controller-native-scope.json").toString]
    discard <| invoke #["common-sources",productBuild.toString,(runRoot/"controller-build").toString,
      (study/"controller-sources-scope.json").toString]
  else if args == ["scope-checks"] then
    checkedController
    guard "current-six-scope-checks" #[(runRoot/"controller-build/StudyMain").toString,"readiness-checks",
      (runRoot/"cohort/native-gate/recall-warm/stdout").toString,(runRoot/"cohort/native-gate/output.egg").toString,
      (study/"readiness-checks-scoped.json").toString]
  else if args == ["scope-gate"] then
    discard <| finished "current-six-scope-checks"
    idle
    let cohort := runRoot/"cohort"
    write (study/"source-only-recovery.json") (← read (cohort/"native-gate/recovery.json"))
    IO.FS.removeDirAll (cohort/"native-gate")
    let settings ← read (cohort/"native-gate.settings.json")
    write (cohort/"native-gate-scoped.settings.json") (settings.setObjVal! "record"
      (toJson (cohort/"native-gate-scoped.guard.json").toString))
  else if args == ["record-gate"] then
    idle
    checkedController
    let cohort := runRoot/"cohort"
    let closed ← read (cohort/"native-gate-scoped.guard.json")
    check (closed.getObjValD "exitCode" == toJson (0 : Nat) && closed.getObjValD "ownedPids" == toJson (#[] : Array Nat))
      "successful native lifecycle must be closed"
    let root := cohort/"native-gate"
    let audit ← read (root/"recall-audit.json")
    write (study/"native-lifecycle.json") (Json.mkObj [("guard",closed),("capture",← read (root/"result.json")),
      ("recovery",← read (root/"recovery.json")),("delivery",audit.getObjValD "availableDelivery"),
      ("readonlyWarm",← read (root/"recall-warm/record.json")),("hook",← read (root/"recall-hook/record.json")),
      ("bodySha256",toJson (← hash (root/"recall-body.txt"))),
      ("shutdown",← read (root/"recall-shutdown.json")),("publisherShutdown",← read (root/"recall-publisher-shutdown.json")),
      ("adopted",toJson false),("answeringModelCalls",toJson (0 : Nat))])
    let plan ← read (cohort/"seed-1.plan.json")
    write (study/"frozen-seed.json") (Json.mkObj (["model","effort","handoffChars","runtime","runner","prompt","sourceCommit"].map
      (fun field => (field,plan.getObjValD field)) ++ [("limits",← read (cohort/"seed-1.limits.json")),
        ("seedStarted",toJson false),("adopted",toJson false)]))
  else if args == ["retire-parent-study"] then
    check located "only the replacement cohort may retire its predecessor"
    idle
    checkedController
    let oldRoot := base/"current-six"
    let retired := #[oldRoot/"cohort",oldRoot/"controller-build",oldRoot/"controller-source",
      oldRoot/"readonly-probe-build",oldRoot/"readonly-probe-source",oldRoot/"catalog",oldRoot/"catalog-account",oldRoot/"tmp"]
    let active ← read (runRoot/"cohort/seed-1.plan.json")
    let serialized := active.compress
    for root in retired do check (!(serialized.contains (root.toString++"/"))) "seed plan references a retired study"
    for build in #[productBuild,runRoot/"controller-build"] do
      let response ← IO.FS.readFile (build/"runtime.rsp")
      for root in retired do check (!(response.contains (root.toString++"/"))) "native closure references a retired study"
      excludesLinks (build/"lib") retired
    let keep := #[productRuntime,runRoot/"controller-build/StudyMain",runRoot/"cohort/seed-1.plan.json",
      base/"owned-selection-runtime-build/StudyMain",base/"reference-records-fixture/work.egg/head"]
    let before ← keep.mapM fun path => return (path.toString,← hash path)
    let mut removed := #[]
    for path in retired do
      if !(← path.pathExists) then continue
      let (files,bytes) ← sizeOfTree path
      IO.FS.removeDirAll path
      removed := removed.push (Json.mkObj [("path",toJson path.toString),("files",toJson files),("logicalBytes",toJson bytes)])
    let after ← keep.mapM fun path => return (path.toString,← hash path)
    check (before == after) "protected active inputs changed during cleanup"
    write (study/"parent-cleanup.json") (Json.mkObj [("removed",toJson removed),("protected",toJson after),
      ("archiveCreated",toJson false),("physicalFreedBytesClaimed",toJson false)])
  else if args == ["owned-seed"] then
    idle
    checkedController
    let cohort := runRoot/"cohort"
    let path := cohort/"seed-1.plan.json"
    let plan ← read path
    let output ← IO.ofExcept (plan.getObjValAs? String "output")
    check (!(← (System.FilePath.mk output).pathExists)) "acquisition must not be resubmitted into an existing result"
    let prior ← read (cohort/"seed-1.guard.json")
    check (prior.getObjValD "state" == toJson "finished" && prior.getObjValD "exitCode" == toJson (1 : Nat) &&
      prior.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "initial monitor admission is not closed"
    write (study/"seed-monitor-admission-failure.json") (Json.mkObj [("guard",prior),
      ("acquisitionDirectoryCreated",toJson false),("answeringModelCalls",toJson (0 : Nat))])
    let record := cohort/"seed-1-owned.guard.json"
    write path (plan.setObjVal! "guardRecord" (toJson record.toString))
    let settings ← read (cohort/"seed-1.settings.json")
    let args ← IO.ofExcept (settings.getObjValAs? (Array String) "command")
    check (args.size == 6 && args[1]! == "acquire-bounded" && args[2]! == path.toString) "unexpected acquisition plan"
    write (cohort/"seed-1-owned.settings.json") (settings.setObjVal! "record" (toJson record.toString)
      |>.setObjVal! "command" (toJson (args.set! 3 (← hash path))))
  else if args == ["retire-ended-fixtures"] then
    idle
    let closed ← read (base/(label "current-six-posting-diagnosis-build"++".guard.json"))
    check (closed.getObjValD "state" == toJson "finished" &&
      closed.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "diagnostic compiler is still active"
    let acquisition := runRoot/"cohort/study/seed-auth-retry"
    let head := acquisition/"work.egg/head"
    let keep := #[productRuntime,runRoot/"controller-build/StudyMain",head,
      acquisition/"work.egg/a000bd9e000d52523ed4d17ea4f083ab38ecfbe12af2f91c3a6cae1a7f6b489c.pages"]
    let before ← keep.mapM fun path => return (path.toString,← hash path)
    let retired := #[base/"reference-records-fixture",base/"prepared-literals-fixture",acquisition/"work.egg/derived"]
    let mut removed := #[]
    for path in retired do
      if !(← path.pathExists) then continue
      let (files,bytes) ← sizeOfTree path
      IO.FS.removeDirAll path
      removed := removed.push (Json.mkObj [("path",toJson path.toString),("files",toJson files),("logicalBytes",toJson bytes)])
    let after ← keep.mapM fun path => return (path.toString,← hash path)
    check (before == after) "current reproduction inputs changed during ended-cache cleanup"
    write (study/"ended-cache-cleanup.json") (Json.mkObj [("removed",toJson removed),("protected",toJson after),
      ("archiveCreated",toJson false),("oldPerformanceFixtureRetired",toJson true),
      ("failedSeedOriginalsAndJournalRetained",toJson true),("physicalFreedBytesClaimed",toJson false)])
  else if args == ["retire-ended-runners"] then
    idle
    let keep := #[productRuntime,runRoot/"controller-build/StudyMain",base/"resource-budget-guard-build/StudyMain",
      base/"owned-selection-runtime-build/StudyMain",base/"controller/StudyMain"]
    let before ← keep.mapM fun path => return (path.toString,← hash path)
    let retired := #["reference-records-build","reference-capacity-build","lexical-graph-build",
      "record-price-packed-build","compiled-owner-plan-build","compiled-owner-plan-auditor-build",
      "byte-pages-runtime-build","byte-pages-auditor-build","full-fallback-build"]
    let active := #[runRoot/"cohort/seed-auth-retry.plan.json",runRoot/"controller-build/runtime.rsp",
      productBuild/"runtime.rsp",base/(label "current-six-posting-diagnosis-settings"++".json")]
    for protectedInput in active do
      let bytes ← IO.FS.readFile protectedInput
      for name in retired do
        check (!(bytes.contains ((base/name/"StudyMain").toString))) "active input references an ended runner"
    let mut removed := #[]
    for name in retired do
      let path := base/name/"StudyMain"
      if !(← path.pathExists) then continue
      let bytes := (← path.metadata).byteSize.toNat
      let digest ← hash path
      IO.FS.removeFile path
      removed := removed.push (Json.mkObj [("path",toJson path.toString),("logicalBytes",toJson bytes),("sha256",toJson digest)])
    let after ← keep.mapM fun path => return (path.toString,← hash path)
    check (before == after) "active executables changed during cleanup"
    write (study/"ended-runner-cleanup.json") (Json.mkObj [("removed",toJson removed),("protected",toJson after),
      ("nativeLinkObjectsAndInterfacesRetained",toJson true),("archiveCreated",toJson false)])
  else if args == ["posting-diagnosis-resume"] then
    idle
    let closed ← read (base/(label "current-six-posting-diagnosis-build"++".guard.json"))
    check (closed.getObjValD "state" == toJson "finished" && closed.getObjValD "reason" == toJson "disk-space" &&
      closed.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "retain the completed disk-protection stop"
    write (study/"posting-diagnosis-build-disk-stop.json") closed
    IO.FS.writeFile (runRoot/"posting-diagnosis-source/tools/research/SourceReadPostingAudit.lean")
      (← IO.FS.readFile (project/"tools/research/SourceReadPostingAudit.lean"))
    guard "current-six-posting-diagnosis-resume" #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(base/(label "current-six-posting-diagnosis-settings"++".json")).toString]
  else if args == ["posting-diagnosis-build"] then
    idle
    checkedController
    let cohort := runRoot/"cohort"
    let failed ← read (cohort/"study/seed-auth-retry/failure.json")
    let closed ← read (cohort/"seed-auth-retry.guard.json")
    check (failed.getObjValD "runError" == toJson "seed keep failed" &&
      closed.getObjValD "state" == toJson "finished") "retain the actual native source publication failure"
    let pids ← IO.ofExcept (closed.getObjValAs? (Array Nat) "ownedPids")
    if !pids.isEmpty then
      let remaining ← IO.Process.output {cmd := "/bin/ps",args := #["-p",String.intercalate "," (pids.toList.map toString),"-o","pid=,comm="]}
      check (remaining.exitCode == 1 && remaining.stdout.trimAscii.toString.isEmpty)
        "the previous failed acquisition still owns live processes"
    write (study/"seed-publication-failure.json") (Json.mkObj [
      ("result",failed),("guard",closed),("postGuardPidsGone",toJson true),
      ("acceptedAsSeed",toJson false),("sixStagesCompleted",toJson (0 : Nat)),("adopted",toJson false)])
    let destination := runRoot/"posting-diagnosis-source"
    let build := runRoot/"posting-diagnosis-build"
    let settings := label "current-six-posting-diagnosis-settings"++".json"
    materialize (runRoot/"controller-build") destination build "tools.research.SourceReadPostingAudit" settings
    IO.FS.writeFile (destination/"tools/research/SourceReadPostingAudit.lean")
      (← IO.FS.readFile (project/"tools/research/SourceReadPostingAudit.lean"))
    guard "current-six-posting-diagnosis-build" #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(base/settings).toString]
  else if args == ["posting-diagnosis"] then
    discard <| finished "current-six-posting-diagnosis-resume"
    let acquisition := runRoot/"cohort/study/seed-auth-retry"
    let thread ← read (acquisition/"thread.json")
    let session ← IO.ofExcept ((thread.getObjValD "thread").getObjValAs? String "id")
    guard "current-six-posting-diagnosis" #["/usr/bin/env","EGGSHELL_DATA_ROOT="++(acquisition/"data").toString,
      (runRoot/"posting-diagnosis-build/StudyMain").toString,(acquisition/"work.egg").toString,
      (acquisition/"data/sessions"/session/"checkpoints").toString,(study/"posting-diagnosis.json").toString]
  else if args == ["read-audit-build"] then
    idle
    discard <| finished "current-six-seed-finalize"
    let destination := runRoot/"read-audit-source"
    let build := runRoot/"read-audit-build"
    let settings := label "current-six-read-audit-settings"++".json"
    materialize (runRoot/"controller-build") destination build "tools.research.ReadCoverageAudit" settings
    let seen ← IO.mkRef #[]
    controllerSources destination "tools.research.ReadCoverageAudit" seen
    let entry := destination/"tools/research/ReadCoverageAudit.lean"
    IO.FS.writeFile entry ("import Eggshell.ContractAudit\nimport Eggshell.Setup\n"++(← IO.FS.readFile entry))
    guard "current-six-read-audit-build" #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(base/settings).toString]
  else if args == ["read-audit-check"] then
    discard <| finished "current-six-read-audit-build"
    guard "current-six-read-audit-check" (#["/usr/bin/env","LEAN_PATH="++(base/"study-local-lib").toString,
      (compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (project/"tools/research/CurrentSixStudy.lean").toString]++(if located then #["located"] else #[])++#["read-audit-check-worker"])
  else if args == ["read-audit-check-worker"] then
    let audit := fun arguments => command (compiler/"bin/lean").toString
      (#["-j1","-M1536","--run",(project/"tools/research/StudyBuildClosureAudit.lean").toString]++arguments)
    discard <| audit #["inspect",(runRoot/"read-audit-build").toString,(study/"read-audit-native.json").toString]
    discard <| audit #["common-sources",productBuild.toString,
      (runRoot/"read-audit-build").toString,(study/"read-audit-sources.json").toString]
  else if args == ["read-audit"] then
    discard <| finished "current-six-read-audit-check"
    let cohort := runRoot/"cohort"
    guard "current-six-read-audit" #[(runRoot/"read-audit-build/StudyMain").toString,
      (cohort/"seed-ready/ready.egg").toString,"/Users/ovm/Code/eggshell-benchmarks/aamas-2027/sources/llvm-project",
      (study/"task-definitions.json").toString,(cohort/"seed-read-audit.json").toString]
  else if args == ["finish-seed"] then
    idle
    checkedController
    let cohort := runRoot/"cohort"
    let acquisition := cohort/"study/seed-auth-retry"
    let result ← read (acquisition/"result.json")
    let closed ← read (cohort/"seed-auth-retry.guard.json")
    check (result.getObjValD "completed" == toJson true && closed.getObjValD "state" == toJson "finished" &&
      closed.getObjValD "exitCode" == toJson (0 : Nat) && closed.getObjValD "ownedPids" == toJson (#[] : Array Nat))
      "seed generation and its resource monitor must complete before finalization"
    write (study/"seed-acquisition.json") (Json.mkObj [
      ("runtime",result.getObjValD "runtime"),("usage",result.getObjValD "usage"),
      ("guard",closed),("sixStagesCompleted",toJson (0 : Nat)),("adopted",toJson false)])
    guard "current-six-seed-finalize" #["/usr/bin/env","EGGSHELL_DATA_ROOT="++(acquisition/"data").toString,
      (runRoot/"controller-build/StudyMain").toString,"seed-finalize",acquisition.toString,(cohort/"seed-ready").toString]
  else if args == ["audit-seed"] then
    discard <| finished "current-six-seed-finalize"
    let cohort := runRoot/"cohort"
    let acquisition := cohort/"study/seed-auth-retry"
    let definitions := base.parent.get!/"task-definitions.json"
    check ((← read definitions).getArr?.isOk) "frozen task definitions must be an array"
    write (study/"task-definitions.json") (← read definitions)
    guard "current-six-seed-audit" #["/usr/bin/env","EGGSHELL_DATA_ROOT="++(acquisition/"data").toString,
      (runRoot/"controller-build/StudyMain").toString,"seed-audit",acquisition.toString,
      (study/"task-definitions.json").toString,(cohort/"seed-ready/ready.egg").toString,(cohort/"seed-source-audit.json").toString]
  else if args == ["auth-seed-retry"] then
    check located "authentication retry belongs to the current frozen cohort"
    idle
    checkedController
    let cohort := runRoot/"cohort"
    let prior ← read (cohort/"seed-1-owned.guard.json")
    check (prior.getObjValD "state" == toJson "finished" &&
      prior.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "previous acquisition is still live"
    let failure ← read (cohort/"study/seed-1/failure.json")
    let usage := failure.getObjValD "usage"
    let errors := (usage.getObjValD "errors").getArr?.toOption.getD #[]
    check (usage.getObjValD "protocolPassed" == toJson false && errors.any
      (fun row => ((row.getObjValD "params").getObjValD "error").getObjValD "codexErrorInfo" == toJson "unauthorized"))
      "only the recorded unauthorized acquisition may be retried"
    let target := "/Users/ovm/.codex/auth.json"
    let auth := cohort/"account/auth.json"
    check ((← auth.symlinkMetadata).type == .file) "do not replace an existing credential link"
    let current ← read target
    check (current.getObjValD "auth_mode" == toJson "chatgpt") "current credentials are not ChatGPT managed"
    let planPath := cohort/"seed-auth-retry.plan.json"
    let settingsPath := cohort/"seed-auth-retry.settings.json"
    let output := cohort/"study/seed-auth-retry"
    check (!(← planPath.pathExists) && !(← settingsPath.pathExists) && !(← output.pathExists))
      "preserve earlier retry plans and results"
    write (study/"seed-authentication-failure.json") (Json.mkObj [
      ("guard",prior),("usage",usage),("runError",failure.getObjValD "runError"),
      ("cleanupError",failure.getObjValD "cleanupError"),("publisherError",failure.getObjValD "publisherError"),
      ("unknownUsageCountedAsZero",toJson false),("adopted",toJson false)])
    -- The pinned CLI's FileAuthStorage follows this link when loading and
    -- saving. A rotating refresh token must never have independent copies.
    IO.FS.removeFile auth
    discard <| command "/bin/ln" #["-s",target,auth.toString]
    let oldPlan ← read (cohort/"seed-1.plan.json")
    let record := cohort/"seed-auth-retry.guard.json"
    let plan := oldPlan.setObjVal! "label" (toJson "new-native-seed-auth-retry")
      |>.setObjVal! "output" (toJson output.toString)
      |>.setObjVal! "guardRecord" (toJson record.toString)
    write planPath plan
    let settings ← read (cohort/"seed-1-owned.settings.json")
    let arguments ← IO.ofExcept (settings.getObjValAs? (Array String) "command")
    check (arguments.size == 6 && arguments[1]! == "acquire-bounded") "unexpected acquisition command"
    write settingsPath (settings.setObjVal! "record" (toJson record.toString)
      |>.setObjVal! "command" (toJson (arguments.set! 2 planPath.toString |>.set! 3 (← hash planPath))))
    write (study/"seed-authentication-retry.json") (Json.mkObj [
      ("runtime",plan.getObjValD "runtime"),("runner",plan.getObjValD "runner"),
      ("model",plan.getObjValD "model"),("effort",plan.getObjValD "effort"),
      ("planSha256",toJson (← hash planPath)),("newEmptyDatabase",toJson true),
      ("credentialValuesRecorded",toJson false),("independentRefreshTokenCopy",toJson false),
      ("authenticationStoreSource",toJson "https://github.com/openai/codex/blob/rust-v0.145.0/codex-rs/login/src/auth/storage.rs#L185-L200"),
      ("adopted",toJson false)])
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
