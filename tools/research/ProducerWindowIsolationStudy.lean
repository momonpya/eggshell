import tools.research.StudyLocal
open Lean StudyLocal
namespace ProducerWindowIsolationStudy
def parent := base/"practical-runtime/source-snapshot"
def root := base/"practical-runtime/producer-window-isolation"
def records := project/"docs/candidates/producer-window-isolation"
def configure (build : String) (mainModule : String) : IO Json := do
  return (← read (parent/"build/build.json")).getObjValD "settings"
    |>.setObjVal! "project" (toJson (root/"source").toString)
    |>.setObjVal! "core" (toJson (root/"source").toString)
    |>.setObjVal! "output" (toJson (root/build).toString)
    |>.setObjVal! "parents" (toJson #[(parent/"build").toString,(root/"build").toString])
    |>.setObjVal! "baselineResponse" (toJson (parent/"build/runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (parent/"build/tools_research_StudyMain.o").toString)
    |>.setObjVal! "objectModules" (toJson (parent/"build/object-mapping.json").toString)
    |>.setObjVal! "mainModule" (toJson mainModule)
def buildGuard (tag settings : String) : IO Unit :=
  guard tag #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/settings).toString]
def audit (arguments : Array String) : IO Unit := do
  discard <| command (compiler/"bin/lean").toString (#["-j1","-M768","--run",
    (project/"tools/research/StudyBuildClosureAudit.lean").toString]++arguments)
def prepare : IO Unit := do
  idle
  check (!(← root.pathExists) && !(← records.pathExists)) "fresh isolated window comparison required"
  check ((← hash (parent/"build/StudyMain")) == "720e64d9daf08a8c8f5e716b8cb877bc378253ba51fb43738dc33e05c1b6c534")
    "fixed parent changed"
  IO.FS.createDirAll root
  IO.FS.createDirAll records
  discard <| command "/bin/cp" #["-cR",(parent/"source").toString,(root/"source").toString]
  copyLocalArtifacts (parent/"build") (root/"build")
  discard <| command "/usr/bin/patch" #["-p1","-d",(root/"source").toString,"-i",
    (project/"tools/research/producer-windows/candidate.patch").toString]
  IO.FS.writeFile (root/"source/Eggshell/ProducerWindows.lean")
    (← IO.FS.readFile (project/"tools/research/producer-windows/ProducerWindows.lean"))
  let path := root/"source/tools/research/PreparedSourceView.lean"
  let candidate ← IO.FS.readFile path
  let unrelated := "  let bytes := (toJson stored).compress.utf8ByteSize\n"
  let original := "  let bytes := json.compress.utf8ByteSize+\n"++
    "    (stored.focus.map (fun facts => (toJson facts).compress.utf8ByteSize)).getD 0\n"
  check ((candidate.splitOn unrelated).length == 2 &&
    (← IO.FS.readFile (parent/"source/tools/research/PreparedSourceView.lean")).contains original)
    "parent accounting definition differs; do not fit a new admission rule"
  IO.FS.writeFile path (candidate.replace unrelated original)
  write (records/"plan.json") (Json.mkObj [("parentSha256",toJson (← hash (parent/"build/StudyMain"))),
    ("hypothesis",toJson "carry actual producer-window original-row membership through publication and selection"),
    ("removedConfound",toJson "restore the parent's exact OwnerReady.bytes definition; the prior candidate never reached search"),
    ("unchanged",toJson #["model","ranking/weights","authority","character budget","frame budget","resident limits","charge multiplier"]),
    ("stopRule",toJson "no fitted window widths, weights, owner reservations or budgets"),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  write (root/"settings.json") (← configure "build" "tools.research.StudyMain")
  buildGuard "producer-window-isolation-build" "settings.json"
def observer : IO Unit := do
  idle
  discard <| finished "producer-window-isolation-build"
  audit #["inspect",(root/"build").toString,(records/"native.json").toString]
  audit #["compare-sources",(parent/"build").toString,(root/"build").toString,(records/"sources.json").toString,
    "tools.research.PreparedSourceView","Eggshell.CanonicalSourceCache","+Eggshell.ProducerWindows"]
  let mut patch := ""
  for relative in ["tools/research/PreparedSourceView.lean","Eggshell/CanonicalSourceCache.lean"] do
    let result ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","-L","a/"++relative,
      "-L","b/"++relative,(parent/"source"/relative).toString,(root/"source"/relative).toString]}
    check (result.exitCode == 1) "isolated source change missing"
    patch := patch++result.stdout
  IO.FS.writeFile (records/"candidate.patch") patch
  for name in ["Audit","Checks"] do
    IO.FS.writeFile (root/"source/tools/research"/("ProducerWindow"++name++".lean"))
      (← IO.FS.readFile (project/"tools/research/producer-windows"/(name++".lean")))
  let observer ← IO.FS.readFile (project/"tools/research/LLVMProjectChecks.lean")
  IO.FS.writeFile (root/"source/tools/research/LLVMProjectChecks.lean")
    (observer.replace "import Main\n" "import Main\nimport tools.research.ProducerWindowChecks\n"
      |>.replace "  | [\"bind\",directory,inherited]" ("  | [\"checks\",output] => do ProducerWindowChecks.run (.mk output); return 0\n"++
        "  | [\"bind\",directory,inherited]"))
  copyLocalArtifacts (root/"build") (root/"llvm-build")
  write (root/"llvm-settings.json") (← configure "llvm-build" "tools.research.LLVMProjectChecks")
  buildGuard "producer-window-isolation-observer" "llvm-settings.json"
def checks : IO Unit := do
  idle
  discard <| finished "producer-window-isolation-observer"
  audit #["inspect",(root/"llvm-build").toString,(records/"observer-native.json").toString]
  audit #["common-sources",(root/"build").toString,(root/"llvm-build").toString,(records/"observer-sources.json").toString]
  write (records/"proofs.json") (Json.mkObj [
    ("stdout",toJson (← IO.FS.readFile (root/"llvm-build/tools_research_ProducerWindowAudit-lean.stdout"))),
    ("stderr",toJson (← IO.FS.readFile (root/"llvm-build/tools_research_ProducerWindowAudit-lean.stderr")))])
  guard "producer-window-isolation-checks" #["/usr/bin/env","-u","LEAN_NUM_THREADS",
    (root/"llvm-build/StudyMain").toString,"checks",(records/"checks.json").toString]
