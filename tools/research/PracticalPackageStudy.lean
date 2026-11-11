import tools.research.StudyLocal

open Lean StudyLocal
namespace PracticalPackageStudy
def practical := base/"practical-runtime"
def origin := practical/"cohort/prefix"
def root := practical/"package"
def installation := root/"prefix"
def records := project/"docs/practical-runtime/package"
def runtimeHash := "7cc1432d2d3931a26d60e3e614807545e3f6b522737838bdabc1b1c626e657ab"

/-- Rebase model-internal links to the new installation. A candidate package
must not depend on an ended experiment; the host's system Python remains an
explicit dependency. No credentials, DB, sessions or query caches are copied. -/
partial def rebase (source target sourceRoot targetRoot : System.FilePath) : IO Unit := do
  let metadata ← source.symlinkMetadata
  if metadata.type == .dir then
    for entry in ← source.readDir do rebase entry.path (target/entry.fileName) sourceRoot targetRoot
  else if metadata.type == .symlink then
    let actual ← IO.FS.realPath source
    let old := sourceRoot.toString++"/"
    let mapped := if actual.toString.startsWith old then
      targetRoot/(actual.toString.drop old.length).toString else actual
    if mapped.toString.startsWith "/Users/ovm/.codex/experiments/" &&
        !mapped.toString.startsWith (installation.toString++"/") then
      -- The working model support has top-level links to a shared venv and
      -- weights. Materialize those dependencies instead of copying dead links.
      let kind := (← actual.metadata).type
      let copied := (← target.symlinkMetadata).type != .symlink
      if !copied then
        IO.FS.removeFile target
        discard <| command "/bin/cp" #[(if kind == .dir then "-cR" else "-c"),actual.toString,target.toString]
      if kind == .dir then rebase actual target actual target
    else
      check (mapped.toString.startsWith (installation.toString++"/") ||
        #["/opt/","/usr/","/System/","/Library/"].any (mapped.toString.startsWith ·))
        ("undeclared external model dependency: "++mapped.toString)
      IO.FS.removeFile target
      discard <| command "/bin/ln" #["-s",mapped.toString,target.toString]

partial def regular (path : System.FilePath) : IO (Array System.FilePath) := do
  let kind := (← path.metadata).type
  if kind == .file then return #[path]
  if kind != .dir then return #[]
  let mut paths := #[]
  for entry in ← path.readDir do paths := paths ++ (← regular entry.path)
  return paths

def hashes (paths : Array System.FilePath) : IO (Array String) := do
  let mut output := #[]
  for first in [:((paths.size+127)/128)] do
    let batch := paths.extract (first*128) (min paths.size ((first+1)*128))
    let text ← command "/usr/bin/shasum" (#["-a","256","--"]++batch.map System.FilePath.toString)
    let rows := (text.splitOn "\n").filter (!·.isEmpty) |>.toArray
    check (rows.size == batch.size) "asset hash report is incomplete"
    for row in rows do
      let digest := (row.take 64).toString
      check (digest.length == 64 && digest.toList.all (fun c => c.isDigit || ('a' ≤ c && c ≤ 'f')))
        "invalid asset hash"
      output := output.push digest
  return output

def prepare : IO Unit := do
  idle
  check (!(← (records/"prepared.json").pathExists)) "preserve a verified package candidate"
  let binary := origin/"libexec/eggshell"
  check ((← hash binary) == runtimeHash) "fixed product changed"
  let support ← IO.FS.realPath (origin/"share/eggshell/minilm")
  let resuming ← root.pathExists
  IO.FS.createDirAll root
  IO.FS.createDirAll records
  if !resuming then discard <| command "/bin/cp" #["-cR",origin.toString,installation.toString]
  else write (records/"first-layout-rejected.json") (Json.mkObj [
    ("reason",toJson "Working MiniLM support contains links to a shared venv and weights; materialize them within the candidate."),
    ("nativePackageCalls",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat))])
  let native := installation/"libexec/eggshell"
  if (← native.symlinkMetadata).type == .symlink then
    IO.FS.removeFile native
    discard <| command "/bin/cp" #["-c",(← IO.FS.realPath binary).toString,native.toString]
  check ((← native.symlinkMetadata).type == .file) "packaged runtime still depends on an experiment link"
  let model := installation/"share/eggshell/minilm"
  if (← model.symlinkMetadata).type == .symlink then
    IO.FS.removeFile model
    discard <| command "/bin/cp" #["-cR",support.toString,model.toString]
  rebase support model support model
  let sourceFiles := (← regular support).filter (!·.toString.endsWith ".pyc")
  check (sourceFiles.size > 0 && sourceFiles.any (·.toString.endsWith ".onnx")) "model manifest is unexpectedly empty"
  let targetFiles := sourceFiles.map fun file =>
    model/(file.toString.drop (support.toString.length+1)).toString
  let before ← hashes sourceFiles
  let after ← hashes targetFiles
  check (before == after && (← hash native) == runtimeHash) "copied product or inference assets differ"
  let plugin := installation/"plugins/eggshell"
  for name in #["egg","eggshelld"] do
    let path := plugin/"bin"/name
    let text ← IO.FS.readFile path
    check (text.contains origin.toString) "reviewed plugin launcher does not bind its original installation"
    IO.FS.writeFile path (text.replace origin.toString installation.toString)
  let source ← IO.FS.readFile (base/"canonical-decoder-runtime/source/Eggshell/Install.lean")
  let sections := source.splitOn "def commandLauncher : String := r#\""
  check (sections.length == 2) "native launcher's source declaration changed"
  let launcher := (sections[1]!.splitOn "\"#").headD ""
  check (launcher.startsWith "#!/bin/sh\n") "native launcher is not a shell entry point"
  IO.FS.createDirAll (installation/"bin")
  IO.FS.writeFile (installation/"bin/egg") launcher
  discard <| command "/bin/chmod" #["755",(installation/"bin/egg").toString]
  let profile := "default = \"work\"\nsemantic_matcher = "++
    (toJson #[(installation/"libexec/eggshell").toString,"search-provider"]).compress++
    "\n[eggs]\nwork = \".eggs/work.egg\"\n[profiles.work]\nread = [\"work\"]\nwrite = \"work\"\nhandoff_chars = 500000\n"
  IO.FS.writeFile (root/"project-config.example.toml") profile
  let manifest ← read (plugin/"hooks/hooks.json")
  for name in #["UserPromptSubmit","PreToolUse","PostToolUse"] do
    let groups ← IO.ofExcept ((manifest.getObjValD "hooks").getObjValAs? (Array Json) name)
    for group in groups do
      for hook in ← IO.ofExcept (group.getObjValAs? (Array Json) "hooks") do
        check (hook.getObjValD "additionalContextLimit" == toJson (0 : Nat) &&
          hook.getObjValD "timeout" == toJson (30 : Nat)) "packaged hook differs from validated envelope"
  let assets := sourceFiles.zip before |>.map fun (file,digest) =>
    ((file.toString.drop (support.toString.length+1)).toString,digest)
  write (root/"model-assets.json") (toJson assets)
  write (records/"prepared.json") (Json.mkObj [
    ("installation",toJson installation.toString),("runtimeSha256",toJson runtimeHash),
    ("modelFilesVerified",toJson assets.size),("modelManifestSha256",toJson (← hash (root/"model-assets.json"))),
    ("handoffChars",toJson (500000 : Nat)),("clientAdditionalContextLimit",toJson (0 : Nat)),
    ("hookDeadlineSeconds",toJson (30 : Nat)),("credentialsCopied",toJson false),("databasesCopied",toJson false),
    ("projectConfigurationSha256",toJson (← hash (root/"project-config.example.toml"))),
    ("globalInstallationModified",toJson false),("sourceRuntimeChanged",toJson false),
    ("nativeInstallDefaultsMatchValidatedEnvelope",toJson false),
    ("sourceDefaultHandoffChars",toJson (120000 : Nat)),("sourceDefaultAdditionalContextLimit",toJson (128000 : Nat)),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])

def qualify : IO Unit := do
  idle
  check ((← read (records/"prepared.json")).getObjValD "runtimeSha256" == toJson runtimeHash)
    "package copy has not been verified"
  let area := root/"validation"
  check (!(← area.pathExists)) "preserve prior package qualification"
  IO.FS.createDirAll (area/"project")
  IO.FS.writeFile (area/"project/.eggshell.toml") (← IO.FS.readFile (root/"project-config.example.toml"))
  let original := practical/"interrupted-recovery/topic-1/template.json"
  let template ← read original
  let plugin := installation/"plugins/eggshell"
  let files ← regular plugin
  let artifacts ← files.mapM fun file => do
    pure (Json.mkObj [("path",toJson file.toString),("sha256",toJson (← hash file))])
  let environment : Array (String × Option String) ← IO.ofExcept (fromJson? (template.getObjValD "environment"))
  let updates : Array (String × Option String) := #[
    ("EGGSHELL_PREFIX",some installation.toString),("PLUGIN_ROOT",some plugin.toString)]
  let updated := template.setObjVal! "label" (toJson "packaged-interrupted-recovery-1")
    |>.setObjVal! "runtime" (Json.mkObj [("path",toJson (installation/"libexec/eggshell").toString),("sha256",toJson runtimeHash)])
    |>.setObjVal! "pluginRoot" (toJson plugin.toString)
    |>.setObjVal! "pluginFiles" (toJson artifacts)
    |>.setObjVal! "environment" (toJson (environment.filter (fun row => !updates.any (·.1 == row.1))++updates))
    |>.setObjVal! "database" (toJson (area/"project/.eggs/work.egg").toString)
    |>.setObjVal! "output" (toJson (area/"no-model-trial").toString)
    |>.setObjVal! "guardRecord" (toJson (area/"no-model-trial.guard.json").toString)
  write (area/"template.json") updated
  guard "practical-package-qualification" #[(practical/"build/StudyMain").toString,"prepare",
    (area/"template.json").toString,(area/"preparation").toString]

