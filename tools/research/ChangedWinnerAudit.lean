import tools.SharedCoverageInput
import tools.ChangedWinnerCoverage
import Lean.Data.Json.Parser
open Lean SharedCoverage

#print axioms StableWinnerIndex.Tree.best_exact
#print axioms SharedCoverage.Deferred.ChangedWinner.updateCache_exact
#print axioms SharedCoverage.Rating.better_trans
#print axioms SharedCoverage.Rating.better_neg_trans

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def compare (p : Problem) : IO Unit := do
  let reference := SharedCoverage.Deferred.Sparse.choose? p
  let candidate := SharedCoverage.Deferred.ChangedWinner.choose? p
  check (candidate.map (fun row => row.1.selected.map (·.val)) == reference.map (·.selected.map (·.val)))
    "point-updated winner cache changed the full selected sequence"

private def fixture (count population groups budget : Nat) : Problem := Id.run do
  let costs := (Array.range (count+2)).map fun i =>
    if i == 0 then (40,80) else if i%11 == 0 then (0,0) else (i%7+1,i%9+2)
  let weights := (Array.range population).map fun i => if i%13 == 0 then 0 else 2^300+i%19
  let offers : Array (Offer costs.size weights.size) := (Array.range count).map fun i => {
    closure := (List.finRange costs.size).filter fun node => node.val == 0 || node.val == i+1
    covers := let selected := (List.finRange weights.size).filter fun cue => cue.val%groups == i%groups
      selected ++ selected.take 4}
  return {costs,weights,offers,limit := (budget,2*budget)}

def main (args : List String) : IO Unit := do
  let [input,output] := args | throw (IO.userError "actual selector input, new result directory")
  let root := System.FilePath.mk output
  check (!(← root.pathExists)) "preserve previous winner comparison"
  let raw ← IO.ofExcept (Json.parse (← IO.FS.readFile (.mk input)) >>= fromJson? (α := SharedCoverage.Input.RawProblem))
  let problem ← IO.ofExcept raw.decode
  let mut fixtures := 0
  for count in [0,1,7,32,64,128] do
    for population in [0,8,128,512] do
      for budget in [0,10,50,140] do
        compare (fixture count population 8 budget)
        fixtures := fixtures+1
  compare problem
  let some reference := SharedCoverage.Deferred.Sparse.choose? problem | throw (IO.userError "missing reference selection")
  let mut timings : Array Json := #[]
  for round in [:3] do
    for fast in (if round%2 == 0 then [false,true] else [true,false]) do
      let started ← IO.monoMsNow
      let (chosen,stats) ← if fast then do
        let some result := SharedCoverage.Deferred.ChangedWinner.choose? problem | throw (IO.userError "winner cache failed")
        pure result
      else do
        let some chosen := SharedCoverage.Deferred.Sparse.choose? problem | throw (IO.userError "full scan failed")
        pure (chosen,({} : SharedCoverage.Deferred.ChangedWinner.Statistics))
      let elapsed := (← IO.monoMsNow)-started
      check (chosen.selected.map (·.val) == reference.selected.map (·.val)) "timed sequence differs"
      timings := timings.push (Json.mkObj [("round",toJson round),("pointUpdates",toJson fast),
        ("elapsedMs",toJson elapsed),("statistics",toJson stats)])
  IO.FS.createDir root
  IO.FS.writeFile (root / "result.json") (Json.mkObj [
    ("syntheticCases",toJson fixtures),("actualInputExactSequence",toJson true),("timings",toJson timings),
    ("productionConnected",toJson false),("fullOrderedRefinementProved",toJson false),
    ("productionLatencyClaim",toJson false),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
