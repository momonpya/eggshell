module
public import tools.SharedCoverage
@[expose] public section
namespace SharedCoverage.Exchange
variable {p : Problem} {prior : Selection p}
structure Proposal (p : Problem) where
  dropped : Fin p.offers.size
  added : Fin p.offers.size
  cost : Nat × Nat
  value : Nat

structure Improvement (prior : Selection p) where
  result : Selection p
  proposal : Proposal p
  removed : proposal.dropped ∈ prior.selected
  fresh : proposal.added ∉ prior.selected
  shape : result.selected = prior.selected.filter (· != proposal.dropped) ++ [proposal.added]
  costExact : cost p result.selected = proposal.cost
  valueExact : benefit p result.selected = proposal.value
  better : benefit p prior.selected < benefit p result.selected

def check? (prior : Selection p) (proposal : Proposal p) : Option (Improvement prior) :=
  if permitted : proposal.dropped ∈ prior.selected ∧ proposal.added ∉ prior.selected then
    let selected := prior.selected.filter (· != proposal.dropped) ++ [proposal.added]
    if unique : selected.Nodup then
      if bounded : (cost p selected).1 ≤ p.limit.1 ∧ (cost p selected).2 ≤ p.limit.2 then
        if exactCost : cost p selected = proposal.cost then
          if exactValue : benefit p selected = proposal.value then
            if better : benefit p prior.selected < benefit p selected then
              some ⟨⟨selected,unique,bounded.1,bounded.2⟩,proposal,permitted.1,permitted.2,rfl,exactCost,exactValue,better⟩
            else none
          else none
        else none
      else none
    else none
  else none

theorem strictly_better (choice : Improvement prior) :
    benefit p prior.selected < benefit p choice.result.selected := choice.better
theorem keeps_limits (choice : Improvement prior) :
    (cost p choice.result.selected).1 ≤ p.limit.1 ∧ (cost p choice.result.selected).2 ≤ p.limit.2 :=
  ⟨choice.result.charsFit,choice.result.bytesFit⟩

def remainder? (prior : Selection p) (dropped : Fin p.offers.size) : Option (Selection p) :=
  let selected := prior.selected.filter (· != dropped)
  if unique : selected.Nodup then
    if bounded : (cost p selected).1 ≤ p.limit.1 ∧ (cost p selected).2 ≤ p.limit.2 then
      some ⟨selected,unique,bounded.1,bounded.2⟩
    else none
  else none

theorem remainder_selected (found : remainder? prior dropped = some rest) :
    rest.selected = prior.selected.filter (· != dropped) := by
  unfold remainder? at found
  dsimp only at found
  split at found <;> try contradiction
  split at found <;> try contradiction
  cases Option.some.inj found
  rfl

/-- Independent verifier: rebuild each deletion with the original evaluator,
whose marginal cost and benefit already have kernel-checked exactness laws. -/
def verifyRemoval (prior : Selection p) (upper : Nat) (dropped : Fin p.offers.size) : Bool :=
  match remainder? prior dropped with
  | none => false
  | some rest =>
      let cached := evaluation rest
      (List.finRange p.offers.size).all fun added =>
        if added ∈ prior.selected then true
        else if (cached.afterCost added).1 ≤ p.limit.1 ∧ (cached.afterCost added).2 ≤ p.limit.2 then
          decide (cached.afterBenefit added ≤ upper)
        else true

theorem verify_removal_sound (accepted : verifyRemoval prior upper dropped = true)
    (fresh : added ∉ prior.selected)
    (bounded : (cost p (prior.selected.filter (· != dropped)++[added])).1 ≤ p.limit.1 ∧
      (cost p (prior.selected.filter (· != dropped)++[added])).2 ≤ p.limit.2) :
    benefit p (prior.selected.filter (· != dropped)++[added]) ≤ upper := by
  unfold verifyRemoval at accepted
  cases found : remainder? prior dropped with
  | none => simp [found] at accepted
  | some rest =>
    rw [found] at accepted
    dsimp only at accepted
    have decision := List.all_eq_true.mp accepted added (by simp)
    have selected := remainder_selected found
    have actualCost : (evaluation rest).afterCost added = cost p (prior.selected.filter (· != dropped)++[added]) := by
      simpa [selected] using (evaluation rest).afterCost_exact added
    have actualValue : (evaluation rest).afterBenefit added = benefit p (prior.selected.filter (· != dropped)++[added]) := by
      simpa [selected] using (evaluation rest).afterBenefit_exact added
    simpa [fresh,actualCost,actualValue,bounded] using decision

