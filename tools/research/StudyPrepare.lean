import tools.research.StudyAdmission
import tools.research.StudyCommand

open Lean Eggshell

namespace Eggshell.Research.StudyPrepare

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

def artifact (path : System.FilePath) : IO StudyAdmission.Artifact :=
  return ⟨path.toString,← ArtifactHash.hex path⟩

private def setEnv (original updates : Array (String × Option String)) : Array (String × Option String) :=
  original.filter (fun row => !updates.any (·.1 == row.1)) ++ updates

private def write (path : System.FilePath) (json : Json) : IO Unit :=
  IO.FS.writeFile path (json.compress ++ "\n")

/-- Source-only restore, explicit off-hook warming, two independent native
chats and exact-source audit. No App Server turn or answering model is invoked. -/
def prepare (templatePath directory : String) (live : Bool := false) : IO StudyAdmission.Plan := do
  let template ← IO.ofExcept (fromJson? (α := StudyAdmission.Plan) (← StudyAdmission.readJson templatePath))
  let root := System.FilePath.mk directory
  check (root.isAbsolute && !(← root.pathExists)) "keep the existing preparation"
  for artifact in #[template.prompt,template.runtime,template.accountConfiguration] ++ template.pluginFiles do
    StudyAdmission.verifyArtifact artifact
  let original ← StudyRuntime.files (.mk template.sourceSnapshot)
  check (original == template.sourceFiles.qsort (fun a b => a.1 < b.1)) "source snapshot changed before preparation"
  IO.FS.createDir root
  let ancestry ← StudySource.inspect (.mk template.sourceSnapshot)
  write (root / "source-ancestry.json") (toJson ancestry)
  StudySource.requireValid ancestry
  let data := if live then System.FilePath.mk template.dataRoot else root / "data"
  let config := if live then System.FilePath.mk template.configuration.path else root / "config.toml"
  for path in #[template.runtime.path,template.database] do
    check (!(path.contains '"') && !(path.contains '\\') && !(path.contains '\n')) "unsupported TOML path quoting"
  let source := "default = \"work\"\nsemantic_matcher = " ++
    (toJson #[template.runtime.path,"search-provider"]).compress ++ "\n[eggs]\nwork = " ++
    (toJson template.database).compress ++
    "\n[profiles.work]\nread = [\"work\"]\nwrite = \"work\"\nhandoff_chars = 120000\n"
  if live then
    StudyAdmission.verifyArtifact template.configuration
    check (data.isAbsolute && (← data.pathExists) && (← IO.FS.readFile config) == source)
      "live preparation requires the sealed study configuration and existing private history"
    check ((← StudyRuntime.files (.mk template.database)) == original)
      "live database differs from the frozen source checkpoint"
    let privateFiles ← StudyAdmission.tree data
    check (!privateFiles.any (fun row => row.1.endsWith "/daemon.json"))
      "a live daemon still owns the persistent private history"
  else
    IO.FS.createDir data
    IO.FS.writeFile config source
  let environment := setEnv template.environment #[
    ("EGGSHELL_CONFIG",some config.toString),("EGGSHELL_DATA_ROOT",some data.toString),
    ("EGGSHELL_PROFILE",some "work"),("PLUGIN_ROOT",some template.pluginRoot),
    ("LEAN_NUM_THREADS",some "1"),("OMP_NUM_THREADS",some "1"),("OPENBLAS_NUM_THREADS",some "1"),
    ("MKL_NUM_THREADS",some "1"),("TOKENIZERS_PARALLELISM",some "false"),("HF_HUB_OFFLINE",some "1")]
  if !live then StudyRuntime.restore (.mk template.sourceSnapshot) (.mk template.database)
  let warm ← StudyCommand.run template.runtime.path #["egg","warm","work"] environment template.workspace "" (root / "warm") 240000
  check (warm.exitCode == 0) "explicit source warm failed"
  let warmed ← IO.ofExcept (Json.parse warm.stdout >>= (·.getObjValAs? (Array Json) "databases"))
  check (warmed.size == 1) "warm returned another database set"
  let coverage ← IO.ofExcept (warmed[0]!.getObjVal? "after")
  check ((coverage.getObjValAs? Nat "missing").toOption == some 0 &&
    (coverage.getObjValAs? Nat "invalid").toOption == some 0) "source warm is incomplete"
  let doctor ← StudyCommand.run template.runtime.path #["egg","doctor"] environment template.workspace "" (root / "doctor") 60000
  check (doctor.exitCode == 0) "native doctor failed"
  let prompt ← IO.FS.readFile (.mk template.prompt.path)
  let prototype ← StudyAdmission.readJson template.preparation.auditInput.path
  let originalSource ← IO.ofExcept (prototype.getObjVal? "source")
  let required ← IO.ofExcept (originalSource.getObjVal? "required")
  let auditSource := Json.mkObj [("source",toJson template.sourceSnapshot),("workspace",toJson template.workspace),
    ("prompt",toJson prompt),("files",toJson original),("required",required)]
  let frozenAvailable ← NativeTrialAudit.freezeAvailable auditSource
  write (root / "available-evidence.json") (toJson frozenAvailable)
  let mut lastBody : Option String := none
  let mut finalSession := ""
  let mut finalCall := root
  for index in [0:2] do
    let session := s!"prepare-{template.label}-{index}"
    let call := root / s!"chat-{index}"
    IO.FS.createDir call
    let endpoint := data / "sessions" / session / "daemon.json"
    let managed ← StudyRuntime.startManaged (.mk template.runtime.path) (.mk template.pluginRoot) session endpoint environment
    try
      let mut body := ""
      for event in #["SessionStart","UserPromptSubmit"] do
        let fields := [("hook_event_name",toJson event),("session_id",toJson session),("turn_id",toJson "first"),
          ("cwd",toJson template.workspace),("_eggshell_config",toJson config.toString)]
        let request := Json.mkObj (if event == "UserPromptSubmit" then fields ++ [("prompt",toJson prompt)] else fields)
        let result ← StudyCommand.run template.runtime.path #["codex-hook"] environment template.workspace
          (request.compress ++ "\n") (call / event) 35000
        check (result.exitCode == 0 && result.elapsedMs < 30000) "native preparation hook failed or expired"
        if event == "UserPromptSubmit" then
          let reply ← IO.ofExcept (Json.parse result.stdout)
          body ← IO.ofExcept (reply.getObjVal? "hookSpecificOutput" >>= (·.getObjValAs? String "additionalContext"))
      check (!body.trimAscii.isEmpty && !(body.contains "EGGSHELL SEARCH INCOMPLETE")) "new chat did not deliver source memory"
      if let some previous := lastBody then check (previous == body) "new chat changed the fixed-source preflight body"
      lastBody := some body
      IO.FS.writeFile (call / "body.txt") body
      finalSession := session
      finalCall := call
    finally
      StudyRuntime.stopManaged managed (call / "shutdown.json")
  let mut receipt : Option System.FilePath := none
  for entry in ← (data / "receipts").readDir do
    let request := entry.path / "request.json"
    if !(← request.pathExists) then continue
    let fields ← IO.ofExcept ((← StudyAdmission.readJson request.toString).getObjVal? "data")
    if (fields.getObjValAs? String "event").toOption == some "UserPromptSubmit" &&
        (fields.getObjValAs? String "session").toOption == some finalSession then
      check receipt.isNone "multiple receipts for the qualification hook"
      receipt := some entry.path
  let some qualifiedReceipt := receipt | throw (IO.userError "qualification has no native receipt")
  let mut numerical := #[]
  for entry in ← qualifiedReceipt.readDir do
    if entry.fileName.startsWith "numerical-" && entry.fileName.endsWith ".json" then
      numerical := numerical.push (← artifact entry.path)
  let auditInput := root / "audit-input.json"
  let hook := finalCall / "UserPromptSubmit"
  write auditInput (Json.mkObj [("source",auditSource),("database",toJson template.database),
    ("request",toJson (hook / "stdin").toString),("stdout",toJson (hook / "stdout").toString),
    ("timing",toJson (hook / "record.json").toString),("body",toJson (finalCall / "body.txt").toString)])
  let auditReport := root / "audit-report.json"
  let audit ← NativeTrialAudit.inspect auditInput.toString
  check (audit.getObjValD "availableEvidence" == toJson frozenAvailable)
    "available evidence changed after viewing the delivery"
  write auditReport audit
  let p : StudyAdmission.Preparation := {
    input := ← artifact (hook / "stdin"),stdout := ← artifact (hook / "stdout"),timing := ← artifact (hook / "record.json")
    body := ← artifact (finalCall / "body.txt"),state := ← artifact (data / "sessions" / finalSession / "state.json")
    shutdown := ← artifact (finalCall / "shutdown.json"),search := ← artifact (qualifiedReceipt / "search.json")
    numerical,auditInput := ← artifact auditInput,auditReport := ← artifact auditReport,session := finalSession }
  check ((← StudyRuntime.files (.mk template.sourceSnapshot)) == original) "preparation changed the protected source"
  let plan := {template with
    configuration := ← artifact config,dataRoot := data.toString,environment
    databaseFiles := ← StudyRuntime.files (.mk template.database),privateFiles := ← StudyAdmission.tree data,preparation := p}
  write (root / "plan.json") (toJson plan)
  write (root / "preparation-mode.json") (Json.mkObj [
    ("mode",toJson (if live then "persistent-private-history" else "source-only-portability")),
    ("dataRoot",toJson data.toString),("restoredDatabase",toJson (!live))])
  return plan

end Eggshell.Research.StudyPrepare
