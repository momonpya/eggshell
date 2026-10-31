module
public import tools.SharedCoverage
@[expose] public section

namespace SharedCoverage.CarriedSelectionValue
variable {p : Problem}

/-- The current query determines benefit. Carry its exact value with the
selection instead of recomputing the same winner's union for every rival. -/
structure Rated (p : Problem) where
  selection : Selection p
  value : Nat
  exact : value = benefit p selection.selected

def rate (selection : Selection p) : Rated p :=
  ⟨selection,benefit p selection.selected,rfl⟩

def prefer (first second : Rated p) : Rated p :=
  if first.value < second.value then second else first

theorem prefer_exact (first second : Rated p) :
    (prefer first second).selection = SharedCoverage.prefer first.selection second.selection := by
  simp only [prefer,SharedCoverage.prefer,first.exact,second.exact]
  split <;> rfl

def scan (initial : Selection p) (best : Rated p)
    (pending : List (Fin p.offers.size)) : Rated p :=
  match pending with
  | [] => best
  | index :: tail =>
      scan initial (match extend? initial index with
        | none => best
        | some next => prefer best (rate next)) tail

theorem scan_exact (initial : Selection p) (best : Rated p)
    (pending : List (Fin p.offers.size)) :
    (scan initial best pending).selection = singletonScan initial best.selection pending := by
  induction pending generalizing best with
  | nil => rfl
  | cons index tail ih =>
      simp only [scan,singletonScan]
      cases found : extend? initial index with
      | none => exact ih best
      | some next =>
          simpa only [prefer_exact,rate] using ih (prefer best (rate next))

def bestSingleton (initial : Selection p) : Selection p :=
  (scan initial (rate initial) (List.finRange p.offers.size)).selection

@[csimp] theorem bestSingleton_exact :
    @SharedCoverage.bestSingleton = @bestSingleton := by
  funext p initial
  exact (scan_exact initial (rate initial) _).symm

end SharedCoverage.CarriedSelectionValue
