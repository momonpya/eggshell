import Eggshell.PluginHooks

open Lean Eggshell

namespace Eggshell.Research.SessionStateProbe

private def check (value : Bool) (message : String) : IO Unit :=
  unless value do throw (IO.userError message)

private def timed (action : IO α) : IO (α × Nat) := do
  let started ← IO.monoMsNow
  let value ← action
  return (value,(← IO.monoMsNow)-started)

private def source : Synapses.Subject := .file {
  relative := "fixture/source", fingerprint := String.ofList (List.replicate 64 'a'), bytes := 1000000 }

/-- Eight observed lines followed by three absent lines. Gaps must never
become confirmed merely because the surrounding observations were sent. -/
private def line (i : Nat) : Nat := i + (i/8)*3 + 1

private def projection (unique repeated bindings : Nat) : Synapses.DeliveryLedger.Projection := Id.run do
  let rows := (Array.range unique).map fun i =>
    ({database := "fixture-project",source := ⟨source,line i,line i⟩} : Synapses.DeliveryLedger.Row)
  let repeats := if unique == 0 then #[] else (Array.range repeated).map fun i =>
    ({database := "fixture-project",source := ⟨source,line (i%unique),line (i%unique)⟩} : Synapses.DeliveryLedger.Row)
  return {rows := rows ++ repeats, complete := true, bindings := (Array.range bindings).map fun i =>
    { database := "fixture-project",owner := "owner-" ++ toString (i%9),work := "work-" ++ toString (i%9),
      first := i*10,limit := i*10+5 }}

private def verify (reference : Option Synapses.DeliveryLedger.Reference) (unique : Nat) : IO Nat := do
  if unique == 0 then
    check reference.isNone "empty projection invented a confirmed ledger"
    return 0
  let some reference := reference | throw (IO.userError "missing confirmed ledger")
  let rows ← Synapses.DeliveryLedger.lookup reference "fixture-project"
  check (rows.all (·.subject == source)) "confirmed ranges crossed subject identity"
  let index := RangeReach.prepare (rows.map fun row => ⟨row.first,row.last+1,()⟩)
  let expected : Std.HashSet Nat := (Array.range unique).foldl (fun acc i => acc.insert (line i)) {}
  for point in [:line (unique-1)+4] do
    check ((index.lookup? point).isSome == expected.contains point)
      s!"confirmed range coverage differs at {point}"
  return rows.size

private def runCase (name : String) (unique repeated bindings chars : Nat) : IO Json := do
  let session := "session-state-" ++ name
  let files ← Plugin.sessionFiles session
  check (!(← files.directory.pathExists)) "probe refuses to reuse an old session"
  let body := String.ofList (List.replicate chars 'x')
  let metadata := projection unique repeated bindings
  let now ← IO.monoMsNow
  let offer : Plugin.DeliveryOffer := {
    id := "offered-body",stamp := ⟨"turn",7,now+120000⟩,
    graphs := (List.range 9).map (fun i => "graph-" ++ toString i),
    text := body,reason := "synthetic session metadata probe",projection := metadata }
  let state : Plugin.ThreadState := {profile := "work",epoch := 7,offers := [offer]}
  let pending : Plugin.PendingTurn := {
    sessionId := session,turnId := "turn",cwd := "/fixture",prompt := "metadata probe",
    profile := "work",semanticMatcher := none,read := [],write := none,
    handoffChars := 500000,projection := .none }
  let (serialized,serializeMs) ← timed do
    let _ ← IO.monoMsNow
    pure ((toJson state).compress.toUTF8)
  let (_,stateWriteMs) ← timed (Plugin.writeJson files.state state)
  Plugin.writeJson files.pending pending
  let (read,readMs) ← timed (Plugin.readState? files)
  check (read.any (fun state => state.enabled && state.offers.length == 1)) "session state read failed"
  let (_,ledgerOnlyMs) ← timed do
    let reference ← Synapses.DeliveryLedger.confirm (session ++ "-ledger-only") 7 none metadata
    let _ ← verify reference unique
  let done ← IO.mkRef false
  let started ← IO.monoMsNow
  let task ← IO.asTask (do
    try timed (Plugin.acknowledge session offer.id) finally done.set true) .dedicated
  -- Let the real acknowledgement enter its critical section before probing
  -- the background worker's ordinary 100 ms session admission path.
  IO.sleep 5
  let mut waits : Array Nat := #[]
  let mut errors : Array String := #[]
  while !(← done.get) do
    let (result,elapsed) ← timed do
      try
        let _ ← Plugin.withSession session fun files => Plugin.readState? files
        return none
      catch error => return some error.toString
    waits := waits.push elapsed
    if let some message := result then errors := errors.push message
    IO.sleep 5
  let (accepted,acknowledgeMs) ← IO.ofExcept task.get
  check accepted "synthetic offered body was not acknowledged"
  let overlapMs := (← IO.monoMsNow)-started
  let some confirmed ← Plugin.readState? files | throw (IO.userError "session disappeared after ACK")
  check (confirmed.lastHandoff == body && confirmed.offers.isEmpty && confirmed.epoch == 7)
    "acknowledgement changed the text, epoch, or offer lifecycle"
  let confirmedRanges ← verify confirmed.confirmedDelivery unique
  let result := Json.mkObj [
    ("name",toJson name),("inputRows",toJson metadata.rows.size),("uniqueRows",toJson unique),
    ("inputBindings",toJson bindings),("bodyCharacters",toJson chars),
    ("stateBytes",toJson serialized.size),("serializeMs",toJson serializeMs),
    ("stateWriteMs",toJson stateWriteMs),("stateReadMs",toJson readMs),
    ("standaloneConfirmAndVerifyMs",toJson ledgerOnlyMs),("acknowledgeMs",toJson acknowledgeMs),
    ("overlapWallMs",toJson overlapMs),
    ("backgroundReadWaitMs",toJson waits),("backgroundReadErrors",toJson errors),
    ("confirmedRanges",toJson confirmedRanges),("exactSparseCoverage",toJson true),
    ("unchangedAcknowledgedBody",toJson true)]
  IO.println result.compress
  return result

def run (output : String) : IO Unit := do
  let mut results := #[]
  -- The last shape takes counts from the retained real hook packet. Binding
  -- count 623 is an explicit synthetic assumption, not a measured ACK count.
  for repetition in [:3] do
    for (name,unique,repeated,bindings,chars) in
        #[ ("empty",0,0,0,0), ("small",64,0,9,4096), ("real-sized",6231,5309,623,500000) ] do
      results := results.push (← runCase (name ++ "-" ++ toString repetition) unique repeated bindings chars)
      Plugin.writeJson (.mk output) (Json.mkObj [
        ("kind",toJson "synthetic-real-ack-metadata"),("answeringModelCalls",toJson (0:Nat)),
        ("cases",toJson results)])

end Eggshell.Research.SessionStateProbe
