import Eggshell.SearchProvider

open Lean Eggshell

private def check (accepted : Bool) (message : String) : IO Unit :=
  unless accepted do throw (IO.userError message)

/-- Independent pre-change implementation; no csimp alias to the candidate. -/
private def referenceFused (rankings : List (List Nat)) : List Nat :=
  let ids := rankings.flatten.eraseDups
  let scores := ids.map fun id =>
    (rankings.foldl (fun score ranking =>
      match (ranking.zipIdx.find? (·.1 == id)) with
      | some (_, rank) => score + 1 / (61 + rank).toFloat
      | none => score) (0 : Float), id)
  (scores.mergeSort SearchRank.scoreOrder).map (·.2)

private def referencePresentation (mode : String) (count : Nat) (semantic lexical : List Nat) : List Nat :=
  let combined := if mode == "lexical" then lexical
    else if mode == "semantic" then semantic
    else referenceFused [semantic, lexical]
  (combined ++ semantic ++ lexical ++ List.range count).eraseDups.filter (· < count)

private def referenceNominations (documents : List Persistence.Store.SearchDocument)
    (response : SemanticMatcher.IndexedResponse) :
    Except String (List (SemanticMatcher.IndexedNomination documents)) :=
  response.related.eraseDups.foldlM (fun nominations index => do
    match present : documents[index]? with
    | none => pure nominations
    | some document =>
        let owned := List.mem_of_getElem? present
        let indices := (response.evidence.find? (·.document == index)).map (·.indices) |>.getD []
        if indices.isEmpty then pure (nominations ++ [⟨document, owned, [], by simp⟩]) else
          let some pull := SemanticMatcher.WindowPull.check? document indices |
            throw "semantic evidence window lies outside its document"
          pure (nominations ++ [⟨document, owned, pull.handles, pull.handles_bounded⟩])) []

private def shape (result : Except String (List (SemanticMatcher.IndexedNomination documents))) :
    Bool × String × List (Nat × Nat × List Nat) :=
  match result with
  | .error message => (false, message, [])
  | .ok rows => (true, "", rows.map fun nomination =>
      (nomination.document.owner, nomination.document.work, nomination.indices))

def main : IO UInt32 := do
  let mut comparisons := 0
  for count in [0, 1, 2, 8, 32, 257, 1024] do
    let original := List.range count
    for rankings in [[], [original], [original, original.reverse],
        [original ++ original, original.reverse ++ [count + 1000000]],
        [original.reverse, [], original, [0, 0, 2^60]]] do
      check (SearchRank.fused rankings == referenceFused rankings) "complete RRF order changed"
      comparisons := comparisons + 1
    for mode in ["semantic", "lexical", "hybrid", "other"] do
      let semantic := original.reverse ++ original
      let lexical := [count + 1, 2^60, 0] ++ original
      check (SearchProvider.presentationRanking mode count semantic lexical ==
        referencePresentation mode count semantic lexical) "complete presentation order changed"
      for limit in [0, 1, 8, count + 1] do
        let expected := ((lexical ++ semantic).eraseDups.filter (· < count)).take limit
        check (SearchRank.select count limit lexical semantic == expected) "admission order changed"
        comparisons := comparisons + 1
    let rows := (original.map fun index => (index, [index, index + 1])) ++ [(0, [999]), (2^60, [17])]
    let directory := FirstIndex.make Prod.fst rows
    for key in [0, 1, count, 2^60, 2^60 + 1] do
      check (directory.read key == rows.find? (·.1 == key)) "first-wins lookup changed"
      comparisons := comparisons + 1
    let ranked := original.reverse ++ [0, count + 3, 2^60, 0]
    let expected : List SemanticMatcher.WindowChoice := ranked.filterMap fun index =>
      (rows.find? (·.1 == index)).map fun row => ⟨row.1, row.2⟩
    check (toJson (SearchProvider.indexedEvidenceWindows rows ranked) == toJson expected)
      "ordered window choices changed or foreign/duplicate keys were conflated"
  let large := List.range 50000
  check (SearchProvider.presentationRanking "semantic" 50000 large large.reverse == large)
    "large complete ranking dropped or reordered a candidate"
  let directory := FirstIndex.make Prod.fst (large.map fun index => (index, index + 1))
  for key in [0, 31, 49999, 50000, 2^60] do
    check (directory.read key == if key < 50000 then some (key, key + 1) else none)
      "large sparse-key directory changed a row"
  let mut boundaryComparisons := 0
  for count in [0, 1, 2, 8, 32, 257] do
    let documents := (List.range count).map fun index =>
      ({owner := 100000 + index * 17, work := index + 7, windows := ["first", "second", "third"]} :
        Persistence.Store.SearchDocument)
    let choices : List SemanticMatcher.WindowChoice := (List.range count).map fun index => ⟨index, [0, 2]⟩
    for related in [List.range count, (List.range count).reverse, [2^60, 0, 0, count + 2]] do
      for evidence in [[], choices, choices.reverse ++ choices,
          ⟨0, [3]⟩ :: choices, ⟨0, [0, 0]⟩ :: choices,
          ⟨0, []⟩ :: choices, ⟨0, List.range 33⟩ :: choices,
          ⟨2^60, [999]⟩ :: choices] do
        let response : SemanticMatcher.IndexedResponse := {
          related, ranked := List.range count, evidence }
        check (shape (SemanticMatcher.indexedNominations documents response) ==
          shape (referenceNominations documents response))
          "receiver changed original ownership, duplicate handling, ordering or first rejection"
        boundaryComparisons := boundaryComparisons + 1
  let documents := large.map fun index =>
    ({owner := index * 17, work := index + 7, windows := ["saved"]} : Persistence.Store.SearchDocument)
  let response : SemanticMatcher.IndexedResponse := {
    related := large.reverse, ranked := large.reverse,
    evidence := large.map fun index => ⟨index, [0]⟩ }
  let found ← IO.ofExcept (SemanticMatcher.indexedNominations documents response)
  let observed := found.map fun nomination =>
    (nomination.document.owner, nomination.document.work, nomination.indices)
  check (observed == large.reverse.map (fun index => (index * 17, index + 7, [0])))
    "large receiver omitted, reordered or substituted an original document/window"
  IO.println (Json.mkObj [("passed", toJson true), ("independentComparisons", toJson comparisons),
    ("receiverBoundaryComparisons", toJson boundaryComparisons),
    ("largeDomain", toJson (50000 : Nat)), ("generationModelCalls", toJson (0 : Nat)),
    ("productionAdoption", toJson false)]).compress
  pure 0
