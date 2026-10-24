import Eggshell.Warm
import Eggshell.PluginHooks

open Lean Eggshell Eggshell.Persistence.Store

private def check (value : Bool) (message : String) : IO Unit :=
  unless value do throw (IO.userError message)

private def failed (action : IO α) : IO Bool := do
  try let _ ← action; return false catch _ => return true

private def outcome (name : String) : IO Value :=
  IO.ofExcept (Plugin.relation? .outcome [
    .semantic (.text ("kernel timer question "++name)),
    .semantic (.text ("original timer observation "++name++" "++String.ofList (List.replicate 620 'x')))])

private def publish (source : DB.PageMap.Snapshot) (values : List Value)
    (removed : List Nat := []) : IO DB.PageMap.Snapshot := do
  let _ ← DB.PageMap.withWriter source fun writer => do
    for id in removed do removeRoot writer id
    let intern : Intern := ⟨writer,← IO.mkRef {}⟩
    let ids ← values.mapM intern.root
    writeChange writer ⟨ids,removed,false⟩
  DB.PageMap.pin source.directory

private def signatures (windows : List Warm.Window) :=
  windows.map fun row => (row.document.owner,row.key,row.start)

private def historicalRewrite (root : System.FilePath) : IO Unit := do
  let initial ← DB.PageMap.create (root / "history.egg") "history-authority"
  let first ← publish initial [← outcome "history-first"]
  let second ← publish first [← outcome "history-second"]
  let _ ← DB.PageMap.withWriter second fun writer => do
    -- Deliberately damage an old size descriptor in a later root. Both the
    -- budget check and replay must use that record's original child root.
    putNat writer (key "change" first.head.revision) (8*1024*1024+1)
    putChunks writer "change" (second.head.revision+1)
      (publicationCodec.encode ⟨second.head,⟨[],[],false⟩⟩).toByteArray
  let latest ← DB.PageMap.pin initial.directory
  let some delta ← SourceDelta.read? latest initial.head |
    throw (IO.userError "later journal rewrite changed historical replay")
  check (delta.records == 3 && delta.owners.length == 2)
    "historical journal replay lost source changes"

