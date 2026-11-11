import Main
import Eggshell.ContractAudit
import tools.research.SharedTrafficChecks
open Lean Eggshell Eggshell.Plugin Eggshell.Research
open Eggshell.Research.SharedProjectLifecycle
namespace TerminalCaptureChecks

def sample (root : System.FilePath) (session turn : String) (target : Option String) : PendingTurn := {
  sessionId := session
  turnId := turn
  cwd := root.toString
  prompt := "Keep the original captured writer boundary."
  profile := "work"
  semanticMatcher := none
  read := target.toList
  write := target
  handoffChars := 500000
  projection := .automatic }

def stopInput (session : String) (turn : Option String) (message : String) : Json :=
  Json.mkObj ([("hook_event_name",toJson "Stop"),("session_id",toJson session),
    ("last_assistant_message",toJson message)]++turn.toList.map ("turn_id",toJson ·))

def queued (files : SessionFiles) : IO (Array PendingTurn) := do
  let folder := files.directory/"checkpoints"
  if !(← folder.pathExists) then return #[]
  let mut result := #[]
  for entry in ← folder.readDir do
    if entry.fileName.endsWith ".json" then
      let some pending ← (readJson? entry.path pendingJsonDefaults : IO (Option PendingTurn)) |
        throw (IO.userError "checkpoint disappeared")
      result := result.push pending
  return result

def create (root : System.FilePath) (session : String) (target : Option String) : IO (SessionFiles × PendingTurn) := do
  let files ← sessionFiles session
  let pending := sample root session "original-turn" target
  writeJson files.state ({profile := "work"} : ThreadState)
  writeJson files.pending pending
  return (files,pending)

def boundaries (directory : String) : IO Unit := do
  let root : System.FilePath := .mk directory
  check (root.isAbsolute && !(← root.pathExists) && (← Paths.dataRoot) == root/"data") "isolated native boundary root required"
  IO.FS.createDirAll root
  let target := (root/"old.egg").toString
  let (files,pending) ← create root "capture-lock" (some target)
  let message := "Capture must not wait for the session state lock."
  let started ← IO.monoMsNow
  Persistence.withLockWithin files.lock 1000 do
    captureTerminal (stopInput pending.sessionId (some pending.turnId) message)
  let elapsed := (← IO.monoMsNow)-started
  let captured ← queued files
  check (captured.size == 1 && captured.all (fun row => row.write == pending.write &&
    row.turnId == pending.turnId && row.finalMessage == some message && row.closed && row.inFlight.isEmpty))
    "locked native ingress did not retain the exact terminal scope"
  check ((← readPendingBase? files).any (fun row => row.finalMessage.isNone && !row.closed))
    "native ingress changed lifecycle metadata outside its owner"
  captureTerminal (stopInput pending.sessionId (some pending.turnId) message)
  check ((← queued files).size == 1) "duplicate capture created a second checkpoint"

  let (late,older) ← create root "capture-late" (some target)
  writeJson (closedTurnPath late older.turnId) {older with closed := true}
  writeJson late.pending {older with turnId := "new-turn",write := some (root/"other.egg").toString}
  captureTerminal (stopInput older.sessionId (some older.turnId) "Late answer belongs to the older project.")
  check ((← queued late).all (fun row => row.turnId == older.turnId && row.write == older.write))
    "late answer borrowed the active writer target"
  check ((← queued late).size == 1) "late closed-turn answer was not queued"
  captureTerminal (stopInput older.sessionId (some "unknown-turn") "Unbound answer.")
  check ((← queued late).size == 1 && (← (late.directory/"unbound-answers").readDir).size == 1)
    "unknown turn acquired a writer grant or lost private recovery evidence"

  let (readonly,readTurn) ← create root "capture-readonly" none
  captureTerminal (stopInput readTurn.sessionId (some readTurn.turnId) "Read-only answer.")
  check ((← queued readonly).isEmpty) "readonly terminal capture created a source job"
  let (omitted,noTurn) ← create root "capture-omitted" (some target)
  captureTerminal (stopInput noTurn.sessionId none "Omitted ID retains the active captured boundary.")
  check ((← queued omitted).size == 1 && (← queued omitted).all (fun row =>
    row.turnId == noTurn.turnId && row.write == noTurn.write)) "omitted turn changed the existing active-turn convention"
  let (disabled,offTurn) ← create root "capture-off" (some target)
  writeJson disabled.state ({profile := "work",enabled := false} : ThreadState)
  captureTerminal (stopInput offTurn.sessionId (some offTurn.turnId) "Disabled answer.")
  check ((← queued disabled).isEmpty && !(← (disabled.directory/"unbound-answers").pathExists))
    "disabled capture retained new memory"

  let (corrupt,badTurn) ← create root "capture-corrupt" (some target)
  IO.FS.writeFile corrupt.pending "invalid control metadata"
  let rejected ← try
      captureTerminal (stopInput badTurn.sessionId (some badTurn.turnId) "Retain without inventing a writer.")
      pure false
    catch _ => pure true
  check (rejected && (← queued corrupt).isEmpty &&
    (← (corrupt.directory/"unbound-answers").readDir).size == 1)
    "corrupt control state granted publication or lost the native answer"
  let (foreign,foreignTurn) ← create root "capture-foreign" (some target)
  writeJson foreign.pending {foreignTurn with sessionId := "different-chat"}
  captureTerminal (stopInput foreignTurn.sessionId (some foreignTurn.turnId) "Wrong session must not publish.")
  check ((← queued foreign).isEmpty && (← (foreign.directory/"unbound-answers").readDir).size == 1)
    "foreign metadata granted the caller a source target"
  check (!(← (root/"old.egg").pathExists) && !(← (root/"other.egg").pathExists))
    "metadata capture performed foreground DB work"
  save (root/"result.json") (Json.mkObj [("captureWhileStateLockedMs",toJson elapsed),
    ("scopeAndAnswerRetained",toJson true),("duplicateIdempotent",toJson true),
    ("closedTurnTargetRetained",toJson true),("unknownTurnOnlyPrivate",toJson true),
    ("readonlyAndDisabledDoNotPublish",toJson true),("corruptAndForeignMetadataDoNotAuthorize",toJson true),
    ("foregroundDatabaseWrites",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat))])

