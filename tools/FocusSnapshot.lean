import Eggshell.Handoff

open Lean Eggshell Plugin

/-- Run unchanged complete focus over one pinned publication. This helper is
compiled separately against the reference and the isolated candidate. -/
def main (arguments : List String) : IO UInt32 := do
  let [database, question] := arguments |
    throw (IO.userError "expected database and fixed question")
  let snapshot ← DB.PageMap.pin (.mk database)
  let documents ← Persistence.Store.searchDocuments snapshot
  let reader ← Persistence.Store.NodeReader.new snapshot
  let expectedReads ← IO.mkRef 0
  let actualReads ← IO.mkRef 0
  let binary := (← IO.appPath).withFileName "eggshell"
  let some (order, positions) ← focusIndexedEvidence
      [binary.toString, "search-provider"] question documents
      (fun document => do
        let work ← reader.read document.work
        let some text := Matcher.atomText? work | throw (IO.userError "nontext Work")
        expectedReads.modify (· + ((List.range document.windows.length).countP
          (fun index => index * 384 < text.length + 1)))
        pure text)
      (fun document index => do
        actualReads.modify (· + 1)
        Persistence.Store.readSearchWindow snapshot document index.val) |
    throw (IO.userError "complete cached focus was unavailable")
  unless (← actualReads.get) == (← expectedReads.get) do
    throw (IO.userError "cached focus performed a foreground source repair")
  IO.println (Json.mkObj [("order", toJson order), ("positions", toJson positions),
    ("documents", toJson documents.length), ("prefixReads", toJson (← actualReads.get)),
    ("windowReferences", toJson (documents.foldl (fun n d => n + d.windows.length) 0))]).compress
  pure 0
