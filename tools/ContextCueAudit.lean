import Eggshell.Handoff

open Lean Eggshell Eggshell.Plugin

/-- Read-only diagnostics: expose existing window orders and the original
renderer at several allowances. This cannot publish graph equivalences. -/
def main (arguments : List String) : IO UInt32 := do
  let [database, request, wanted] := arguments |
    throw (IO.userError "expected database, fixed question and comma-separated local owner ids")
  let question ← IO.FS.readFile (.mk request)
  let owners ← IO.ofExcept ((wanted.splitOn ",").mapM fun text =>
    match text.toNat? with
    | some value => Except.ok value
    | none => Except.error "invalid owner id")
  let snapshot ← DB.PageMap.pin (.mk database)
  let documents ← Persistence.Store.searchDocuments snapshot
  let reader ← Persistence.Store.NodeReader.new snapshot
  let readWork := fun (document : Persistence.Store.SearchDocument) => do
    let value ← reader.read document.work
    let some text := Matcher.atomText? value | throw (IO.userError "nontext Work")
    pure text
  let works ← documents.mapM readWork
  let focus := evidenceFocusQuestion question works
  let binary := (← IO.appPath).withFileName "eggshell"
  let some (_, positions) ← focusIndexedEvidence [binary.toString, "search-provider"]
      focus documents readWork (fun document index =>
        Persistence.Store.readSearchWindow snapshot document index.val) |
    throw (IO.userError "cached source focus unavailable")
  for document in documents do
    if !owners.contains document.owner then continue
    let owner ← reader.outcome (← reader.locateOutcome document.owner)
    let some source := Matcher.atomText? owner.outcome | throw (IO.userError "nontext Outcome")
    let work ← readWork document
    let semantic := (positions.find? (·.1 == document.owner)).map Prod.snd |>.getD []
    let windows := evidenceSearchWindows owner
    let focused := focusedEvidenceWindows focus windows semantic
    let decoded := (decodedToolText? source).map DecodedLayout.make
    let records := contextRecordSpans source decoded
    let heads := contextStructureHeads source decoded
    let structural := completeStructureContexts records
      (structureContextRanges source (work.length + 1) focused heads)
    let required := prepareCueViews records heads decoded
      (prerequisiteCueRanges source (work.length + 1) focused structural)
    let render := prepareContextualOwnerPart [] focused owner "" []
      {keys := [], text := "", members := [], visibleKeys := []}
    IO.println (Json.mkObj [
      ("localOwner", toJson document.owner), ("owner", toJson (relationKey owner.relation)),
      ("focusQuestion", toJson focus),
      ("source", toJson source), ("work", toJson work),
      ("semantic", toJson semantic), ("lexical", toJson (SearchRank.lexical focus windows)),
      ("focused", toJson focused),
      ("required", toJson (required.map fun view => (view.range.start, view.range.stop))),
      ("deliveries", toJson ([2048, 4096, 8192, 16384, 32768].map fun budget =>
        (budget, (render budget).map (·.text))))]).compress
  pure 0
