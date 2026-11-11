import tools.research.StudyLocal

open Lean StudyLocal
namespace PracticalRuntimeStudy

def runtime := base/"canonical-decoder-runtime"
def previous := base/"current-six/fixed-sequence"
def root := base/"practical-runtime"
def records := project/"docs/practical-runtime"
def runtimeHash := "7cc1432d2d3931a26d60e3e614807545e3f6b522737838bdabc1b1c626e657ab"

partial def copySource (origin target : System.FilePath) : IO Unit := do
  let metadata ← origin.symlinkMetadata
  if metadata.type == .dir then
    IO.FS.createDirAll target
    for entry in ← origin.readDir do
      if entry.fileName != ".lake" then copySource entry.path (target/entry.fileName)
  else if metadata.type == .file then
    IO.FS.writeBinFile target (← IO.FS.readBinFile origin)

partial def pluginFiles (path : System.FilePath) : IO (Array System.FilePath) := do
  let metadata ← path.symlinkMetadata
  if metadata.type == .file then return #[path]
  if metadata.type != .dir then return #[]
  let mut files := #[]
  for entry in ← path.readDir do files := files ++ (← pluginFiles entry.path)
  return files

/-- Keep the existing product sources. Missing research drivers come from the
already frozen answering controller, never from unrelated working-tree edits. -/
partial def freeze (name : String) (seen : IO.Ref (Std.HashSet String)) : IO Unit := do
  if (← seen.get).contains name then return
  seen.modify (·.insert name)
  let relative := name.replace "." "/"++".lean"
  let current := runtime/"source"/relative
  let fallback := previous/"controller-source"/relative
  let origin ← if ← current.pathExists then pure current else do
    if !name.startsWith "tools.research." then
      check (!(← fallback.pathExists)) ("product module missing from fixed runtime: "++name)
      return
    if !(← fallback.pathExists) then return
    pure fallback
  let text ← IO.FS.readFile origin
  let target := root/"source"/relative
  IO.FS.createDirAll target.parent.get!
  IO.FS.writeFile target text
  for line in text.splitOn "\n" do
    let line := line.trimAscii.toString
    let introducer := if line.startsWith "public import " then "public import " else "import "
    if line.startsWith introducer then
      for dependency in (line.drop introducer.length).toString.splitOn " " do
        if !dependency.isEmpty then freeze dependency seen

