import tools.research.ClosureFlow
import tools.research.PrincipalOffers
import tools.research.FrozenCanonicalBasis
import tools.research.OriginalPayloadBasis
import tools.research.AvailableDelivery
import tools.SharedCoverageInput
import tools.VerifiedWinnerCoverage
open Lean Eggshell Eggshell.Research SharedCoverage

private def read (p : System.FilePath) : IO Json := IO.FS.readFile p >>= fun s => IO.ofExcept (Json.parse s)
private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)

private def fixtures : IO Unit := do
  for vertices in [2:8] do
    for seed in [0:5] do
      let mut arcs := #[]
      for first in [:vertices] do
        for last in [:vertices] do
          let capacity := (first*17+last*31+seed*13)%11
          if first != last && capacity%3 != 0 then arcs := arcs.push ⟨first,last,capacity⟩
      let network : ClosureFlow.Network := ⟨vertices,0,vertices-1,arcs⟩
      let result ← ClosureFlow.solve network ((← IO.monoMsNow)+2000)
      let mut best := network.arcs.foldl (fun sum arc => sum+arc.capacity) 0
      for mask in [:2^(vertices-2)] do
        let selected := (Array.range vertices).map fun vertex =>
          vertex == 0 || (vertex+1 < vertices && (mask/2^(vertex-1))%2 == 1)
        best := min best (ClosureFlow.cutCapacity network selected)
      check (result.value == best) "native max-flow disagrees with exhaustive independent cuts"

private def select? (p : Problem) (indices : List (Fin p.offers.size)) : Option (Selection p) :=
  let selected := Eggshell.hashDistinct indices
  if fits : (cost p selected).1 ≤ p.limit.1 ∧ (cost p selected).2 ≤ p.limit.2 then
    some ⟨selected,HashDistinct.nodup indices,fits.1,fits.2⟩
  else none

private structure Point (p : Problem) where
  offers : List (Fin p.offers.size)
  reward : Nat
  charge : Nat

private def solve (p : Problem) (witnesses : Array (Sigma (PrincipalOffers.Witness p)))
    (domain : PrincipalOffers.Domain p) (byteAxis : Bool) (numerator denominator deadline : Nat) :
    IO (Point p × Json) := do
  check (denominator > 0) "closure slope denominator must be positive"
  let firstReward := 2+p.costs.size
  let vertices := firstReward+witnesses.size
  let rewardSum := witnesses.foldl (fun total witness => total+p.weights[witness.1]) 0
  let infinite := rewardSum*denominator+1
  let axis := fun node : Fin p.costs.size => if byteAxis then p.costs[node].2 else p.costs[node].1
  let mut arcs : Array ClosureFlow.Arc := #[]
  for node in List.finRange p.costs.size do
    if axis node > 0 then arcs := arcs.push ⟨2+node.val,1,axis node*numerator⟩
  for index in List.finRange witnesses.size do
    let witness := witnesses[index]
    arcs := arcs.push ⟨0,firstReward+index.val,p.weights[witness.1]*denominator⟩
    for node in domain.paidAt witness.2.offer do
      arcs := arcs.push ⟨firstReward+index.val,2+node.val,infinite⟩
  let network : ClosureFlow.Network := ⟨vertices,0,1,arcs⟩
  let started ← IO.monoMsNow
  let result ← ClosureFlow.solve network deadline
  let mut offers := []
  let mut reward := 0
  for index in List.finRange witnesses.size do
    if result.selected[firstReward+index.val]! then
      let witness := witnesses[index]
      check ((domain.paidAt witness.2.offer).all (fun node => result.selected[2+node.val]!))
        "a cut split its witnessed original closure"
      reward := reward+p.weights[witness.1]
      offers := witness.2.offer::offers
  let selectedOffers := Eggshell.hashDistinct offers
  let charge := (nodes p selectedOffers).foldl (fun total node => total+axis node) 0
  let cutCharge := (List.finRange p.costs.size).foldl (fun total node =>
    if result.selected[2+node.val]! then total+axis node else total) 0
  check (charge == cutCharge) "selected cut atoms differ from their original offers"
  check (result.value+reward*denominator == rewardSum*denominator+charge*numerator)
    "closure score and checked network objective disagree"
  let stats := Json.mkObj [("axis",toJson (if byteAxis then "bytes" else "characters")),
    ("numerator",toJson numerator),("denominator",toJson denominator),
    ("reward",toJson reward),("charge",toJson charge),("nodes",toJson vertices),
    ("arcs",toJson arcs.size),("phases",toJson result.phases),("augmentations",toJson result.augmentations),
    ("flowCutChecked",toJson result.flowCutChecked),("elapsedMs",toJson ((← IO.monoMsNow)-started))]
  return (⟨selectedOffers,reward,charge⟩,stats)

