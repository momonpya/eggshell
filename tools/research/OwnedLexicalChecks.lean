import Eggshell.ContractAudit
import tests.FullSearchOracle
import tools.RetrievalIndex

open Lean Eggshell Eggshell.Plugin Eggshell.DB Eggshell.Persistence Eggshell.Persistence.Store

namespace Eggshell.Research.OwnedLexicalChecks

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def rejected (action : IO α) : IO Bool := do
  try let _ ← action; return false catch _ => return true

/-- The producer label is private diagnostic routing information. Every model
byte, packet, source record and certification field remains in the comparison. -/
private def comparable (result : Option Handoff) : Option Handoff :=
  result.map fun handoff =>
    let suffix := " producer=work-class"
    {handoff with reason := if handoff.reason.endsWith suffix then
      (handoff.reason.take (handoff.reason.length-suffix.length)).copy else handoff.reason}

private def outcome (work text : String) : Value :=
  (OutcomeEdge.make (.text work) (.text text) [] (by simp) (by simp)).relation

private def save (path : System.FilePath) (values : List Value) : IO Unit := do
  let previous ← if ← path.pathExists then pure (← Persistence.load path).values else pure []
  let values := previous.filter values.contains ++ values.filter (!previous.contains ·)
  if valid : values.all Relation.wellFormed then
    Persistence.saveAtomic path {
      (Graph.empty (.text "owned lexical source fixture")) with
      values,values_wellFormed := fun value member => (List.all_eq_true.mp valid) value member}
  else throw (IO.userError "invalid original fixture")

private def verify (source : PageMap.Snapshot) : IO Nat := do
  let graph ← materialize source
  let corpus := Matcher.Corpus.build LogicalText.logicalNormalizer (WorkGraph.fromValues graph.values)
  let units := hashDistinct ((corpus.candidates.flatMap Matcher.Corpus.candidateTerms) ++ ["ABSENT_QUARTZ987"])
  for unit in units do
    check ((← Store.frequency source unit) == corpus.frequency unit) "original Work frequency changed"
    let ids ← Store.postings source unit
    let mut expected := #[]
    for value in graph.values do
      if let some candidate := corpus.candidates.find? (·.edge.relation == value) then
        if (Matcher.Corpus.candidateTerms candidate).contains unit then
          let some id ← Store.findNode? source value | throw (IO.userError "missing original owner")
          expected := expected.push id
    check (ids == expected.toList) "original Work postings changed owner identity or order"
  let documents ← Store.searchDocuments source
  let reader ← NodeReader.new source
  let texts ← documents.mapM fun document => do
    let owner ← reader.outcome (← reader.locateOutcome document.owner)
    let text := Store.searchText owner
    let windows := SearchRank.windows text
    check (document.windows == windows.map Store.windowKey) "source window keys changed"
    for (expected,index) in windows.zipIdx do
      check ((← Store.readSearchWindow source document index) == expected) "original source window bytes changed"
    return (document.owner,SearchRank.terms text)
  let _ ← RetrievalResearch.Index.warm source .database
  let lexicalUnits := hashDistinct (texts.flatMap Prod.snd ++ SearchRank.terms "absent_quartz987")
  for unit in lexicalUnits do
    let (ids,count) ← RetrievalResearch.Index.strictPosting source unit
    let expected := (texts.filter (·.2.contains unit)).map Prod.fst
    check (ids == expected && count == expected.length) "prepared posting differs from independent original tokenization"
  return units.length+lexicalUnits.length