structure Certificate (prior : Selection p) where
  upper : Nat
  verified : prior.selected.all (verifyRemoval prior upper) = true

def certify? (prior : Selection p) (upper : Nat) : Option (Certificate prior) :=
  if verified : prior.selected.all (verifyRemoval prior upper) = true then some ⟨upper,verified⟩ else none

theorem all_exchanges_bounded (certificate : Certificate prior) (member : dropped ∈ prior.selected)
    (fresh : added ∉ prior.selected)
    (bounded : (cost p (prior.selected.filter (· != dropped)++[added])).1 ≤ p.limit.1 ∧
      (cost p (prior.selected.filter (· != dropped)++[added])).2 ≤ p.limit.2) :
    benefit p (prior.selected.filter (· != dropped)++[added]) ≤ certificate.upper :=
  verify_removal_sound (List.all_eq_true.mp certificate.verified dropped member) fresh bounded

structure Data (p : Problem) where
  index : Fin p.offers.size
  nodes : List (Fin p.costs.size)
  cues : List (Fin p.weights.size)
  nodeSet : Std.HashSet (Fin p.costs.size)
  cueSet : Std.HashSet (Fin p.weights.size)

structure Search (prior : Selection p) where
  proposal : Option (Proposal p)
  checked : Option (Improvement prior)
  pairs : Nat
  feasible : Nat

/-- One exhaustive drop/add pass over the fixed original objective. Counts
refund a shared atom or cue only after its final selected user is removed.
The winner crosses an independent full-cost/full-benefit certificate check. -/
def search (prior : Selection p) : Search prior := Id.run do
  let entries := (List.finRange p.offers.size).toArray.map fun index =>
    let nodes := p.offers[index].closure.eraseDups
    let cues := p.offers[index].covers.eraseDups
    ({index,nodes,cues,nodeSet := Std.HashSet.ofList nodes,cueSet := Std.HashSet.ofList cues} : Data p)
  let selected := Std.HashSet.ofList prior.selected
  let mut nodeCounts : Std.HashMap (Fin p.costs.size) Nat := {}
  let mut cueCounts : Std.HashMap (Fin p.weights.size) Nat := {}
  for index in prior.selected do
    let data := entries[index.val]'(by simp [entries])
    for node in data.nodes do nodeCounts := nodeCounts.insert node ((nodeCounts[node]?.getD 0)+1)
    for cue in data.cues do cueCounts := cueCounts.insert cue ((cueCounts[cue]?.getD 0)+1)
  let sumCost := fun (nodes : List (Fin p.costs.size)) => nodes.foldl (fun total node =>
    (total.1+p.costs[node].1,total.2+p.costs[node].2)) (0,0)
  let old := prior.selected.toArray.map fun index =>
    let data := entries[index.val]'(by simp [entries])
    (index,data.nodes.filter (fun node => nodeCounts[node]? == some 1),
      data.cues.filter (fun cue => cueCounts[cue]? == some 1))
  let beforeCost := cost p prior.selected
  let beforeValue := benefit p prior.selected
  let mut best : Option (Proposal p) := none
  let mut pairs := 0
  let mut feasible := 0
  for next in entries do
    if selected.contains next.index then continue
    let extraCost := sumCost (next.nodes.filter (fun node => !nodeCounts.contains node))
    let extraValue := (next.cues.filter (fun cue => !cueCounts.contains cue)).foldl
      (fun total cue => total+p.weights[cue]) 0
    for (index,exclusiveNodes,exclusiveCues) in old do
      pairs := pairs+1
      let refund := sumCost (exclusiveNodes.filter (fun node => !next.nodeSet.contains node))
      let charge := (beforeCost.1-refund.1+extraCost.1,beforeCost.2-refund.2+extraCost.2)
      if p.limit.1 < charge.1 || p.limit.2 < charge.2 then continue
      feasible := feasible+1
      let lost := (exclusiveCues.filter (fun cue => !next.cueSet.contains cue)).foldl
        (fun total cue => total+p.weights[cue]) 0
      let value := beforeValue-lost+extraValue
      if beforeValue < value && value > ((best.map (·.value)).getD beforeValue) then
        best := some ⟨index,next.index,charge,value⟩
  return ⟨best,best.bind (check? prior),pairs,feasible⟩
end SharedCoverage.Exchange
