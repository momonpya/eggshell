import tools.research.StudyAcquire

open Lean Eggshell Eggshell.Research

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def replaceEnv (original updates : Array (String × Option String)) :=
  original.filter (fun row => !updates.any (·.1 == row.1)) ++ updates

private def queued (directory : System.FilePath) : IO (Array String) := do
  let mut result := #[]
  for lane in #["checkpoints","deferred"] do
    let path := directory / lane
    if !(← path.pathExists) then continue
    for entry in ← path.readDir do
      if entry.fileName.endsWith ".json" then result := result.push entry.path.toString
  return result.qsort (· < ·)

/-- Finish the actual frozen runtime's durable work, without an answering
model or reconstructed hook events. Only that executable may write the DB. -/
def main (args : List String) : IO UInt32 := do
  try
    let [acquisition,directory] := args |
      throw (IO.userError "NativeSeedFinalize ACQUISITION NEW-REPORT-DIRECTORY")
    let root := System.FilePath.mk acquisition
    let output := System.FilePath.mk directory
    check (root.isAbsolute && output.isAbsolute && !(← output.pathExists)) "new absolute finalization output required"
    let plan ← IO.ofExcept (fromJson? (α := StudyAcquire.Plan)
      (← StudyAdmission.readJson (root / "plan.json").toString))
    let result ← StudyAdmission.readJson (root / "result.json").toString
    check (plan.kind == "seed" && (result.getObjValAs? Bool "completed").toOption == some true)
      "completed real seed acquisition required"
    StudyAdmission.verifyArtifact plan.runtime
    for artifact in plan.pluginFiles do StudyAdmission.verifyArtifact artifact
    IO.FS.createDir output
    let thread ← StudyAdmission.readJson (root / "thread.json").toString
    let session ← IO.ofExcept ((← IO.ofExcept (thread.getObjVal? "thread")).getObjValAs? String "id")
    let data := root / "data"
    let files := data / "sessions" / session
    let before ← queued files
    IO.FS.writeFile (output / "queued-before.json") ((toJson before).compress ++ "\n")
    let environment := replaceEnv plan.environment #[
      ("EGGSHELL_DATA_ROOT",some data.toString),("EGGSHELL_CONFIG",some (root / "config.toml").toString),
      ("EGGSHELL_PROFILE",some "work"),("CODEX_THREAD_ID",some session),("CODEX_TURN_ID",none)]
    if !before.isEmpty then
      let managed ← StudyRuntime.startManaged (.mk plan.runtime.path) (.mk plan.pluginRoot)
        session (files / "daemon.json") environment
      try
        let deadline := (← IO.monoMsNow)+120000
        repeat
          if (← queued files).isEmpty then break
          check ((← IO.monoMsNow) < deadline) "frozen runtime did not drain its queued seed publication"
          IO.sleep 100
      finally StudyRuntime.stopManaged managed (output / "shutdown.json")
    let after ← queued files
    check after.isEmpty "queued source work remains after owned daemon exit"
    -- Warm after the save/index child has exited: there is only one writer.
    let warm ← StudyCommand.run plan.runtime.path #["egg","warm","work"] environment
      plan.workspace "" (output / "warm") 240000
    check (warm.exitCode == 0) "frozen runtime warm failed"
    let databases ← IO.ofExcept (Json.parse warm.stdout >>= (·.getObjValAs? (Array Json) "databases"))
    check (databases.size == 1) "seed warm returned another database set"
    let coverage ← IO.ofExcept (databases[0]!.getObjVal? "after")
    check ((coverage.getObjValAs? Nat "missing").toOption == some 0 &&
      (coverage.getObjValAs? Nat "invalid").toOption == some 0) "seed vectors remain incomplete"
    let doctor ← StudyCommand.run plan.runtime.path #["egg","doctor"] environment
      plan.workspace "" (output / "doctor") 60000
    check (doctor.exitCode == 0) "frozen runtime doctor failed"
    let publication ← StudyRuntime.checkpoint (root / "work.egg") (output / "ready.egg")
    StudyAdmission.verifyArtifact plan.runtime
    check ((← queued files).isEmpty) "source queue changed while finalizing the seed"
    IO.FS.writeFile (output / "result.json") ((Json.mkObj [
      ("runtime",toJson plan.runtime),("acquisition",toJson acquisition),
      ("publication",toJson (output / "ready.egg").toString),("sourceFiles",toJson publication),
      ("queuedBefore",toJson before.size),("queuedAfter",toJson after.size),
      ("coverage",coverage),("answeringModelCalls",toJson (0 : Nat)),
      ("syntheticHookEvents",toJson (0 : Nat)),("directRelationInsertions",toJson (0 : Nat)),
      ("productionAdoption",toJson false)]).compress ++ "\n")
    return 0
  catch error =>
    IO.eprintln error.toString
    return 1
