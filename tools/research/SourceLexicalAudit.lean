module
import all Eggshell.LexicalAdvice
import all Eggshell.Persistence
public meta import Lean
open Lean Eggshell Eggshell.DB Eggshell.Persistence.Store

#print axioms SourceLexicalPolicy.unrecorded_nonempty_rejected
#print axioms SourceLexical.OwnerWitness.source_checks
#print axioms LexicalAdvice.rank_prepared_exact

run_meta do
  let env ← getEnv
  for root in #[``LexicalAdvice.query, ``LexicalReads.sourceQuery, ``SourceLexical.status] do
    let mut pending := [root]
    let mut seen : Std.HashSet Name := {}
    while let current :: rest := pending do
      pending := rest
      if seen.contains current then continue
      seen := seen.insert current
      if let some info := env.find? current then
        if let some body := info.value? then
          for dependency in body.getUsedConstants do
            if dependency.toString.startsWith "Eggshell." then pending := dependency :: pending
    for forbidden in #[``PageMap.withWriter, ``Sidecar.prepare, ``RetrievalResearch.Index.warm,
        ``searchDocuments, ``locateOutcome, "Eggshell.Matcher.localUnion?".toName] do
      if seen.contains forbidden then throwError "source lexical nomination reaches {forbidden}"
    logInfo m!"Source lexical read has no publication, preparation, whole-owner hydration or Union: {root}"

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def rejected (action : IO α) : IO Bool := do
  try let _ ← action; pure false catch _ => pure true

private def owner (work body : String) : OutcomeEdge :=
  OutcomeEdge.make (.text work) (.text body) [] (by simp) (by simp)

private def append (source : Snapshot) (values : List OutcomeEdge) : IO (Snapshot × List Nat) := do
  let (ids,_,_) ← PageMap.withWriter source fun writer => do
    let intern : Intern := ⟨writer, ← IO.mkRef {}⟩
    let ids ← values.mapM (fun edge => intern.root edge.relation)
    writeChange writer {added := ids,removed := [],unionsChanged := false}
    return ids
  return (← PageMap.pin source.directory,ids)

private def queries : List String := ["保存", "한국어 검색", "Поиск", "résumé", "resume",
  "ＡＢＣ１２３", "abc123", "ｶﾞｲﾄﾞ", "ガイド", "木", "Serializer.load_payload", "/src/main.cpp",
  "newfound", "missing-value"]

/-- The independent reference tokenizes original plaintext and ranks the full
live source catalogue. The candidate reads only publication-time postings. -/
private def compare (source : Snapshot) : IO Json := do
  let documents ← searchDocuments source
  let reader ← NodeReader.new source
  let originals ← documents.mapM fun document => do
    pure (searchText (← reader.outcome (← reader.locateOutcome document.owner)))
  let terms := originals.map SearchRank.terms
  let mut count := 0
  for query in queries do
    let found ← LexicalAdvice.query source query
    let lookup ← LexicalReads.sourceQuery source
    for unit in SearchRank.terms query do
      let (ids,frequency) ← lookup.posting unit
      let expected := (documents.zip terms).filterMap fun (document,units) =>
        if units.contains unit then some document.owner else none
      check (ids == expected && frequency == expected.length) s!"source posting differs from original text: {query}"
      for id in ids do
        check ((← lookup.ordinal id) == (← getNat source.get (key "member" id))) "source query changed its original ordinal"
    for anchors in [false,true] do
      let ranked := SearchRank.rankRows query documents
        (fun document unit => ((documents.zip terms).find? (fun pair => pair.1.owner == document.owner)).any (fun pair => pair.2.contains unit))
        (fun unit => terms.countP (·.contains unit)) anchors documents.length
      let expected := ranked.filterMap (fun position => (documents[position]?).map (·.owner))
      check ((if anchors then found.anchors else found.ranked) == expected) s!"complete lexical order differs from plaintext reference: {query}"
      count := count+1
    let consumed ← LexicalAdvice.originals found found.ranked
    check (consumed.map (·.owner) == found.ranked) "nominated originals did not survive authoritative owner checks"
  return Json.mkObj [("comparisons",toJson count),("candidates",toJson documents.length),
    ("primaryPolicy",toJson SourceLexicalPolicy.contract),("source",toJson source.head)]