def collect : IO Unit := do
  idle
  let monitor ← finished "practical-package-qualification"
  let area := root/"validation/preparation"
  let audit ← read (area/"audit-report.json")
  let baseline := practical/"interrupted-recovery/topic-1/preparation/chat-0/body.txt"
  let bodyHash ← hash (area/"chat-0/body.txt")
  check (bodyHash == (← hash baseline) && bodyHash == (← hash (area/"chat-1/body.txt")))
    "packaging changed the actual hook body"
  check ((audit.getObjValD "availableDelivery").getObjValD "targetMet" == toJson true &&
    (← hash (installation/"libexec/eggshell")) == runtimeHash) "packaged delivery or product differs"
  let plan ← read (area/"plan.json")
  let searchPath ← IO.ofExcept ((plan.getObjValD "preparation").getObjValD "search" |>.getObjValAs? String "path")
  let search := (← read (.mk searchPath)).getObjValD "data"
  let synapse := (← read ((System.FilePath.mk searchPath).parent.get!/"synaptic-delivery.json")).getObjValD "data"
  check ((search.getObjValD "trace").getObjValD "semantic" == toJson "completed" &&
    synapse.getObjValD "complete" == toJson true && synapse.getObjValD "packetVerified" == toJson true)
    "packaged inference or synaptic traversal failed"
  let mut chats := #[]
  for index in [0,1] do
    let call := area/s!"chat-{index}"
    let timing ← read (call/"UserPromptSubmit/record.json")
    let stopped ← read (call/"shutdown.json")
    check ((timing.getObjValAs? Nat "elapsedMs").toOption.any (· < 30000) &&
      stopped.getObjValD "daemonExitCode" == toJson (0 : Nat) && stopped.getObjValD "processExited" == toJson true)
      "packaged hook or service exceeded its contract"
    chats := chats.push (Json.mkObj [("timing",timing),("shutdown",stopped)])
  write (records/"qualification.json") (Json.mkObj [("guard",monitor),
    ("runtimeSha256",toJson runtimeHash),("bodySha256",toJson bodyHash),("matchesOriginalRuntimeBody",toJson true),
    ("requiredDelivery",audit.getObjValD "requiredDelivery"),("availableDelivery",audit.getObjValD "availableDelivery"),
    ("chats",toJson chats),("search",search),("synapse",synapse),
    ("warm",← read (area/"warm/record.json")),("publisherShutdown",← read (area/"publisher-shutdown.json")),
    ("answeringModelCalls",toJson (0 : Nat)),("globalInstallationModified",toJson false),("adopted",toJson false)])

