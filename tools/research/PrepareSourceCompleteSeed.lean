import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/source-complete-seed-20261028"
private def previous : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/feedback-pilot-20261028"
private def built : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/verified-winner-20261027"
private def controller := root / "controller/StudyMain"
private def runtime := root / "prefix/libexec/eggshell"

private def call (program : String) (args : Array String) : IO String := do
  let result ← IO.Process.output {cmd := program,args}
  unless result.exitCode == 0 do throw (IO.userError result.stderr)
  return result.stdout
private def save (path : System.FilePath) (value : Json) : IO Unit := do
  unless !(← path.pathExists) do throw (IO.userError "preserve earlier seed preparation")
  IO.FS.writeFile path value.pretty
private def environment : IO (Array (String × Option String)) := do
  return #[("PATH",← IO.getEnv "PATH"),("CODEX_HOME",some (root / "account").toString),
    ("TMPDIR",some (root / "tmp").toString),("EGGSHELL_PREFIX",some (root / "prefix").toString),
    ("PLUGIN_ROOT",some (root / "prefix/plugins/eggshell").toString),
    ("EGGSHELL_DATA_ROOT",some (root / "installation-data").toString),
    ("LEAN_NUM_THREADS",some "1"),("OMP_NUM_THREADS",some "1"),("OPENBLAS_NUM_THREADS",some "1"),
    ("MKL_NUM_THREADS",some "1"),("HF_HUB_OFFLINE",some "1"),("TOKENIZERS_PARALLELISM",some "false"),
    ("CODEX_THREAD_ID",none),("CODEX_TURN_ID",none)]
