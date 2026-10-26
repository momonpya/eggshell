import tools.LiteralSearch
import Lean.Data.Json.FromToJson
open LiteralSearch Lean

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def before (left right : Nat × Nat × Nat) : Bool :=
  left.1 < right.1 || (left.1 == right.1 &&
    (left.2.1 < right.2.1 || (left.2.1 == right.2.1 && left.2.2 < right.2.2)))

private def actual (patterns : Array String) (original : String) : Array (Nat × Nat × Nat) :=
  (find (prepare patterns) original).map (fun hit => (hit.pattern.val,hit.first,hit.limit))
    |>.qsort before

private def reference (patterns : Array String) (original : String) : Array (Nat × Nat × Nat) := Id.run do
  let chars := original.toList.toArray
  let mut result := #[]
  for pattern in [:patterns.size] do
    let text := patterns[pattern]!
    if text.isEmpty then continue
    for first in [:chars.size] do
      let limit := first+text.length
      if limit ≤ chars.size && String.ofList (chars.extract first limit).toList == text then
        result := result.push (pattern,first,limit)
  return result.qsort before

private def referenceFirst (occurrences : Array (Nat × Nat × Nat)) : Array (Nat × Nat × Nat) := Id.run do
  let mut result := #[]
  for occurrence in occurrences do
    if !result.any (·.1 == occurrence.1) then result := result.push occurrence
  return result

def main : IO Unit := do
  let patterns := #["a","aa","aba","b","ba","", "a"]
  let mut level := #[""]
  let mut checked := 0
  for _ in [:11] do
    for original in level do
      check (actual patterns original == reference patterns original) "literal search disagreed with independent exhaustive enumeration"
      let found := (first (prepare patterns) original).map (fun hit => (hit.pattern.val,hit.first,hit.limit)) |>.qsort before
      check (found == referenceFirst (reference patterns original)) "bounded witness search lost first occurrences"
      checked := checked+1
    level := level.flatMap fun text => #[text ++ "a",text ++ "b"]
  for (wanted,original) in #[
      (#["she","he","hers","his"],"ushers his she hers"),
      (#["警告","告","界\n終","-x","ToolChainKey"],"  10\tToolChainKey\n警告 -x 世界\n終端"),
      (#["é","é","🙂","🙂🙂"],"é é 🙂🙂🙂"),
      (#["LARGE_FIELD_TAIL"],String.ofList (List.replicate 6000 '界') ++ "LARGE_FIELD_TAIL") ] do
    check (actual wanted original == reference wanted original) "literal search lost Unicode, overlaps or a long-field tail"
  let forged : Index #["absent"] := ⟨#[{terminal := #[0]}]⟩
  check ((find forged "actual data").isEmpty) "an invalid automaton fabricated original content"
  let repeated := String.ofList (List.replicate 100000 'a')
  check ((first (prepare #["a","aa","absent"]) repeated).size == 2)
    "repeated input accumulated more than one witness per pattern"
  IO.println (Json.mkObj [("exhaustiveInputs",toJson checked),
    ("unicodeAndLongTail",toJson true),("overlappingMatches",toJson true),
    ("independentReferenceAgreement",toJson true),("invalidIndexCannotForge",toJson true),
    ("boundedWitnessesFor100000RepeatedCharacters",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("productionAdoption",toJson false)]).compress
