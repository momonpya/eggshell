import Eggshell.CanonicalSourceRecipe
open Lean Eggshell.Synapses CanonicalSource

private def check (yes : Bool) (message : String) : IO Unit :=
  unless yes do throw (IO.userError message)

private def rows (database session : String) (selected : List Nat) : Array StoredRow :=
  let file : File := ⟨"source.cc",String.ofList (List.replicate 64 'a'),128⟩
  let text := #["","if (ready) {","  use();","}","","next();",""]
  selected.toArray.map fun position =>
    ⟨⟨file,position+1⟩,text[position]!,
      #[⟨⟨session,"turn","call"⟩,⟨database,"same-owner","same-work",position*8,position*8+8⟩⟩]⟩

def main : IO Unit := do
  let left ← IO.ofExcept (Recipe.compile (rows (String.ofList (List.replicate 64 'b')) "left" [0,1,2,3,4]))
  let right ← IO.ofExcept (Recipe.compile (rows (String.ofList (List.replicate 64 'c')) "right" [1,2,3,4,5,6]))
  let merged ← IO.ofExcept (Delivery.merge (left.rows++right.rows))
  let entries ← IO.ofExcept (Recipe.combine left.rows right.rows merged left.records right.records)
  let checked ← IO.ofExcept (Recipe.check merged entries)
  check (merged.size == 7) "federation duplicated or lost original rows"
  for index in List.finRange merged.size do
    check (checked.catalogue.flatten.contains index) "federation lost a purchasable original row"
  check ((merged.toList.filter (·.origins.size == 2)).length == 4)
    "federation discarded independent DB/occurrence provenance"
  check (!(Recipe.check merged [⟨[1000],none,1001⟩]).isOk) "forged prepared layout was accepted"
  let conflict := right.rows.map fun row => if row.key.line == 2 then {row with code := "different"} else row
  check (!(Delivery.merge (left.rows++conflict)).isOk) "conflicting original code was merged"
  IO.println (Json.mkObj [("rows",toJson merged.size),("allRowsPurchasable",toJson true),
    ("independentOriginsKept",toJson true),("forgedLayoutRejected",toJson true),
    ("conflictingCodeRejected",toJson true),("authorityAdded",toJson false)]).compress