private def guarded (label : String) (command : Array String)
    (updates : Array (String × Option String) := #[]) : IO Unit := do
  let original ← environment
  let env := original.filter (fun row => !updates.any (·.1 == row.1)) ++ updates
  let unset := env.filterMap fun row => if row.2.isNone then some #["-u",row.1] else none
  let values := env.filterMap fun row => row.2.map (fun value => row.1 ++ "=" ++ value)
  save (root / (label ++ ".settings.json")) (Json.mkObj [
    ("command",toJson (#["/usr/bin/env"] ++ unset.flatten ++ values ++ command)),
    ("cwd",toJson root.toString),("ownedPrefixes",toJson #[root.toString,built.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat)),
    ("record",toJson (root / (label ++ ".guard.json")).toString)])

def main (args : List String) : IO Unit := do
  match args with
  | ["init"] =>
    unless !(← root.pathExists) do throw (IO.userError "preserve the existing new-seed attempt")
    let compiled ← IO.ofExcept (Json.parse (← IO.FS.readFile (built / "storage-controller-seed-budget-build.guard.json")))
    unless compiled.getObjValD "state" == toJson "finished" && compiled.getObjValD "exitCode" == toJson (0 : Nat) do
      throw (IO.userError "finish the bounded controller build before freezing it")
    for path in #[root / "controller",root / "prefix/libexec",root / "account",root / "tmp"] do IO.FS.createDirAll path
    let _ ← call "/bin/chmod" #["700",(root / "account").toString,(root / "tmp").toString]
    for (source,target) in #[(built / "storage-controller-build/StudyMain",controller),
        (built / "storage-controller-build/build.json",root / "controller/build.json"),
        (previous / "storage-integration/prefix/libexec/eggshell",runtime)] do
      let _ ← call "/bin/cp" #["-c",source.toString,target.toString]
      pure ()
    let hashes ← call controller.toString #["artifacts",runtime.toString,controller.toString]
    let rows ← IO.ofExcept (Json.parse hashes >>= (·.getArr?))
    unless rows[0]!.getObjValD "sha256" == toJson "c255d23527bc4aba06c9fd38932f5cab446dd4d1c775472064e0c16d9a913860" do
      throw (IO.userError "storage candidate runtime changed")
    IO.FS.writeFile (root / "frozen-native.json") hashes
    let _ ← call "/bin/cp" #["-cR",(previous / "prompts").toString,(root / "prompts").toString]
    IO.FS.writeFile (root / "account/config.toml")
      ("model = \"gpt-5.6-luna\"\nmodel_reasoning_effort = \"xhigh\"\nproject_doc_max_bytes = 0\n" ++
       "approval_policy = \"never\"\ndefault_permissions = \"pilot\"\n[features]\nplugins = true\nhooks = true\n" ++
       "remote_plugin = false\nmulti_agent = false\n[permissions.pilot]\nextends = \":read-only\"\n" ++
       "[permissions.pilot.network]\nenabled = false\n")
    let _ ← call "/bin/chmod" #["600",(root / "account/config.toml").toString]
    let _ ← call "/bin/ln" #["-s","/Users/ovm/.codex/auth.json",(root / "account/auth.json").toString]
    let support := root / "prefix/share/eggshell/minilm"
    IO.FS.createDirAll support
    for entry in ← (previous / "prefix/share/eggshell/minilm").readDir do
      let actual ← IO.FS.realPath entry.path
      let _ ← call "/bin/ln" #["-s",actual.toString,(support / entry.fileName).toString]
      pure ()
    guarded "setup-install" #[runtime.toString,"install","codex"]
  | ["budgets"] =>
    guarded "budget-checks" #[controller.toString,"test-budgets",(built / "storage-fixture-build/StudyMain").toString,
      (root / "budget-checks").toString]
  | ["refresh-controller"] =>
    unless !(← (root / "seed-1.plan.json").pathExists) && !(← (root / "study/seed-1").pathExists) do
      throw (IO.userError "do not change the controller after sealing or starting the seed")
    let compiled ← IO.ofExcept (Json.parse (← IO.FS.readFile (built / "storage-controller-seed-ready-build.guard.json")))
    unless compiled.getObjValD "state" == toJson "finished" && compiled.getObjValD "exitCode" == toJson (0 : Nat) do
      throw (IO.userError "finish the readiness controller build before freezing it")
    for name in #["StudyMain","build.json"] do
      let _ ← call "/bin/cp" #["-c",(built / "storage-controller-build" / name).toString,(root / "controller" / name).toString]
      pure ()
    IO.FS.writeFile (root / "admission-controller.json")
      (← call controller.toString #["artifacts",controller.toString,runtime.toString])
  | ["probe"] =>
    save (root / "discovery.settings.json") (Json.mkObj [
      ("command",toJson #["/Users/ovm/.nodebrew/current/bin/codex","--strict-config","-c",
        "features.remote_plugin=false","app-server","--listen","stdio://"]),
      ("cwd",toJson "/Users/ovm/Code/eggshell-benchmarks/aamas-2027/sources/llvm-project"),
      ("environment",toJson (← environment)),("output",toJson (root / "discovery").toString),
      ("timeoutMs",toJson (60000 : Nat)),("responseBytes",toJson (32*1024*1024 : Nat)),
      ("transcriptBytes",toJson (64*1024*1024 : Nat))])
    guarded "setup-probe" #[controller.toString,"probe",(root / "discovery.settings.json").toString]
  | ["native"] =>
    let models ← IO.ofExcept (Json.parse (← IO.FS.readFile (root / "discovery/models.json")))
    let available ← IO.ofExcept (models.getObjValAs? (Array Json) "data")
    let some model := available.find? (fun row => row.getObjValD "model" == toJson "gpt-5.6-luna") |
      throw (IO.userError "fixed model is not advertised by the actual CLI")
    let efforts ← IO.ofExcept (model.getObjValAs? (Array Json) "supportedReasoningEfforts")
    unless efforts.any (fun row => row.getObjValD "reasoningEffort" == toJson "xhigh") do
      throw (IO.userError "fixed model does not advertise xhigh")
    let _ ← call controller.toString #["bootstrap","trust-hooks",root.toString]
    let _ ← call controller.toString #["bootstrap","seed-input",root.toString]
    guarded "native-gate" #[controller.toString,"seed-checks-generic",(root / "native-gate-input.json").toString,
      (root / "native-gate").toString] #[("EGGSHELL_DATA_ROOT",some (root / "native-gate/data").toString)]
  | ["seal"] =>
    let budget ← IO.ofExcept (Json.parse (← IO.FS.readFile (root / "budget-checks/result.json")))
    unless budget.getObjValD "answeringModelCalls" == toJson (0 : Nat) do throw (IO.userError "native budget fixture required")
    let report := root / "native-gate/source-ancestry.json"
    let _ ← call controller.toString #["source-ancestry",(root / "native-gate/output.egg").toString,report.toString]
    let ancestry ← IO.ofExcept (Json.parse (← IO.FS.readFile report))
    unless ancestry.getObjValD "complete" == toJson true do throw (IO.userError "fixture ancestry is unreadable")
    let _ ← call controller.toString #["bootstrap","seal-seed",root.toString]
    pure ()
  | "finalize" :: labels =>
    let label ← match labels with
      | [] => pure "seed-finalized"
      | [label] => pure label
      | _ => throw (IO.userError "one finalization report label")
    unless !label.isEmpty && label.toList.all (fun c => c.isAlphanum || c == '-') do
      throw (IO.userError "simple finalization label required")
    let finished ← IO.ofExcept (Json.parse (← IO.FS.readFile (root / "seed-1.guard.json")))
    unless finished.getObjValD "state" == toJson "finished" &&
        finished.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
      throw (IO.userError "wait for the same seed acquisition to finish before finalizing")
    guarded label #[controller.toString,"seed-finalize",(root / "study/seed-1").toString,
      (root / label).toString]
      #[("EGGSHELL_DATA_ROOT",some (root / "study/seed-1/data").toString)]
  | ["audit"] =>
    let ready ← IO.ofExcept (Json.parse (← IO.FS.readFile (root / "seed-ready/result.json")))
    unless ready.getObjValD "queuedAfter" == toJson (0 : Nat) do
      throw (IO.userError "drain the same seed before freezing its source evidence")
    let definitions := root / "task-definitions.json"
    unless !(← definitions.pathExists) do throw (IO.userError "preserve the frozen task definitions")
    IO.FS.writeBinFile definitions (← IO.FS.readBinFile
      "/Users/ovm/.codex/experiments/eggshell/study-services-20261026/task-definitions.json")
    guarded "seed-audit" #[controller.toString,"seed-audit",(root / "study/seed-1").toString,
      definitions.toString,(root / "seed-ready/ready.egg").toString,(root / "seed-audit.json").toString]
      #[("EGGSHELL_DATA_ROOT",some (root / "study/seed-1/data").toString)]
  | ["journal-audit"] =>
    guarded "seed-journal-audit" #[(built / "storage-events-build/StudyMain").toString,
      (root / "study/seed-1").toString,(root / "seed-journal-audit.json").toString]
      #[("EGGSHELL_DATA_ROOT",some (root / "study/seed-1/data").toString)]
  | ["correct-monitor"] =>
    let path := root / "seed-1.guard.json"
    let previousGuard ← IO.ofExcept (Json.parse (← IO.FS.readFile path))
    unless previousGuard.getObjValD "state" == toJson "finished" &&
        previousGuard.getObjValD "exitCode" == toJson (1 : Nat) &&
        previousGuard.getObjValD "ownedPids" == toJson (#[] : Array Nat) &&
        !(← (root / "study/seed-1").pathExists) &&
        !(← (root / "pre-generation-monitor.guard.json").pathExists) do
      throw (IO.userError "only the terminal pre-generation monitor mismatch may be corrected")
    IO.FS.rename path (root / "pre-generation-monitor.guard.json")
    save (root / "monitor-correction.json") (Json.mkObj [("answeringModelCalls",toJson (0 : Nat)),
      ("acquisitionOutputNotCreated",toJson true),("sealedPlanAndLimitsChanged",toJson false),
      ("requiredGuardExecutable",toJson controller.toString)])
  | _ => throw (IO.userError "init | budgets | probe | native | refresh-controller | seal | finalize | audit | journal-audit | correct-monitor")
