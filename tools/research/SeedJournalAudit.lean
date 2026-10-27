import Eggshell.SynapseJournal
open Lean Eggshell Eggshell.Synapses

/-- Explain native starts without finishes and retained pre-read index heads.
Read-only: no relation, event, usage label or model call is manufactured. -/
def main (args : List String) : IO Unit := do
  let [acquisition,report] := args | throw (IO.userError "ACQUISITION NEW-REPORT")
  let root := System.FilePath.mk acquisition
  unless (← IO.getEnv "EGGSHELL_DATA_ROOT") == some (root / "data").toString &&
      !(← (System.FilePath.mk report).pathExists) do throw (IO.userError "actual private root and new report required")
  let thread ← IO.ofExcept (Json.parse (← IO.FS.readFile (root / "thread.json")))
  let session ← IO.ofExcept ((thread.getObjValD "thread").getObjValAs? String "id")
  let started ← IO.ofExcept (Json.parse (← IO.FS.readFile (root / "turn-start.json")))
  let turn ← IO.ofExcept ((started.getObjValD "turn").getObjValAs? String "id")
  let source ← DB.PageMap.pin (root / "work.egg")
  let some journal ← Journal.open? source | throw (IO.userError "missing actual journal")
  let entries ← Journal.turnEntries journal ⟨session,turn⟩
  let finishes := entries.filterMap fun entry => match entry.payload with | .finish occurrence .. => some occurrence | _ => none
  let mut rows := #[]
  let mut unmatched := #[]
  for entry in entries do
    let .start occurrence work _ known := entry.payload | continue
    let usable ← Journal.indexAt? source known
    let mut indexSource : Option DB.PageMap.Head := none
    let mut retained := false
    if let some saved := known.indexed then
      if let some current ← DB.PageMap.open? (← Index.directory source saved.storage .shared) then
        if current.head.identity == saved.head.identity && current.head.authority == saved.head.authority &&
            saved.head.bytes ≤ current.head.bytes then
          retained := true
          if let some manifest ← Index.manifest? {current with head := saved.head} then indexSource := some manifest.source
    let matched := finishes.contains occurrence
    rows := rows.push (Json.mkObj [("useId",toJson occurrence.useId),("finished",toJson matched),
      ("uncertain",toJson known.uncertain),("sourceRevision",toJson known.source.revision),
      ("indexCaptured",toJson known.indexed.isSome),("indexHeadRetained",toJson retained),
      ("indexSourceRevision",toJson (indexSource.map (·.revision))),("indexUsable",toJson usable.isSome)])
    if !matched then
      unmatched := unmatched.push (Json.mkObj [("useId",toJson occurrence.useId),("work",toJson work),
        ("matchingRpc",toJson (#[] : Array Json))])
  let input ← IO.FS.Handle.mk (root / "rpc/exchange.jsonl") .read
  repeat
    let line ← input.getLine
    if line.isEmpty then break
    let row ← IO.ofExcept (Json.parse line)
    let message := row.getObjValD "message"
    let params := message.getObjValD "params"
    let item := params.getObjValD "item"
    let hook := params.getObjValD "run"
    let itemId := (item.getObjValAs? String "id").toOption.getD ""
    let hookId := (hook.getObjValAs? String "id").toOption.getD ""
    unmatched := unmatched.map fun entry => Id.run do
      let useId := (entry.getObjValAs? String "useId").toOption.getD ""
      if itemId != useId && !hookId.endsWith (":" ++ useId) then return entry
      let old := (entry.getObjValAs? (Array Json) "matchingRpc").toOption.getD #[]
      let summary := Json.mkObj [("method",message.getObjValD "method"),("itemId",toJson itemId),
        ("itemType",item.getObjValD "type"),("itemStatus",item.getObjValD "status"),
        ("hookId",toJson hookId),("hookEvent",hook.getObjValD "eventName"),("hookStatus",hook.getObjValD "status")]
      return entry.setObjVal! "matchingRpc" (toJson (old.push summary))
  let after ← DB.PageMap.pin (root / "work.egg")
  unless source.head == after.head do throw (IO.userError "source changed during journal diagnosis")
  let result := Json.mkObj [("sourceUnchanged",toJson true),("nativeStarts",toJson rows.size),
    ("nativeFinishes",toJson finishes.size),("starts",toJson rows),("unmatched",toJson unmatched),
    ("answeringModelCalls",toJson (0 : Nat)),("indexOrJournalWrites",toJson (0 : Nat))]
  IO.FS.writeFile (.mk report) result.compress
  IO.println (Json.mkObj [("nativeStarts",toJson rows.size),("nativeFinishes",toJson finishes.size),
    ("unmatched",toJson unmatched),
    ("usableCapturedIndexes",toJson (rows.filter (fun row => row.getObjValD "indexUsable" == toJson true)).size)]).compress