private def run (root : System.FilePath) : IO Unit := do
  check (root.isAbsolute && !(← root.pathExists)) "fresh absolute lexical check root required"
  IO.FS.createDirAll root
  let left := root / "left.egg"
  let right := root / "right.egg"
  let first := outcome "inspect alpha deployment" "alpha controls retry_controller42 /login"
  let shared := outcome "read shared original" "shared gamma 한국어 検索 ｶﾞｲﾄﾞ ＡＢＣ café"
  let corrected := outcome "inspect alpha deployment" "beta changes retry_controller42 /login"
  let other := outcome "inspect delta source" "delta 原文 original evidence"
  let all ← if valid : ([Value.text "read shared original"] : List Value) ≠ [] ∧
      Value.text "inspect alpha deployment" ∉ [.text "read shared original"] then
    pure (AllEdge.make (.text "inspect alpha deployment") [.text "read shared original"] valid.1 valid.2).relation
    else throw (IO.userError "invalid Work topology fixture")
  save left [first,shared,all]
  save right [shared,other]
  let initial ← PageMap.pin left
  check (← rejected (RetrievalResearch.Index.strictLookup initial)) "cold prepared index became a successful empty lookup"
  let mut checked := (← verify initial)+(← verify (← PageMap.pin right))
  let some pinned ← RetrievalResearch.Index.open? initial | throw (IO.userError "missing initial prepared view")
  let tracked := SearchRank.terms "alpha retry_controller42"
  let before ← tracked.mapM fun unit => pinned.posting unit
  let mut comparisons := 0
  let mut positive := 0
  let mut mismatches : Array Json := #[]
  for values in [[corrected,shared,all],[shared,all],[first,shared,all]] do
    save left values
    let source ← PageMap.pin left
    check (← rejected (RetrievalResearch.Index.strictLookup source)) "advanced source silently reused a stale complete index"
    check ((← tracked.mapM fun unit => pinned.posting unit) == before) "later publication changed a pinned prepared view"
    checked := checked+(← verify source)
    let sources := #[source,← PageMap.pin right]
    let catalogue ← Store.Federated.prepare sources
    let original ← TestOracle.FederationBeforeCanonical.prepare sources
    check (catalogue.roots.length == original.roots.length && catalogue.documents.length == original.documents.length)
      "complete federated WorkGraph lost original roots or owners"
    let selection : Config.Selection := {
      label := "owned lexical check",semanticMatcher := none
      read := [⟨"left",left⟩,⟨"right",right⟩],write := none,handoffChars := 120000}
    for query in ["inspect alpha deployment","read shared original","inspect delta source","absent_quartz987"] do
      for native in [false,true] do
        TestOracle.runtimeCache.set {}
        let expected ← TestOracle.computeGeneralAutomaticHandoff selection (sources.toList.map some) query [] native
        TestOracle.runtimeCache.set {}
        let actual ← computeAutomaticHandoff selection (sources.toList.map some) query [] native
        if (toJson (comparable actual)).compress != (toJson (comparable expected)).compress then
          mismatches := mismatches.push (Json.mkObj [
            ("query",toJson query),("native",toJson native),
            ("expected",toJson expected),("actual",toJson actual)])
        if actual.isSome then positive := positive+1
        comparisons := comparisons+1
  check (positive > 0) "handoff oracle comparisons were all empty"
  let source ← PageMap.pin left
  let some lexical ← RetrievalResearch.Index.open? source | throw (IO.userError "missing final prepared view")
  let some unit := (SearchRank.terms "alpha").head? | throw (IO.userError "missing checked term")
  let some term ← findTerm? lexical.index lexical.index.get unit | throw (IO.userError "missing prepared term")
  let _ ← PageMap.withWriter lexical.index fun writer => putNat writer (Store.key "frequency" term.id) 999
  PreparedRoot.publish source (← PageMap.pin lexical.index.directory)
  check (← rejected (RetrievalResearch.Index.strictPosting source unit)) "corrupt prepared frequency became a successful lookup"
  let report := Json.mkObj [("allPassed",toJson mismatches.isEmpty),("sourceAndPreparedPassed",toJson true),
    ("sourceAndPreparedChecks",toJson checked),("oracleMismatches",toJson mismatches),
    ("completeHandoffOracleComparisons",toJson comparisons),("coldStaleCorruptRejected",toJson true),
    ("positiveHandoffs",toJson positive),
    ("pinnedPreparedViewStable",toJson true),("answeringModelCalls",toJson (0 : Nat)),
    ("notTokenAdoptionEvidence",toJson true)]
  IO.FS.writeFile (root / "report.json") (report.pretty ++ "\n")
  IO.println report.compress

end Eggshell.Research.OwnedLexicalChecks

def main (args : List String) : IO Unit := do
  let [pathText] := args | throw (IO.userError "OwnedLexicalChecks NEW_ROOT")
  Eggshell.Research.OwnedLexicalChecks.run (.mk pathText)
