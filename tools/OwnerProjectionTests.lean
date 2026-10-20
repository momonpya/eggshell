import tools.OwnerProjection
import Lean

open Lean Eggshell OwnerProjection

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

/-- Independent original append/any program; no compiler alias to the builder. -/
private def original (initial : Result Nat Value) (related ranked : List (Choice Nat Value)) :
    Result Nat Value := Id.run do
  let mut found := initial
  for (owner, indices) in related do
    match owner with
    | .inl key => found := {found with
        durable := found.durable ++ [key]
        durableWindows := found.durableWindows ++ [(key, indices)]}
    | .inr key => found := {found with
        staged := found.staged ++ [key]
        stagedWindows := found.stagedWindows ++ [(key, indices)]}
  for (owner, indices) in ranked do
    match owner with
    | .inl key => found := {found with
        durableRanking := found.durableRanking ++ [key]
        durableWindows := if found.durableWindows.any (·.1 == key) || indices.isEmpty
          then found.durableWindows else found.durableWindows ++ [(key, indices)]
        presentationOrder := found.presentationOrder ++ [.inl key]}
    | .inr key => found := {found with
        stagedRanking := found.stagedRanking ++ [key]
        stagedWindows := if found.stagedWindows.any (·.1 == key) || indices.isEmpty
          then found.stagedWindows else found.stagedWindows ++ [(key, indices)]
        presentationOrder := found.presentationOrder ++ [.inr key]}
  return found

@[noinline] private def timedProjection (action : Unit → IO α) : IO (α × Nat) := do
  let start ← IO.monoNanosNow
  let value ← action ()
  let elapsed := (← IO.monoNanosNow) - start
  pure (value, elapsed)

private abbrev Resolver := ExceptT String (StateM (List Nat))

private def resolve (failed : Option Nat) (row : Nat) : Resolver (Choice Nat Value) := do
  modify (· ++ [row])
  if failed == some row then throw s!"rejected row {row}"
  return (if row % 2 == 0 then .inl (row % 3) else .inr (Value.text (toString (row % 3))),
    if row % 3 == 0 then [] else [row])

private def effectShape (value : Except String (Result Nat Value) × List Nat) :
    String × Option (Result Nat Value) × List Nat :=
  match value.1 with
  | .ok rows => ("", some rows, value.2)
  | .error message => (message, none, value.2)

def main : IO UInt32 := do
  let stage := Value.text "段階: café / 작업"
  let seeds : List (Result Nat Value) := [{}, {
    durable := [4, 4], staged := [stage], durableWindows := [(3, []), (3, [7])],
    stagedWindows := [(stage, [])], durableRanking := [99], stagedRanking := [stage],
    presentationOrder := [.inr stage, .inl 99], focused := [999, 1000] }]
  let alphabet : List (Choice Nat Value) := [(.inl 0, []), (.inl 0, [1]),
    (.inl 3, [2]), (.inl (2^60), [31, 0]), (.inr stage, []), (.inr stage, [5]),
    (.inr (Value.text "別の所有者"), [0, 0])]
  let mut comparisons := 0
  let mut resolverCases := 0
  for seed in seeds do
    for failed in [none, some 0, some 2, some 5, some 8, some 99] do
      let related := [0, 1, 2]; let ranked := [3, 4, 5, 6, 7, 8]
      let before := (ExceptT.run (referenceM seed related ranked (resolve failed) (resolve failed))).run []
      let after := (ExceptT.run (projectM seed related ranked (resolve failed) (resolve failed))).run []
      let legacy := (ExceptT.run (legacyM seed related ranked (resolve failed) (resolve failed))).run []
      check (effectShape before == effectShape after) "resolver effect order or first error changed"
      check (effectShape before == effectShape legacy) "imperative traversal differs from its reference fold"
      resolverCases := resolverCases + 1
    for count in [0, 1, 2, 7, 8, 31, 128] do
      let rows := (List.range count).map fun index =>
        alphabet[index % alphabet.length]?.getD (.inl 0, [])
      for related in [[], rows.take 8, rows.reverse, rows ++ rows] do
        for ranked in [[], rows, rows.reverse, rows ++ rows.reverse] do
          check (project seed related ranked == original seed related ranked)
            "owner/window order, duplicate or empty-window behavior changed"
          comparisons := comparisons + 1
  let rows : List (Choice Nat Value) := (List.range 10000).map fun key => (.inl key, [key % 32])
  let (before, beforeNs) ← timedProjection fun _ => pure (original {} [] rows)
  let (after, afterNs) ← timedProjection fun _ => pure (project {} [] rows)
  check (before == after) "complete 10k owner projection differs"
  let large : List (Choice Nat Value) := (List.range 50000).map fun key => (.inl key, [key % 32])
  let (result, largeNs) ← timedProjection fun _ => pure (project {} [] large)
  check (result.durableRanking == List.range 50000 &&
      result.presentationOrder == large.map Prod.fst && result.durableWindows.length == 50000)
    "complete 50k projection was shortened or reordered"
  IO.println (Json.mkObj [("passed", toJson true), ("comparisons", toJson comparisons),
    ("resolverCases", toJson resolverCases),
    ("original10kNs", toJson beforeNs), ("builder10kNs", toJson afterNs),
    ("builder50kNs", toJson largeNs), ("largeRows", toJson (50000 : Nat)),
    ("generationModelCalls", toJson (0 : Nat)), ("productionAdoption", toJson false)]).compress
  pure 0
