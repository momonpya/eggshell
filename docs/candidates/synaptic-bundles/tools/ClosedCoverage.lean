module
public import tools.SharedCoverage
@[expose] public section

namespace ClosedCoverage

/-- A proposal may earn an additional cue only together with every original
payload offer it names. This module cannot name Work, Match or Union. -/
structure Recipe (p : SharedCoverage.Problem) where
  parts : List (Fin p.offers.size)
  bonus : List (Fin p.weights.size) := []

def Recipe.offer (recipe : Recipe p) : SharedCoverage.Offer p.costs.size p.weights.size := {
  closure := recipe.parts.flatMap fun index => p.offers[index].closure
  covers := (recipe.parts.flatMap fun index => p.offers[index].covers) ++ recipe.bonus}

def compile (p : SharedCoverage.Problem) (recipes : Array (Recipe p)) : SharedCoverage.Problem := {
  costs := p.costs, weights := p.weights, offers := recipes.map Recipe.offer
  fixed := p.fixed, limit := p.limit}

def original (p : SharedCoverage.Problem) : Array (Recipe p) :=
  (List.finRange p.offers.size).toArray.map fun index => {parts := [index]}

def recipeAt (p : SharedCoverage.Problem) (recipes : Array (Recipe p))
    (index : Fin (compile p recipes).offers.size) : Recipe p :=
  recipes[index.val]'(by simpa [compile] using index.isLt)

theorem offer_at (p : SharedCoverage.Problem) (recipes : Array (Recipe p))
    (index : Fin (compile p recipes).offers.size) :
    (compile p recipes).offers[index] = (recipeAt p recipes index).offer := by
  have bounds : index.val < recipes.size := by simpa [compile] using index.isLt
  change (recipes.map Recipe.offer)[index.val]'(by simpa using bounds) =
    (recipes[index.val]'bounds).offer
  rw [Array.getElem_map]

def expand (p : SharedCoverage.Problem) (recipes : Array (Recipe p))
    (selected : List (Fin (compile p recipes).offers.size)) : List (Fin p.offers.size) :=
  selected.flatMap fun index => (recipeAt p recipes index).parts

theorem part_is_expanded (p : SharedCoverage.Problem) (recipes : Array (Recipe p))
    (selected : List (Fin (compile p recipes).offers.size))
    (index : Fin (compile p recipes).offers.size) (chosen : index ∈ selected)
    (part : Fin p.offers.size) (required : part ∈ (recipeAt p recipes index).parts) :
    part ∈ expand p recipes selected := by
  exact List.mem_flatMap.mpr ⟨index,chosen,required⟩

theorem closure_expansion (p : SharedCoverage.Problem) (recipes : Array (Recipe p))
    (selected : List (Fin (compile p recipes).offers.size)) :
    selected.flatMap (fun index => (compile p recipes).offers[index].closure) =
      (expand p recipes selected).flatMap (fun index => p.offers[index].closure) := by
  simp only [offer_at, Recipe.offer, expand, List.flatMap_assoc]
  rfl

theorem cost_expansion (p : SharedCoverage.Problem) (recipes : Array (Recipe p))
    (selected : List (Fin (compile p recipes).offers.size)) :
    SharedCoverage.cost (compile p recipes) selected =
      SharedCoverage.cost p (expand p recipes selected) := by
  unfold SharedCoverage.cost SharedCoverage.nodes
  rw [closure_expansion]
  rfl

/-- The gate changes when an existing source cue can be credited, not its
maximum value. Duplicate evidence cannot create a second source vote. -/
theorem bonus_conserved (base graph : Nat) : base + (max base graph - base) = max base graph := by
  omega

theorem credited_has_complete_recipe (p : SharedCoverage.Problem) (recipes : Array (Recipe p))
    (selected : List (Fin (compile p recipes).offers.size))
    (index : Fin (compile p recipes).offers.size) (chosen : index ∈ selected)
    (cue : Fin p.weights.size) (credited : cue ∈ (recipeAt p recipes index).bonus) :
    cue ∈ SharedCoverage.cues (compile p recipes) selected ∧
      ∀ part ∈ (recipeAt p recipes index).parts, part ∈ expand p recipes selected := by
  constructor
  · have present : cue ∈ selected.flatMap (fun index => (compile p recipes).offers[index].covers) := by
      apply List.mem_flatMap.mpr
      refine ⟨index,chosen,?_⟩
      rw [offer_at]
      exact List.mem_append_right _ credited
    change cue ∈ (selected.flatMap (fun index => (compile p recipes).offers[index].covers)).eraseDups
    exact List.mem_eraseDups.mpr present
  · intro part required
    exact part_is_expanded p recipes selected index chosen part required

end ClosedCoverage