def settings : IO Unit := do
  idle
  check ((← read (records/"qualification.json")).getObjValD "matchesOriginalRuntimeBody" == toJson true)
    "qualify the copied runtime before checking the normal project entry"
  let skeleton := root/"project-template"
  IO.FS.createDirAll (skeleton/".eggs")
  IO.setAccessRights (skeleton/".eggs") {user := {read := true,write := true,execution := true}}
  IO.FS.writeFile (skeleton/".eggshell.toml") (← IO.FS.readFile (root/"project-config.example.toml"))
  IO.FS.writeFile (skeleton/".eggs/.gitignore") "*\n!.gitignore\n"
  let projectRoot := root/"validation/project"
  let environment := #["-u","CODEX_THREAD_ID","-u","CODEX_TURN_ID",
    "EGGSHELL_PREFIX="++installation.toString,
    "EGGSHELL_CONFIG="++(projectRoot/".eggshell.toml").toString,
    "EGGSHELL_DATA_ROOT="++(root/"validation/preparation/data").toString,
    "CODEX_HOME="++(practical/"cohort/account").toString,
    "HF_HUB_OFFLINE=1","OMP_NUM_THREADS=1","OPENBLAS_NUM_THREADS=1","MKL_NUM_THREADS=1"]
  guard "practical-package-project-settings" (#["/usr/bin/env"]++environment++#[(installation/"bin/egg").toString,"doctor"])
  let path := base/"practical-package-project-settings.guard-settings.json"
  write path ((← read path).setObjVal! "cwd" (toJson projectRoot.toString))

def collectSettings : IO Unit := do
  idle
  let monitor ← finished "practical-package-project-settings"
  let report ← read (base/"practical-package-project-settings.shell.log")
  check (report.getObjValD "configuration" == toJson "ready" &&
    report.getObjValD "profile" == toJson "work" && report.getObjValD "memory" == toJson "read/write")
    "normal packaged command did not use the supplied project configuration"
  let databases ← IO.ofExcept (report.getObjValAs? (Array Json) "databases")
  check (databases.size == 1 && databases[0]!.getObjValD "path" ==
    toJson (root/"validation/project/.eggs/work.egg").toString &&
    databases[0]!.getObjValD "state" == toJson "warm") "normal command selected a different or cold project DB"
  write (records/"project-settings.json") (Json.mkObj [
    ("guard",monitor),("doctor",report),("normalLauncherUsed",toJson true),
    ("relativeProjectDatabaseResolved",toJson true),("handoffChars",toJson (500000 : Nat)),
    ("projectConfigurationSha256",toJson (← hash (root/"validation/project/.eggshell.toml"))),
    ("globalInstallationModified",toJson false),("adopted",toJson false)])

def main (args : List String) : IO Unit := match args with
  | ["prepare"] => prepare
  | ["qualify"] => qualify
  | ["collect"] => collect
  | ["settings"] => settings
  | ["collect-settings"] => collectSettings
  | _ => throw (IO.userError "PracticalPackageStudy prepare")
end PracticalPackageStudy
def main := PracticalPackageStudy.main
