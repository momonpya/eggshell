import tools.SharedCoverageInput
import tools.VerifiedWinnerCoverage
import Lean.Data.Json.Parser
open Lean SharedCoverage SharedCoverage.Deferred

private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= fun s => IO.ofExcept (Json.parse s)

private def measured (prior : Selection p) (stored : Sparse.Values prior)
    (index : Fin p.offers.size) (winner : Option (Score prior (evaluation prior))) : Json := Id.run do
  let after := stored.afterCost index
  let fits := decide (after.1 ≤ p.limit.1 ∧ after.2 ≤ p.limit.2)
  let selected := prior.selected.contains index
  let candidate := Sparse.score? prior stored (known prior) index
  let reason := if selected then "already-selected" else if !fits then "budget"
    else if stored.gains[index] == 0 then "zero-gain" else "eligible"
  return Json.mkObj [("id",toJson index.val),("reason",toJson reason),
    ("beforeCost",toJson stored.base.beforeCost),("marginalCost",toJson stored.costs[index]),
    ("afterCost",toJson after),("gain",toJson stored.gains[index]),
    ("winner",toJson (winner.map (·.index.val))),
    ("winnerGain",toJson (winner.map (·.gain))),("winnerCharge",toJson (winner.map (·.charge))),
    ("beatsWinner",toJson (match candidate,winner with
      | some candidate,some winner => betterScore candidate winner
      | _,_ => false))]

/- The probe selects report rows only. Winner selection always calls the
unchanged production score comparison on every offer. The final sequence is
checked against the public production entry, including best-singleton choice. -/
def main (args : List String) : IO Unit := do
  let [planPath,unitText,destination] := args | throw (IO.userError "captured product plan, diagnostic unit and fresh output")
  let some unit := unitText.toNat? | throw (IO.userError "invalid probe unit")
  let output := System.FilePath.mk destination
  check (!(← output.pathExists)) "preserve previous selection decision audit"
  let captured := (← read (.mk planPath)).getObjValD "data"
  let raw : SharedCoverage.Input.RawProblem ← IO.ofExcept (captured.getObjValAs? _ "selectorInput")
  let p ← IO.ofExcept raw.decode
  check (SharedCoverage.Input.ofProblem p == raw) "captured selector input changed during decoding"
  let some target := p.offers[unit]? | throw (IO.userError "probe outside captured offers")
  let targetCues := target.covers.flatMap fun cue =>
    if h : cue.val+1 < p.weights.size then [cue,⟨cue.val+1,h⟩] else [cue]
  let probes := (List.finRange p.offers.size).filter fun index =>
    p.offers[index].covers.any targetCues.contains
  check (!probes.isEmpty) "probe has no original relevance cells"
  let some initial := empty? p | throw (IO.userError "captured fixed cost exceeds limit")
  let layout := Sparse.layout p
  let mut state : (prior : Selection p) × Sparse.Values prior := ⟨initial,Sparse.values initial⟩
  let mut lastEligible : Std.HashMap Nat Json := {}
  let mut initialProbes := #[]
  let mut transitions := #[]
  let mut previouslyEligible : Std.HashSet Nat := {}
  let mut winners := #[]
  let started ← IO.monoMsNow
  let mut finished := false
  for round in [:p.offers.size+1] do
    let prior := state.1
    let stored := state.2
    let winner := Sparse.best prior stored
    for index in probes do
      let measurement := measured prior stored index winner
      let eligible := measurement.getObjValD "reason" == toJson "eligible"
      if round == 0 then initialProbes := initialProbes.push measurement
      if eligible then
        lastEligible := lastEligible.insert index.val (measurement.setObjVal! "round" (toJson round))
      else if previouslyEligible.contains index.val then
        transitions := transitions.push (Json.mkObj [("round",toJson round),("current",measurement),
          ("lastEligible",lastEligible[index.val]?.getD Json.null)])
      previouslyEligible := if eligible then previouslyEligible.insert index.val else previouslyEligible.erase index.val
    let some score := winner | finished := true; break
    winners := winners.push score.index.val
    let next := score.proposal.result
    state := ⟨next,stored.advance layout next score.index rfl⟩
  check finished "decision audit exceeded finite offer bound"
  let greedy := state.1
  let singleton := bestSingleton initial
  let chosen := prefer greedy singleton
  let some reference := SharedCoverage.choose? p | throw (IO.userError "production reference declined captured problem")
  check (chosen.selected.map (·.val) == reference.selected.map (·.val)) "instrumented decision sequence differs from production"
  let finalValues := Sparse.values chosen
  let possible := Sparse.best chosen finalValues
  let finalProbes := probes.map fun index => measured chosen finalValues index possible
  IO.FS.writeFile output (Json.mkObj [("probeUnit",toJson unit),("probeOffers",toJson (probes.map (·.val))),
    ("greedyWinners",toJson winners),("greedyCost",toJson (cost p greedy.selected)),
    ("singletonCost",toJson (cost p singleton.selected)),("greedyBenefit",toJson (benefit p greedy.selected)),
    ("singletonBenefit",toJson (benefit p singleton.selected)),
    ("chosenBranch",toJson (if benefit p greedy.selected < benefit p singleton.selected then "singleton" else "greedy")),
    ("chosenCost",toJson (cost p chosen.selected)),("selected",toJson (chosen.selected.map (·.val))),
    ("initialProbes",toJson initialProbes),("transitions",toJson transitions),("finalProbes",toJson finalProbes),
    ("positiveFeasibleAfterChoice",toJson possible.isSome),("sameProductionSequence",toJson true),
    ("elapsedMs",toJson ((← IO.monoMsNow)-started)),("newActualHookCalls",toJson (0 : Nat)),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
  IO.println s!"Explained {probes.length} competing offers through {winners.size} unchanged production choices"
