import tools.research.StudyRuntime
import tools.research.StudyCommand
open Lean Eggshell Eggshell.Research

/-- Profile the rejected, unchanged executable. This produces no candidate,
answering-model call, expanded deadline, or delivery-success claim. -/
def main : IO Unit := do
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/direct-evidence"
  let output := root / "selection-profile"
  unless !(← output.pathExists) do throw (IO.userError "preserve previous profile")
  IO.FS.createDir output
  let input := root / "trial-navigation"
  let data := input / "data"
  let config := input / "config.toml"
  let database := input / "work.egg"
  let before ← StudyRuntime.files database
  let installation := root / "prefix"
  let binary := installation / "libexec/eggshell"
  let binaryBefore ← ArtifactHash.hex binary
  let plugin := installation / "share/eggshell/plugin"
  let environment := #[("EGGSHELL_PREFIX",some installation.toString),("EGGSHELL_DATA_ROOT",some data.toString),
    ("EGGSHELL_CONFIG",some config.toString),("EGGSHELL_PROFILE",some "work"),("PLUGIN_ROOT",some plugin.toString),
    ("EGGSHELL_HANDOFF_TRACE",some (output / "handoff.trace").toString),
    ("EGGSHELL_TRACE_SELECTION_RANGES",some "1"),("EGGSHELL_TRACE_SELECTOR_INPUT",some "1"),
    ("LEAN_NUM_THREADS",some "1"),("OMP_NUM_THREADS",some "1"),("OPENBLAS_NUM_THREADS",some "1"),
    ("MKL_NUM_THREADS",some "1"),("HF_HUB_OFFLINE",some "1"),("TOKENIZERS_PARALLELISM",some "false")]
  let workspace := "/Users/ovm/Code/eggshell-benchmarks/aamas-2027/sources/llvm-project"
  let publisher ← StudyRuntime.startPublisher binary data environment
  try
    let session := "direct-evidence-os-profile"
    let managed ← StudyRuntime.startManaged binary plugin session (data / "sessions" / session / "daemon.json") environment
    try
      let request := fun event extra => Json.mkObj ([("hook_event_name",toJson event),
        ("session_id",toJson session),("turn_id",toJson "first"),("cwd",toJson workspace),
        ("_eggshell_config",toJson config.toString)] ++ extra)
      let _ ← StudyCommand.run binary.toString #["codex-hook"] environment workspace
        ((request "SessionStart" []).compress ++ "\n") (output / "SessionStart") 35000
      let prompt ← IO.FS.readFile (root.parent.get! / "prompts/topic-1.txt")
      let hook ← IO.asTask (prio := .dedicated) (StudyCommand.run binary.toString #["codex-hook"] environment workspace
        ((request "UserPromptSubmit" [("prompt",toJson prompt)]).compress ++ "\n")
        (output / "UserPromptSubmit") 35000)
      let deadline := (← IO.monoMsNow)+22000
      let mut focused := false
      while (← IO.monoMsNow) < deadline && !focused do
        if ← (output / "handoff.trace").pathExists then
          focused := (← IO.FS.readFile (output / "handoff.trace")).contains "source focus"
        if !focused then IO.sleep 50
      unless focused do throw (IO.userError "search did not reach the selection boundary")
      for index in [0:2] do
        if index > 0 then IO.sleep 6000
        let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","pid=,ppid=,command="]}
        let owned := processes.stdout.splitOn "\n" |>.filter (fun row =>
          row.contains (binary.toString ++ " codex-worker ") && row.contains "search")
        IO.FS.writeFile (output / s!"owned-search-{index}.txt") ("\n".intercalate owned)
        let [worker] := owned | throw (IO.userError "expected one owned search worker")
        let some pid := (worker.splitOn " " |>.filter (! ·.isEmpty)).head? >>= String.toNat? |
          throw (IO.userError "invalid owned worker PID")
        let measured ← IO.Process.output {cmd := "/usr/bin/sample",args := #[toString pid,"2","1",
          "-file",(output / s!"selection-{index}.sample.txt").toString]}
        IO.FS.writeFile (output / s!"sample-{index}.json") (Json.mkObj [
          ("pid",toJson pid),("exitCode",toJson measured.exitCode.toNat),
          ("stdout",toJson measured.stdout),("stderr",toJson measured.stderr)]).pretty
      let result ← IO.ofExcept hook.get
      IO.FS.writeFile (output / "result.json") (Json.mkObj [
        ("diagnosticOnly",toJson true),("answeringModels",toJson (0 : Nat)),
        ("deadlineChanged",toJson false),("runtimeSha256",toJson binaryBefore),
        ("sameRuntime",toJson ((← ArtifactHash.hex binary) == binaryBefore)),
        ("sameSourcePublication",toJson ((← StudyRuntime.files database) == before)),
        ("hookElapsedMsUnderSampling",toJson result.elapsedMs)]).pretty
    finally StudyRuntime.stopManaged managed (output / "shutdown.json")
  finally StudyRuntime.stopManaged publisher (output / "publisher-shutdown.json")
