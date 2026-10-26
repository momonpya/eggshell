import Eggshell.Warm

open Lean Eggshell Eggshell.Synapses

private def emit (output : System.FilePath) (value : Json) : IO Unit := do
  let text := value.compress ++ "\n"
  IO.FS.withFile output .append fun handle => handle.putStr text
  (← IO.getStdout).putStr text
  (← IO.getStdout).flush

/-- Profile the stopped real-seed replay without another full warm. Only the
already published source and private journal are read; no model is invoked. -/
def main (args : List String) : IO UInt32 := do
  try
    let [database,destination] := args | throw (IO.userError "SynapticReplayProfile DB UNUSED-JSONL")
    let output := System.FilePath.mk destination
    unless output.isAbsolute && !(← output.pathExists) do throw (IO.userError "keep prior profile")
    let source ← DB.PageMap.pin (.mk database)
    emit output (Json.mkObj [("phase",toJson "start"),("pid",toJson (← IO.Process.getPID).toNat),
      ("source",toJson source.head),("answeringModelCalls",toJson (0 : Nat))])
    let started ← IO.monoMsNow
    let prepared ← Build.refresh source .database
    emit output (Json.mkObj [("phase",toJson "shared-index"),("elapsedMs",toJson ((← IO.monoMsNow)-started)),
      ("result",toJson prepared)])
    let some journal ← Journal.open? source | throw (IO.userError "no private source journal")
    let turns ← journal.foldRange ⟨"turn:","turn;"⟩ (fun turns row => do
      let some bytes := row.2 | return turns
      let turn ← Index.decode (α := Journal.Turn) bytes
      return turns.push turn) #[]
    for turn in turns do
      let values ← Journal.turnEntries journal turn
      emit output (Json.mkObj [("phase",toJson "replay-start"),("turn",toJson turn),
        ("events",toJson values.size),
        ("acknowledgedOwners",toJson (values.filterMap fun entry => match entry.payload with
          | .start _ _ _ known => some (Journal.ownerKeys known.acknowledged).size
          | _ => none))])
      let started ← IO.monoMsNow
      try
        let replayed ← Journal.replay source values (started+60000)
        emit output (Json.mkObj [("phase",toJson "replay-end"),("elapsedMs",toJson ((← IO.monoMsNow)-started)),
          ("consumptionFacts",toJson replayed.consumed.size),("usageFacts",toJson replayed.usage.size),
          ("consumedDigest",toJson (Index.contentKey replayed.consumed)),
          ("usageDigest",toJson (Index.contentKey replayed.usage)),
          ("originsDigest",toJson (Index.contentKey replayed.origins)),
          ("origins",toJson replayed.origins.size),("pending",toJson replayed.pending),
          ("unknown",toJson replayed.unknown)])
      catch error =>
        emit output (Json.mkObj [("phase",toJson "replay-error"),("elapsedMs",toJson ((← IO.monoMsNow)-started)),
          ("error",toJson error.toString)])
        throw error
    return 0
  catch error => IO.eprintln error.toString; return 1
