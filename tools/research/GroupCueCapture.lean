import tools.research.StudyRuntime
import tools.research.StudyCommand
open Lean Eggshell Eggshell.Research

private def check (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)
private def read (p : System.FilePath) : IO Json :=
  IO.FS.readFile p >>= fun s => IO.ofExcept (Json.parse s)

/- One unchanged hook for a missing-stage and native sampling diagnostic.
No answer model or second benchmark repetition. No warm or DB rewriting. -/
def main (args : List String) : IO Unit := do
  check (args.isEmpty || args == ["profile"]) "fixed diagnostic or one native profile only"
  let profile := args == ["profile"]
  let study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let records := project / "docs/candidates/group-cue-coverage"
  let out := records / (if profile then "topic-2-profile" else "topic-2-capture")
  check (!(← out.pathExists)) "preserve completed diagnostic"
  let arm := study / "shared-snapshot/group-cue-trial"
  let before ← StudyRuntime.files (arm / "work.egg")
  let runtime : StudyRuntime.PublisherRuntime ← IO.ofExcept (fromJson? (← read (records / "runtime-descriptor.json")))
  let installation := arm / "prefix"
  let binary := installation / "libexec/eggshell"
  check ((← ArtifactHash.hex binary) == runtime.sha256) "do not change the captured runtime"
  let config := arm / "readonly.toml"
  let data := arm / "data"
  let plugin := installation / "share/eggshell/codex-plugin"
  let workspace := "/Users/ovm/Code/eggshell-benchmarks/aamas-2027/sources/llvm-project"
  let session := if profile then "group-cue-profile-topic-2" else "group-cue-capture-topic-2"
  let env := #[("CODEX_HOME",some (study / "account").toString),("TMPDIR",some (study / "tmp").toString),
    ("EGGSHELL_PREFIX",some installation.toString),("EGGSHELL_DATA_ROOT",some data.toString),
    ("EGGSHELL_CONFIG",some config.toString),("EGGSHELL_PROFILE",some "work"),("PLUGIN_ROOT",some plugin.toString),
    ("CODEX_THREAD_ID",none),("CODEX_TURN_ID",none),("LEAN_NUM_THREADS",some "1"),
    ("OMP_NUM_THREADS",some "1"),("OPENBLAS_NUM_THREADS",some "1"),("MKL_NUM_THREADS",some "1"),
    ("HF_HUB_OFFLINE",some "1"),("TOKENIZERS_PARALLELISM",some "false"),
    ("EGGSHELL_TRACE_SELECTION_RANGES",some "1"),
    ("EGGSHELL_TRACE_SELECTOR_INPUT",if profile then none else some "1")]
  IO.FS.createDirAll out
  let publisher ← StudyRuntime.startPublisher binary data env (expectedRuntime := some runtime)
  try
    let daemon ← StudyRuntime.startManaged binary plugin session (data / "sessions" / session / "daemon.json") env
    try
      let prompt ← IO.FS.readFile (study / "prompts/topic-2.txt")
      for event in ["SessionStart","UserPromptSubmit"] do
        IO.FS.writeFile (out / "phase.json") (Json.mkObj [("event",toJson event),("startedMs",toJson (← IO.monoMsNow))]).pretty
        let request := Json.mkObj ([("hook_event_name",toJson event),("session_id",toJson session),
          ("turn_id",toJson "group-capture-turn"),("cwd",toJson workspace),("_eggshell_config",toJson config.toString)] ++
          if event == "UserPromptSubmit" then [("prompt",toJson prompt)] else [])
        let sampling ← if profile && event == "UserPromptSubmit" then
          some <$> IO.asTask (prio := .dedicated) (do
            IO.sleep 8000
            let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","pid,command"]}
            let some target := (processes.stdout.splitOn "\n").find? (fun line =>
              line.contains (binary.toString ++ " codex-worker search")) |
              throw (IO.userError "native search worker absent at declared sampling time")
            let some pid := (target.splitOn " ").find? (!·.isEmpty) |
              throw (IO.userError "search worker has no process identity")
            let sample ← IO.Process.output {cmd := "/usr/bin/sample",args :=
              #[pid,"5","5","-file",(out / "worker.sample.txt").toString]}
            IO.FS.writeFile (out / "sampling.json") (Json.mkObj [
              ("pid",toJson pid),("exitCode",toJson sample.exitCode.toNat),("stderr",toJson sample.stderr),
              ("afterQueryStartMs",toJson (8000 : Nat)),("durationSeconds",toJson (5 : Nat))]).pretty)
        else pure none
        let response ← StudyCommand.run binary.toString #["codex-hook"] env workspace
          (request.compress ++ "\n") (out / event) 35000
        if let some task := sampling then
          let _ ← IO.ofExcept (task.get.mapError IO.Error.toString)
        check (response.exitCode == 0) "diagnostic hook failed"
        if event == "UserPromptSubmit" then
          let reply ← IO.ofExcept (Json.parse response.stdout)
          let body ← IO.ofExcept ((reply.getObjValD "hookSpecificOutput").getObjValAs? String "additionalContext")
          check (body == (← IO.FS.readFile (records / "actual/topic-2/body.txt"))) "capture changed actual topic-2 body"
          IO.FS.writeFile (out / "result.json") (Json.mkObj [("elapsedMs",toJson response.elapsedMs),
            ("bodySha256",toJson (Sha256.hex body.toUTF8)),("bodyUnchanged",toJson true),
            ("outsideLatencyComparison",toJson true),("answeringModelCalls",toJson (0 : Nat))]).pretty
    finally StudyRuntime.stopManaged daemon (out / "shutdown.json")
  finally StudyRuntime.stopManaged publisher (out / "publisher-shutdown.json")
  IO.FS.createDirAll (out / "receipts")
  for entry in ← (data / "receipts").readDir do
    let request := (← read (entry.path / "request.json")).getObjValD "data"
    unless request.getObjValD "session" == toJson session do continue
    let target := out / "receipts" / entry.fileName
    IO.FS.createDirAll target
    for name in ["request.json","selection-plan.json","transport.json","canonical-source-reuse.json"] do
      let file := entry.path / name
      if ← file.pathExists then IO.FS.writeFile (target / name) (← IO.FS.readFile file)
  check ((← StudyRuntime.files (arm / "work.egg")) == before) "diagnostic changed original DB"
