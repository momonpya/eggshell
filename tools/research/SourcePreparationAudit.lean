import Eggshell.Warm
open Lean Eggshell

/-- Execute the ordinary query-independent preparation stages separately.
No vector encoder, answering model or selector is started. -/
def main (args : List String) : IO Unit := do
  let [database,storageName,output] := args |
    throw (IO.userError "DATABASE user|database NEW-REPORT")
  let storage ← match storageName with
    | "user" => pure DB.Sidecar.Storage.user
    | "database" => pure DB.Sidecar.Storage.database
    | _ => throw (IO.userError "explicit preparation storage required")
  let directory := System.FilePath.mk output
  unless directory.isAbsolute && !(← directory.pathExists) do
    throw (IO.userError "preserve the previous preparation report")
  let source ← DB.PageMap.pin (.mk database)
  IO.FS.createDirAll directory
  let mut phases := #[]
  let steps : Array (String × IO Json) := #[
    ("synaptic-journal",do
      let result ← Synapses.Journal.refresh source storage ((← IO.monoMsNow)+60000)
      pure (toJson result)),
    ("canonical-source",do pure (toJson (← Synapses.CanonicalSource.Cache.refresh source storage))),
    ("window-owners",do pure (toJson (← WindowOwners.refresh source storage))),
    ("lexical",do pure (toJson (← RetrievalResearch.Index.warm source storage)))]
  let mut complete := true
  let mut allCallsReturned := true
  for (name,action) in steps do
    let started ← IO.monoMsNow
    let result : Except String Json ← try pure (.ok (← action)) catch error => pure (.error error.toString)
    let row := Json.mkObj [("phase",toJson name),("elapsedMs",toJson ((← IO.monoMsNow)-started)),
      ("result",match result with | .ok value => value | .error _ => .null),
      ("error",match result with | .ok _ => .null | .error error => toJson error)]
    IO.FS.writeFile (directory / (name ++ ".json")) row.compress
    phases := phases.push row
    IO.println row.compress
    (← IO.getStdout).flush
    match result with
    | .error _ => complete := false; allCallsReturned := false; break
    | .ok value =>
      if (value.getObjValAs? Bool "complete").toOption == some false then complete := false
  let after ← DB.PageMap.pin (.mk database)
  let synapticDebt ← Synapses.Journal.required after storage
  IO.FS.writeFile (directory / "result.json") (Json.mkObj [
    ("complete",toJson complete),("allCallsReturned",toJson allCallsReturned),
    ("sourceBefore",toJson source.head),("sourceAfter",toJson after.head),
    ("sourceUnchanged",toJson (source.head == after.head)),("phases",toJson phases),
    ("synapticDebtRemaining",toJson synapticDebt),
    ("answeringModelCalls",toJson (0 : Nat)),("encoderStarted",toJson false)]).compress