def main (args : List String) : IO Unit := do
  let [destination] := args | throw (IO.userError "fresh closure-frontier replay required")
  let output : System.FilePath := .mk destination
  check (!(← output.pathExists)) "preserve previous closure frontier"
  fixtures
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  let input := project / "docs/candidates/prepared-bindings/resumed/cue-capture/receipts/43ba2a13af5aae5fc34557e5b8747cafce13fa0063d0da7356b09f43de8cd9ca/selection-plan.json"
  let data := (← read input).getObjValD "data"
  let raw : SharedCoverage.Input.RawProblem ← IO.ofExcept (data.getObjValAs? _ "selectorInput")
  let p ← IO.ofExcept raw.decode
  let some baseline := SharedCoverage.choose? p | throw (IO.userError "baseline empty selection infeasible")
  let previous : List Nat ← IO.ofExcept ((← read (project / "docs/candidates/read-signal-trace/selector-decisions.json")).getObjValAs? _ "selected")
  check (baseline.selected.map Fin.val == previous) "baseline does not reproduce the actual sequence"
  let domain := PrincipalOffers.prepare p
  let mut witnesses : Array (Sigma (PrincipalOffers.Witness p)) := #[]
  let mut otherMass := 0
  for cue in List.finRange p.weights.size do
    if p.weights[cue] == 0 then continue
    if let some witness := PrincipalOffers.find? domain cue then witnesses := witnesses.push ⟨cue,witness⟩
    else if !(domain.alternatives cue).isEmpty then otherMass := otherMass+p.weights[cue]
  let mut best := baseline
  let mut records := #[]
  let started ← IO.monoMsNow
  let deadline := started+15000
  for byteAxis in [false,true] do
    let limit := if byteAxis then p.limit.2-p.fixed.2 else p.limit.1-p.fixed.1
    let mut low : Point p := ⟨[],0,0⟩
    let (initial,stats) ← solve p witnesses domain byteAxis 0 1 deadline
    let mut high := initial
    records := records.push stats
    if let some selected := select? p initial.offers then
      if benefit p best.selected < benefit p selected.selected then best := selected
    for _ in [:32] do
      if high.charge ≤ limit || high.charge == low.charge then break
      let numerator := high.reward-low.reward
      let denominator := high.charge-low.charge
      let (point,stats) ← solve p witnesses domain byteAxis numerator denominator deadline
      records := records.push stats
      if let some selected := select? p point.offers then
        if benefit p best.selected < benefit p selected.selected then best := selected
      let same := (point.reward == low.reward && point.charge == low.charge) ||
        (point.reward == high.reward && point.charge == high.charge)
      if same then break
      if point.charge ≤ limit then low := point else high := point
  let frontierMs := (← IO.monoMsNow)-started
  -- Human labels and original-coordinate restoration follow the final solve.
  let (source,rows) ← FrozenCanonicalBasis.load study (study / "shared-snapshot")
  let families : Nat ← IO.ofExcept (data.getObjValAs? _ "families")
  let some basis := OriginalPayloadBasis.prepare families rows p | throw (IO.userError "original cost basis differs")
  let frozenTopics ← IO.ofExcept ((← read (project / "docs/candidates/prepared-bindings/resumed/trial/frozen-before-delivery.json")).getArr?)
  let frozen : AvailableDelivery.Frozen ← IO.ofExcept (fromJson? (frozenTopics[0]!.getObjValD "available"))
  let assess := fun selected =>
    let paid := Std.HashSet.ofList ((nodes p selected).map Fin.val)
    AvailableDelivery.assess frozen (basis.sourceRows.filterMap fun (row,atom) =>
      if paid.contains atom.val then some (⟨row.key.file,row.key.line,row.key.line⟩ : Synapses.Range) else none)
  check ((← DB.PageMap.pin source.directory).head == source.head) "read-only closure replay changed source"
  IO.FS.writeFile output (Json.mkObj [("baseline",toJson (assess baseline.selected)),("candidate",toJson (assess best.selected)),
    ("baselineBenefit",toJson (benefit p baseline.selected)),("candidateBenefit",toJson (benefit p best.selected)),
    ("candidateCost",toJson (cost p best.selected)),("candidateOffers",toJson (best.selected.map Fin.val)),
    ("principalCues",toJson witnesses.size),("otherReachableMass",toJson otherMass),("cuts",toJson records),
    ("frontierMs",toJson frontierMs),("includingOriginalRestoreMs",toJson ((← IO.monoMsNow)-started)),
    ("weightsCostsOffersAndLimitsUnchanged",toJson true),
    ("sourceUnchanged",toJson true),("independentExhaustiveFlowFixtures",toJson (30 : Nat)),
    ("plannedOriginalNodesOnly",toJson true),("actualHookCalls",toJson (0 : Nat)),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
  IO.println s!"Closure frontier preview: {(assess baseline.selected).delivered}/{frozen.units.size} -> {(assess best.selected).delivered}"
