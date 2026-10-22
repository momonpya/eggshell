import Eggshell.Handoff
open Lean Eggshell Eggshell.Plugin

private def nativeIdentities (edge : OutcomeEdge) : List Json :=
  edge.observations.filterMap fun observation => do
    let .apply .occurrence references := observation | none
    match references.toList with
    | [(.semantic,result),(.semantic,work),(.exact,session),(.exact,turn),(.exact,useId)] => do
        if result != edge.outcome || work != edge.work then none else do
          let session ← Matcher.atomText? session
          let turn ← Matcher.atomText? turn
          let useId ← Matcher.atomText? useId
          pure (Json.mkObj [("session",toJson session),("turn",toJson turn),("useId",toJson useId)])
    | _ => none

/-- Read-only input for advisory derivation. This exports no new graph facts,
never runs a tool, and pins one immutable publication for all records. -/
def main (args : List String) : IO Unit := do
  let [path] := args | throw (IO.userError "SynapseExport DB")
  let snapshot ← DB.PageMap.pin (.mk path)
  let reader ← Persistence.Store.NodeReader.new snapshot
  let documents ← Persistence.Store.searchDocuments snapshot
  let all ← reader.topology
  IO.println (Json.mkObj [("kind",toJson "publication"),("head",toJson snapshot.head),
    ("all",toJson (all.map fun edge => Json.mkObj [
      ("parent",toJson (relationKey edge.parent)),
      ("children",toJson (edge.children.map relationKey))]))]).compress
  for document in documents do
    let edge ← reader.outcome (← reader.locateOutcome document.owner)
    let records ← reader.sources document.owner
    IO.println (Json.mkObj [
      ("kind",toJson "outcome"),("id",toJson document.owner),
      ("owner",toJson (relationKey edge.relation)),
      ("workKey",toJson (relationKey edge.work)),
      ("work",toJson (Matcher.atomText? edge.work)),
      ("source",toJson (Matcher.atomText? edge.outcome)),
      ("native",toJson (Matcher.nativeOutcome edge)),
      ("occurrences",toJson (nativeIdentities edge)),
      ("records",toJson records)]).compress
