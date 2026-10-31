import Lean
import tools.research.CarriedSelectionValue
open Lean SharedCoverage

#print axioms SharedCoverage.CarriedSelectionValue.bestSingleton_exact

private def ensure (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)

/-- Explicit old entry: the csimp theorem rewrites bestSingleton, not this
independent call to the unchanged reference recursion. -/
@[noinline] private def reference (initial : Selection p) : Selection p :=
  singletonScan initial initial (List.finRange p.offers.size)

private def fixture (nodes count mode : Nat) : Problem := Id.run do
  let costs := (Array.range nodes).map fun i => (i%3+1,i%5+1)
  let weights := (Array.range nodes).map fun i => if mode%4 == 0 then 0 else (i%7+1)*(2^mode)
  let allNodes := List.finRange costs.size
  let allCues := List.finRange weights.size
  let offers := (Array.range count).map fun i =>
    let closure := if i == 0 then allNodes ++ allNodes.take 3 else (allNodes.drop (i%nodes)).take (mode%8+1)
    let covers := if i == 0 then allCues ++ allCues.take 3 else (allCues.drop (i%nodes)).take (mode%8+1)
    ({closure,covers} : Offer costs.size weights.size)
  let limit := if mode%5 == 0 then (nodes/2,nodes/2) else (nodes*3+3,nodes*5+5)
  return ⟨costs,weights,offers,(0,0),limit⟩

private def timed (initial : Selection p) (candidate : Bool) : IO (Nat × List Nat) := do
  let began ← IO.monoNanosNow
  let result ← IO.mkRef ((if candidate then CarriedSelectionValue.bestSingleton initial else reference initial).selected.map Fin.val)
  let stopped ← IO.monoNanosNow
  return (stopped-began,← result.get)

def main (args : List String) : IO Unit := do
  let [output] := args | throw (IO.userError "fresh native audit output required")
  let path : System.FilePath := .mk output
  ensure (!(← path.pathExists)) "preserve the carried value audit"
  let mut cases := 0
  for nodes in [0,1,3,17,64] do
    for offers in [0,1,9,65] do
      for mode in [0,1,5,9,65] do
        let p := fixture nodes offers mode
        -- The generic empty-domain cases are checked without an assumed offer.
        let some initial := empty? p | throw (IO.userError "missing initial")
        ensure ((reference initial).selected == (CarriedSelectionValue.bestSingleton initial).selected &&
          (reference initial).selected == (SharedCoverage.bestSingleton initial).selected) "ordered singleton mismatch"
        if positive : 0 < p.offers.size then
          if let some prior := extend? initial ⟨0,positive⟩ then
            ensure ((reference prior).selected == (CarriedSelectionValue.bestSingleton prior).selected)
              "nonempty initial changed"
        cases := cases+1
  let p := fixture 2048 8640 66
  let some initial := empty? p | throw (IO.userError "large fixture has no initial")
  let mut timings := #[]
  for repetition in [:3] do
    for reverse in [false,true] do
      let order := if reverse then [true,false] else [false,true]
      let mut old := (0,[])
      let mut candidate := (0,[])
      for changed in order do
        let result ← timed initial changed
        if changed then candidate := result else old := result
      ensure (old.2 == candidate.2) "timed native selections differ"
      timings := timings.push (Json.mkObj [("repetition",toJson repetition),("reversed",toJson reverse),
        ("referenceNs",toJson old.1),("candidateNs",toJson candidate.1),("selected",toJson old.2)])
  IO.FS.createDirAll path.parent.get!
  IO.FS.writeFile path (Json.mkObj [("syntheticCases",toJson cases),("orderedResultsExact",toJson true),
    ("largeSynthetic",Json.mkObj [("nodes",toJson p.costs.size),("offers",toJson p.offers.size),("timings",toJson timings)]),
    ("realProblemReplay",toJson false),("actualHookCalls",toJson (0 : Nat)),
    ("tokenImprovementMeasured",toJson false),("adopted",toJson false)]).pretty
  IO.println "Exact carried-value singleton selection passed native synthetic checks"