private def scenario (root : System.FilePath) : IO Unit := do
  let initial ← DB.PageMap.create (root / "source.egg") (Persistence.valueToJson (.text "authority")).compress
  let values ← (List.range 8).mapM fun i => outcome (toString i)
  let source ← publish initial values
  let binary := (← IO.appPath).withFileName "eggshell"
  let command := [binary.toString,"search-provider"]
  let target ← Plugin.registerIndexTarget source command true
  let originalHead := source.head
  let first ← Warm.runTarget source target true
  check (first.scope == "full-source" && first.requested > 0 && first.after.missing == 0 &&
    first.after.invalid == 0 && (← DB.PageMap.pin source.directory).head == originalHead)
    "full preparation failed or changed original facts"
  let repeated ← Warm.runTarget source target
  check (repeated.scope == "publication-delta" && repeated.before.windows == 0 &&
    repeated.requested == 0 && repeated.projections.any (·.requested == 0)) "unchanged source was rescanned"
  let path ← Warm.checkpointPath target source
  let checkpointBytes ← IO.FS.readBinFile path
  let pending : Plugin.PendingTurn := {
    sessionId := "deadline-observation"
    turnId := "deadline-observation"
    cwd := root.toString
    prompt := "kernel timer"
    profile := "work"
    handoffChars := 120000
    projection := .automatic
    read := [source.directory.toString]
    write := some source.directory.toString
    semanticMatcher := some command }
  let registrations ← Plugin.requestBackgroundWarm pending ((← IO.monoMsNow)+5000)
  check (registrations == 1 && (← IO.FS.readBinFile path) == checkpointBytes && !(← Warm.required target source))
    "deadline registration invalidated or forced preparation"
  let alternate := {target with command := "/unavailable-provider-path" :: command.tail}
  check ((← Warm.checkpointPath alternate source) == path && !(← Warm.required alternate source))
    "executable placement created a different semantic checkpoint"
  let _ ← DB.PageMap.withWriter source fun writer => do
    writer.put "memo:delta-warm" (some "derived".toUTF8)
    writeChange writer ⟨[],[],false⟩
  let memo ← DB.PageMap.pin source.directory
  let memoWarm ← Warm.runTarget memo target
  check (memoWarm.scope == "publication-delta" && memoWarm.publications == 1 &&
    memoWarm.changedOwners == 0 && memoWarm.before.windows == 0) "neutral journal required old windows"
  let addedValue ← outcome "new-owner"
  let appended ← publish memo [addedValue]
  let some addedId ← findNode? appended addedValue | throw (IO.userError "new owner missing")
  appended.trace.set (some {})
  let selected ← Warm.plan appended target false false
  let traced ← appended.trace.get
  check (selected.scope == "publication-delta" && selected.owners == 1 &&
    traced.any (fun trace => trace.complete && trace.operations.all (fun operation => match operation with
      | .range .. => false
      | _ => true))) "delta plan scanned complete source directories"
  appended.trace.set none
  let (allDiscovery,allFocus) ← Warm.planWindows appended false
  check (signatures selected.windows.1 == signatures (allDiscovery.filter (·.document.owner == addedId)) &&
    signatures selected.windows.2 == signatures (allFocus.filter (·.document.owner == addedId)))
    "changed owner windows differ from full source planning"
  let updated ← Warm.runTarget appended target
  check (updated.scope == "publication-delta" && updated.changedOwners == 1 &&
    updated.before.windows == (hashDistinct ((selected.windows.1++selected.windows.2).map (·.key))).length &&
    updated.projections.any (fun result => result.requested == updated.before.windows))
    "warm did not pass only changed window keys"
  let replacement ← outcome "replacement"
  let replaced ← publish appended [replacement] [addedId]
  let replacementWarm ← Warm.runTarget replaced target
  check (replacementWarm.scope == "publication-delta" && replacementWarm.changedOwners == 1)
    "remove/add replacement reused the old counter-only checkpoint"
  let gap := replaced
  let saved : Warm.Checkpoint ← IO.ofExcept (Json.parse (← IO.FS.readFile path) >>= fromJson?)
  let invalid := {saved with source := {saved.source with bytes := saved.source.bytes+1}}
  FileSystem.atomicExistingBytes path (toJson invalid).compress.toUTF8
  check ((← Warm.plan gap target false false).scope == "full-source" && (← Warm.required target gap))
    "a different head with the same counters bypassed history validation"
  FileSystem.atomicExistingBytes path (toJson saved).compress.toUTF8
  let settings ← Warm.options gap command
  PreparationDebt.record target.owner settings.model SearchProvider.encoderContract .unavailableInput 1
  let captured ← PreparationDebt.capture target.owner settings.model SearchProvider.encoderContract
  PreparationDebt.record target.owner settings.model SearchProvider.encoderContract .unavailableInput 1
  PreparationDebt.acknowledge target.owner settings.model SearchProvider.encoderContract captured
  check (← PreparationDebt.pending target.owner settings.model SearchProvider.encoderContract)
    "repair acknowledgement erased a newer event"
  let debtWarm ← Warm.runTarget gap target
  check (debtWarm.scope == "full-source" && debtWarm.planReason == "observed-unavailable-input" &&
    !(← PreparationDebt.pending target.owner settings.model SearchProvider.encoderContract))
    "observed repair debt did not force and finish verification"
  let docs ← searchDocuments gap
  let some doc := docs.head? | throw (IO.userError "missing source document")
  let some window := doc.windows.head? | throw (IO.userError "missing source window")
  IO.FS.removeDirAll (VectorMatrix.folder settings.cache settings.model SearchProvider.encoderContract)
  IO.FS.writeFile (settings.cache / "vectors" /
    (SearchProvider.windowCacheKey settings.model window ++ ".json")) "damaged fixture input"
  let result ← SemanticMatcher.nominateIndexed command "kernel timer" docs [] []
    (fun document index => readSearchWindow gap document index.val)
  check (result.isNone && (← PreparationDebt.pending target.owner settings.model SearchProvider.encoderContract))
    "actual unavailable-input search did not retain repair debt"
  let repaired ← Warm.runTarget gap target
  check (repaired.scope == "full-source" && repaired.requested == 1 &&
    !(← PreparationDebt.pending target.owner settings.model SearchProvider.encoderContract) &&
    !(← Warm.required target gap)) "actual source hint repair did not complete"
  let _ ← DB.PageMap.withWriter gap fun writer => writer.put "memo:no-journal" (some "derived".toUTF8)
  let discontinuousSource ← DB.PageMap.pin source.directory
  let discontinuous ← Warm.plan discontinuousSource target false false
  check (discontinuous.scope == "full-source") "journal gap was treated as no source work"
  check (← failed (Warm.runTarget discontinuousSource target))
    "full preparation silently accepted a broken original journal"
  let ordinal ← getNat discontinuousSource.get (key "member" doc.owner)
  let _ ← DB.PageMap.withWriter discontinuousSource fun writer =>
    writer.put (key "searchCandidate" ordinal) none
  let inconsistent ← DB.PageMap.pin source.directory
  check (← failed (SourceDelta.documents inconsistent [doc.owner]))
    "delta planning accepted an inconsistent reverse candidate directory"
  historicalRewrite root
  let report := Json.mkObj [
    ("first",toJson first),("unchanged",toJson repeated),("memo",toJson memoWarm),
    ("addition",toJson updated),("replacement",toJson replacementWarm),
    ("journalGapPlan",toJson discontinuous.scope),("brokenSourceJournalRejected",toJson true),
    ("inconsistentCandidateRejected",toJson true),
    ("historicalJournalRewriteIgnored",toJson true),
    ("debtVerification",toJson debtWarm),("actualUnavailableRepair",toJson repaired),
    ("deadlinePreservesCheckpoint",toJson true),("providerPathIndependent",toJson true),
    ("deltaTraceNoCatalogueScan",toJson true),("changedWindowsEqualFullPlan",toJson true),
    ("newDebtSurvivesAcknowledgement",toJson true),("differentHeadRejected",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]
  IO.FS.writeFile (root / "result.json") report.pretty
  IO.println report.compress

def main (args : List String) : IO Unit := do
  let [output] := args | throw (IO.userError "SourceDeltaWarmSmoke NEW-OUTPUT")
  let root := System.FilePath.mk output
  check (!(← root.pathExists)) "preserve previous warm tests"
  FileSystem.privateDirectory root
  scenario root
