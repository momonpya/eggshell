import tools.research.StudyLocal
open Lean StudyLocal
namespace SourcePlanContractStudy
def parent := base/"practical-runtime/producer-window-isolation"
def root := base/"practical-runtime/source-plan-contract"
def records := project/"docs/candidates/source-plan-contract"
def frame : System.FilePath := root/"Frames.lean"
def invoke (action : String) : IO Unit := do
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",frame.toString,action]

/-- Instantiate the existing direct-hook harness. The source project is a
shared read-only input; each installation gets fresh services and clients. -/
def frames : IO Unit := do
  let source ← IO.FS.readFile (project/"tools/research/ProducerWindowIsolationStudy.lean")
  let names := ["configure","buildGuard","audit","observer","checks","capture","run"]
  let functions := (source.splitOn "\ndef ").filter fun part => names.any (fun name => part.startsWith (name++" "))
  check (functions.length == names.length) "comparison harness structure changed"
  let mut body := "import tools.research.StudyLocal\nopen Lean StudyLocal\nnamespace ContractFrames\n"++
    "def parent : System.FilePath := "++(toJson parent.toString).compress++"\n"++
    "def root : System.FilePath := "++(toJson root.toString).compress++"\n"++
    "def records : System.FilePath := "++(toJson records.toString).compress++"\n"
  for function in functions do
    let function := function.replace "producer-window-isolation" "source-plan-contract"
    let function := function.replace
      "\"tools.research.PreparedSourceView\",\"Eggshell.CanonicalSourceCache\",\"+Eggshell.ProducerWindows\""
      "\"tools.research.PreparedOwnerArena\",\"+Eggshell.SourcePlanContract\""
    let function := function.replace
      "[\"tools/research/PreparedSourceView.lean\",\"Eggshell/CanonicalSourceCache.lean\"]"
      "[\"tools/research/PreparedOwnerArena.lean\"]"
    let function := function.replace "let plan := Json.mkObj [(\"installation\",installation)"
      "let plan := Json.mkObj [(\"project\",toJson (parent/\"llvm/llvm.egg\").toString),(\"installation\",installation)"
    body := body++"def "++function++"\n"
  body := body++"end ContractFrames\ndef main : List String → IO Unit\n"++
    "  | [\"configure\"] => do\n"++
    "      StudyLocal.write (ContractFrames.root/\"settings.json\") (← ContractFrames.configure \"build\" \"tools.research.StudyMain\")\n"++
    "      ContractFrames.buildGuard \"source-plan-contract-build\" \"settings.json\"\n"++
    "  | [\"observer\"] => ContractFrames.observer\n"++
    "  | [\"checks\"] => ContractFrames.checks\n"++
    "  | [\"capture\"] => ContractFrames.capture\n"++
    "  | [\"run\"] => ContractFrames.run\n"++
    "  | _ => throw (IO.userError \"ContractFrames action\")\n"
  check (body.contains "[\"tools/research/PreparedOwnerArena.lean\"]" &&
    body.contains "(\"project\",toJson (parent/\"llvm/llvm.egg\").toString)")
    "comparison harness did not preserve the explicit shared project"
  IO.FS.writeFile frame body
  write (records/"harness.json") (Json.mkObj [("source",toJson body),
    ("baseHarnessSha256",toJson (← hash (project/"tools/research/ProducerWindowIsolationStudy.lean"))),
    ("sharedProject",toJson (parent/"llvm/llvm.egg").toString),
    ("freshClientRoot",toJson (root/"llvm/client").toString)])