public def main (args : List String) : IO Unit := do
  let [destination] := args | throw (IO.userError "fresh fixture directory required")
  let root := System.FilePath.mk destination
  check (!(← root.pathExists) && (← Paths.dataRoot) == root / "private") "fresh isolated source lexical fixture required"
  IO.FS.createDir root
  let empty ← PageMap.create (root / "source.egg") (Persistence.valueToJson (.text "source lexical")).compress
  check (← SourceLexical.ready empty) "empty original publication is unavailable"
  let phrases := ["保存した本文 木", "한국어 검색 기록", "Поиск сохранённых записей", "café résumé",
    "ｶﾞｲﾄﾞ ＡＢＣ１２３", "Serializer.load_payload /src/main.cpp"]
  let examples := (List.range 40).map fun i => owner s!"record {i}" s!"{phrases[i % phrases.length]!} BODY_{i}"
  let (first,ids) ← append empty examples
  let firstRows ← compare first
  check (!(← (root / "private").pathExists)) "primary lexical reads created a private cache"
  let sourceHead := first.head
  let _ ← append first examples
  let retry ← PageMap.pin first.directory
  check ((← compare retry).getObjValD "candidates" == toJson (40 : Nat)) "repeated roots duplicated lexical frequency"
  let (next,newIds) ← append retry [owner "new arrival" "newfound 保存 한국어"]
  let began ← IO.monoMsNow
  let immediate ← LexicalAdvice.query next "newfound"
  check (immediate.ranked == newIds) "new source evidence requires a separate warm"
  let newArrivalMs := (← IO.monoMsNow)-began
  let nextRows ← compare next
  check ((← compare first).getObjValD "candidates" == toJson (40 : Nat) && first.head == sourceHead)
    "new source publication changed an old pinned lexical corpus"
  let _ ← PageMap.withWriter next fun writer => do
    for id in ids.take 8 do removeRoot writer id
    writeChange writer {added := [],removed := ids.take 8,unionsChanged := false}
  let removed ← PageMap.pin first.directory
  let removedRows ← compare removed
  let (restored,_) ← append removed (examples.take 2)
  let restoredRows ← compare restored
  let stable := restored.head
  check (← rejected (PageMap.withWriter restored fun writer => do
    let intern : Intern := ⟨writer, ← IO.mkRef {}⟩
    let _ ← intern.root (owner "cancelled" "not_published").relation
    if true then throw (IO.userError "abort fixture transaction")
    pure ())) "aborted source transaction unexpectedly succeeded"
  check ((← PageMap.pin restored.directory).head == stable && (← LexicalAdvice.query restored "not_published").ranked.isEmpty)
    "aborted publication exposed partial lexical postings"
  let began ← IO.monoMsNow
  let tasks ← (Array.range 80).mapM fun i => IO.asTask (do
    let source := if i % 2 == 0 then first else restored
    let ranked ← LexicalAdvice.query source "保存"
    let expected ← LexicalAdvice.query source "保存"
    check (ranked.ranked == expected.ranked && ranked.anchors == expected.anchors) "parallel source lexical read changed a pinned result") .dedicated
  for task in tasks do IO.ofExcept (← IO.wait task)
  let parallelMs := (← IO.monoMsNow)-began
  check ((← PageMap.pin restored.directory).head == stable && !(← (root / "private").pathExists))
    "parallel lexical reads wrote a DB or cache"
  let _ ← PageMap.withWriter restored fun writer => writer.put SourceLexicalPolicy.name none
  let unrecorded ← PageMap.pin restored.directory
  check ((← SourceLexical.open? unrecorded).isNone && (← rejected (LexicalAdvice.query unrecorded "保存")))
    "unrecorded policy certified a nonempty corpus"
  check (← rejected (append unrecorded [owner "must fail" "wrong_policy"] )) "mixed-policy source accepted a new stamp"
  check ((← PageMap.pin restored.directory).head == unrecorded.head && (← SourceLexical.ready restored))
    "failed mixed-policy append changed source or an old pinned policy"
  let foreign ← PageMap.create (root / "foreign.egg") (Persistence.valueToJson (.text "foreign lexical")).compress
  let (foreign,_) ← append foreign [owner "isolated" "unrelated_private_phrase"]
  check ((← LexicalAdvice.query foreign "newfound").ranked.isEmpty) "another project reused source postings"
  let _ ← PageMap.withWriter foreign fun writer => writer.put SourceLexicalPolicy.name (some "wrong-policy".toUTF8)
  check ((← SourceLexical.open? (← PageMap.pin foreign.directory)).isNone) "foreign lexical policy was accepted"
  IO.FS.writeFile (root / "result.json") (Json.mkObj [
    ("first",firstRows),("next",nextRows),("removed",removedRows),("restored",restoredRows),
    ("newEvidenceQueryMs",toJson newArrivalMs),("parallelReaders",toJson (80 : Nat)),("parallelElapsedMs",toJson parallelMs),
    ("allFullOrdersEqualPlaintext",toJson true),("oldPinsUnchanged",toJson true),("retryIdempotent",toJson true),
    ("abortedPublicationInvisible",toJson true),("unknownAndWrongPolicyRejected",toJson true),
    ("readsCreateNoCacheOrSourceWrite",toJson true),("projectsIsolated",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("derivedLexicalWarmCalls",toJson (0 : Nat)),
    ("adopted",toJson false)]).pretty
  IO.println "Source-published lexical nominations match complete plaintext order; no separate lexical warm"
