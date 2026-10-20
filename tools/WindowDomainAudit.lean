import Eggshell.Install

open Lean Eggshell Eggshell.Plugin

/-- Export the original bounded windows with their owners and positions.
This is a read-only diagnostic, not a second retrieval implementation. -/
def main (arguments : List String) : IO UInt32 := do
  try
    let [database] := arguments | throw (IO.userError "window_domain_audit DB")
    let snapshot ← DB.PageMap.pin (.mk database)
    let documents ← Persistence.Store.searchDocuments snapshot
    let reader ← Persistence.Store.NodeReader.new snapshot
    for document in documents do
      let value ← reader.read document.work
      let some work := Matcher.atomText? value | throw (IO.userError "nontext Work")
      let owner ← reader.outcome (← reader.locateOutcome document.owner)
      for index in [:document.windows.length] do
        let original ← Persistence.Store.readSearchWindow snapshot document index
        let focus := (original.drop (work.length + 1 - index * 384)).copy
        IO.println (Json.mkObj [
          ("owner", toJson document.owner), ("work", toJson document.work),
          ("relation", toJson (relationKey owner.relation)), ("position", toJson index),
          ("discovery", toJson (Persistence.Store.windowKey original)),
          ("focus", toJson (Persistence.Store.windowKey focus))]).compress
    return 0
  catch error =>
    IO.eprintln s!"window domain audit: {error}"
    return 1
