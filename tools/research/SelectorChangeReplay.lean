import tools.SharedCoverageInput
import tools.DeferredCoverage
import Lean.Data.Json.Parser
open Lean SharedCoverage
open SharedCoverage.Deferred SharedCoverage.Deferred.Sparse

namespace Eggshell.Research.SelectorChangeReplay

def scanStep (prior : Selection p) (stored : Values prior) (seen : Known prior)
    (state : Option (Score prior (evaluation prior)) × Nat) (index : Fin p.offers.size) :=
  match Sparse.score? prior stored seen index,state.1 with
  | none,_ => state
  | some next,none => (some next,state.2)
  | some next,some previous =>
      (if betterScore next previous then some next else state.1,state.2+1)

theorem counted_scan_exact (prior : Selection p) (stored : Values prior) (seen : Known prior)
    (indices : List (Fin p.offers.size)) (state : Option (Score prior (evaluation prior)) × Nat) :
    (indices.foldl (scanStep prior stored seen) state).1 =
      indices.foldl (Sparse.step prior stored seen) state.1 := by
  have step (state : Option (Score prior (evaluation prior)) × Nat) (index : Fin p.offers.size) :
      (scanStep prior stored seen state index).1 = Sparse.step prior stored seen state.1 index := by
    unfold scanStep Sparse.step
    cases Sparse.score? prior stored seen index <;> cases state.1 <;> rfl
  induction indices generalizing state with
  | nil => rfl
  | cons head tail ih => simp only [List.foldl_cons,ih,step]

def replay (p : Problem) : IO Json := do
  let some initial := empty? p | throw (IO.userError "fixed cost does not fit")
  let started ← IO.monoMsNow
  let prepared := Sparse.layout p
  let mut state : (prior : Selection p) × Values prior := ⟨initial,Sparse.values initial⟩
  let mut iterations : Array Json := #[]
  let mut visited := 0
  let mut compared := 0
  let mut totalTouched := 0
  let mut finished := false
  for round in [:p.offers.size+1] do
    let prior := state.1
    let stored := state.2
    let seen := Deferred.known prior
    let found := (List.finRange p.offers.size).foldl (scanStep prior stored seen) (none,0)
    visited := visited+p.offers.size
    compared := compared+found.2
    let some score := found.1 | finished := true; break
    let next := score.proposal.result
    let nodes := prepared.nodes.changed stored.base.nodeIndex p.offers[score.index].closure
    let cues := prepared.cues.changed stored.base.cueIndex p.offers[score.index].covers
    let touched := Eggshell.hashDistinct (nodes++cues)
    let updated := stored.advance prepared next score.index rfl
    let selected := Std.HashSet.ofList next.selected
    let pending := touched.filter (!selected.contains ·)
    let mut scalarChanges := 0
    let mut newlyFeasible := 0
    for index in pending do
      if stored.costs[index] != updated.costs[index] || stored.gains[index] != updated.gains[index] then
        scalarChanges := scalarChanges+1
      let before := stored.afterCost index
      let after := updated.afterCost index
      if !(before.1 ≤ p.limit.1 && before.2 ≤ p.limit.2) &&
          after.1 ≤ p.limit.1 && after.2 ≤ p.limit.2 then newlyFeasible := newlyFeasible+1
    totalTouched := totalTouched+pending.length
    iterations := iterations.push (Json.mkObj [
      ("round",toJson round),("winner",toJson score.index.val),("comparisons",toJson found.2),
      ("nodeTouched",toJson nodes.length),("cueTouched",toJson cues.length),
      ("unselectedTouched",toJson pending.length),("scalarChanges",toJson scalarChanges),
      ("newlyFeasible",toJson newlyFeasible),("selectedCost",toJson updated.base.beforeCost)])
    state := ⟨next,updated⟩
  unless finished do throw (IO.userError "selection exhausted its finite candidate bound")
  let chosen := SharedCoverage.prefer state.1 (SharedCoverage.bestSingleton initial)
  let elapsed := (← IO.monoMsNow)-started
  let some reference := SharedCoverage.choose? p | throw (IO.userError "native reference declined replay")
  unless chosen.selected.map (·.val) == reference.selected.map (·.val) do
    throw (IO.userError "counted replay changed the selected sequence")
  return Json.mkObj [
    ("offers",toJson p.offers.size),("nodes",toJson p.costs.size),("cues",toJson p.weights.size),
    ("rounds",toJson iterations.size),("visitedCandidates",toJson visited),("scoreComparisons",toJson compared),
    ("totalUnselectedTouched",toJson totalTouched),("iterations",toJson iterations),
    ("selected",toJson (chosen.selected.map (·.val))),("sameNativeReferenceSequence",toJson true),
    ("instrumentedReplayMs",toJson elapsed),("productionLatencyClaim",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]

end Eggshell.Research.SelectorChangeReplay

#print axioms SharedCoverage.Input.decode_problem
#print axioms Eggshell.Research.SelectorChangeReplay.counted_scan_exact

def main (args : List String) : IO Unit := do
  let [input,output] := args | throw (IO.userError "captured input, new output directory")
  let root := System.FilePath.mk output
  unless !(← root.pathExists) do throw (IO.userError "keep previous replay")
  let path := System.FilePath.mk input
  unless (← path.metadata).byteSize ≤ 64*1024*1024 do throw (IO.userError "unexpectedly large replay input")
  let raw ← IO.ofExcept (Json.parse (← IO.FS.readFile path) >>= fromJson? (α := SharedCoverage.Input.RawProblem))
  let problem ← IO.ofExcept raw.decode
  unless SharedCoverage.Input.ofProblem problem == raw do throw (IO.userError "replay input did not round-trip exactly")
  let result ← Eggshell.Research.SelectorChangeReplay.replay problem
  IO.FS.createDir root
  IO.FS.writeFile (root / "result.json") result.pretty
