import Eggshell.Install

open Lean Eggshell Eggshell.Plugin

/-- Exercise the real worker with a published owner and inspect both source
views. The index role consumes its ordinary JSON payload on stdin. -/
def main (arguments : List String) : IO UInt32 := do
  match arguments with
  | ["index"] => Worker.run "index"
  | [operation, database, provider] =>
      unless operation == "prepare" || operation == "inspect" do
        throw (IO.userError "index completion audit: unknown operation")
      let snapshot ← DB.PageMap.pin (.mk database)
      let command := [provider, "search-provider"]
      let target ← registerIndexTarget snapshot command
      if operation == "prepare" then
        let documents ← Persistence.Store.searchDocuments snapshot
        let some document := documents.getLast? |
          throw (IO.userError "index completion audit needs a published candidate")
        let located ← Persistence.Store.locateOutcome snapshot document.owner
        let owner ← Persistence.Store.readLocatedOutcome snapshot located
        let graph ← Persistence.Store.materialize snapshot
        let promotion ← prepareCommitted graph {outcomeRelations := [owner.relation]}
        queueIndex database command promotion
      let settings ← Warm.options snapshot command target.storage
      let inspected ← Warm.inspect snapshot settings
      let directory ← target.indexes snapshot
      let entries ← if ← directory.pathExists then directory.readDir else pure #[]
      let paths := entries.toList.filter (·.fileName.endsWith ".json") |>.map (·.path.toString)
      IO.println (Json.mkObj [("target", toJson target), ("paths", toJson paths),
        ("coverage", toJson inspected.coverage),
        ("needed", toJson (inspected.needed.map (·.key)))]).compress
      return 0
  | _ => throw (IO.userError "index_completion_audit index | prepare/inspect DB PROVIDER")
