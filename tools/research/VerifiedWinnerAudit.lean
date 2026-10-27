import tools.SharedCoverageInput
import tools.VerifiedWinnerCoverage
import Lean.Data.Json.Parser
open Lean SharedCoverage

#print axioms SharedCoverage.Deferred.VerifiedWinner.choose_exact
#print axioms SharedCoverage.Deferred.VerifiedWinner.State.best_exact
#print axioms SharedCoverage.Deferred.VerifiedWinner.State.advance
#print axioms SharedCoverage.Deferred.VerifiedWinner.State.clear_decreases
#print axioms SharedCoverage.Budget.no_reactivation

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def fixture (count population groups budget : Nat) : Problem := Id.run do
  let costs := (Array.range (count+2)).map fun i =>
    if i == 0 then (40,80) else if i%11 == 0 then (0,0) else (i%7+1,i%9+2)
  let weights := (Array.range population).map fun i => if i%13 == 0 then 0 else 2^300+i%19
  let offers : Array (Offer costs.size weights.size) := (Array.range count).map fun i => {
    closure := (List.finRange costs.size).filter fun node => node.val == 0 || node.val == i+1
    covers := let selected := (List.finRange weights.size).filter fun cue => cue.val%groups == i%groups
      selected ++ selected.take 4}
  return {costs,weights,offers,limit := (budget,2*budget)}

private def compare (p : Problem) : IO Unit := do
  let reference := SharedCoverage.Deferred.Sparse.choose? p
  let candidate := SharedCoverage.choose? p
  let direct := SharedCoverage.Deferred.VerifiedWinner.choose? p
  let selected := fun (result : Option (Selection p)) => result.map fun selection => selection.selected.map (·.val)
  check (selected candidate == selected reference && selected direct == selected reference)
    "verified public selector changed the full ordered sequence"

def main (args : List String) : IO Unit := do
  let [input,output] := args | throw (IO.userError "fixed selector input and new result directory required")
  let root := System.FilePath.mk output
  check (!(← root.pathExists)) "preserve previous native verification"
  let raw ← IO.ofExcept (Json.parse (← IO.FS.readFile (.mk input)) >>= fromJson? (α := SharedCoverage.Input.RawProblem))
  let problem ← IO.ofExcept raw.decode
  let mut count := 0
  for size in [0,1,7,32,64,128] do
    for population in [0,8,128,512] do
      for budget in [0,10,50,140] do
        compare (fixture size population 8 budget)
        count := count+1
  compare problem
  let some reference := SharedCoverage.Deferred.Sparse.choose? problem | throw (IO.userError "reference declined fixed input")
  let mut timings := #[]
  for round in [:3] do
    for cached in (if round%2 == 0 then [false,true] else [true,false]) do
      let started ← IO.monoMsNow
      let selected := if cached then SharedCoverage.choose? problem else SharedCoverage.Deferred.Sparse.choose? problem
      let result := selected.map (·.selected.map (·.val))
      check (result == some (reference.selected.map (·.val))) "timed selector changed ordered result"
      timings := timings.push (round,cached,(← IO.monoMsNow)-started)
  IO.FS.createDir root
  IO.FS.writeFile (root / "result.json") (Json.mkObj [
    ("allPassed",toJson true),("syntheticCases",toJson count),("actualInputExactSequence",toJson true),
    ("publicAndDirectEntriesChecked",toJson true),("fullOrderedRefinementProved",toJson true),
    ("timingsRoundCachedMs",toJson timings),("productionLatencyClaim",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
