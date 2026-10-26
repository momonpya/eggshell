import tools.research.StudySeedChecks
open Lean Eggshell Eggshell.Research

def main (args : List String) : IO UInt32 := do
  try
    let [trial] := args | throw (IO.userError "ProfileSynapticSource EXISTING-TRIAL")
    let root := System.FilePath.mk trial
    let output := root / "profile-topic-2"
    unless root.isAbsolute && !(← output.pathExists) do throw (IO.userError "keep existing source profile")
    IO.FS.createDir output
    let binary := root / "prefix/libexec/eggshell"
    let prefixPath := root / "prefix"
    let plugin := prefixPath / "share/eggshell/codex-plugin"
    let data := root / "data"
    let warm ← IO.ofExcept (Json.parse (← IO.FS.readFile (root / "warm-complete.json")))
    unless (warm.getObjValAs? String "runtimeSha256").toOption == some (← ArtifactHash.hex binary) do
      throw (IO.userError "profile product differs from timed fixture")
    let environment := #[
      ("EGGSHELL_PREFIX",some prefixPath.toString),("EGGSHELL_DATA_ROOT",some data.toString),
      ("EGGSHELL_CONFIG",some (root / "config.toml").toString),("EGGSHELL_PROFILE",some "work"),
      ("PLUGIN_ROOT",some plugin.toString),("CODEX_THREAD_ID",none),("CODEX_TURN_ID",none),
      ("LEAN_NUM_THREADS",some "1"),("OMP_NUM_THREADS",some "1"),("OPENBLAS_NUM_THREADS",some "1"),
      ("MKL_NUM_THREADS",some "1"),("HF_HUB_OFFLINE",some "1"),("TOKENIZERS_PARALLELISM",some "false")]
    let publisher ← StudyRuntime.startPublisher binary data environment
    let session := "atomic-topology-source-profile-2"
    let managed ← try StudyRuntime.startManaged binary plugin session (data / "sessions" / session / "daemon.json") environment
      catch error =>
        StudyRuntime.stopManaged publisher (output / "publisher-shutdown.json")
        throw error
    try
      let original ← IO.ofExcept (Json.parse (← IO.FS.readFile (root / "topic-2/hook/stdin")))
      let request := original.setObjVal! "session_id" (toJson session)
      let workspace ← IO.ofExcept (request.getObjValAs? String "cwd")
      let sampler ← IO.asTask (prio := .dedicated) do
        IO.sleep 16000
        for label in ["selection","render"] do
          let sampled ← IO.Process.output {
            cmd := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean"
            args := #["-j1","-M512","--run","/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/tools/research/SampleCandidate.lean",root.toString,label]}
          unless sampled.exitCode == 0 do throw (IO.userError sampled.stderr)
          if label == "selection" then IO.sleep 5000
      try
        let result ← StudyCommand.run binary.toString #["codex-hook"] environment workspace
          (request.compress ++ "\n") (output / "hook") 35000
        IO.println (Json.mkObj [("elapsedMs",toJson result.elapsedMs),("exitCode",toJson result.exitCode),
          ("diagnosticOnly",toJson true),("latencyAcceptance",toJson false)]).compress
      finally
        let sampled ← IO.wait sampler
        let _ ← IO.ofExcept sampled
        pure ()
    finally
      try StudyRuntime.stopManaged managed (output / "shutdown.json")
      finally StudyRuntime.stopManaged publisher (output / "publisher-shutdown.json")
    return 0
  catch error => IO.eprintln error.toString; return 1
