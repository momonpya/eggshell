import tools.research.StudySeedChecks
import tools.research.StudyWorkerProbe
open Lean Eggshell Eggshell.Research

def main (args : List String) : IO UInt32 := do
  try
    let (replay,trialName,outputName,workerName) ← match args with
      | [trialName,outputName] => pure (false,trialName,outputName,none)
      | ["replay",trialName,outputName] => pure (true,trialName,outputName,none)
      | [trialName,outputName,workerName] => pure (false,trialName,outputName,some workerName)
      | _ => throw (IO.userError "WorkerEvidenceAudit [replay] PROBE NEW-DIRECTORY [WORKER-DIRECTORY]")
    let trial := System.FilePath.mk trialName
    let output := System.FilePath.mk outputName
    unless output.isAbsolute && !(← output.pathExists) do throw (IO.userError "new worker evidence directory required")
    IO.FS.createDir output
    let source := trial / "work.egg"
    let study := System.FilePath.mk "/Users/ovm/.codex/experiments/eggshell/study-services-20261026"
    let definitions ← IO.ofExcept (Json.parse (← IO.FS.readFile (study / "task-definitions.json")) >>= Json.getArr?)
    let some definition := definitions.find? fun row => (row.getObjValAs? Nat "topic").toOption == some 2 |
      throw (IO.userError "missing fixed diagnostic question")
    let worker := workerName.map System.FilePath.mk |>.getD (trial / "topic-2/worker")
    let request ← IO.ofExcept (Json.parse (← IO.FS.readFile (worker / "stdin")))
    let pending := request.getObjValD "pending"
    if replay then
      let prefixPath := trial / "prefix"
      let binary := prefixPath / "libexec/eggshell"
      let warm ← IO.ofExcept (Json.parse (← IO.FS.readFile (trial / "warm-complete.json")))
      let runtime ← ArtifactHash.hex binary
      unless (warm.getObjValAs? String "runtimeSha256").toOption == some runtime do
        throw (IO.userError "replay runtime differs from prepared source")
      let data := trial / "data"
      let environment := #[
        ("EGGSHELL_PREFIX",some prefixPath.toString),("EGGSHELL_DATA_ROOT",some data.toString),
        ("EGGSHELL_CONFIG",some (trial / "config.toml").toString),("EGGSHELL_PROFILE",some "work"),
        ("PLUGIN_ROOT",some (prefixPath / "share/eggshell/codex-plugin").toString),
        ("CODEX_THREAD_ID",none),("CODEX_TURN_ID",none),("LEAN_NUM_THREADS",some "1"),
        ("OMP_NUM_THREADS",some "1"),("OPENBLAS_NUM_THREADS",some "1"),("MKL_NUM_THREADS",some "1"),
        ("HF_HUB_OFFLINE",some "1"),("TOKENIZERS_PARALLELISM",some "false")]
      let publisher ← StudyRuntime.startPublisher binary data environment
      try
        let session := "worker-diagnostic-" ++ ((Sha256.hex output.toString.toUTF8).take 16).toString
        let managed ← StudyRuntime.startManaged binary (prefixPath / "share/eggshell/codex-plugin")
          session (data / "sessions" / session / "daemon.json") environment
        try
          let result ← StudyWorkerProbe.run binary source data session
            (← IO.ofExcept (pending.getObjValAs? String "cwd"))
            (← IO.ofExcept (pending.getObjValAs? String "prompt")) environment (output / "worker")
          unless result.exitCode == 0 do throw (IO.userError "diagnostic replay failed")
          IO.FS.writeFile (output / "replay.json") (Json.mkObj [("diagnosticOnly",toJson true),
            ("latencyAcceptance",toJson false),("elapsedMs",toJson result.elapsedMs),
            ("runtimeSha256",toJson runtime)]).pretty
          IO.println s!"Worker diagnostic replay completed in {result.elapsedMs} ms"
        finally StudyRuntime.stopManaged managed (output / "shutdown.json")
      finally StudyRuntime.stopManaged publisher (output / "publisher-shutdown.json")
    let worker := if replay then output / "worker" else worker
    let specification := Json.mkObj [("source",toJson source.toString),
      ("workspace",pending.getObjValD "cwd"),("prompt",pending.getObjValD "prompt"),
      ("files",toJson (← StudyRuntime.files source)),("required",definition.getObjValD "referenceRanges")]
    let input := output / "input.json"
    IO.FS.writeFile input (Json.mkObj [("source",specification),("database",toJson source.toString),
      ("request",toJson (worker / "stdin").toString),("stdout",toJson (worker / "stdout").toString),
      ("timing",toJson (worker / "record.json").toString),("body",toJson "not-a-hook")]).pretty
    let report ← NativeTrialAudit.inspectWorker input.toString
    let available ← IO.ofExcept (Json.parse (← IO.FS.readFile (trial / "frozen-before-delivery.json")))
    let some frozen := (← IO.ofExcept available.getArr?).find? fun row =>
      (row.getObjValAs? Nat "topic").toOption == some 2 | throw (IO.userError "frozen denominator missing")
    unless report.getObjValD "frozenEvidence" == frozen.getObjValD "frozenEvidence" do
      throw (IO.userError "worker diagnostic changed the frozen denominator")
    IO.FS.writeFile (output / "result.json") report.pretty
    IO.println (report.getObjValD "coverageWithoutDeadline").compress
    return 0
  catch error => IO.eprintln error.toString; return 1
