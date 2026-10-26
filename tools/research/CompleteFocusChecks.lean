import Eggshell.Handoff
import Eggshell.SearchProvider
open Lean Eggshell

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def document (count : Nat) : Persistence.Store.SearchDocument := {
  owner := 0
  work := 0
  windows := (List.range count).map toString }

def main : IO Unit := do
  for count in #[0,1,16,17,32,33,127,512] do
    let doc := document count
    let positions := (List.range count).reverse
    let some full := SemanticMatcher.WindowOrder.check? doc positions |
      throw (IO.userError "a complete source order was rejected at a former constant bound")
    check (full.evidence.handles.map Fin.val == positions) "rank order changed at the ownership boundary"
    if count > 0 then
      check ((SemanticMatcher.WindowOrder.check? doc positions.tail).isNone)
        "an incomplete focus response was accepted"
      check ((SemanticMatcher.WindowEvidence.check? doc (positions ++ [0])).isNone &&
        (SemanticMatcher.WindowEvidence.check? doc [count]).isNone)
        "duplicate or foreign evidence acquired a source handle"
    if count > 32 then
      check ((SemanticMatcher.WindowPull.check? doc positions).isNone)
        "complete ranking weakened the foreground repair batch limit"
    let mut bounded : SearchProvider.WindowScore := {}
    let mut complete : SearchProvider.WindowScore := {}
    for position in positions do
      let score := (position % 7).toFloat / 7
      bounded := bounded.add score position
      complete := complete.addComplete score position
      check (bounded.best == complete.best) "owner nomination score changed"
    let ordered := complete.positions.mergeSort SearchRank.scoreOrder
    check (ordered.take 16 == bounded.positions && ordered.length == count)
      "existing top positions changed or lower scored positions disappeared"
    let original := (List.range count).map fun index => s!"original field {index}"
    let fused := Plugin.focusedEvidenceWindows "original field" original positions
    let hinted := QueryLiterals.focus "original field" original fused
    check (hinted.windows.mergeSort (· ≤ ·) == List.range count)
      "a later fusion stage discarded an original focus position"
  IO.FS.withTempDir fun scratch => do
    let options : SearchProvider.Options := {cache := scratch,models := scratch,mode := "lexical"}
    let doc := document 127
    let request := Json.mkObj [
      ("purpose",toJson "focus"),("lexical",toJson [0]),("anchors",toJson ([] : List Nat)),
      ("documents",toJson #[Json.mkObj [("id",toJson (0 : Nat)),("windows",toJson doc.windows)]])]
    let reply ← SearchProvider.handleIndexedUsing options none "opaque output" request
    let parsed ← IO.ofExcept (fromJson? (α := SemanticMatcher.IndexedResponse) reply)
    let resolved ← IO.ofExcept (SemanticMatcher.indexedNominations [doc] parsed)
    let some first := resolved.head? | throw (IO.userError "provider omitted its source document")
    check ((SemanticMatcher.WindowOrder.check? doc first.indices).isSome)
      "lexical-only focus did not keep its original directory"
  IO.println (Json.mkObj [
    ("formerBoundaryCounts",toJson #[0,1,16,17,32,33,127,512]),
    ("completeOriginalOrder",toJson true),("ownerScoresAndTop16Unchanged",toJson true),
    ("repairStillBounded32",toJson true),("duplicatesAndForeignRejected",toJson true),
    ("fusionKeepsCompleteDomain",toJson true),("lexicalProviderRoundTrip",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("productionAdoption",toJson false)]).compress
