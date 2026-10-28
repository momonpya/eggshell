module
public import tools.SharedCoverage
@[expose] public section

namespace SharedCoverage.SetupAlternatives
open Eggshell

/-- A shared frame is paid once for a group. It earns only the existing
credits whose complete existing payload is contained in that payment. -/
def contained (p : Problem) (paid : List (Fin p.costs.size)) : List (Fin p.offers.size) :=
  (List.finRange p.offers.size).filter fun index =>
    p.offers[index].closure.all (fun atom => paid.contains atom)

def offer (p : Problem) (paid : List (Fin p.costs.size)) : Offer p.costs.size p.weights.size :=
  {closure := hashDistinct paid
   covers := hashDistinct ((contained p paid).flatMap fun index => p.offers[index].covers)}

theorem credit_has_paid_witness (p : Problem) (paid : List (Fin p.costs.size))
    (cue : Fin p.weights.size) (credited : cue ∈ (offer p paid).covers) :
    ∃ index : Fin p.offers.size, cue ∈ p.offers[index].covers ∧
      ∀ atom ∈ p.offers[index].closure, atom ∈ (offer p paid).closure := by
  obtain ⟨index,included,present⟩ := List.mem_flatMap.mp ((HashDistinct.mem _ _).mp credited)
  have complete := (List.mem_filter.mp included).2
  refine ⟨index,present,?_⟩
  intro atom member
  exact (HashDistinct.mem _ _).mpr
    (List.contains_iff_mem.mp (List.all_eq_true.mp complete atom member))

def compile (p : Problem) (groups : Array (List (Fin p.costs.size))) : Problem :=
  {p with offers := p.offers ++ groups.map (offer p)}

theorem keeps_costs (p : Problem) (groups : Array (List (Fin p.costs.size))) :
    (compile p groups).costs = p.costs := rfl
theorem keeps_weights (p : Problem) (groups : Array (List (Fin p.costs.size))) :
    (compile p groups).weights = p.weights := rfl
theorem keeps_limit (p : Problem) (groups : Array (List (Fin p.costs.size))) :
    (compile p groups).limit = p.limit := rfl
theorem keeps_original (p : Problem) (groups : Array (List (Fin p.costs.size)))
    (index : Fin p.offers.size) :
    (compile p groups).offers[index.val]'(by simp [compile]; omega) = p.offers[index] := by
  simp [compile,Array.getElem_append_left,index.isLt]

end SharedCoverage.SetupAlternatives
