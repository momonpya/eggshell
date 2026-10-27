import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def trial : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/feedback-pilot-20261028"
private def previous : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/verified-winner-20261027"
private def study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/study-services-20261026"
private def controller : System.FilePath := trial / "controller/StudyMain"
private def binary : System.FilePath := trial / "prefix/libexec/eggshell"

private def save (path : System.FilePath) (value : Json) : IO Unit := do
  unless !(← path.pathExists) do throw (IO.userError "preserve previous preparation")
  IO.FS.writeFile path value.pretty

private def call (command : String) (args : Array String) : IO String := do
  let result ← IO.Process.output {cmd := command,args}
  unless result.exitCode == 0 do throw (IO.userError s!"{command}: {result.stderr}")
  pure result.stdout

private partial def captureTrace (source target : System.FilePath) : IO Unit := do
  if source.fileName == some "data" || source.toString.endsWith ".egg" then return
  match (← source.symlinkMetadata).type with
  | .dir =>
      IO.FS.createDirAll target
      for entry in ← source.readDir do captureTrace entry.path (target / entry.fileName)
  | .file =>
      IO.FS.createDirAll target.parent.get!
      IO.FS.writeBinFile target (← IO.FS.readBinFile source)
  | _ => throw (IO.userError "fixture trace must contain plain files")

private partial def erase (path : System.FilePath) : IO (Nat × Nat) := do
  let state ← path.symlinkMetadata
  if state.type == .dir then
    let mut count := (0,0)
    for entry in ← path.readDir do
      let next ← erase entry.path
      count := (count.1+next.1,count.2+next.2)
    IO.FS.removeDir path
    return count
  IO.FS.removeFile path
  return (1,if state.type == .file then state.byteSize.toNat else 0)

private def environment : IO (Array (String × Option String)) := do
  let path ← IO.getEnv "PATH"
  return #[
    ("PATH",some ("/Users/ovm/.nodebrew/current/bin:" ++ path.getD "/usr/bin:/bin")),
    ("CODEX_HOME",some (trial / "account").toString),("TMPDIR",some (trial / "tmp").toString),
    ("EGGSHELL_PREFIX",some (trial / "prefix").toString),
    ("PLUGIN_ROOT",some (trial / "prefix/plugins/eggshell").toString),
    ("EGGSHELL_DATA_ROOT",some (trial / "installation-data").toString),
    ("LEAN_NUM_THREADS",some "1"),("OMP_NUM_THREADS",some "1"),("OPENBLAS_NUM_THREADS",some "1"),
    ("MKL_NUM_THREADS",some "1"),("HF_HUB_OFFLINE",some "1"),("TOKENIZERS_PARALLELISM",some "false"),
    ("CODEX_THREAD_ID",none),("CODEX_TURN_ID",none)]

