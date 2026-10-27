import Eggshell.Handoff
open Lean Eggshell Eggshell.Plugin.SharedRangeAdapter

#print axioms PreparedCueIndex.Prepared.one_exact
#print axioms PreparedCueIndex.Prepared.many_exact
#print axioms base_pieces_exact
#print axioms bonus_pieces_exact
#print axioms problem_prepared_compiled
#print axioms bundle_recipe_indexed_exact

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

def main (args : List String) : IO Unit := do
  let [output] := args | throw (IO.userError "new output directory required")
  let root := System.FilePath.mk output
  unless !(← root.pathExists) do throw (IO.userError "preserve prior incidence audit")
  IO.FS.createDir root
  let values := (Array.range 1024).flatMap fun i => #[(toString (i%17),i),(toString (i%17),i)]
  let keyOf := fun (entry : String × Nat) => entry.1
  let index := PreparedCueIndex.prepare keyOf values
  let mut positive := 0
  for family in List.range 19 do
    let key := toString family
    let accept := fun (entry : String × Nat) => entry.1 == key && entry.2%3 == 1
    let actual := index.one key accept
    let expected := values.toList.filter accept
    check (actual == expected) "single-key postings changed input order or duplicate values"
    positive := positive+actual.length
  check (positive > 0) "single-key audit had no positive values"
  let keys := ["1","6","1","12","missing","6"]
  let accept := fun (entry : String × Nat) => keys.contains entry.1 && entry.2%5 == 2
  let selected := index.many keys accept
  check (selected == values.toList.filter accept && !selected.isEmpty)
    "multi-key union changed original order, ties or duplicates"
  let empty := PreparedCueIndex.prepare (fun (entry : String × Nat) => entry.1) #[]
  check ((empty.many keys (fun _ => false)).isEmpty && (index.one "absent" (fun _ => false)).isEmpty)
    "empty or absent-key postings returned invented values"
  let pieces := (Array.range 4096).map fun i => ({
    family := i%31,first := i%97,last := i%97+3,weight := i+1,baseWeight := if i%7 == 0 then 0 else i+1
    } : CuePiece)
  let entries := pieces.toList.zipIdx.toArray
  let prepared := PreparedCueIndex.prepare cueFamilyKey entries
  let mut originalChecks := 0
  for family in List.range 33 do
    let unit : UnitPlan := {
      family,ranges := [(0,12),(20,40),(41,99)]
      slice := {owner := none,keys := [],text := "",members := [],visibleKeys := []}}
    let actual := basePiecesPrepared entries prepared unit
    let expected := entries.toList.filter (basePieceAccept unit)
    check (actual.map Prod.snd == expected.map Prod.snd) "original cue incidence or order changed"
    originalChecks := originalChecks+actual.length
  check (originalChecks > 0) "range audit had no positive original cues"
  IO.FS.writeFile (root / "result.json") (Json.mkObj [
    ("duplicateInputValues",toJson values.size),("positiveSingleKeyValues",toJson positive),
    ("multiKeyPositiveValues",toJson selected.length),("originalCueChecks",toJson originalChecks),
    ("sameOrderAndDuplicates",toJson true),("emptyAndMissingKeysChecked",toJson true),
    ("modelCalls",toJson (0 : Nat)),("warmCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
