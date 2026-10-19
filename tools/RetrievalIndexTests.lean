import Eggshell.Install
import tools.RetrievalIndex

open Lean Eggshell RetrievalResearch
open Persistence Store

private def require (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)

private def owner (work body : String) : OutcomeEdge :=
  OutcomeEdge.make (.text work) (.text body) [] (by simp) (by simp)

private def append (source : Snapshot) (owners : List OutcomeEdge) : IO (List Nat) := do
  let (ids, _, _) ← DB.PageMap.withWriter source fun writer => do
    let intern : Intern := ⟨writer, ← IO.mkRef {}⟩
    let ids ← owners.mapM (fun edge => intern.root edge.relation)
    writeChange writer {added := ids, removed := [], unionsChanged := false}
    pure ids
  pure ids

private def compareRanks (source : Snapshot) : IO Nat := do
  let some indexed ← Index.open? source | throw (IO.userError "new index is not ready")
  let documents ← searchDocuments source
  let reader ← NodeReader.new source
  let originals ← documents.mapM fun document => do
    pure (searchText (← reader.outcome (← reader.locateOutcome document.owner)))
  let mut compared := 0
  for query in ["保存", "한국어 검색", "Поиск", "résumé", "resume", "ＡＢＣ１２３", "abc123",
      "ｶﾞｲﾄﾞ", "ガイド", "木", "Serializer.load_payload", "/src/main.py", "newfound", "missing-value"] do
    let mut postings : Std.HashMap String (Std.HashSet Nat) := {}
    let mut frequencies : Std.HashMap String Nat := {}
    for unit in tokens query do
      let (ids, count) ← indexed.posting unit
      postings := postings.insert unit (Std.HashSet.ofList ids)
      frequencies := frequencies.insert unit count
    for anchors in [false, true] do
      let actual := rankRows query documents
        (fun document unit => (postings.getD unit {}).contains document.owner)
        (frequencies.getD · 0) anchors
      let parsed := terms query
      let wanted := if anchors then {
        primary := parsed.primary.filter SearchRank.anchor
        auxiliary := parsed.auxiliary.filter SearchRank.anchor } else parsed
      let expected := rank wanted (originals.map terms)
      require (actual == expected) s!"indexed/reference full order differs: {query}"
      compared := compared + 1
  pure compared

private def scenario (root : System.FilePath) : IO Unit := do
  let root ← IO.FS.realPath root
  let database := root / "source.egg"
  let authority := (Persistence.valueToJson (.text "lexical-index-fixture")).compress
  let initial ← DB.PageMap.create database authority
  let phrases := ["保存した本文 木", "한국어 검색 기록", "Поиск сохранённых записей", "café résumé",
    "ｶﾞｲﾄﾞ ＡＢＣ１２３", "Serializer.load_payload /src/main.py"]
  let examples := (List.range 40).map fun index =>
    owner s!"original source {index}" s!"{phrases[index % phrases.length]!} ORIGINAL_LEXICAL_BODY_{index}"
  let some firstOwner := examples.head? | throw (IO.userError "empty source fixture")
  let ids ← append initial examples
  let source ← DB.PageMap.pin database
  let head ← IO.FS.readBinFile (database / "head")
  require ((← Index.open? source).isNone) "A missing derived index was ready"
  let first ← Index.warm source .user
  require (first.added == 40 && first.hydrated == 40 && first.batches == 2)
    "Initial warm did not cover the complete original corpus in bounded batches"
  let comparisons ← compareRanks source
  let some before ← Index.open? source | throw (IO.userError "missing ready index")
  let repeated ← Index.warm source .user
  require (repeated.added == 0 && repeated.hydrated == 0 && repeated.batches == 0)
    "An unchanged warm read source bodies or wrote another batch"
  require ((← DB.PageMap.pin before.index.directory).head == before.index.head)
    "An unchanged warm republished its index"
  require ((← IO.FS.readBinFile (database / "head")) == head) "Lexical warm wrote the source DB"

  let _ ← DB.PageMap.withWriter source fun writer => do
    writer.put "memo:lexical-test" (some "derived-only".toUTF8)
    writeChange writer {added := [], removed := [], unionsChanged := false}
  let memo ← DB.PageMap.pin database
  require (memo.head.revision > source.head.revision && (← Index.open? memo).isSome)
    "Derived query memo changes invalidated an unchanged source corpus"
  let addedIds ← append memo [owner "new source" "newfound 한국어 木"]
  let extended ← DB.PageMap.pin database
  require ((← Index.open? extended).isNone) "A stale index certified a new source corpus"
  let extendedResult ← Index.warm extended .user
  require (extendedResult.added == 1 && extendedResult.hydrated == 1 && extendedResult.removed == 0)
    "Appending one source rehydrated unrelated owners"
  let comparisons := comparisons + (← compareRanks extended)
  let _ ← before.posting "P保存"

  let _ ← DB.PageMap.withWriter extended fun writer => do
    removeRoot writer ids[0]!
    writeChange writer {added := [], removed := [ids[0]!], unionsChanged := false}
  let deleted ← DB.PageMap.pin database
  let deletedResult ← Index.warm deleted .user
  require (deletedResult.removed == 1 && deletedResult.added == 0 && deletedResult.hydrated == 0)
    "Retraction changed unrelated owners or kept stale posting membership"
  let comparisons := comparisons + (← compareRanks deleted)
  let _ ← append deleted [firstOwner]
  let restored ← DB.PageMap.pin database
  require ((← Index.open? restored).isNone) "Equal population hid a changed source root ordinal"
  let restoredResult ← Index.warm restored .user
  require (restoredResult.added == 1 && restoredResult.hydrated == 0)
    "A reintroduced immutable owner could not reuse its reverse terms"
  let comparisons := comparisons + (← compareRanks restored)

  let some ready ← Index.open? restored | throw (IO.userError "missing restored index")
  let ordinal ← getNat restored.get (key "member" addedIds[0]!)
  let _ ← DB.PageMap.withWriter ready.index fun writer => do
    writer.put "ready" none
    Index.retract writer addedIds[0]! ordinal
  require ((← Index.open? restored).isNone) "A partial index was certified complete"
  let recovered ← Index.warm restored .user
  require (recovered.added == 1 && recovered.hydrated == 0)
    "Interrupted index maintenance did not resume from complete retained terms"
  let comparisons := comparisons + (← compareRanks restored)

  let copy := root / "copy.egg"
  let copied ← IO.Process.output {cmd := "/bin/cp", args := #["-cpR", database.toString, copy.toString]}
  require (copied.exitCode == 0) "Source fixture copy failed"
  let duplicated ← DB.PageMap.pin copy
  require ((← Index.open? duplicated).isSome) "A DB copy lost its shared identity-owned private index"
  let different ← DB.PageMap.create (root / "different.egg") authority
  require ((← Index.open? different).isNone) "Another DB reused a foreign lexical index"
  IO.println s!"lexical index: {comparisons} exact full-order comparisons, 40-source batches, memo stability, append/delete/re-add, partial recovery, copy and DB isolation passed"

def main : IO Unit := IO.FS.withTempDir scenario