def fault (inputPath directory : String) : IO Unit := do
  let plan ← IO.ofExcept (fromJson? (α := StudySeedChecks.Input) (← StudyAdmission.readJson inputPath))
  StudyAdmission.verifyArtifact plan.runtime
  for artifact in plan.pluginFiles do StudyAdmission.verifyArtifact artifact
  StudySeedChecks.requireNumericalSupport plan
  let root : System.FilePath := .mk directory
  check (root.isAbsolute && !(← root.pathExists) && (← Paths.dataRoot) == root/"data") "isolated native fault root required"
  IO.FS.createDirAll (root/"src")
  let item : Case := {
    session := "terminal-fault-writer"
    path := "src/fault.cpp"
    symbol := "CAPTURE_FAULT_BASE"
    first := "int CAPTURE_FAULT_BASE = 17;"
    second := "int CAPTURE_FAULT_DETAIL = 23;" }
  IO.FS.writeFile (root/item.path) (item.first++"\n"++item.second++"\n")
  let active ← ProjectStore.create (root/"active.egg") 4
  let config := root/"active.toml"
  IO.FS.writeFile config (SharedTrafficChecks.config plan.runtime.path active.directory true)
  let data := root/"data"
  let env := replaceEnv plan.environment #[("EGGSHELL_DATA_ROOT",some data.toString)]
  let publisher ← IO.mkRef (none : Option StudyRuntime.Managed)
  let frontend ← IO.mkRef (none : Option StudyRuntime.Managed)
  let stopServices := fun label => do
    try
      if let some managed ← frontend.get then
        StudyRuntime.stopManaged managed (root/(label++"-frontend-stop.json"))
        frontend.set none
    finally
      if let some managed ← publisher.get then
        StudyRuntime.stopManaged managed (root/(label++"-publisher-stop.json"))
        publisher.set none
  let startServices := fun initial => do
    check ((← publisher.get).isNone && (← frontend.get).isNone) "owned services already live"
    publisher.set (some (← StudyRuntime.startPublisher (.mk plan.runtime.path) data env))
    frontend.set (some (← StudyRuntime.startManaged (.mk plan.runtime.path) (.mk plan.pluginRoot)
      initial (data/"daemon.json") env))
  try
    startServices item.session
    let invoke := fun session label event fields => do
      if event != "Stop" then
        return ← RegisteredHook.invoke plan root root data config session label event fields
      let files ← sessionFiles session
      Persistence.withLockWithin files.lock 1000 do
        let failed ← try
            discard <| RegisteredHook.invoke plan root root data config session label event fields
            pure false
          catch _ => pure true
        check failed "held session lock did not reproduce the terminal transport failure"
        let call := root/"calls"/session/label
        let output ← IO.FS.readFile (call/"stdout")
        check ((← IO.ofExcept (Json.parse output)) ==
          (← IO.ofExcept (Json.parse (Daemon.incompleteHook "Stop")))) "fault did not return the expected incomplete notice"
        let checkpoints ← queued files
        check (checkpoints.any (fun row => row.write == some active.directory.toString &&
          row.finalMessage == some (answer item))) "deadline expired before durable answer capture"
        save (root/"captured-before-services-stop.json") (toJson checkpoints)
        stopServices "fault"
        check ((← queued files).any (fun row => row.finalMessage == some (answer item)))
          "service shutdown lost captured terminal work"
        let timing ← StudyAdmission.readJson (call/"record.json").toString
        return ({
          exitCode := ← IO.ofExcept (timing.getObjValAs? Nat "exitCode")
          elapsedMs := ← IO.ofExcept (timing.getObjValAs? Nat "elapsedMs")
          stdout := output
          stderr := ← IO.FS.readFile (call/"stderr") } : StudyCommand.Result)
    discard <| writer plan root data config active.directory item true 1 invoke false
    let before ← originals active
    startServices item.session
    discard <| SharedTrafficChecks.waitAnswers active #[item]
    let recovered ← originals active
    check (recovered != before) "recovery did not publish the captured answer"
    let some sourceService ← frontend.get | throw (IO.userError "missing owned recovery frontend")
    save (root/"recovered-answer.json") (Json.mkObj [("automaticRecovery",toJson true),
      ("hookReplayed",toJson false),("keepOrWarmIssued",toJson false),("before",before),("after",recovered)])
    let healthy : Case := {item with
      session := "terminal-healthy-writer"
      path := "src/healthy.cpp"
      symbol := "CAPTURE_HEALTHY_BASE"
      first := "int CAPTURE_HEALTHY_BASE = 31;"
      second := "int CAPTURE_HEALTHY_DETAIL = 37;" }
    IO.FS.writeFile (root/healthy.path) (healthy.first++"\n"++healthy.second++"\n")
    discard <| writer plan root data config active.directory healthy true 1
      (fun session label event fields => RegisteredHook.invoke plan root root data config session label event fields) false
    discard <| SharedTrafficChecks.waitAnswers active #[item,healthy]
    let faultSource ← active.current (ProjectStore.routeSlot item.session 4)
    let faultJournal ← Synapses.Journal.prepare faultSource
    let faultEntries ← Synapses.Journal.turnEntries faultJournal ⟨item.session,"recorded-turn"⟩
    let healthySource ← active.current (ProjectStore.routeSlot healthy.session 4)
    let healthyJournal ← Synapses.Journal.prepare healthySource
    let healthyEntries ← Synapses.Journal.turnEntries healthyJournal ⟨healthy.session,"recorded-turn"⟩
    check (healthyEntries.size == 7) "normal Pre/Post/Stop synaptic journal regressed"
    discard <| warm plan root data config "ready-after-recovery"
    let preparedHealthy ← active.current (ProjectStore.routeSlot healthy.session 4)
    let some prepared ← Synapses.Index.open? preparedHealthy .database .shared |
      throw (IO.userError "healthy source did not prepare its synaptic index")
    let facts ← Synapses.Index.allFacts prepared.index
    let consumed := (facts.filter fun fact => match fact with | .consumed _ => true | _ => false).size
    let supported := (facts.filter fun fact => match fact with | .supports _ => true | _ => false).size
    let coquoted := (facts.filter fun fact => match fact with | .coquoted _ _ => true | _ => false).size
    check (consumed > 0 && supported ≥ 2 && coquoted > 0) "healthy hooks lost an advisory edge type"
    save (root/"result.json") (Json.mkObj [("runtime",toJson plan.runtime),
      ("faultAnswerPersistedAfterServiceRestart",toJson true),("failedStopRelabeledSuccessful",toJson false),
      ("healthyStopCompleted",toJson true),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false),
      ("sourceAfter",← originals active),("recoveryFrontendPid",toJson (StudyRuntime.pid sourceService)),
      ("faultJournalEntries",toJson faultEntries.size),("healthyJournalEntries",toJson healthyEntries.size),
      ("healthySynapses",Json.mkObj [("consumed",toJson consumed),("supports",toJson supported),
        ("coquoted",toJson coquoted)])])
  finally stopServices "final"
end TerminalCaptureChecks
def main (args : List String) : IO UInt32 := do
  match args with
  | ["boundaries",directory] => TerminalCaptureChecks.boundaries directory; return 0
  | ["fault",input,directory] => TerminalCaptureChecks.fault input directory; return 0
  | _ => sourceRouteEngine args
