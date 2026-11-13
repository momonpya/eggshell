import tools.research.StudyAcquire
import tools.research.StudyReadiness
import tools.research.StudyRecordedRun

open Lean Eggshell Eggshell.Research

namespace Eggshell.Research.NativeSeedFinalize

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
def cliMain (args : List String) : IO UInt32 := do
  try
    let (drainOnly,args) := match args with
      | "--drain-only" :: rest => (true,rest)
      | _ => (false,args)
    let (kind,args) := if args.head? == some "--trial" then (StudyRecordedRun.Kind.memory,args.drop 1)
      else (.seed,args)
    let [acquisition,directory] := args |
      throw (IO.userError "NativeSeedFinalize ACQUISITION NEW-REPORT-DIRECTORY")
    let root := System.FilePath.mk acquisition
    let output := System.FilePath.mk directory
    check (root.isAbsolute && output.isAbsolute && !(← output.pathExists)) "new absolute finalization output required"
    let plan ← StudyRecordedRun.read kind root
    for artifact in plan.pluginFiles do StudyAdmission.verifyArtifact artifact
    IO.FS.createDir output
    let thread ← StudyAdmission.readJson (root / "thread.json").toString
    let session ← IO.ofExcept ((← IO.ofExcept (thread.getObjVal? "thread")).getObjValAs? String "id")
    let data := plan.data
    check ((← IO.getEnv "EGGSHELL_DATA_ROOT") == some data.toString)
      "finalization probes must use the seed's actual private root"
    let files := data / "sessions" / session
    let before ← queued files
    IO.FS.writeFile (output / "queued-before.json") ((toJson before).compress ++ "\n")
    let environment := replaceEnv plan.environment #[
      ("EGGSHELL_DATA_ROOT",some data.toString),("EGGSHELL_CONFIG",some plan.configuration.toString),
      ("EGGSHELL_PROFILE",some "work"),("CODEX_THREAD_ID",some session),("CODEX_TURN_ID",none)]
    if !before.isEmpty then
      let publisher ← StudyRuntime.startPublisher (.mk plan.runtime.path) data environment
      let managed ← try
        StudyRuntime.startManaged (.mk plan.runtime.path) (.mk plan.pluginRoot)
          session (data / "daemon.json") environment
        catch error =>
          StudyRuntime.stopManaged publisher (output / "publisher-shutdown.json")
          throw error
      try
        let deadline := (← IO.monoMsNow)+120000
        repeat
          if (← queued files).isEmpty then break
          check ((← IO.monoMsNow) < deadline) "frozen runtime did not drain its queued seed publication"
          IO.sleep 100
      finally
        try StudyRuntime.stopManaged managed (output / "shutdown.json")
        finally StudyRuntime.stopManaged publisher (output / "publisher-shutdown.json")
    let after ← queued files
    check after.isEmpty "queued source work remains after owned daemon exit"
    let ancestry ← StudySource.inspect plan.database
    IO.FS.writeFile (output / "source-ancestry.json") (toJson ancestry).compress
    StudySource.requireValid ancestry
    if drainOnly then
      let publication ← StudyRuntime.checkpoint plan.database (output / "drained.egg")
      IO.FS.writeFile (output / "result.json") ((Json.mkObj [
        ("mode",toJson "drain-only"),("runtime",toJson plan.runtime),("sourceFiles",toJson publication),
        ("queuedBefore",toJson before.size),("queuedAfter",toJson after.size),
        ("answeringModelCalls",toJson (0 : Nat)),("numericalProviderStarted",toJson false)]).compress ++ "\n")
      return 0
    -- Warm after the save/index child has exited: there is only one writer.
    let replay ← StudyReadiness.finishJournal plan.runtime.path plan.database environment plan.workspace (output/"finish-replay")
    let preparation ← StudyRuntime.startPublisher (.mk plan.runtime.path) data environment
    let warm ← try
      StudyCommand.run plan.runtime.path #["egg","warm","work"] environment
        plan.workspace "" (output / "warm") 240000
      finally StudyRuntime.stopManaged preparation (output/"preparation-publisher-shutdown.json")
    check (warm.exitCode == 0) "frozen runtime warm failed"
    let coverage := (← StudyReadiness.warm warm plan.database).coverage
    let prepared ← DB.PageMap.pin plan.database
    let target : Eggshell.Plugin.IndexTarget := {
      owner := DB.Sidecar.Owner.ofSnapshot prepared
      command := [plan.runtime.path,"search-provider"]
      storage := .database}
    let numericalAndOriginalViews := !(← Eggshell.Warm.required target prepared)
    let sharedSynapses := !(← Synapses.Build.required prepared .database)
    let journalExists := (← Synapses.Journal.open? prepared).isSome
    let journalReplayed := replay.complete && replay.pending == 0
    IO.FS.writeFile (output / "view-readiness.json") (Json.mkObj [
      ("source",toJson prepared.head),("numericalAndOriginalViews",toJson numericalAndOriginalViews),
      ("sharedSynapses",toJson sharedSynapses),("privateJournalPresent",toJson journalExists),
      ("privateJournalReplayed",toJson journalReplayed),("freshnessCertifiedByReplay",toJson false)]).compress
    check (numericalAndOriginalViews && sharedSynapses && journalReplayed)
      "seed preparation debt remains; retain the durable seed and finish preparation before model trials"
    let doctor ← StudyCommand.run plan.runtime.path #["egg","doctor"] environment
      plan.workspace "" (output / "doctor") 60000
    check (doctor.exitCode == 0) "frozen runtime doctor failed"
    let publication ← StudyRuntime.checkpoint plan.database (output / "ready.egg")
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

end Eggshell.Research.NativeSeedFinalize
