import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def root := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell/study-services-20261026"
private def previous := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell/lean-study-20261025"

private def read (path : System.FilePath) : IO Json := do
  IO.ofExcept (Json.parse (← IO.FS.readFile path))

private def save (path : System.FilePath) (value : Json) : IO Unit := do
  unless !(← path.pathExists) do throw (IO.userError "keep the existing execution evidence")
  IO.FS.writeFile path (value.pretty ++ "\n")

private def process (command : String) (args : Array String) : IO Unit := do
  let output ← IO.Process.output {cmd := command,args}
  unless output.exitCode == 0 do throw (IO.userError s!"setup command failed: {command}")

private def artifact (path : System.FilePath) : IO Json := do
  let output ← IO.Process.output {cmd := (root / "controller").toString,args := #["artifacts",path.toString]}
  unless output.exitCode == 0 do throw (IO.userError "execution artifact hashing failed")
  let rows ← IO.ofExcept (Json.parse output.stdout >>= Json.getArr?)
  let some row := rows[0]? | throw (IO.userError "missing execution artifact")
  return row

private def environment : Array (String × Option String) := #[
  ("CODEX_HOME",some (root / "account").toString),("TMPDIR",some (root / "tmp").toString),
  ("EGGSHELL_PREFIX",some (root / "prefix").toString),
  ("PLUGIN_ROOT",some (root / "prefix/plugins/eggshell").toString),
  ("EGGSHELL_DATA_ROOT",some (root / "installation-data").toString),
  ("HF_HUB_OFFLINE",some "1"),("LEAN_NUM_THREADS",some "1"),("OMP_NUM_THREADS",some "1"),
  ("OPENBLAS_NUM_THREADS",some "1"),("MKL_NUM_THREADS",some "1"),("TOKENIZERS_PARALLELISM",some "false"),
  ("CODEX_THREAD_ID",none),("CODEX_TURN_ID",none)]