private def guarded (label : String) (command : Array String)
    (updates : Array (String × Option String) := #[]) : IO Unit := do
  let original ← environment
  let env := original.filter (fun row => !updates.any (·.1 == row.1)) ++ updates
  let unset := env.filterMap (fun row => if row.2.isNone then some #["-u",row.1] else none) |>.flatten
  let variables := env.filterMap (fun row => row.2.map (fun value => row.1 ++ "=" ++ value))
  save (trial / (label ++ ".settings.json")) (Json.mkObj [
    ("command",toJson (#["/usr/bin/env"] ++ unset ++ variables ++ command)),
    ("cwd",toJson trial.toString),("ownedPrefixes",toJson #[trial.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat)),
    ("record",toJson (trial / (label ++ ".guard.json")).toString)])

def main (args : List String) : IO Unit := do
  match args with
  | ["init"] =>
    unless !(← trial.pathExists) do throw (IO.userError "keep the existing pilot")
    IO.FS.createDirAll (trial / "controller")
    IO.FS.createDirAll (trial / "prefix/libexec")
    IO.FS.createDirAll (trial / "account")
    IO.FS.createDirAll (trial / "tmp")
    let _ ← call "/bin/chmod" #["700",(trial / "account").toString,(trial / "tmp").toString]
    let _ ← call "/bin/cp" #["-c",(previous / "study-build/StudyMain").toString,controller.toString]
    let _ ← call "/bin/cp" #["-c",(previous / "study-build/build.json").toString,(trial / "controller/build.json").toString]
    let _ ← call "/bin/cp" #["-c",(previous / "product-build/StudyMain").toString,binary.toString]
    let hashes ← call controller.toString #["artifacts",binary.toString,controller.toString]
    let rows ← IO.ofExcept (Json.parse hashes >>= Json.getArr?)
    unless rows[0]!.getObjValD "sha256" == toJson "3551bb5ad8df6ce3387e237e80f5c27f6f5149762edb0c70b75de893ce82687c" do
      throw (IO.userError "the frozen baseline runtime changed")
    IO.FS.writeFile (trial / "initial-digests.json") hashes
    let _ ← call "/bin/cp" #["-cR",(study / "prompts").toString,(trial / "prompts").toString]
    let config := "model = \"gpt-5.6-luna\"\nmodel_reasoning_effort = \"xhigh\"\n" ++
      "project_doc_max_bytes = 0\napproval_policy = \"never\"\nsandbox_mode = \"read-only\"\n" ++
      "[features]\nplugins = true\nhooks = true\nremote_plugin = false\nmulti_agent = false\n"
    IO.FS.writeFile (trial / "account/config.toml") config
    let _ ← call "/bin/chmod" #["600",(trial / "account/config.toml").toString]
    -- Only reuse the credential reference. Never read or copy its contents.
    let _ ← call "/bin/ln" #["-s","/Users/ovm/.codex/auth.json",(trial / "account/auth.json").toString]
    let support := trial / "prefix/share/eggshell/minilm"
    let numerical := System.FilePath.mk
      "/Users/ovm/.codex/experiments/eggshell/numerical-owned-20261024/prefix/share/eggshell/minilm"
    IO.FS.createDirAll support
    for entry in ← numerical.readDir do
      if (← entry.path.symlinkMetadata).type == .file then
        let _ ← call "/bin/cp" #["-cp",entry.path.toString,(support / entry.fileName).toString]
      else
        let _ ← call "/bin/ln" #["-s",entry.path.toString,(support / entry.fileName).toString]
    guarded "setup-install" #[binary.toString,"install","codex"]
  | ["probe"] =>
    save (trial / "discovery.settings.json") (Json.mkObj [
      ("command",toJson #["/Users/ovm/.nodebrew/current/bin/codex","--strict-config","-c",
        "features.remote_plugin=false","app-server","--listen","stdio://"]),
      ("cwd",toJson "/Users/ovm/Code/eggshell-benchmarks/aamas-2027/sources/llvm-project"),
      ("environment",toJson (← environment)),("output",toJson (trial / "discovery").toString),
      ("timeoutMs",toJson (60000 : Nat)),("responseBytes",toJson (32*1024*1024 : Nat)),
      ("transcriptBytes",toJson (64*1024*1024 : Nat))])
    guarded "setup-probe" #[controller.toString,"probe",(trial / "discovery.settings.json").toString]
  | ["native"] =>
    let models ← IO.ofExcept (Json.parse (← IO.FS.readFile (trial / "discovery/models.json")))
    let available ← IO.ofExcept (models.getObjValAs? (Array Json) "data")
    let some model := available.find? (fun row => row.getObjValD "model" == toJson "gpt-5.6-luna") |
      throw (IO.userError "the fixed model is not advertised by the actual CLI")
    let efforts ← IO.ofExcept (model.getObjValAs? (Array Json) "supportedReasoningEfforts")
    unless efforts.any (fun row => row.getObjValD "reasoningEffort" == toJson "xhigh") do
      throw (IO.userError "the fixed model does not advertise xhigh")
    save (trial / "model-admission.json") (Json.mkObj [
      ("model",toJson "gpt-5.6-luna"),("effort",toJson "xhigh"),
      ("advertisedByActualCli",toJson true),("generationCalls",toJson (0 : Nat))])
    let _ ← call controller.toString #["bootstrap","trust-hooks",trial.toString]
    let _ ← call controller.toString #["bootstrap","seed-input",trial.toString]
    guarded "native-gate" #[controller.toString,"seed-checks",(trial / "native-gate-input.json").toString,
      (trial / "native-gate").toString]
      #[("EGGSHELL_DATA_ROOT",some (trial / "native-gate/data").toString)]
  | ["native-env"] =>
    let record ← IO.ofExcept (Json.parse (← IO.FS.readFile (trial / "native-gate.guard.json")))
    unless record.getObjValD "state" == toJson "finished" &&
        record.getObjValD "ownedPids" == toJson (#[] : Array Nat) &&
        record.getObjValD "exitCode" == toJson (1 : Nat) && !(← (trial / "native-gate").pathExists) do
      throw (IO.userError "only the terminal pre-DB environment failure can be repaired here")
    IO.FS.rename (trial / "native-gate.guard.json") (trial / "native-gate-precheck.guard.json")
    IO.FS.rename (trial / "native-gate.settings.json") (trial / "native-gate-precheck.settings.json")
    guarded "native-gate" #[controller.toString,"seed-checks",(trial / "native-gate-input.json").toString,
      (trial / "native-gate").toString]
      #[("EGGSHELL_DATA_ROOT",some (trial / "native-gate/data").toString)]
  | ["refresh-controller"] =>
    unless !(← (trial / "study/seed-1").pathExists) && !(← (trial / "seed-1.guard.json").pathExists) do
      throw (IO.userError "cannot change the controller after a seed has started")
    if ← (trial / "seed-1.plan.json").pathExists then
      unless !(← (trial / "seed-1-before-generic.plan.json").pathExists) do
        throw (IO.userError "keep the retired unstarted plan")
      IO.FS.rename (trial / "seed-1.plan.json") (trial / "seed-1-before-generic.plan.json")
      IO.FS.rename (trial / "seed-1.settings.json") (trial / "seed-1-before-generic.settings.json")
    let _ ← call "/bin/cp" #["-c",(previous / "study-build/StudyMain").toString,controller.toString]
    let _ ← call "/bin/cp" #["-c",(previous / "study-build/build.json").toString,(trial / "controller/build.json").toString]
  | ["generic"] =>
    guarded "generic-gate" #[controller.toString,"seed-checks-generic",(trial / "native-gate-input.json").toString,
      (trial / "generic-gate").toString]
      #[("EGGSHELL_DATA_ROOT",some (trial / "generic-gate/data").toString)]
  | ["retire-generic",label] =>
    unless ["literal-fixture","quote-digest"].contains label do
      throw (IO.userError "use an explicit known fixture failure label")
    let record ← IO.ofExcept (Json.parse (← IO.FS.readFile (trial / "generic-gate.guard.json")))
    unless record.getObjValD "state" == toJson "finished" &&
        record.getObjValD "ownedPids" == toJson (#[] : Array Nat) &&
        record.getObjValD "exitCode" == toJson (1 : Nat) do
      throw (IO.userError "preserve a live or successful generic fixture")
    for name in ["shutdown.json","publisher-shutdown.json"] do
      let closed ← IO.ofExcept (Json.parse (← IO.FS.readFile (trial / "generic-gate" / name)))
      unless closed.getObjValD "processExited" == toJson true do
        throw (IO.userError "fixture daemon has not exited")
    let output := System.FilePath.mk
      ("/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/feedback-pilot/generic-" ++ label)
    unless !(← output.pathExists) do throw (IO.userError "preserve fixture failure records")
    captureTrace (trial / "generic-gate") (output / "trace")
    IO.FS.writeFile (output / "guard.json") record.pretty
    let removed ← erase (trial / "generic-gate")
    IO.FS.rename (trial / "generic-gate.guard.json") (trial / ("generic-gate-" ++ label ++ ".guard.json"))
    IO.FS.rename (trial / "generic-gate.settings.json") (trial / ("generic-gate-" ++ label ++ ".settings.json"))
    save (output / "failure.json") (Json.mkObj [
      ("observedError",toJson "original substring quote lost its support: NEEDED_SYMBOL"),
      ("fixtureInputMissingOpaqueSubstringCase",toJson (label == "literal-fixture")),
      ("staleWholeRecordDigestPredicate",toJson (label == "quote-digest")),
      ("runtimeChanged",toJson false),
      ("generationCalls",toJson (0 : Nat)),("removedFilesAndLogicalBytes",toJson removed),
      ("dbAndCacheRetained",toJson false),("archiveCreated",toJson false)])
  | ["close-fixtures"] =>
    let output := System.FilePath.mk
      "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/feedback-pilot/generic-verified"
    unless !(← output.pathExists) do throw (IO.userError "preserve completed fixture records")
    -- Check all owned workers before deleting any completed fixture data.
    for label in ["generic-gate","native-gate"] do
      let record ← IO.ofExcept (Json.parse (← IO.FS.readFile (trial / (label ++ ".guard.json"))))
      unless record.getObjValD "state" == toJson "finished" &&
          record.getObjValD "ownedPids" == toJson (#[] : Array Nat) &&
          record.getObjValD "exitCode" == toJson (0 : Nat) do
        throw (IO.userError "preserve a live or incomplete fixture")
      for name in ["shutdown.json","publisher-shutdown.json"] do
        let closed ← IO.ofExcept (Json.parse (← IO.FS.readFile (trial / label / name)))
        unless closed.getObjValD "processExited" == toJson true &&
            closed.getObjValD "endpointRemoved" == toJson true do
          throw (IO.userError "fixture service has not closed")
    let result ← IO.ofExcept (Json.parse (← IO.FS.readFile (trial / "generic-gate/result.json")))
    let recovered ← IO.ofExcept (Json.parse (← IO.FS.readFile (trial / "generic-gate/recovery.json")))
    unless result.getObjValD "answeringModelCalls" == toJson (0 : Nat) &&
        result.getObjValD "literalSubstringChecks" == toJson (2 : Nat) &&
        result.getObjValD "genericContentAliases" == toJson (15 : Nat) &&
        recovered.getObjValD "sourceOnlyCheckpoint" == toJson true &&
        recovered.getObjValD "publicationUnchanged" == toJson true do
      throw (IO.userError "generic quotation or portable recovery did not pass")
    let mut removed := (0,0)
    for label in ["generic-gate","native-gate"] do
      captureTrace (trial / label) (output / label)
      IO.FS.writeBinFile (output / (label ++ ".guard.json"))
        (← IO.FS.readBinFile (trial / (label ++ ".guard.json")))
      let next ← erase (trial / label)
      removed := (removed.1+next.1,removed.2+next.2)
    IO.FS.writeBinFile (output / "controller-build.guard.json")
      (← IO.FS.readBinFile (previous / "compile-feedback-quote-witness.guard.json"))
    let hashes ← call controller.toString #["artifacts",binary.toString,controller.toString]
    IO.FS.writeFile (output / "digests.json") hashes
    save (output / "cleanup.json") (Json.mkObj [
      ("generationCalls",toJson (0 : Nat)),("removedFilesAndLogicalBytes",toJson removed),
      ("dbAndCacheRetained",toJson false),("archiveCreated",toJson false)])
  | _ => throw (IO.userError "init | probe | native | native-env | refresh-controller | generic | retire-generic LABEL | close-fixtures")