def prepare : IO Unit := do
  idle
  check (!(← root.pathExists)) "preserve prior practical-runtime evidence"
  check ((← hash (runtime/"build/StudyMain")) == runtimeHash) "fixed product changed"
  let seed := previous/"controller-source/tools/research/StudyMain.lean"
  check (← seed.pathExists) "frozen study driver missing"
  IO.FS.createDirAll root
  IO.FS.createDirAll records
  IO.FS.createDirAll (root/"source/.lake/build/lib/lean")
  copySource (runtime/"source") (root/"source")
  freeze "tools.research.StudyMain" (← IO.mkRef {})
  let mapping := root/"source/object-mapping.json"
  IO.FS.writeFile mapping (← IO.FS.readFile (runtime/"source/object-mapping.json"))
  let settings := (← read (runtime/"build/build.json")).getObjValD "settings"
    |>.setObjVal! "project" (toJson (root/"source").toString)
    |>.setObjVal! "core" (toJson (root/"source").toString)
    |>.setObjVal! "output" (toJson (root/"build").toString)
    |>.setObjVal! "parents" (toJson #[(runtime/"build").toString,(previous/"controller-build").toString])
    |>.setObjVal! "objectModules" (toJson mapping.toString)
    |>.setObjVal! "baselineResponse" (toJson (runtime/"build/runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (runtime/"build/tools_research_OwnedSelectionRuntime.o").toString)
    |>.setObjVal! "mainModule" (toJson "tools.research.StudyMain")
    |>.setObjVal! "force" (toJson (#[] : Array String))
  write (root/"build-settings.json") settings
  write (records/"plan.json") (Json.mkObj [
    ("runtimeSha256",toJson runtimeHash),
    ("productChanges",toJson (0 : Nat)),
    ("additionalOptimizationTrials",toJson false),
    ("sequence",toJson #["native save/stop/source-only recovery/new-chat delivery",
      "actual Codex seed/topic1/topic2/topic3/topic1/topic2/topic3"]),
    ("temporaryConcurrencyCriterion",toJson "at least 10 clients, all finish within client-count seconds; 16-client local ceiling"),
    ("adoptionRequiresMatchedInclusiveTokensQualityAndDeadline",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  guard "practical-controller-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"build-settings.json").toString]

def audit : IO Unit := do
  idle
  discard <| finished "practical-controller-build3"
  let inspect := fun args => command (compiler/"bin/lean").toString
    (#["-j1","-M768","--run",(project/"tools/research/StudyBuildClosureAudit.lean").toString]++args)
  discard <| inspect #["inspect",(root/"build").toString,(records/"native.json").toString]
  discard <| inspect #["common-sources",(runtime/"build").toString,(root/"build").toString,
    (records/"sources.json").toString]
  check ((← read (records/"native.json")).getObjValD "consistent" == toJson true &&
    (← read (records/"sources.json")).getObjValD "allProductCorePresent" == toJson true &&
    (← read (records/"sources.json")).getObjValD "commonSourcesUnchanged" == toJson true)
    "native observer does not have the fixed product closure"

def lifecycle : IO Unit := do
  idle
  check ((← read (records/"sources.json")).getObjValD "commonSourcesUnchanged" == toJson true)
    "native source audit required"
  check ((← hash (runtime/"build/StudyMain")) == runtimeHash) "fixed product changed"
  let template ← read (runtime/"preflight-input.json")
  let plugin ← IO.ofExcept (template.getObjValAs? String "plugin")
  let files ← pluginFiles (.mk plugin)
  let artifacts ← files.mapM fun path => do
    pure (Json.mkObj [("path",toJson path.toString),("sha256",toJson (← hash path))])
  let destination := root/"lifecycle"
  check (!(← destination.pathExists)) "never retry the same lifecycle directory"
  let environment : Array (String × Option String) ← IO.ofExcept (fromJson? (template.getObjValD "environment"))
  let environment := environment.filter (fun row =>
      !["EGGSHELL_CONFIG","EGGSHELL_DATA_ROOT"].contains row.1) ++
    #[("EGGSHELL_DATA_ROOT",some (destination/"data").toString)]
  let input := root/"lifecycle-input.json"
  write input (Json.mkObj [
    ("runtime",Json.mkObj [("path",template.getObjValD "runtime"),("sha256",toJson runtimeHash)]),
    ("handoffChars",toJson (500000 : Nat)),("pluginRoot",toJson plugin),
    ("pluginFiles",toJson artifacts),("environment",toJson environment)])
  let unset := environment.filterMap fun (key,value) => if value.isNone then some key else none
  let set := environment.filterMap fun (key,value) => value.map fun text => key++"="++text
  guard "practical-lifecycle" (#["/usr/bin/env"]++unset.flatMap (fun key => #["-u",key])++set++
    #[(root/"build/StudyMain").toString,"seed-checks-generic",input.toString,destination.toString])

def collectLifecycle : IO Unit := do
  idle
  let monitor ← finished "practical-lifecycle"
  let area := root/"lifecycle"
  let result ← read (area/"result.json")
  let recovery ← read (area/"recovery.json")
  let audit ← read (area/"recall-audit.json")
  let timing ← read (area/"recall-hook/record.json")
  check ((audit.getObjValD "requiredDelivery").getObjValD "targetMet" == toJson true &&
    recovery.getObjValD "publicationUnchanged" == toJson true &&
    timing.getObjValD "exitCode" == toJson (0 : Nat)) "lifecycle did not pass"
  let mut stops := #[]
  for name in #["shutdown.json","publisher-shutdown.json","recall-shutdown.json","recall-publisher-shutdown.json"] do
    let value ← read (area/name)
    check (value.getObjValD "processExited" == toJson true &&
      value.getObjValD "daemonExitCode" == toJson (0 : Nat)) "owned service did not exit normally"
    stops := stops.push (name,value)
  write (records/"lifecycle.json") (Json.mkObj [
    ("runtimeSha256",toJson runtimeHash),("observerSha256",toJson (← hash (root/"build/StudyMain"))),
    ("guard",monitor),("capture",result),("recovery",recovery),
    ("requiredDelivery",audit.getObjValD "requiredDelivery"),
    ("availableDelivery",audit.getObjValD "availableDelivery"),("hookTiming",timing),
    ("bodySha256",toJson (← hash (area/"recall-body.txt"))),
    ("stops",toJson stops),("actualCodexChat",toJson false),
    ("realMcpServerUsed",toJson false),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])

def prepareCodex : IO Unit := do
  idle
  check ((← read (records/"lifecycle.json")).getObjValD "actualCodexChat" == toJson false)
    "complete model-free lifecycle first"
  let cohort := root/"cohort"
  let environment := "EGGSHELL_STUDY_AUTH_FILE="++(previous/"cohort/account/auth.json").toString
  discard <| command "/usr/bin/env" #[environment,(root/"build/StudyMain").toString,"bootstrap","prepare",
    cohort.toString,(previous/"cohort").toString,(runtime/"prefix/libexec/eggshell").toString]
  guard "practical-codex-discovery" #[(root/"build/StudyMain").toString,"probe",(cohort/"discovery.input.json").toString]

def registerCodex : IO Unit := do
  idle
  let monitor ← finished "practical-codex-discovery"
  let cohort := root/"cohort"
  let discovery ← read (cohort/"discovery/hooks.json")
  write (records/"unregistered-codex.json") (Json.mkObj [
    ("guard",monitor),("hooks",discovery),("answeringModelCalls",toJson (0 : Nat)),
    ("admitted",toJson false),("reason",toJson "A new CODEX_HOME needs plugin registration in addition to copied marketplace configuration.")])
  IO.FS.rename (cohort/"discovery") (cohort/"unregistered-discovery")
  let invoke := fun args => command "/usr/bin/env" (#["CODEX_HOME="++(cohort/"account").toString,
    "/Users/ovm/.nodebrew/current/bin/codex"]++args)
  IO.FS.writeFile (cohort/"marketplace-add.json")
    (← invoke #["plugin","marketplace","add",(cohort/"prefix").toString,"--json"])
  IO.FS.writeFile (cohort/"plugin-add.json") (← invoke #["plugin","add","eggshell@eggshell","--json"])
  guard "practical-codex-registered" #[(root/"build/StudyMain").toString,"probe",(cohort/"discovery.input.json").toString]

def prepareSequence : IO Unit := do
  idle
  let discovery ← finished "practical-codex-registered"
  let cohort := root/"cohort"
  let driver := (root/"build/StudyMain").toString
  discard <| command driver #["bootstrap","trust-hooks",cohort.toString]
  discard <| command driver #["bootstrap","seed-input",cohort.toString,"500000"]
  let input ← read (cohort/"native-gate-input.json")
  let environment : Array (String × Option String) ← IO.ofExcept (fromJson? (input.getObjValD "environment"))
  let unset := environment.filterMap fun (key,value) => if value.isNone then some key else none
  let set := environment.filterMap fun (key,value) => value.map fun text => key++"="++text
  -- These committed files are metadata of the existing fixed trial contract.
  -- They are sealed before model acquisition, never taken from mutable output.
  let paths := #["tools/research/StudyBuildMain.lean","docs/benchmarks/reseed-delivery-contract.json",
      "docs/benchmarks/llvm-three-topics.json","docs/benchmarks/readme-memory-facts.json"]
  discard <| command "/usr/bin/git" (#["diff","--exit-code","--"]++paths)
  let mut harness := #[]
  for relative in paths do
    let target := root/"source"/relative
    IO.FS.createDirAll target.parent.get!
    IO.FS.writeFile target (← IO.FS.readFile (project/relative))
    harness := harness.push (relative,← hash target)
  write (records/"codex-discovery.json") (Json.mkObj [
    ("guard",discovery),("hooks",← read (cohort/"hooks-trusted.json")),
    ("sealedMetadata",toJson harness),("answeringModelCalls",toJson (0 : Nat))])
  guard "practical-sequence-native" (#["/usr/bin/env"]++unset.flatMap (fun key => #["-u",key])++set++
    #[driver,"seed-checks-generic",(cohort/"native-gate-input.json").toString,(cohort/"native-gate").toString])
  let settingsPath := base/"practical-sequence-native.guard-settings.json"
  write settingsPath ((← read settingsPath).setObjVal! "record" (toJson (cohort/"native-gate.guard.json").toString))

def sealSeed : IO Unit := do
  idle
  let cohort := root/"cohort"
  let monitor ← read (cohort/"native-gate.guard.json")
  check (monitor.getObjValD "state" == toJson "finished" && monitor.getObjValD "exitCode" == toJson (0 : Nat) &&
    monitor.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "isolated hook gate has not passed and drained"
  discard <| command (root/"build/StudyMain").toString #["bootstrap","seal-seed",cohort.toString]
  write (records/"sequence-plan.json") (Json.mkObj [
    ("runtimeSha256",toJson runtimeHash),("controllerSha256",toJson (← hash (root/"build/StudyMain"))),
    ("model",toJson "gpt-5.6-luna"),("effort",toJson "xhigh"),
    ("order",toJson #["new empty-DB seed","1/1","1/2","1/3","2/1","2/2","2/3"]),
    ("seedPlanSha256",toJson (← hash (cohort/"seed-1.plan.json"))),
    ("inclusiveSeedLimit",toJson (5000000 : Nat)),("seedTimeoutMs",toJson (900000 : Nat)),
    ("cohortGate",monitor),("answeringModelCallsAtSealing",toJson (0 : Nat)),
    ("allSixStagesCompleted",toJson false),("adopted",toJson false)])

def main (args : List String) : IO Unit := match args with
  | ["prepare"] => prepare
  | ["audit"] => audit
  | ["lifecycle"] => lifecycle
  | ["collect-lifecycle"] => collectLifecycle
  | ["prepare-codex"] => prepareCodex
  | ["register-codex"] => registerCodex
  | ["prepare-sequence"] => prepareSequence
  | ["seal-seed"] => sealSeed
  | ["resume-build"] => do
    idle
    let failed ← read (base/"practical-controller-build.guard.json")
    check (failed.getObjValD "state" == toJson "finished" &&
      failed.getObjValD "exitCode" == toJson (1 : Nat) &&
      failed.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "previous build has not drained"
    write (records/"first-build-rejected.json") (Json.mkObj [
      ("guard",failed),("reason",toJson "Missing empty inherited-library directory; no DB, hook or model ran."),
      ("productChanges",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat))])
    IO.FS.createDirAll (root/"source/.lake/build/lib/lean")
    guard "practical-controller-build2" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(root/"build-settings.json").toString]
  | ["fix-research-root"] => do
    idle
    let failed ← read (base/"practical-controller-build2.guard.json")
    check (failed.getObjValD "state" == toJson "finished" &&
      failed.getObjValD "exitCode" == toJson (1 : Nat) &&
      failed.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "previous build has not drained"
    if !(← (records/"second-build-rejected.json").pathExists) then
      write (records/"second-build-rejected.json") (Json.mkObj [
        ("guard",failed),("reason",toJson "Research project root still pointed at product-only sources; no DB, hook or model ran.")])
    copySource (runtime/"source") (root/"source")
    let settings := (← read (root/"build-settings.json")).setObjVal! "project" (toJson (root/"source").toString)
    write (root/"build-settings.json") settings
    guard "practical-controller-build3" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
      (project/"tools/research/StudyBuildMain.lean").toString,(root/"build-settings.json").toString]
  | _ => throw (IO.userError "PracticalRuntimeStudy prepare")
end PracticalRuntimeStudy
def main := PracticalRuntimeStudy.main