def capture : IO Unit := do
  idle
  discard <| finished "producer-window-isolation-checks"
  check ((← read (records/"checks.json")).getObjValD "allPassed" == toJson true) "native component checks did not pass"
  let target := root/"prefix"
  check (!(← target.pathExists) && !(← (records/"llvm").pathExists)) "fresh candidate installation required"
  discard <| command "/bin/cp" #["-cR",(parent/"prefix").toString,target.toString]
  let executable := target/"libexec/eggshell"
  check ((← executable.symlinkMetadata).type == .symlink) "expected inherited backend symlink"
  IO.FS.removeFile executable
  discard <| command "/bin/ln" #["-s",(root/"build/StudyMain").toString,executable.toString]
  discard <| command (root/"llvm-build/StudyMain").toString #["bind",target.toString,(parent/"prefix").toString]
  let prior ← read (parent/"installation.json")
  let files ← (← IO.ofExcept (prior.getObjValAs? (Array Json) "pluginFiles")).mapM fun file => do
    let before ← IO.ofExcept (file.getObjValAs? String "path")
    check (before.startsWith ((parent/"prefix").toString++"/")) "plugin artifact escaped its installation"
    let path := before.replace (parent/"prefix").toString target.toString
    return Json.mkObj [("path",toJson path),("sha256",toJson (← hash (.mk path)))]
  let environment : Array (String × Option String) ← IO.ofExcept (prior.getObjValAs? _ "environment")
  let updates := #[("EGGSHELL_PREFIX",some target.toString),("PLUGIN_ROOT",some (target/"plugins/eggshell").toString),
    ("EGGSHELL_DATA_ROOT",some (root/"llvm/client").toString),("TMPDIR",some (root/"llvm/tmp").toString)]
  let environment := environment.filter (fun field => !updates.any (·.1 == field.1))++updates
  let installation := prior
    |>.setObjVal! "runtime" (Json.mkObj [("path",toJson executable.toString),("sha256",toJson (← hash executable))])
    |>.setObjVal! "pluginRoot" (toJson (target/"plugins/eggshell").toString)
    |>.setObjVal! "pluginFiles" (toJson files)
    |>.setObjVal! "environment" (toJson environment)
    |>.setObjVal! "handoffChars" (toJson (120000 : Nat))
  write (root/"installation.json") installation
  IO.FS.createDirAll (records/"llvm")
  let original ← read (project/"docs/practical-runtime/recovery/before-delivery.json")
  let plan := Json.mkObj [("installation",installation),("original",original.getObjValD "source"),
    ("originalFiles",original.getObjValD "sourceFiles"),
    ("definitions",toJson (base/"practical-runtime/interrupted-recovery/definitions.json").toString),
    ("workspace",toJson "/Users/ovm/Code/eggshell-benchmarks/aamas-2027/sources/llvm-project"),
    ("root",toJson (root/"llvm").toString),("records",toJson (records/"llvm").toString)]
  write (root/"llvm-plan.json") plan
  write (records/"llvm/plan.json") plan
  guard "producer-window-isolation-capture" #["/usr/bin/env","-u","LEAN_NUM_THREADS",
    "EGGSHELL_PREFIX="++target.toString,"EGGSHELL_DATA_ROOT="++(root/"llvm/client").toString,
    (root/"llvm-build/StudyMain").toString,"prepare",(root/"llvm-plan.json").toString]
