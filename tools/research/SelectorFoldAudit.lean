import tools.DeferredCoverage
import Lean.Data.Json.FromToJson
open Lean Eggshell SharedCoverage

#print axioms Deferred.weighted_exact
#print axioms Deferred.after_benefit_fold_compiled
#print axioms Deferred.benefit_fold_compiled
#print axioms Deferred.choose_deferred_compiled

private def check (valid : Bool) (message : String) : IO Unit :=
  unless valid do throw (IO.userError message)

/-- Literal parent formula, without calling the function replaced by csimp. -/
private def original {p : Problem} {prior : Selection p}
    (cached : Evaluation prior) (index : Fin p.offers.size) : Nat :=
  let fresh := hashDistinct (p.offers[index].covers.filter fun cue => !cached.cueIndex.contains cue)
  cached.beforeBenefit + (fresh.map fun cue => p.weights[cue]).sum

private def scenario (population : Nat) : IO Json := do
  let costs := (Array.range 32).map (fun i => (i+1,2*i+1))
  let weights := (Array.range population).map (fun i => 2^300+i+1)
  let offers : Array (Offer costs.size weights.size) := (Array.range 64).map fun i => {
    closure := (List.finRange costs.size).filter fun node => node.val%16 == i%16
    covers := let first := (List.finRange weights.size).filter fun cue => cue.val%4 == i%4
      first ++ first.take 4}
  let p : Problem := {costs,weights,offers,limit := (100000,400000)}
  let some initial := empty? p | throw (IO.userError "empty problem rejected")
  let mut selected := initial
  let mut records := #[]
  for stage in [0:4] do
    let cached := evaluation selected
    let indices := List.finRange p.offers.size
    let before ← IO.monoMsNow
    let reference := indices.map (original cached)
    check (0 < reference.sum) "reference was not evaluated before timing"
    let referenceMs := (← IO.monoMsNow)-before
    let started ← IO.monoMsNow
    let folded := indices.map (Deferred.afterBenefitFold cached)
    check (folded == reference) "fold changed exact marginal values or their order"
    let foldedMs := (← IO.monoMsNow)-started
    records := records.push (Json.mkObj [("selected",toJson selected.selected.length),
      ("referenceMs",toJson referenceMs),("foldedMs",toJson foldedMs),("exactAllMarginals",toJson true)])
    let some index := indices[stage]? | throw (IO.userError "missing next fixture offer")
    let some next := extend? selected index | throw (IO.userError "fixture extension no longer fits")
    selected := next
  return Json.mkObj [("cues",toJson population),("offers",toJson offers.size),
    ("largeWeights",toJson true),("duplicateCues",toJson true),("states",toJson records)]

def main (args : List String) : IO UInt32 := do
  try
    let [destination] := args | throw (IO.userError "SelectorFoldAudit NEW-DIRECTORY")
    let root := System.FilePath.mk destination
    check (root.isAbsolute && !(← root.pathExists)) "new weight-fold audit required"
    IO.FS.createDir root
    let mut records := #[]
    for population in [64,512,4096,16384] do
      let record ← scenario population
      records := records.push record
      IO.println record.compress
    IO.FS.writeFile (root / "results.json") (Json.mkObj [("synthetic",toJson true),
      ("scenarios",toJson records),("answeringModelCalls",toJson (0 : Nat)),("productionAdoption",toJson false)]).pretty
    return 0
  catch error => IO.eprintln error.toString; return 1
