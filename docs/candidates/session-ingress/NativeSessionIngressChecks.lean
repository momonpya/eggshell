import tools.research.StudyRuntime
import tools.research.StudyCommand
import Eggshell.SynapseJournal

open Lean Eggshell Eggshell.Plugin Eggshell.Research Eggshell.Synapses

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def session := "contended-native-hooks"

private def hold (root : System.FilePath) (label : String) : IO Unit := do
  let files ← sessionFiles session
  Persistence.withLock files.lock do
    FileSystem.immutableBytes (root / label) ByteArray.empty
    IO.sleep 500

private def contention (root : System.FilePath) (label : String) (action : IO Unit) : IO Unit := do
  let child ← IO.Process.spawn {
    cmd := (← IO.appPath).toString
    args := #["hold",root.toString,label]
    stdin := .null,stdout := .null,stderr := .null,setsid := true}
  try
    let deadline := (← IO.monoMsNow)+5000
    while !(← (root / label).pathExists) do
      check ((← IO.monoMsNow) < deadline) "contention holder did not become ready"
      IO.sleep 1
    action
    check ((← child.wait) == 0) "contention holder failed"
  finally
    try child.kill; let _ ← child.wait; pure () catch _ => pure ()

private def scenario (binary root : System.FilePath) : IO Unit := do
  check (binary.isAbsolute && root.isAbsolute && !(← root.pathExists)) "new absolute native fixture required"
  check ((← IO.getEnv "EGGSHELL_DATA_ROOT") == some (root / "private").toString) "isolated native fixture root required"
  IO.FS.createDirAll root
  let database := root / "source.egg"
  let _ ← DB.PageMap.create database (Persistence.valueToJson (.text "contended-native-hooks")).compress
  let config := root / "config.toml"
  IO.FS.writeFile config ("default = \"work\"\nsemantic_matcher = " ++
    (toJson #[binary.toString,"search-provider","--mode","lexical"]).compress ++
    "\n[eggs]\nwork = " ++ (toJson database.toString).compress ++
    "\n[profiles.work]\nread = [\"work\"]\nwrite = \"work\"\nhandoff_chars = 24000\n")
  let plugin := root / "plugin"
  IO.FS.createDirAll (plugin / "bin")
  let linked ← IO.Process.output {cmd := "/bin/ln",args := #["-s",binary.toString,(plugin / "bin/eggshelld").toString]}
  check (linked.exitCode == 0) "could not bind the isolated daemon launcher"
  IO.FS.writeFile (root / "source.txt") "symbol\n"
  let environment := #[("EGGSHELL_DATA_ROOT",some (root / "private").toString),
    ("EGGSHELL_PREFIX",some (root / "empty-prefix").toString),("PLUGIN_ROOT",some plugin.toString),
    ("EGGSHELL_CONFIG",some config.toString),("CODEX_THREAD_ID",some session),("CODEX_TURN_ID",some "turn")]
  let files ← sessionFiles session
  let managed ← StudyRuntime.startManaged binary plugin session (files.directory / "daemon.json") environment
  let results ← IO.mkRef (#[] : Array Nat)
  try
    let hook := fun label event fields => do
      let input := Json.mkObj ([("session_id",toJson session),("turn_id",toJson "turn"),
        ("cwd",toJson root.toString),("hook_event_name",toJson event)] ++ fields)
      let result ← StudyCommand.run binary.toString #["codex-hook"] environment root.toString
        (input.compress ++ "\n") (root / label) 35000
      check (result.exitCode == 0 && result.elapsedMs < 30000) s!"native hook failed: {label}: {result.stderr}"
      results.modify (·.push result.elapsedMs)
    hook "session" "SessionStart" []
    hook "prompt" "UserPromptSubmit" [("prompt",toJson "Read the original symbol")]
    let tool := [("tool_name",toJson "Bash"),("tool_use_id",toJson "native-read"),
      ("tool_input",Json.mkObj [("command",toJson "sed -n '1,1p' source.txt")])]
    contention root "pre-ready" (hook "pre" "PreToolUse" tool)
    let read ← IO.Process.output {cmd := "/bin/sh",args := #["-c","sed -n '1,1p' source.txt"],cwd := some root}
    check (read.exitCode == 0 && read.stdout == "symbol\n") "native source operation failed"
    contention root "post-ready" (hook "post" "PostToolUse" (tool ++ [("tool_response",toJson read.stdout)]))
    hook "stop" "Stop" [("last_assistant_message",toJson "source.txt:1 contains symbol")]
    let source ← DB.PageMap.pin database
    let some journal ← Journal.open? source | throw (IO.userError "actual native hooks left no journal")
    let entries ← Journal.turnEntries journal ⟨session,"turn"⟩
    let starts := entries.filter fun entry => match entry.payload with | .start .. => true | _ => false
    let finishes := entries.filter fun entry => match entry.payload with | .finish .. => true | _ => false
    let answers := entries.filter fun entry => match entry.payload with | .answer .. => true | _ => false
    let complete := starts.size == 1 && finishes.size == 1 && answers.size == 1
    IO.FS.writeFile (root / "result.json") ((Json.mkObj [
      ("nativeStarts",toJson starts.size),("nativeFinishes",toJson finishes.size),("nativeAnswers",toJson answers.size),
      ("nativeJournalComplete",toJson complete),
      ("hookElapsedMs",toJson (← results.get)),("answeringModelCalls",toJson (0 : Nat)),
      ("numericalModelCalls",toJson (0 : Nat))]).compress ++ "\n")
    check complete "actual contended native hooks lost events"
  finally StudyRuntime.stopManaged managed (root / "shutdown.json")

def main (args : List String) : IO Unit := do
  match args with
  | ["hold",root,label] => hold (.mk root) label
  | [binary,root] => scenario (.mk binary) (.mk root)
  | _ => throw (IO.userError "NativeSessionIngressChecks RUNTIME NEW-DIRECTORY")
