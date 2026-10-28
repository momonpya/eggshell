import tools.SharedCoverageInput
import tools.VerifiedWinnerCoverage
import Lean.Data.Json.Parser
open Lean SharedCoverage

#print axioms SharedCoverage.Evaluation.advance_exact
#print axioms SharedCoverage.Deferred.VerifiedWinner.choose_exact
#print axioms Eggshell.DistinctPostings.collect_exact

private def check (yes : Bool) (message : String) : IO Unit :=
  unless yes do throw (IO.userError message)

private def fixture (count cues budget : Nat) : Problem := Id.run do
  let costs := (Array.range (count+1)).map fun index =>
    if index == 0 then (9,18) else if index%4 == 0 then (0,0) else (index%7+1,index%9+2)
  let weights := (Array.range cues).map fun index => if index%5 == 0 then 0 else 2^300+index%11
  let offers := (Array.range count).map fun index =>
    let nodes := (List.finRange costs.size).filter fun node => node.val == 0 || node.val == index+1
    let covered := (List.finRange weights.size).filter fun cue => cue.val%3 == index%3
    ({closure := nodes ++ nodes.take 1,covers := covered ++ covered.take 2} : Offer costs.size weights.size)
  return {costs,weights,offers,fixed := (1,2),limit := (budget,2*budget)}

/-- Independent scan entry: it never calls Sparse.Values.advance or the
tournament. It includes zero marginal costs, large integers and stable ties. -/
private def scan (p : Problem) : Option (Selection p) := do
  let initial ← empty? p
  return prefer (fill p.offers.size initial) (bestSingleton initial)

def main (args : List String) : IO Unit := do
  let [parent,candidate,expectedPath,output] := args |
    throw (IO.userError "AggregateDeltaAudit PARENT-INPUT CANDIDATE-INPUT EXPECTED NEW-OUTPUT")
  let destination := System.FilePath.mk output
  check (!(← destination.pathExists)) "keep earlier aggregate result"
  IO.FS.createDir destination
  let expected ← IO.ofExcept (Json.parse (← IO.FS.readFile (.mk expectedPath)) >>= Json.getArr?)
  let mut cases := 0
  for size in [0,1,7,32] do
    for population in [0,8,64] do
      for budget in [0,10,50,140] do
        let p := fixture size population budget
        let selected := fun result => (result : Option (Selection p)).map (·.selected.map Fin.val)
        check (selected (SharedCoverage.choose? p) == selected (scan p)) "full scan order changed"
        cases := cases+1
  let mut results := #[]
  for (path,position) in #[(parent,0),(candidate,1)] do
    let data ← IO.ofExcept (Json.parse (← IO.FS.readFile (.mk path)))
    let raw ← IO.ofExcept (fromJson? (α := Input.RawProblem) ((data.getObjValD "data").getObjValD "selectorInput"))
    let p ← IO.ofExcept raw.decode
    let expectedRow := expected[position]!
    let expectedIds ← IO.ofExcept (expectedRow.getObjValAs? (List Nat) "selected")
    for round in [:3] do
      let forced ← IO.mkRef (none : Option (Selection p))
      let start ← IO.monoMsNow
      forced.set (SharedCoverage.choose? p)
      let elapsed := (← IO.monoMsNow)-start
      let some chosen ← forced.get | throw (IO.userError "recorded problem was rejected")
      let ids := chosen.selected.map Fin.val
      check (ids == expectedIds) "ordered selection differs from frozen old executable"
      let price := SharedCoverage.cost p chosen.selected
      check (toJson price == expectedRow.getObjValD "cost") "exact union cost differs"
      let rawNodes := chosen.selected.foldl (fun total index => total+p.offers[index].closure.length) 0
      let uniqueNodes := chosen.selected.foldl
        (fun total index => total+(Eggshell.hashDistinct p.offers[index].closure).length) 0
      let report := Json.mkObj [("input",toJson position),("round",toJson round),("selectionMs",toJson elapsed),
        ("selectedOffers",toJson ids.length),("cost",toJson price),("orderedSelectionEqual",toJson true),
        ("selectedRawNodeEntries",toJson rawNodes),("selectedUniqueNodeEntries",toJson uniqueNodes)]
      results := results.push report
      IO.FS.writeFile (destination / "result.json") (Json.mkObj [("syntheticCases",toJson cases),
        ("measurements",toJson results),("answeringModelCalls",toJson (0 : Nat)),
        ("productionAdoption",toJson false),("fullHookMeasured",toJson false)]).pretty
      IO.println report.compress
      (← IO.getStdout).flush
