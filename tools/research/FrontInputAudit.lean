import Main
open Lean Eggshell Eggshell.Plugin
namespace Eggshell.Research.FrontInputAudit
def run (args : List String) : IO Unit := do
  let folder::mode := args | throw (IO.userError "controlled fixture required")
  unless mode == [] || mode == ["retry"] do throw (IO.userError "unknown audit mode")
  let root : System.FilePath := .mk folder
  let files ← sessionFiles "seed-chat"
  let mut rows := #[]
  for entry in ← (files.directory/"checkpoints").readDir do
    if !entry.fileName.endsWith ".json" then continue
    let pending ← readBoundedJson (α := PendingTurn) entry.path (1024*1024)
    let selection ← ProjectAccess.resolve pending.sessionId (pendingSelection pending)
    let some write := selection.write | throw (IO.userError "diagnostic project lost its writer")
    let source ← write.project.current write.slot.val
    let journal ← Synapses.Journal.open? source
    let items ← NativePublication.planUsing pending (some source) journal
    for item in items do
      let first ← journal.mapM fun journal => Synapses.Journal.lookup? journal "start" item.occurrence
      let last ← journal.mapM fun journal => Synapses.Journal.lookup? journal "finish" item.occurrence
      let evidence := match item.evidence with
        | .timed .. => "timed" | .stored .. => "stored" | .observed .. => "observed"
        | .awaiting => "awaiting" | .unavailable => "unavailable"
      let first := first.join
      let last := last.join
      let agreed := match first,last with
        | some first,some last => NativePublication.agrees item.occurrence item.tool first last
        | _,_ => false
      let events ← match journal with
        | some journal => Synapses.Journal.turnEntries journal ⟨pending.sessionId,pending.turnId⟩
        | none => pure #[]
      rows := rows.push (Json.mkObj [("queue",toJson entry.fileName),("tool",toJson item.tool.useId),
        ("evidence",toJson evidence),("start",toJson first.isSome),("finish",toJson last.isSome),
        ("agrees",toJson agreed),("source",toJson source.head),
        ("journal",toJson (journal.map (·.head))),
        ("events",toJson (events.map fun event => (event.payload.kind,event.payload.occurrence.useId,event.clock)))])
    unless (← DB.PageMap.pin source.directory).head == source.head do throw (IO.userError "audit changed original head")
    if let some journal := journal then
      unless (← DB.PageMap.pin journal.directory).head == journal.head do throw (IO.userError "audit changed private journal")
  let result := Json.mkObj [("rows",toJson rows),("originalAndJournalHeadsUnchanged",toJson true)]
  IO.FS.writeFile (root/"original-audit.json") (result.pretty++"\n")
  IO.println result.pretty
  if mode == ["retry"] then
    let mut attempts := #[]
    try
      for entry in ← (files.directory/"checkpoints").readDir do
        if !entry.fileName.endsWith ".json" then continue
        let started ← IO.monoMsNow
        let result ← Worker.exchange "seed-chat" "save" (Json.mkObj [
          ("session",toJson "seed-chat"),("path",toJson entry.path.toString)]) (started+30000)
        attempts := attempts.push (Json.mkObj [("queue",toJson entry.fileName),("result",toJson result),
          ("elapsedMs",toJson ((← IO.monoMsNow)-started)),("remains",toJson (← entry.path.pathExists))])
      IO.FS.writeFile (root/"save-retry.json") ((toJson attempts).pretty++"\n")
    finally
      Worker.shutdown
      let _ ← Publication.Client.control "shutdown"
      pure ()
def recoveryChecks (root : System.FilePath) : IO Unit := do
  let pending ← readBoundedJson (α := PendingTurn) (root/"retry-basis.json") (1024*1024)
  let selection ← ProjectAccess.resolve pending.sessionId (pendingSelection pending)
  let some write := selection.write | throw (IO.userError "replay lost its configured project")
  let before ← write.project.current write.slot.val
  try
    let replay ← Publication.Client.run pending write.directory true
    unless replay.source.complete && replay.source.head == before.head &&
        (← write.project.current write.slot.val).head == before.head do
      throw (IO.userError "same-boundary replay changed the original DB or lost its complete ACK")
    let fresh ← ProjectAccess.pin selection ((← IO.monoMsNow)+30000)
    let changed := {pending with projectInputs := some fresh.images}
    let changedBoundaryRejected ← try
        let _ ← Publication.Client.run changed write.directory true
        pure false
      catch error => pure (error.toString.contains "read boundary")
    unless changedBoundaryRejected && (← write.project.current write.slot.val).head == before.head do
      throw (IO.userError "replay accepted a changed boundary or mutated its original")
    let rejectedSource ← DB.PageMap.create (root/"neutral-negative.egg") (valueEncoding (.text "metadata negative"))
    let neutralRejected ← try
        let _ ← Persistence.appendPrepared rejectedSource.directory
          (fun graph => pure (Transaction.begin graph,()))
          (fun intern _ => do
            intern.writer.put "untracked-authoritative" (some ByteArray.empty)
            return {changed := true})
        pure false
      catch error => pure (error.toString.contains "empty graph delta")
    unless neutralRejected && (← DB.PageMap.pin rejectedSource.directory).head == rejectedSource.head do
      throw (IO.userError "neutral authoritative guard was weakened")
    let foreign ← DB.PageMap.create (root/"unpublished-owner-negative.egg") (valueEncoding (.text "membership negative"))
    let unpublishedRejected ← try
        let _ ← DB.PageMap.withWriter foreign fun writer => do
          let intern : Persistence.Store.Intern := ⟨writer,← IO.mkRef {}⟩
          NativePublication.promotedOwners intern #[{outcomeRelations := [.text "not a published Outcome"]}]
        pure false
      catch error => pure (error.toString.contains "unpublished Outcome")
    unless unpublishedRejected && (← DB.PageMap.pin foreign.directory).head == foreign.head do
      throw (IO.userError "publication metadata accepted an unpublished owner")
    IO.FS.writeFile (root/"recovery-checks.json") ((Json.mkObj [
      ("sameBoundaryReplayComplete",toJson true),("sourceHeadUnchangedOnReplay",toJson true),
      ("changedBoundaryRejected",toJson changedBoundaryRejected),("neutralAuthoritativeRejected",toJson neutralRejected),
      ("unpublishedOwnerRejected",toJson unpublishedRejected),("answeringModelCalls",toJson (0 : Nat))]).pretty++"\n")
  finally
    Worker.shutdown
    let _ ← Publication.Client.control "shutdown"
    pure ()

def serviceKeyChecks (root : System.FilePath) : IO Unit := do
  let some config ← Numerical.defaultConfig? | throw (IO.userError "installed numerical configuration required")
  let input ← IO.mkRef config
  let results ← IO.mkRef (#[] : Array String)
  let mut micros := #[]
  for _ in [:16] do
    let config ← input.get
    let started ← IO.monoNanosNow
    results.modify (·.push config.key)
    micros := micros.push (((← IO.monoNanosNow)-started)/1000)
  let hashes ← results.get
  unless hashes.size == 16 && hashes.all (· == hashes[0]!) do throw (IO.userError "stable numerical configuration changed its key")
  let report := Json.mkObj [("microseconds",toJson micros),("sameKey",toJson true),
    ("model",toJson config.model),("models",toJson config.models.toString),("python",toJson config.python.toString),
    ("answeringModelCalls",toJson (0 : Nat))]
  IO.FS.writeFile (root/"service-key-report.json") (report.pretty++"\n")
  IO.println report.pretty

end Eggshell.Research.FrontInputAudit
