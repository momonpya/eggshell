import Eggshell.Warm
open Lean Eggshell DB Persistence.Store Synapses

private def buckets (source : PageMap.Snapshot) : IO Json := do
  let mut checked := 0
  for tag in #["hash","owner"] do
    checked ← source.foldRange ⟨tag ++ ":",tag ++ ";"⟩ (fun count row => do
      try
        let _ ← getIds source.get row.1
        pure (count+1)
      catch error => throw (IO.userError s!"{source.head.identity}@{source.head.revision}:{row.1}: {error}")) checked
  for revision in [1:source.head.revision+1] do
    try
      let _ ← readPublication source revision
      pure ()
    catch error => throw (IO.userError s!"{source.head.identity}:publication:{revision}: {error}")
  return Json.mkObj [("buckets",toJson checked),("publications",toJson source.head.revision)]

/-- Examine field boundaries only. A missing field is reported, never
defaulted or accepted as a current publication. -/
private def publicationLayout (source : PageMap.Snapshot) (revision : Nat) : IO Json := do
  let bytes ← readChunks source source.get "change" revision
  let decoded := do
    let (parent,rest) ← PageMap.headCodec.decode bytes.toList
    let (added,rest) ← (Wire.list Wire.natural).decode rest
    let (removed,rest) ← (Wire.list Wire.natural).decode rest
    let (unions,rest) ← Wire.natural.decode rest
    pure (Json.mkObj [("parentRevision",toJson parent.revision),
      ("addedCount",toJson added.length),("removedCount",toJson removed.length),
      ("unionsFlag",toJson unions),("remainingBytesBeforeAffected",toJson rest.length),
      ("affectedDecodes",toJson ((Wire.list Wire.natural).decode rest).isOk),
      ("fullCurrentDecode",toJson (publicationCodec.decode bytes.toList).isOk)])
  return Json.mkObj [("revision",toJson revision),("bytes",toJson bytes.size),
    ("layout",match decoded with | .ok value => value | .error error => toJson error)]

/-- Inspect saved heads and list-encoded source records without publishing,
preparing indices, re-running tools, or constructing feedback labels. -/
def main (args : List String) : IO Unit := do
  let (database,output,layoutOnly) ← match args with
    | [database,output] => pure (database,output,false)
    | ["publication",database,output] => pure (database,output,true)
    | _ => throw (IO.userError "[publication] DATABASE NEW-REPORT")
  let directory := System.FilePath.mk output
  unless directory.isAbsolute && !(← directory.pathExists) do throw (IO.userError "preserve prior diagnosis")
  let source ← PageMap.pin (.mk database)
  IO.FS.createDirAll directory
  if layoutOnly then
    let mut rows := #[]
    for revision in [1:source.head.revision+1] do rows := rows.push (← publicationLayout source revision)
    let after ← PageMap.pin (.mk database)
    IO.FS.writeFile (directory / "result.json") (Json.mkObj [("source",toJson source.head),
      ("sourceUnchanged",toJson (source.head == after.head)),("publications",toJson rows),
      ("legacyFieldsAccepted",toJson false),("answeringModelCalls",toJson (0 : Nat))]).compress
    IO.println (toJson rows).compress
    return
  let results ← IO.mkRef (#[] : Array Json)
  let stage ← IO.mkRef "current-source"
  let record := fun (name : String) (action : IO Json) => do
    stage.set name
    let value ← action
    results.modify (·.push (Json.mkObj [("stage",toJson name),("result",value)]))
    IO.FS.writeFile (directory / "progress.json") (toJson (← results.get)).compress
  let mut failure : Option String := none
  try
    record "current-source" (buckets source)
    let some journal ← Journal.open? source | throw (IO.userError "missing real event journal")
    let count ← getNat journal.get "count"
    let seen ← IO.mkRef (#[] : Array PageMap.Head)
    for ordinal in [:count] do
      stage.set s!"event:{ordinal}"
      let value ← Journal.entry journal ordinal
      let known := match value.payload with
        | .start _ _ _ known => some known
        | .answer _ _ _ known => some known
        | _ => none
      if let some known := known then
        if !(← seen.get).contains known.source then
          seen.modify (·.push known.source)
          record s!"event:{ordinal}:source-head" do
            let some saved ← Journal.originalAt? source known.source |
              return Json.mkObj [("available",toJson false)]
            pure (← buckets saved)
        record s!"event:{ordinal}:index-head" do
          pure (toJson (← Journal.indexAt? source known).isSome)
        record s!"event:{ordinal}:presentation" do
          let shown ← Journal.presentation source known
          pure (toJson shown.ranges.size)
      if let .finish occurrence name input response archive := value.payload then
        record s!"event:{ordinal}:original" do
          let tool : Plugin.ToolEvent := {name,useId := occurrence.useId,input,response}
          let owner := (Plugin.compileOperationOutcomes (.text occurrence.session) (.text occurrence.turn) tool).2
          let current ← findNode? source owner
          let mut archived := false
          if current.isNone then
            if let some path := archive then
              if let some other ← PageMap.open? (.mk path) then archived := (← findNode? other owner).isSome
          pure (Json.mkObj [("current",toJson current.isSome),("archived",toJson archived)])
    stage.set "finished"
  catch error => failure := some error.toString
  let after ← PageMap.pin (.mk database)
  let result := Json.mkObj [("source",toJson source.head),("sourceUnchanged",toJson (source.head == after.head)),
    ("stage",toJson (← stage.get)),("error",toJson failure),("checks",toJson (← results.get)),
    ("answeringModelCalls",toJson (0 : Nat)),("indexWrites",toJson (0 : Nat))]
  IO.FS.writeFile (directory / "result.json") result.compress
  IO.println (Json.mkObj [("stage",result.getObjValD "stage"),("error",toJson failure),
    ("checks",toJson (← results.get).size)]).compress
