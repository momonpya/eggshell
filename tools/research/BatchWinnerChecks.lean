import tools.research.BatchWinner
import tools.SelectionRating
import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean StableWinnerIndex

#print axioms Batch.Patch.insert_lookup
#print axioms Batch.Patch.apply_lookup
#print axioms Batch.update_lookup
#print axioms Batch.update_values_exact
#print axioms Batch.update_best_exact

namespace BatchWinnerChecks
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def rating (size scale wave : Nat) (index : Fin size) : Option (SharedCoverage.Rating.Key size) :=
  if (index.val+wave)%17 == 0 then none else some {
    index,gain := scale*(1+(index.val*37+wave*13)%1000),
    charge := if index.val%31 == 0 then 0 else (1+(index.val*71+wave)%7000)*512000}

def keys (depth scale wave : Nat) : Array (Option (SharedCoverage.Rating.Key (2^depth))) :=
  Array.ofFn (rating (2^depth) scale wave)

@[noinline,nospecialize] def reference {α : Type} {order : Preference α} {depth : Nat}
    (cache : Cache order depth) (indices : List Nat)
    (value : Nat → Option α) : Cache order depth := Batch.sequential cache indices value

def controls : IO Nat := do
  let mut count := 0
  for depth in [0:7] do
    let order := SharedCoverage.Rating.preference (2^depth)
    let cache := build order depth (keys depth 123456789 0)
    let variants := [[],[0],[2^depth-1],(List.range (2^depth)),(List.range (2^depth)).reverse,
      [0,0,2^depth-1,0],(List.range (2^depth)).filter (fun i => i%3 == 0)]
    for indices in variants do
      for wave in [1:5] do
        let values := keys depth 123456789 wave
        let value := fun index => values[index]?.getD none
        let expected := reference cache indices value
        let actual := Batch.update cache indices value
        check (actual.tree.values == expected.tree.values && actual.best == expected.best)
          "batched update changed a leaf or tie-stable winner"
        count := count+1
  return count

def timed (input : IO.Ref (Cache (SharedCoverage.Rating.preference (2^14)) 14))
    (indices : List Nat) (value : Nat → Option (SharedCoverage.Rating.Key (2^14))) (batch : Bool) :
    IO (Cache (SharedCoverage.Rating.preference (2^14)) 14 × Nat) := do
  let cache ← input.get
  let began ← IO.monoNanosNow
  let output ← (← IO.mkRef (if batch then Batch.update cache indices value else reference cache indices value)).get
  let ended ← IO.monoNanosNow
  return (output,ended-began)

def run (input output : System.FilePath) : IO Unit := do
  check (!(← output.pathExists)) "keep the previous component result"
  let parameters ← IO.ofExcept (Json.parse (← IO.FS.readFile input))
  let scale ← IO.ofExcept (parameters.getObjValAs? Nat "scale")
  let controls ← controls
  let count := 2^14
  let order := SharedCoverage.Rating.preference count
  let initial ← IO.mkRef (build order 14 (keys 14 scale 0))
  let groups := [("empty",[]),("one",[count/2]),
    ("sparse",(List.range 16).map (fun i => (i*997)%count)),
    ("cluster",(List.range 1024).map (2048+·)),
    ("dense",(List.range count).reverse),
    ("duplicates",(List.range 1024)++(List.range 1024))]
  let mut rows := #[]
  for (name,indices) in groups do
    for repetition in [:3] do
      let values ← IO.mkRef (keys 14 scale (repetition+1))
      let current ← values.get
      let value := fun index => current[index]?.getD none
      let batchFirst := repetition%2 == 1
      let first ← timed initial indices value batchFirst
      let second ← timed initial indices value (!batchFirst)
      let (before,after) := if batchFirst then (second,first) else (first,second)
      check (before.1.tree.values == after.1.tree.values && before.1.best == after.1.best)
        "complete candidate rating leaves or winner changed"
      let patch := Batch.replacements 14 indices value
      rows := rows.push (Json.mkObj [("group",toJson name),("repetition",toJson repetition),
        ("batchFirst",toJson batchFirst),("changes",toJson indices.length),
        ("referenceJoins",toJson (14*indices.length)),("batchJoins",toJson patch.joins),
        ("referenceNs",toJson before.2),("batchNs",toJson after.2),
        ("allLeavesAndStableWinnerEqual",toJson true)])
  IO.FS.writeFile output (Json.mkObj [("controls",toJson controls),("rows",toJson rows),
    ("scaleSource",parameters.getObjValD "scaleSource"),("scale",toJson scale),
    ("leaves",toJson count),("batchPreparationIncluded",toJson true),
    ("syntheticUpdatePatterns",toJson true),("actualHookSpeedComparison",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).compress
end BatchWinnerChecks

def main (args : List String) : IO Unit := do
  let [input,output] := args | throw (IO.userError "batch winner INPUT OUTPUT")
  BatchWinnerChecks.run (.mk input) (.mk output)
