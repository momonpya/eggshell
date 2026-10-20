import Eggshell.Handoff

open Lean Eggshell Plugin

/-- Compiled only in the isolated ordinal-tree candidate. -/
private def owner (ordinal : Nat) : OutcomeEdge :=
  OutcomeEdge.make (.text s!"Inspect saved work {ordinal}")
    (.text s!"Original observation body {ordinal}") [] (by simp) (by simp)

private def check (accepted : Bool) (message : String) : IO Unit :=
  unless accepted do throw (IO.userError message)

private def permutations : List Nat → List (List Nat)
  | [] => [[]]
  | head :: tail => (permutations tail).flatMap fun rest =>
      (List.range (rest.length + 1)).map fun index => rest.take index ++ head :: rest.drop index

private def orderCheck (insertion : List Nat) : IO Unit := do
  let reads ← IO.mkRef 0
  let readOwner := fun ordinal => do reads.modify (· + 1); pure (owner ordinal)
  let mut state : IndexedOwners := {}
  for ordinal in insertion ++ insertion.reverse ++ insertion do
    state ← IndexedOwners.load (fun id => pure id) readOwner state ordinal
  let expected := insertion.eraseDups.mergeSort (· ≤ ·)
  check ((← reads.get) == expected.length) "duplicate requests rehydrated an original owner"
  check ((state.owners.toList.map Prod.fst) == expected) "owner tree changed original ordinal order"
  check ((state.rows.map (·.candidate.edge)) == expected.map owner) "owner tree changed original bodies"
  check ((state.graph []).outcomes == expected.map owner) "graph lost an original loaded owner"
  check ((state.candidates.map (·.edge)) == expected.map owner) "candidate projection changed order"

private def admissionCheck : IO Unit := do
  let reads ← IO.mkRef 0
  let workReads ← IO.mkRef 0
  let decisions ← IO.mkRef 0
  let readOwner := fun ordinal => do reads.modify (· + 1); pure (owner ordinal)
  let readWork := fun ordinal => do
    workReads.modify (· + 1)
    pure ({work := (owner ordinal).work, native := false} : Persistence.Store.WorkOrigin)
  let admission := fun (accepted : Bool) (_ : Nat) (_ : Matcher.WorkView) => do
    decisions.modify (· + 1)
    pure accepted
  let empty : IndexedOwners := {}
  let rejected ← IndexedOwners.loadWork (fun id => pure id) readWork readOwner empty 17 (admission false)
  let rejected ← IndexedOwners.loadWork (fun id => pure id) readWork readOwner rejected 17 (admission false)
  check (rejected.rows.isEmpty && (← reads.get) == 0 && (← workReads.get) == 2)
    "a rejected owner acquired body authority or suppressed a later comparison"
  let admitted ← IndexedOwners.loadWork (fun id => pure id) readWork readOwner rejected 17 (admission true)
  let duplicate ← IndexedOwners.loadWork (fun id => pure id) readWork readOwner admitted 17 (admission false)
  check ((← reads.get) == 1 && (← workReads.get) == 3 && (← decisions.get) == 3)
    "a retained original was rehydrated or re-admitted"
  check (duplicate.rows.map (·.candidate.edge) == [owner 17]) "duplicate loading changed the retained owner"
  let mismatch ← try
    let _ ← IndexedOwners.loadWork (fun id => pure id) readWork (fun _ => pure (owner 99))
      empty 17 (admission true)
    pure false
  catch _ => pure true
  check mismatch "Work origin disagreement was accepted"

def main : IO UInt32 := do
  let orders := permutations [1000000, 0, 17, 2, 99999, 3]
  for insertion in [] :: [7, 7, 7] :: orders do orderCheck insertion
  admissionCheck
  IO.println (Json.mkObj [("passed", toJson true), ("permutations", toJson orders.length),
    ("orderCases", toJson (orders.length + 2)), ("admissionCases", toJson (4 : Nat)),
    ("generationModelCalls", toJson (0 : Nat)), ("productionAdoption", toJson false)]).compress
  pure 0
