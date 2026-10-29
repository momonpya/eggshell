import tools.research.StudyRuntime
import tools.research.StudyCommand
open Lean Eggshell Eggshell.Research

/-- One unchanged-runtime CPU diagnosis on the already prepared readonly
fixture. No warm, new DB, answering model, selector change or success claim. -/
def main : IO Unit := do
  let study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  let trial := study / "shared-snapshot/readonly-query-llvm"
  let output : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/query-cache-llvm/profile"
  unless !(← output.pathExists) do throw (IO.userError "preserve existing CPU diagnosis")
  IO.FS.createDir output
  let installation := trial / "candidate/prefix"
  let binary := installation / "libexec/eggshell"
  let plugin := installation / "share/eggshell/codex-plugin"
  let config := trial / "candidate/readonly.toml"
  let data := trial / "data"
  let before ← StudyRuntime.files (trial / "work.egg")
  let binaryHash ← ArtifactHash.hex binary
  unless binaryHash == "d11c80efad039aeb6669c87b914e42f129aded1e40bef46881e75adec078ff53" do
    throw (IO.userError "profile only the checked query-initialization runtime")
  let env := #[("CODEX_HOME",some (study / "account").toString),("TMPDIR",some (study / "tmp").toString),
    ("EGGSHELL_PREFIX",some installation.toString),("EGGSHELL_DATA_ROOT",some data.toString),
    ("EGGSHELL_CONFIG",some config.toString),("EGGSHELL_PROFILE",some "work"),("PLUGIN_ROOT",some plugin.toString),
    ("EGGSHELL_HANDOFF_TRACE",some (output / "handoff.trace").toString),
    ("CODEX_THREAD_ID",none),("CODEX_TURN_ID",none),("LEAN_NUM_THREADS",some "1"),
    ("OMP_NUM_THREADS",some "1"),("OPENBLAS_NUM_THREADS",some "1"),("MKL_NUM_THREADS",some "1"),
    ("HF_HUB_OFFLINE",some "1"),("TOKENIZERS_PARALLELISM",some "false")]
  let workspace := "/Users/ovm/Code/eggshell-benchmarks/aamas-2027/sources/llvm-project"
  let publisher ← StudyRuntime.startPublisher binary data env
  try
    let session := "readonly-query-cpu-profile-2"
    let managed ← StudyRuntime.startManaged binary plugin session (data / "sessions" / session / "daemon.json") env
    try
      let request := fun event extra => Json.mkObj ([("hook_event_name",toJson event),
        ("session_id",toJson session),("turn_id",toJson "profile-turn"),("cwd",toJson workspace),
        ("_eggshell_config",toJson config.toString)] ++ extra)
      let opened ← StudyCommand.run binary.toString #["codex-hook"] env workspace
        ((request "SessionStart" []).compress ++ "\n") (output / "SessionStart") 35000
      unless opened.exitCode == 0 do throw (IO.userError "profile session failed")
      let prompt ← IO.FS.readFile (study / "prompts/topic-2.txt")
      let hook ← IO.asTask (prio := .dedicated) (StudyCommand.run binary.toString #["codex-hook"] env workspace
        ((request "UserPromptSubmit" [("prompt",toJson prompt)]).compress ++ "\n") (output / "UserPromptSubmit") 35000)
      let deadline := (← IO.monoMsNow)+22000
      let mut worker : Option Nat := none
      while worker.isNone && (← IO.monoMsNow) < deadline do
        let trace ← try IO.FS.readFile (output / "handoff.trace") catch _ => pure ""
        if trace.contains "source focus" then
          let rows ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","pid=,command="]}
          unless rows.exitCode == 0 do throw (IO.userError "cannot identify owned search worker")
          let expected := binary.toString ++ " codex-worker search"
          let owned := rows.stdout.splitOn "\n" |>.filter (fun row => row.trimAscii.toString.endsWith expected)
          unless owned.length == 1 do throw (IO.userError "expected one isolated search worker")
          worker := ((owned.head!.trimAscii.toString.splitOn " ").head?.bind String.toNat?)
        if worker.isNone then IO.sleep 50
      let some workerPid := worker | throw (IO.userError "hook never reached post-focus boundary")
      for (label,seconds) in [("source",5),("selection",5)] do
        let sample ← IO.Process.output {cmd := "/usr/bin/sample",args := #[toString workerPid,toString seconds,"2",
          "-file",(output / (label ++ ".sample.txt")).toString]}
        IO.FS.writeFile (output / (label ++ "-sample.json")) (Json.mkObj [
          ("pid",toJson workerPid),("exitCode",toJson sample.exitCode.toNat),
          ("stdout",toJson sample.stdout),("stderr",toJson sample.stderr)]).pretty
        unless sample.exitCode == 0 do throw (IO.userError "CPU sampling failed")
      let result ← IO.ofExcept hook.get
      let reply ← IO.ofExcept (Json.parse result.stdout)
      let body ← IO.ofExcept ((reply.getObjValD "hookSpecificOutput").getObjValAs? String "additionalContext")
      let previous ← IO.FS.readFile (output.parent.get! / "records/candidate/topic-2/body.txt")
      IO.FS.writeFile (output / "body.txt") body
      IO.FS.writeFile (output / "result.json") (Json.mkObj [
        ("diagnosticOnly",toJson true),("answeringModelCalls",toJson (0 : Nat)),
        ("warmCalls",toJson (0 : Nat)),("runtimeSha256",toJson binaryHash),
        ("sourceUnchanged",toJson ((← StudyRuntime.files (trial / "work.egg")) == before)),
        ("bodyUnchanged",toJson (body == previous)),("bodySha256",toJson (Sha256.hex body.toUTF8)),
        ("hookElapsedMsUnderSampling",toJson result.elapsedMs),("hookExitCode",toJson result.exitCode)]).pretty
      unless result.exitCode == 0 do throw (IO.userError "sampled hook failed")
    finally StudyRuntime.stopManaged managed (output / "shutdown.json")
  finally StudyRuntime.stopManaged publisher (output / "publisher-shutdown.json")
