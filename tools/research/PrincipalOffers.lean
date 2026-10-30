module
public import tools.PreparedCueIndex
public import tools.SharedCoverage
@[expose] public section

namespace Eggshell.Research.PrincipalOffers
open SharedCoverage

def occurrences (p : Problem) : List (Fin p.offers.size × Fin p.weights.size) :=
  (List.finRange p.offers.size).flatMap fun offer => p.offers[offer].covers.map fun cue => (offer,cue)

theorem occurrence_exact (p : Problem) (offer : Fin p.offers.size) (cue : Fin p.weights.size) :
    (offer,cue) ∈ occurrences p ↔ cue ∈ p.offers[offer].covers := by
  simp [occurrences]

def key (entry : Fin n × Fin m) : String := toString entry.2.val

def paid (p : Problem) (offer : Fin p.offers.size) : List (Fin p.costs.size) :=
  (p.offers[offer].closure.filter (fun node => p.costs[node] != (0,0))).eraseDups

def paidFast (p : Problem) (offer : Fin p.offers.size) : List (Fin p.costs.size) :=
  Eggshell.hashDistinct (p.offers[offer].closure.filter (fun node => p.costs[node] != (0,0)))

@[csimp] theorem paid_compiled : @paid = @paidFast := by
  funext p offer
  exact (Eggshell.HashDistinct.reference _).symm

structure Domain (p : Problem) where
  values : Array (Fin p.offers.size × Fin p.weights.size)
  index : PreparedCueIndex.Prepared key values
  exact : ∀ offer cue, (offer,cue) ∈ values.toList ↔ cue ∈ p.offers[offer].covers
  paidAt : Fin p.offers.size → List (Fin p.costs.size)
  paidExact : ∀ offer, paidAt offer = paid p offer

def prepare (p : Problem) : Domain p :=
  let values := (occurrences p).toArray
  let payloads := Array.ofFn (paid p)
  {values,index := PreparedCueIndex.prepare key values
   exact := by intro offer cue; simpa [values] using occurrence_exact p offer cue
   paidAt := fun offer => payloads[offer.val]'(by simp [payloads])
   paidExact := by intro offer; simp [payloads]}

def Domain.alternatives (domain : Domain p) (cue : Fin p.weights.size) : List (Fin p.offers.size) :=
  (domain.index.one (toString cue.val) (fun entry => entry.2 == cue)).map Prod.fst

theorem Domain.alternative_exact (domain : Domain p) (cue : Fin p.weights.size) (offer : Fin p.offers.size) :
    offer ∈ domain.alternatives cue ↔ cue ∈ p.offers[offer].covers := by
  unfold Domain.alternatives
  rw [PreparedCueIndex.Prepared.one_exact _ _ _ (by
    intro entry accepted
    have same : entry.2 = cue := beq_iff_eq.mp accepted
    simp [key,same])]
  simp only [List.mem_map,List.mem_filter,beq_iff_eq]
  constructor
  · rintro ⟨⟨index,actual⟩,⟨present,same⟩,found⟩
    change index = offer at found
    change actual = cue at same
    subst index
    subst actual
    exact (domain.exact offer cue).mp present
  · intro present
    exact ⟨(offer,cue),⟨(domain.exact offer cue).mpr present,rfl⟩,rfl⟩

structure Witness (p : Problem) (cue : Fin p.weights.size) where
  offer : Fin p.offers.size
  covered : cue ∈ p.offers[offer].covers
  least : ∀ other : Fin p.offers.size, cue ∈ p.offers[other].covers →
    ∀ node ∈ paid p offer, node ∈ paid p other

def check? (domain : Domain p) (cue : Fin p.weights.size) (candidate : Fin p.offers.size) :
    Option (Witness p cue) :=
  if covered : candidate ∈ domain.alternatives cue then
    if least : ((domain.alternatives cue).all fun other =>
        (domain.paidAt candidate).all fun node => (domain.paidAt other).contains node) = true then
      some ⟨candidate,(domain.alternative_exact cue candidate).mp covered,by
        intro other relevant node present
        have member := (domain.alternative_exact cue other).mpr relevant
        have found := List.all_eq_true.mp least other member
        have present' : node ∈ domain.paidAt candidate := by simpa [domain.paidExact] using present
        have included := List.all_eq_true.mp found node present'
        simpa [domain.paidExact] using included⟩
    else none
  else none

/-- A principal witness is a real original offer. Any other way of covering
this cue already pays every one of its positive-cost atoms. No cue weight,
payload, graph identity or certification is manufactured by the reduction. -/
theorem witness_is_original (witness : Witness p cue) : cue ∈ p.offers[witness.offer].covers :=
  witness.covered

theorem witness_already_paid (witness : Witness p cue) (other : Fin p.offers.size)
    (covered : cue ∈ p.offers[other].covers) (node : Fin p.costs.size)
    (required : node ∈ paid p witness.offer) : node ∈ paid p other :=
  witness.least other covered node required

def find? (domain : Domain p) (cue : Fin p.weights.size) : Option (Witness p cue) := Id.run do
  let choices := domain.alternatives cue
  let some first := choices.head? | return none
  let shortest := choices.foldl (fun best candidate =>
    if (domain.paidAt candidate).length < (domain.paidAt best).length then candidate else best) first
  if let some witness := check? domain cue shortest then return some witness
  -- Negative classifications are exhaustive, not inferred from a greedy
  -- candidate. This branch is a diagnostic, never a hook-time full scan.
  for alternative in choices do
    if let some witness := check? domain cue alternative then return some witness
  return none

end Eggshell.Research.PrincipalOffers
