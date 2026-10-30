module
public import tools.research.ClosureFlow
public import tools.research.PrincipalOffers
@[expose] public section

namespace Eggshell.Research.PrincipalNetwork
open SharedCoverage

def axis (p : Problem) (byteAxis : Bool) (node : Fin p.costs.size) : Nat :=
  if byteAxis then p.costs[node].2 else p.costs[node].1

/-- The unchanged network construction from the first closure-frontier
replay. Shared by the solver and its independent fixed-price diagnosis. -/
def make (p : Problem) (witnesses : Array (Sigma (PrincipalOffers.Witness p)))
    (domain : PrincipalOffers.Domain p) (byteAxis : Bool) (numerator denominator : Nat) :
    ClosureFlow.Network := Id.run do
  let firstReward := 2+p.costs.size
  let rewardSum := witnesses.foldl (fun total witness => total+p.weights[witness.1]) 0
  let infinite := rewardSum*denominator+1
  let mut arcs := #[]
  for node in List.finRange p.costs.size do
    if axis p byteAxis node > 0 then
      arcs := arcs.push ⟨2+node.val,1,axis p byteAxis node*numerator⟩
  for index in List.finRange witnesses.size do
    let witness := witnesses[index]
    arcs := arcs.push ⟨0,firstReward+index.val,p.weights[witness.1]*denominator⟩
    for node in domain.paidAt witness.2.offer do
      arcs := arcs.push ⟨firstReward+index.val,2+node.val,infinite⟩
  return ⟨firstReward+witnesses.size,0,1,arcs⟩

def offers (p : Problem) (witnesses : Array (Sigma (PrincipalOffers.Witness p)))
    (selected : Array Bool) : List (Fin p.offers.size) :=
  Eggshell.hashDistinct ((List.finRange witnesses.size).filterMap fun index =>
    if selected[2+p.costs.size+index.val]! then some witnesses[index].2.offer else none)

end Eggshell.Research.PrincipalNetwork