def run : IO Unit := do
  idle
  discard <| finished "producer-window-isolation-capture"
  let before ← read (project/"docs/candidates/source-snapshot/llvm/before-delivery.json")
  let after ← read (records/"llvm/before-delivery.json")
  let oldTopics ← IO.ofExcept ((before.getObjValD "topics").getArr?)
  let newTopics ← IO.ofExcept ((after.getObjValD "topics").getArr?)
  check (oldTopics.map (·.getObjValD "frozen") == newTopics.map (·.getObjValD "frozen") &&
    before.getObjValD "capturedHead" == after.getObjValD "capturedHead" &&
    before.getObjValD "sourceFiles" == after.getObjValD "sourceFiles") "fixed comparison input differs"
  write (records/"llvm/fixed-inputs.json") (Json.mkObj [("sameHeadAndSourceBytes",toJson true),
    ("sameFrozenEvidence",toJson true),("answeringModelCalls",toJson (0 : Nat)),("acceptedSeed",toJson false)])
  let installation := (← read (root/"llvm-plan.json")).getObjValD "installation"
  let environment : Array (String × Option String) ← IO.ofExcept (installation.getObjValAs? _ "environment")
  let unsets := environment.filterMap fun (key,value) => if value.isNone then some key else none
  let values := environment.filterMap fun (key,value) => value.map (fun item => key++"="++item)
  guard "producer-window-isolation-llvm" (#["/usr/bin/env"]++unsets.flatMap (fun key => #["-u",key])++values++
    #[(root/"llvm-build/StudyMain").toString,"run",(root/"llvm-plan.json").toString])
def probe : IO Unit := do
  idle
  discard <| finished "producer-window-isolation-llvm"
  check ((← read (records/"llvm/result.json")).getObjValD "allSixReachTarget" == toJson false)
    "only diagnose the recorded failed request"
  IO.FS.writeFile (root/"source/tools/research/ProducerPlanProbe.lean")
    (← IO.FS.readFile (project/"tools/research/ProducerPlanProbe.lean"))
  copyLocalArtifacts (root/"llvm-build") (root/"probe-build")
  let configuration := (← read (root/"llvm-build/build.json")).getObjValD "settings"
    |>.setObjVal! "output" (toJson (root/"probe-build").toString)
    |>.setObjVal! "parents" (toJson #[(root/"llvm-build").toString,(root/"build").toString])
    |>.setObjVal! "mainModule" (toJson "tools.research.ProducerPlanProbe")
  write (root/"probe-settings.json") configuration
  buildGuard "producer-window-isolation-probe-build" "probe-settings.json"
def probeRun : IO Unit := do
  idle
  discard <| finished "producer-window-isolation-probe-checked-build"
  audit #["inspect",(root/"probe-build").toString,(records/"probe-native.json").toString]
  audit #["common-sources",(root/"build").toString,(root/"probe-build").toString,(records/"probe-sources.json").toString]
  guard "producer-window-isolation-probe" #["/usr/bin/env","-u","LEAN_NUM_THREADS",
    "EGGSHELL_PREFIX="++(root/"prefix").toString,"EGGSHELL_DATA_ROOT="++(root/"llvm/host").toString,
    (root/"probe-build/StudyMain").toString,(root/"llvm/llvm.egg/owners/0/source.egg").toString,
    (project/"docs/candidates/source-snapshot/llvm/diagnostic/domain.json").toString,
    (records/"plan-probe.json").toString]
def probeRebuild : IO Unit := do
  idle
  let stopped ← read (base/"producer-window-isolation-probe-build.guard.json")
  check (stopped.getObjValD "state" == toJson "finished" && stopped.getObjValD "exitCode" == toJson (1 : Nat) &&
    stopped.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "only correct the stopped probe elaboration"
  write (records/"probe-build-refusal.json") (Json.mkObj [("guard",stopped),
    ("stdout",toJson (← IO.FS.readFile (root/"probe-build/tools_research_ProducerPlanProbe-lean.stdout"))),
    ("stderr",toJson (← IO.FS.readFile (root/"probe-build/tools_research_ProducerPlanProbe-lean.stderr"))),
    ("productChanged",toJson false),("modelOrQueryStarted",toJson false)])
  IO.FS.writeFile (root/"source/tools/research/ProducerPlanProbe.lean")
    (← IO.FS.readFile (project/"tools/research/ProducerPlanProbe.lean"))
  buildGuard "producer-window-isolation-probe-checked-build" "probe-settings.json"
def contractProbe : IO Unit := do
  idle
  discard <| finished "producer-window-isolation-probe"
  write (records/"plan-probe-executed-source.json") (← read (root/"probe-build/tools_research_ProducerPlanProbe.source"))
  IO.FS.writeFile (root/"source/Eggshell/SourcePlanContract.lean")
    (← IO.FS.readFile (project/"tools/research/source-plan-contract/SourcePlanContract.lean"))
  IO.FS.writeFile (root/"source/tools/research/ProducerPlanProbe.lean")
    (← IO.FS.readFile (project/"tools/research/ProducerPlanProbe.lean"))
  copyLocalArtifacts (root/"probe-build") (root/"contract-probe-build")
  let configuration := (← read (root/"probe-build/build.json")).getObjValD "settings"
    |>.setObjVal! "output" (toJson (root/"contract-probe-build").toString)
    |>.setObjVal! "parents" (toJson #[(root/"probe-build").toString,(root/"build").toString])
  write (root/"contract-probe-settings.json") configuration
  buildGuard "source-plan-contract-probe-build" "contract-probe-settings.json"
def contractProbeRun (tag : String) : IO Unit := do
  idle
  discard <| finished tag
  audit #["inspect",(root/"contract-probe-build").toString,(records/"contract-probe-native.json").toString]
  audit #["common-sources",(root/"build").toString,(root/"contract-probe-build").toString,
    (records/"contract-probe-sources.json").toString]
  guard "source-plan-contract-probe" #["/usr/bin/env","-u","LEAN_NUM_THREADS",
    "EGGSHELL_PREFIX="++(root/"prefix").toString,"EGGSHELL_DATA_ROOT="++(root/"llvm/host").toString,
    (root/"contract-probe-build/StudyMain").toString,(root/"llvm/llvm.egg/owners/0/source.egg").toString,
    (project/"docs/candidates/source-snapshot/llvm/diagnostic/domain.json").toString,
    (records/"contract-probe.json").toString]
def contractProbeRebuild (previous next : String) : IO Unit := do
  idle
  check ([previous,next].all fun tag => tag.startsWith "source-plan-contract-" &&
    tag.toList.all (fun char => char.isAlphanum || char == '-')) "source-contract guard tags required"
  let stopped ← read (base/(previous++".guard.json"))
  check (stopped.getObjValD "state" == toJson "finished" && stopped.getObjValD "exitCode" == toJson (1 : Nat) &&
    stopped.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "only correct the stopped source-contract elaboration"
  let receipt := records/(previous++"-refusal.json")
  check (!(← receipt.pathExists)) "preserve source-contract compiler refusal"
  write receipt (Json.mkObj [("guard",stopped),
    ("stdout",toJson (← IO.FS.readFile (root/"contract-probe-build/Eggshell_SourcePlanContract-lean.stdout"))),
    ("stderr",toJson (← IO.FS.readFile (root/"contract-probe-build/Eggshell_SourcePlanContract-lean.stderr"))),
    ("productChanged",toJson false),("modelOrQueryStarted",toJson false)])
  IO.FS.writeFile (root/"source/Eggshell/SourcePlanContract.lean")
    (← IO.FS.readFile (project/"tools/research/source-plan-contract/SourcePlanContract.lean"))
  IO.FS.writeFile (root/"source/tools/research/ProducerPlanProbe.lean")
    (← IO.FS.readFile (project/"tools/research/ProducerPlanProbe.lean"))
  buildGuard next "contract-probe-settings.json"
end ProducerWindowIsolationStudy
def main : List String → IO Unit
  | ["prepare"] => ProducerWindowIsolationStudy.prepare
  | ["observer"] => ProducerWindowIsolationStudy.observer
  | ["checks"] => ProducerWindowIsolationStudy.checks
  | ["capture"] => ProducerWindowIsolationStudy.capture
  | ["run"] => ProducerWindowIsolationStudy.run
  | ["probe"] => ProducerWindowIsolationStudy.probe
  | ["probe-run"] => ProducerWindowIsolationStudy.probeRun
  | ["probe-rebuild"] => ProducerWindowIsolationStudy.probeRebuild
  | ["contract-probe"] => ProducerWindowIsolationStudy.contractProbe
  | ["contract-probe-run",tag] => ProducerWindowIsolationStudy.contractProbeRun tag
  | ["contract-probe-rebuild",previous,next] => ProducerWindowIsolationStudy.contractProbeRebuild previous next
  | _ => throw (IO.userError "ProducerWindowIsolationStudy prepare|observer|checks|capture|run")
