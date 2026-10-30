import tools.research.StudyRuntime
import tools.research.StudyCommand
open Lean Eggshell Eggshell.Research

private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def read (p : System.FilePath) : IO Json := IO.FS.readFile p >>= fun s => IO.ofExcept (Json.parse s)

/- One explicitly diagnostic extra hook on the already prepared unchanged
control. It is outside the predeclared two-repetition latency comparison. -/
def main (args : List String) : IO Unit := do
  check args.isEmpty "fixed unchanged prepared control only"
  let study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let records := project / "docs/candidates/prepared-bindings/resumed"
  let out := records / "cue-capture"
  check (!(← out.pathExists)) "preserve prior cue capture"
  let arm := study / "shared-snapshot/prepared-bindings-trial/baseline"
  let before ← StudyRuntime.files (arm / "work.egg")
  let expected ← read (records / "trial/frozen-before-delivery.json")
  let some entry := (← IO.ofExcept expected.getArr?)[0]? | throw (IO.userError "frozen source missing")
  check ((entry.getObjValD "specification").getObjValD "files" == toJson before) "prepared control source changed"
  IO.FS.createDirAll out
  let installation := arm / "prefix"
  let plugin := installation / "share/eggshell/codex-plugin"
  let binary := installation / "libexec/eggshell"
  let config := arm / "readonly.toml"
  let data := arm / "data"
  let workspace := "/Users/ovm/Code/eggshell-benchmarks/aamas-2027/sources/llvm-project"
  let session := "prepared-cue-capture"
  let env := #[("CODEX_HOME",some (study / "account").toString),("TMPDIR",some (study / "tmp").toString),
    ("EGGSHELL_PREFIX",some installation.toString),("EGGSHELL_DATA_ROOT",some data.toString),
    ("EGGSHELL_CONFIG",some config.toString),("EGGSHELL_PROFILE",some "work"),("PLUGIN_ROOT",some plugin.toString),
    ("CODEX_THREAD_ID",none),("CODEX_TURN_ID",none),("LEAN_NUM_THREADS",some "1"),
    ("OMP_NUM_THREADS",some "1"),("OPENBLAS_NUM_THREADS",some "1"),("MKL_NUM_THREADS",some "1"),
    ("HF_HUB_OFFLINE",some "1"),("TOKENIZERS_PARALLELISM",some "false"),
    ("EGGSHELL_TRACE_SELECTION_RANGES",some "1"),("EGGSHELL_TRACE_SELECTOR_INPUT",some "1")]
  let descriptors ← IO.ofExcept ((← read (records / "runtime-descriptors.json")).getArr?)
  let some baseline := descriptors.find? (fun row => row.getObjValD "arm" == toJson "baseline") |
    throw (IO.userError "control runtime descriptor missing")
  let runtime ← IO.ofExcept (fromJson? (α := StudyRuntime.PublisherRuntime) (baseline.getObjValD "runtime"))
  check ((← ArtifactHash.hex binary) == runtime.sha256) "control executable changed"
  let publisher ← StudyRuntime.startPublisher binary data env (expectedRuntime := some runtime)
  try
    let daemon ← StudyRuntime.startManaged binary plugin session (data / "sessions" / session / "daemon.json") env
    try
      let prompt ← IO.FS.readFile (study / "prompts/topic-1.txt")
      for event in ["SessionStart","UserPromptSubmit"] do
        let request := Json.mkObj ([("hook_event_name",toJson event),("session_id",toJson session),
          ("turn_id",toJson "cue-capture-turn"),("cwd",toJson workspace),("_eggshell_config",toJson config.toString)] ++
          if event == "UserPromptSubmit" then [("prompt",toJson prompt)] else [])
        let response ← StudyCommand.run binary.toString #["codex-hook"] env workspace
          (request.compress ++ "\n") (out / event) 35000
        check (response.exitCode == 0) "cue capture hook failed"
        if event == "UserPromptSubmit" then
          let reply ← IO.ofExcept (Json.parse response.stdout)
          let body ← IO.ofExcept ((reply.getObjValD "hookSpecificOutput").getObjValAs? String "additionalContext")
          let previous ← IO.FS.readFile (records / "trial/baseline/rep-0/topic-1/body.txt")
          check (body == previous) "explicit cue capture changed actual body"
          IO.FS.writeFile (out / "result.json") (Json.mkObj [("elapsedMs",toJson response.elapsedMs),
            ("bodySha256",toJson (Sha256.hex body.toUTF8)),("bodyUnchanged",toJson true),
            ("outsideDeclaredLatencyComparison",toJson true),("answeringModelCalls",toJson (0 : Nat))]).pretty
    finally StudyRuntime.stopManaged daemon (out / "shutdown.json")
  finally StudyRuntime.stopManaged publisher (out / "publisher-shutdown.json")
  IO.FS.createDir (out / "receipts")
  for receipt in ← (data / "receipts").readDir do
    let request := (← read (receipt.path / "request.json")).getObjValD "data"
    unless request.getObjValD "session" == toJson session do continue
    IO.FS.createDir (out / "receipts" / receipt.fileName)
    for entry in ← receipt.path.readDir do
      if entry.fileName.endsWith ".json" then
        IO.FS.writeFile (out / "receipts" / receipt.fileName / entry.fileName) (← IO.FS.readFile entry.path)
  check ((← StudyRuntime.files (arm / "work.egg")) == before) "cue capture changed original source"
