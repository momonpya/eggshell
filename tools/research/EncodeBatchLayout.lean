module
public import Init.Data.List.TakeDrop
public import Lean.Data.Json.FromToJson
@[expose] public section
namespace Eggshell.Research.EncodeBatchLayout
open Lean

/-- A numerical batch carries the exact original text order. Output rows are
partitioned only by these original request lengths, never by a guessed ID. -/
def splitRows (counts : List Nat) (rows : List α) : Option (List (List α)) :=
  match counts with
  | [] => if rows.isEmpty then some [] else none
  | count :: rest =>
      if count ≤ rows.length then
        (rows.take count :: ·) <$> splitRows rest (rows.drop count)
      else none

theorem splitRows_flatten (groups : List (List α)) :
    splitRows (groups.map List.length) groups.flatten = some groups := by
  induction groups with
  | nil => simp [splitRows]
  | cons group groups ih =>
      simp [splitRows,List.length_append,ih]

theorem splitRows_conserves (counts : List Nat) (rows : List α) (groups : List (List α))
    (accepted : splitRows counts rows = some groups) : groups.flatten = rows := by
  induction counts generalizing rows groups with
  | nil =>
      simp only [splitRows] at accepted
      split at accepted
      · cases accepted
        simpa using List.isEmpty_iff.mp ‹_› |>.symm
      · contradiction
  | cons count counts ih =>
      simp only [splitRows] at accepted
      split at accepted
      · cases found : splitRows counts (rows.drop count) with
        | none => simp [found] at accepted
        | some remaining =>
            simp only [found] at accepted
            change some (rows.take count :: remaining) = some groups at accepted
            cases accepted
            simp only [List.flatten_cons,ih _ _ found,List.take_append_drop]
      · contradiction

/-- Extra rows, missing rows and malformed native arrays are rejected before
any caller sees a projection. This does not assume batch-invariant inference. -/
def partition (counts : List Nat) (reply : Json) : Except String (Array Json) := do
  let vectors ← reply.getObjValAs? (Array Json) "vectors"
  let coverage ← reply.getObjValAs? (Array Json) "coverage"
  let some vectorGroups := splitRows counts vectors.toList | throw "batch vector count mismatch"
  let some coverageGroups := splitRows counts coverage.toList | throw "batch coverage count mismatch"
  return (vectorGroups.zip coverageGroups).toArray.map fun (vector,covered) =>
    Json.mkObj [("vectors",toJson vector),("coverage",toJson covered)]

#print axioms splitRows_flatten
#print axioms splitRows_conserves
end Eggshell.Research.EncodeBatchLayout