def prepare : IO Unit := do
  idle
  discard <| finished "source-plan-contract-probe"
  check (!(← root.pathExists) && !(← records.pathExists)) "fresh integrated source-contract candidate required"
  check ((← hash (parent/"build/StudyMain")) == "e1048fde74034ccec16844190dad1df2b2db667df443cbfb194b7f89014dde34")
    "producer-window parent changed"
  let inspected ← read (project/"docs/candidates/producer-window-isolation/contract-probe.json")
  let owners ← IO.ofExcept (inspected.getObjValAs? (Array Json) "owners")
  check (owners.size == 40 && owners.all (·.getObjValD "sourceContractAccepted" == toJson true))
    "original-source contract did not accept the full inspected domain"
  IO.FS.createDirAll root
  IO.FS.createDirAll records
  discard <| command "/bin/cp" #["-cR",(parent/"source").toString,(root/"source").toString]
  copyLocalArtifacts (parent/"build") (root/"build")
  IO.FS.writeFile (root/"source/Eggshell/SourcePlanContract.lean")
    (← IO.FS.readFile (project/"tools/research/source-plan-contract/SourcePlanContract.lean"))
  discard <| command "/usr/bin/patch" #["-p1","-d",(root/"source").toString,"-i",
    (project/"tools/research/source-plan-contract/Arena.patch").toString]
  write (records/"plan.json") (Json.mkObj [("parentSha256",toJson (← hash (parent/"build/StudyMain"))),
    ("change",toJson "validate original references, costs, ranges and complete eligibility independently of advisory grouping"),
    ("unchanged",toJson #["producer groups","ranking and weights","budgets and multiplier","original source","model","authority"]),
    ("sharedProject",toJson (parent/"llvm/llvm.egg").toString),("answeringModelCalls",toJson (0 : Nat)),
    ("adopted",toJson false)])
  frames
  invoke "configure"
def observer : IO Unit := do
  idle
  invoke "observer"
  IO.FS.writeFile (root/"source/tools/research/SourcePlanContractAudit.lean")
    (← IO.FS.readFile (project/"tools/research/source-plan-contract/Audit.lean"))
  let path := root/"source/tools/research/LLVMProjectChecks.lean"
  let source ← IO.FS.readFile path
  check ((source.splitOn "import Main\n").length == 2) "observer main import changed"
  IO.FS.writeFile path (source.replace "import Main\n" "import Main\nimport tools.research.SourcePlanContractAudit\n")
def diagnose : IO Unit := do
  idle
  discard <| finished "source-plan-contract-llvm"
  guard "source-plan-contract-diagnostic" #["/usr/bin/env","-u","LEAN_NUM_THREADS",
    "EGGSHELL_PREFIX="++(root/"prefix").toString,"EGGSHELL_DATA_ROOT="++(root/"llvm/host").toString,
    "EGGSHELL_TRACE_SELECTION_RANGES=1",(root/"llvm-build/StudyMain").toString,
    "diagnose",(root/"llvm-plan.json").toString]
def contextProbe : IO Unit := do
  idle
  discard <| finished "source-plan-contract-diagnostic"
  check ((← read (records/"llvm/diagnostic/validation.json")).getObjValD "sameOrdinaryBody" == toJson true)
    "diagnostic is not the ordinary source body"
  IO.FS.writeFile (root/"source/tools/research/ProducerPlanProbe.lean")
    (← IO.FS.readFile (project/"tools/research/ProducerPlanProbe.lean"))
  copyLocalArtifacts (root/"llvm-build") (root/"context-build")
  let configuration := (← read (root/"llvm-build/build.json")).getObjValD "settings"
    |>.setObjVal! "output" (toJson (root/"context-build").toString)
    |>.setObjVal! "parents" (toJson #[(root/"llvm-build").toString,(root/"build").toString])
    |>.setObjVal! "mainModule" (toJson "tools.research.ProducerPlanProbe")
  write (root/"context-settings.json") configuration
  guard "source-plan-context-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"context-settings.json").toString]
def contextRun : IO Unit := do
  idle
  discard <| finished "source-plan-context-checked-build"
  guard "source-plan-context-audit" #["/usr/bin/env","-u","LEAN_NUM_THREADS",
    "EGGSHELL_PREFIX="++(root/"prefix").toString,"EGGSHELL_DATA_ROOT="++(root/"llvm/host").toString,
    (root/"context-build/StudyMain").toString,"context",(parent/"llvm/llvm.egg/owners/0/source.egg").toString,
    (records/"llvm/diagnostic/domain.json").toString,(records/"llvm/pass-0-topic-1.txt").toString,
    (records/"context-audit.json").toString]
