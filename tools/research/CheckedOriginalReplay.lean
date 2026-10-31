import tools.research.StudyRuntime
import tools.research.StudyCommand
import tools.research.NativeTrialAudit
import Eggshell.Install
open Lean Eggshell Eggshell.Research Eggshell.Synapses
private def ensure (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

def main : IO Unit := do
  let study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  let shared := study / "shared-snapshot"
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let records := project / "docs/candidates/checked-original/replay"
  let root := shared / "checked-original-replay-trial"
  ensure (!(← records.pathExists) && !(← root.pathExists)) "preserve previous fixed-hook replay"
  IO.FS.createDirAll records
  let database := shared / "checked-original-hook-trial/candidate/work.egg"
  let original := study / "r0/stage1/history/source.egg"
  let originalFiles ← StudyRuntime.files original
  ensure ((← StudyRuntime.files database) == originalFiles) "replay changed source checkpoint"
  let source ← DB.PageMap.pin database
  let path ← CanonicalSource.Cache.directory source .database
  let some metadata ← CanonicalSource.Cache.manifestAt? source path |
    throw (IO.userError "prepared DB has no original layout manifest")
  ensure ((← CanonicalSource.Cache.atSource? source path metadata).isSome) "prepared original data failed validation"
  let some _ ← Index.open? source .database .shared | throw (IO.userError "prepared graph index is cold")
  let runtime := shared / "checked-original-fixed-runtime-build/StudyMain"
  let expected : StudyRuntime.PublisherRuntime := {
    binary := runtime.toString,sha256 := ← ArtifactHash.hex runtime,generation := ← Plugin.Publication.generation}
  let installation := root / "prefix"
  let binary := installation / "libexec/eggshell"
  IO.FS.createDirAll binary.parent.get!
  let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-c",runtime.toString,binary.toString]}
  ensure (copied.exitCode == 0 && (← ArtifactHash.hex binary) == expected.sha256) "replay runtime copy changed"
  let plugin := installation / "share/eggshell/codex-plugin"
  IO.FS.createDirAll (plugin / "bin")
  for name in ["egg","eggshelld"] do
    let file := plugin / "bin" / name
    IO.FS.writeFile file (Install.pluginLauncher installation)
    IO.setAccessRights file {
      user := {read := true,write := true,execution := true}
      group := {read := true,execution := true},other := {read := true,execution := true}}
  let linked ← IO.Process.output {cmd := "/bin/ln",args := #["-s",
    (study / "prefix/share/eggshell/minilm").toString,(installation / "share/eggshell/minilm").toString]}
  ensure (linked.exitCode == 0) "cannot share unchanged numerical runtime"
  let configuration := root / "readonly.toml"
  IO.FS.writeFile configuration ("default = \"work\"\nsemantic_matcher = " ++
    (toJson #[binary.toString,"search-provider"]).compress ++ "\n[eggs]\nwork = " ++
    (toJson database.toString).compress ++ "\n[profiles.work]\nread = [\"work\"]\nhandoff_chars = 120000\n")
  let environment : Array (String × Option String) := #[
    ("CODEX_HOME",some (study / "account").toString),("TMPDIR",some (study / "tmp").toString),
    ("EGGSHELL_PREFIX",some installation.toString),("EGGSHELL_DATA_ROOT",some (root / "data").toString),
    ("EGGSHELL_CONFIG",some configuration.toString),("EGGSHELL_PROFILE",some "work"),
    ("PLUGIN_ROOT",some plugin.toString),("CODEX_THREAD_ID",none),("CODEX_TURN_ID",none),
    ("LEAN_NUM_THREADS",some "1"),("OMP_NUM_THREADS",some "1"),("OPENBLAS_NUM_THREADS",some "1"),
    ("MKL_NUM_THREADS",some "1"),("HF_HUB_OFFLINE",some "1"),("TOKENIZERS_PARALLELISM",some "false"),
    ("EGGSHELL_TRACE_SELECTION_RANGES",none),("EGGSHELL_TRACE_SELECTOR_INPUT",none)]
  let workspace := "/Users/ovm/Code/eggshell-benchmarks/aamas-2027/sources/llvm-project"
  let prompt ← IO.FS.readFile (study / "prompts/topic-1.txt")
  let frozen ← read (project / "docs/candidates/prepared-bindings/resumed/trial/frozen-before-delivery.json")
  let some frozen := (frozen.getArr?).toOption.bind (·[0]?) | throw (IO.userError "missing frozen topic")
  ensure ((frozen.getObjValD "specification").getObjValD "prompt" == toJson prompt &&
    (frozen.getObjValD "specification").getObjValD "files" == toJson originalFiles) "frozen question/source differs"
  IO.FS.writeFile (records / "sealed.json") (Json.mkObj [
    ("runtime",toJson expected),("helperSha256",toJson (← ArtifactHash.hex (← IO.appPath))),
    ("sourceFiles",toJson originalFiles),("preparedSource",toJson metadata),
    ("freshPrivateData",toJson true),("sourcePreparationRetakes",toJson (0 : Nat))]).pretty
  let session := "checked-original-fixed-replay"
  let publisher ← StudyRuntime.startPublisher binary (root / "data") environment (expectedRuntime := some expected)
  try
    let daemon ← StudyRuntime.startManaged binary plugin session (root / "data/sessions" / session / "daemon.json") environment
    try
      for event in ["SessionStart","UserPromptSubmit"] do
        let request := Json.mkObj ([("hook_event_name",toJson event),("session_id",toJson session),
          ("turn_id",toJson "checked-original-fixed-turn"),("cwd",toJson workspace),
          ("_eggshell_config",toJson configuration.toString)] ++
          if event == "UserPromptSubmit" then [("prompt",toJson prompt)] else [])
        let response ← StudyCommand.run binary.toString #["codex-hook"] environment workspace
          (request.compress ++ "\n") (records / event) 35000
        ensure (response.exitCode == 0) "fixed hook subprocess failed"
        if event == "UserPromptSubmit" then
          let reply ← IO.ofExcept (Json.parse response.stdout)
          let body := ((reply.getObjValD "hookSpecificOutput").getObjValAs? String "additionalContext").toOption.getD ""
          IO.FS.writeFile (records / "body.txt") body
          let sha := Sha256.hex body.toUTF8
          let audit ← NativeTrialAudit.replayAvailable (frozen.getObjValD "specification") (records / "body.txt").toString sha
          IO.FS.writeFile (records / "audit.json") audit.pretty
          let baseline ← IO.FS.readFile (project / "docs/candidates/checked-original/hooks/baseline/rep-0/topic-1/body.txt")
          IO.FS.writeFile (records / "result.json") (Json.mkObj [
            ("elapsedMs",toJson response.elapsedMs),("bodySha256",toJson sha),("bodyPresent",toJson (!body.isEmpty)),
            ("sameSavedBaselineBody",toJson (body == baseline)),("availableDelivery",audit.getObjValD "availableDelivery"),
            ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false),
            ("pairedPerformanceStudy",toJson false)]).pretty
          ensure (!body.isEmpty && body == baseline && response.elapsedMs < 30000) "fixed hook did not preserve baseline body/deadline"
    finally StudyRuntime.stopManaged daemon (records / "shutdown.json")
  finally StudyRuntime.stopManaged publisher (records / "publisher-shutdown.json")
  ensure ((← StudyRuntime.files original) == originalFiles && (← StudyRuntime.files database) == originalFiles)
    "fixed replay changed original source"
  IO.println (← IO.FS.readFile (records / "result.json"))
