import tools.KeyedOverride
import Lean.Data.Json

open Lean Eggshell

private structure CollisionKey where
  value : Nat
  deriving DecidableEq

private instance : Hashable CollisionKey := ⟨fun _ => 0⟩
private def sequences (choices : List α) : Nat → List (List α)
  | 0 => [[]]
  | count + 1 => [] :: choices.flatMap (fun item => (sequences choices count).map (item :: ·))

private def check (accepted : Bool) (message : String) : IO Unit :=
  unless accepted do throw (IO.userError message)

def main : IO UInt32 := do
  let choices : List (Nat × Nat) := [(0, 0), (0, 1), (1, 0), (1, 1)]
  let originals := sequences choices 2
  let additions := sequences choices 4
  let mut cases := 0
  for previous in originals do
    for added in additions do
      let expected := KeyedOverride.reference Prod.fst previous added
      check (KeyedOverride.merge Prod.fst previous added == expected)
        "override changed the latest payload, prior duplicates or final order"
      let collisionKey := fun (item : Nat × Nat) => CollisionKey.mk item.1
      check (KeyedOverride.merge collisionKey previous added == expected)
        "hash collision changed a retained payload or duplicate decision"
      cases := cases + 1
  let added := (List.range 20000).map fun index => (index % 5000, index)
  let previous := [(2, 0), (5001, 3), (5001, 4), (2, 1)]
  let expected := (List.range 5000).reverse.map (fun key => (key, 15000 + key)) ++ [(5001, 3), (5001, 4)]
  check (KeyedOverride.merge Prod.fst previous added == expected)
    "large override lost latest complete payloads or untouched prior duplicates"
  IO.println (Json.mkObj [("passed", toJson true), ("sequencePairs", toJson cases),
    ("ordinaryAndCollidingChecks", toJson (2 * cases)), ("largeInput", toJson (20000 : Nat)),
    ("generationModelCalls", toJson (0 : Nat)), ("productionAdoption", toJson false)]).compress
  pure 0