def contextRebuild : IO Unit := do
  idle
  let stopped ← read (base/"source-plan-context-build.guard.json")
  check (stopped.getObjValD "state" == toJson "finished" && stopped.getObjValD "exitCode" == toJson (1 : Nat) &&
    stopped.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "only correct the stopped packet-audit observer"
  write (records/"context-build-refusal.json") (Json.mkObj [("guard",stopped),
    ("stdout",toJson (← IO.FS.readFile (root/"context-build/tools_research_ProducerPlanProbe-lean.stdout"))),
    ("stderr",toJson (← IO.FS.readFile (root/"context-build/tools_research_ProducerPlanProbe-lean.stderr"))),
    ("productChanged",toJson false),("modelOrQueryStarted",toJson false)])
  IO.FS.writeFile (root/"source/tools/research/ProducerPlanProbe.lean")
    (← IO.FS.readFile (project/"tools/research/ProducerPlanProbe.lean"))
  guard "source-plan-context-checked-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"context-settings.json").toString]
def witnessBuild : IO Unit := do
  idle
  discard <| finished "source-plan-context-audit"
  check (!(← (root/"witness-build").pathExists)) "preserve the coordinate witness build"
  IO.FS.writeFile (root/"source/tools/research/ProducerPlanProbe.lean")
    (← IO.FS.readFile (project/"tools/research/ProducerPlanProbe.lean"))
  copyLocalArtifacts (root/"context-build") (root/"witness-build")
  let configuration := (← read (root/"context-settings.json"))
    |>.setObjVal! "output" (toJson (root/"witness-build").toString)
    |>.setObjVal! "parents" (toJson #[(root/"context-build").toString,(root/"llvm-build").toString,(root/"build").toString])
  write (root/"witness-settings.json") configuration
  guard "source-plan-coordinate-build" #[(compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/StudyBuildMain.lean").toString,(root/"witness-settings.json").toString]
def witnessRun : IO Unit := do
  idle
  discard <| finished "source-plan-coordinate-build"
  let auditor := project/"tools/research/StudyBuildClosureAudit.lean"
  for arguments in #[#["inspect",(root/"witness-build").toString,(records/"coordinate-native.json").toString],
    #["common-sources",(root/"build").toString,(root/"witness-build").toString,
      (records/"coordinate-sources.json").toString]] do
    discard <| command (compiler/"bin/lean").toString (#["-j1","-M768","--run",auditor.toString]++arguments)
  guard "source-plan-coordinate-audit" #["/usr/bin/env","-u","LEAN_NUM_THREADS",
    "EGGSHELL_PREFIX="++(root/"prefix").toString,"EGGSHELL_DATA_ROOT="++(root/"llvm/host").toString,
    (root/"witness-build/StudyMain").toString,"context",(parent/"llvm/llvm.egg/owners/0/source.egg").toString,
    (records/"llvm/diagnostic/domain.json").toString,(records/"llvm/pass-0-topic-1.txt").toString,
    (records/"coordinate-witnesses.json").toString]
def signalDiagnostic : IO Unit := do
  idle
  discard <| finished "source-plan-coordinate-audit"
  let destination := records/"signals"
  check (!(← destination.pathExists)) "preserve the actual selector signal diagnostic"
  IO.FS.createDirAll destination
  for name in ["before-delivery.json","pass-0-topic-1.txt"] do
    IO.FS.writeBinFile (destination/name) (← IO.FS.readBinFile (records/"llvm"/name))
  let plan := (← read (root/"llvm-plan.json")).setObjVal! "records" (toJson destination.toString)
  write (root/"signal-plan.json") plan
  guard "source-plan-signal-diagnostic" #["/usr/bin/env","-u","LEAN_NUM_THREADS",
    "EGGSHELL_PREFIX="++(root/"prefix").toString,"EGGSHELL_DATA_ROOT="++(root/"llvm/host").toString,
    "EGGSHELL_TRACE_SELECTION_RANGES=1","EGGSHELL_TRACE_SELECTOR_INPUT=1",
    (root/"llvm-build/StudyMain").toString,"diagnose",(root/"signal-plan.json").toString]
end SourcePlanContractStudy
def main : List String → IO Unit
  | ["prepare"] => SourcePlanContractStudy.prepare
  | ["observer"] => SourcePlanContractStudy.observer
  | ["diagnose"] => SourcePlanContractStudy.diagnose
  | ["context-probe"] => SourcePlanContractStudy.contextProbe
  | ["context-run"] => SourcePlanContractStudy.contextRun
  | ["context-rebuild"] => SourcePlanContractStudy.contextRebuild
  | ["witness-build"] => SourcePlanContractStudy.witnessBuild
  | ["witness-run"] => SourcePlanContractStudy.witnessRun
  | ["signals"] => SourcePlanContractStudy.signalDiagnostic
  | [action] => do StudyLocal.idle; SourcePlanContractStudy.invoke action
  | _ => throw (IO.userError "SourcePlanContractStudy prepare|observer|checks|capture|run")