private def guarded (label : String) (command : Array String) (env := environment) : IO Unit := do
  let settings := Json.mkObj [("cwd",toJson root.toString),("ownedPrefixes",toJson #[root.toString]),
    ("record",toJson (root / (label ++ ".guard.json")).toString),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (524288 : Nat)),
    ("environment",toJson env),("command",toJson command)]
  -- ResourceGuard deliberately inherits its environment. Keep the exact
  -- isolated values in the command, rather than relying on an ignored field.
  let variables := env.filterMap fun (key,value) => value.map (fun value => key ++ "=" ++ value)
  let unset := #["-u","CODEX_THREAD_ID","-u","CODEX_TURN_ID"]
  save (root / (label ++ ".settings.json"))
    (settings.setObjVal! "command" (toJson (#["/usr/bin/env"] ++ unset ++ variables ++ command)))

private partial def tree (directory : System.FilePath) : IO (Array Json) := do
  let mut result := #[]
  for entry in ← directory.readDir do
    match (← entry.path.symlinkMetadata).type with
    | .dir => result := result ++ (← tree entry.path)
    | .file => result := result.push (← artifact entry.path)
    | _ => throw (IO.userError "execution plugin must contain regular files only")
  return result

def main (args : List String) : IO Unit := do
  match args with
  | ["init"] =>
    unless !(← (root / "account").pathExists) do throw (IO.userError "keep existing isolated account")
    IO.FS.createDirAll (root / "account")
    IO.FS.createDirAll (root / "tmp")
    let configuration ← IO.FS.readFile (previous / "account/config.toml")
    let some base := (configuration.splitOn "\n[marketplaces.eggshell]").head? |
      throw (IO.userError "missing previous benchmark configuration")
    IO.FS.writeFile (root / "account/config.toml") base
    process "/bin/chmod" #["600",(root / "account/config.toml").toString]
    -- Use the existing account credential reference without reading credentials.
    process "/bin/ln" #["-s","/Users/ovm/.codex/auth.json",(root / "account/auth.json").toString]
    process "/bin/cp" #["-cR",(previous / "prompts").toString,(root / "prompts").toString]
    let support := root / "prefix/share/eggshell/minilm"
    unless (← support.symlinkMetadata).type == .symlink do
      throw (IO.userError "expected the explicitly shared numeric support reference")
    let shared ← IO.FS.realPath support
    IO.FS.removeFile support
    IO.FS.createDir support
    for entry in ← shared.readDir do
      if (← entry.path.symlinkMetadata).type == .file then
        process "/bin/cp" #["-cp",entry.path.toString,(support / entry.fileName).toString]
      else
        process "/bin/ln" #["-s",entry.path.toString,(support / entry.fileName).toString]
    guarded "setup-install" #[(root / "prefix/libexec/eggshell").toString,"install","codex"]
  | ["probe"] =>
    let original ← read (previous / "seed-1.plan.json")
    let settings := Json.mkObj [
      ("command",toJson #["/Users/ovm/.nodebrew/current/bin/codex","--strict-config","-c",
        "features.remote_plugin=false","app-server","--listen","stdio://"]),
      ("cwd",original.getObjValD "workspace"),("environment",toJson environment),
      ("output",toJson (root / "discovery").toString),("timeoutMs",toJson (60000 : Nat)),
      ("responseBytes",toJson (32*1024*1024 : Nat)),("transcriptBytes",toJson (64*1024*1024 : Nat))]
    save (root / "discovery.settings.json") settings
    guarded "setup-probe" #[(root / "controller").toString,"probe",(root / "discovery.settings.json").toString]
  | "seal" :: labels =>
    let label ← match labels with
      | [] => pure "seed-1"
      | [label] =>
        unless !label.isEmpty && label.toList.all (fun c => c.isAlphanum || c == '-') do
          throw (IO.userError "plain distinct seed attempt label required")
        pure label
      | _ => throw (IO.userError "seal [ATTEMPT-LABEL]")
    -- The disk preflight inspects the new acquisition directory's parent.
    -- Prepare that parent before freezing a plan or starting the controller.
    IO.FS.createDirAll (root / "study")
    let original ← read (previous / "seed-1.plan.json")
    let runtime ← artifact (root / "prefix/libexec/eggshell")
    let facts ← read (root / "native/result.json")
    unless facts.getObjValD "runtime" == runtime do throw (IO.userError "product runtime changed after native gate")
    let trusted ← read (root / "hooks-trusted.json")
    unless trusted.getObjValD "runtime" == runtime do throw (IO.userError "trusted hook runtime changed")
    let plugin := System.FilePath.mk (← IO.ofExcept (trusted.getObjValAs? String "pluginRoot"))
    let gate := root / "native"
    let gateFields := Json.mkObj [
      ("report",← artifact (gate / "result.json")),("guard",← artifact (root / "native-owned.guard.json")),
      ("shutdown",← artifact (gate / "shutdown.json")),("recovery",← artifact (gate / "recovery.json")),
      ("publisherShutdown",← artifact (gate / "publisher-shutdown.json"))]
    let project := System.FilePath.mk "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
    let mut harness := #[]
    for entry in ← (project / "tools/research").readDir do
      if entry.fileName.startsWith "Study" && entry.fileName.endsWith ".lean" then
        harness := harness.push (← artifact entry.path)
    harness := harness.push (← artifact (project / "tools/research/PrepareStudyExecutionMain.lean"))
    let plan := original.setObjVal! "label" (toJson "team-source-seed-1")
      |>.setObjVal! "runtime" runtime |>.setObjVal! "runner" (← artifact (root / "controller"))
      |>.setObjVal! "accountConfiguration" (← artifact (root / "account/config.toml"))
      |>.setObjVal! "prompt" (← artifact (root / "prompts/topic-0.txt"))
      |>.setObjVal! "pluginRoot" (toJson plugin.toString) |>.setObjVal! "pluginFiles" (toJson (← tree plugin))
      |>.setObjVal! "gate" gateFields |>.setObjVal! "harness" (toJson harness)
      |>.setObjVal! "environment" (toJson environment)
      |>.setObjVal! "output" (toJson (root / "study/seed-1").toString)
      |>.setObjVal! "guardRecord" (toJson (root / (label ++ ".guard.json")).toString)
    let planFile := root / (label ++ ".plan.json")
    save planFile plan
    let sealed ← artifact planFile
    let digest ← IO.ofExcept (sealed.getObjValAs? String "sha256")
    guarded label #[(root / "controller").toString,"acquire",planFile.toString,digest]
  | _ => throw (IO.userError "PrepareStudyExecutionMain init|probe|seal [ATTEMPT-LABEL]")
