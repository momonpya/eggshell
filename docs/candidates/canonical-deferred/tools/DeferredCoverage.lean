module
public import tools.SharedCoverage
@[expose] public section

namespace SharedCoverage.Deferred
open Eggshell
variable {p : Problem} {prior : Selection p}

/-- Membership is fixed for one scan. Every lookup is tied to the actual
selected list; no unchecked cached membership can reject an offer. -/
structure Known (prior : Selection p) where
  selected : Std.HashMap (Fin p.offers.size) Unit
  exact : ∀ index, selected.contains index = prior.selected.contains index

def known (prior : Selection p) : Known prior := {
  selected := prior.selected.foldl (fun found index => found.insert index ()) {}
  exact := by intro index; simp [HashDistinct.fold_contains]}

def Known.fresh (seen : Known prior) (index : Fin p.offers.size) : Decidable (index ∉ prior.selected) :=
  if present : seen.selected.contains index = true then
    isFalse (by
      have member : index ∈ prior.selected := List.contains_iff_mem.mp (by rwa [seen.exact] at present)
      exact fun absent => absent member)
  else isTrue (by
    intro member
    apply present
    rw [seen.exact]
    exact List.contains_iff_mem.mpr member)

theorem Known.fresh_exact (seen : Known prior) (index : Fin p.offers.size) :
    seen.fresh index = (inferInstance : Decidable (index ∉ prior.selected)) := Subsingleton.elim _ _

/-- Losing candidates carry only an index and scalar score. Construct the
extended selected list once, after choosing the winner. -/
structure Score (prior : Selection p) (cached : Evaluation prior) where
  index : Fin p.offers.size
  fresh : index ∉ prior.selected
  fits : (cached.afterCost index).1 ≤ p.limit.1 ∧ (cached.afterCost index).2 ≤ p.limit.2
  gain : Nat
  positive : 0 < gain
  charge : Nat

def Score.proposal (score : Score prior cached) : Proposal prior := {
  result := {
    selected := prior.selected ++ [score.index]
    unique := by
      apply List.nodup_append.mpr
      refine ⟨prior.unique,by simp,?_⟩
      intro a present b singleton same
      have last : b = score.index := List.mem_singleton.mp singleton
      exact score.fresh ((same.trans last) ▸ present)
    charsFit := by rw [← cached.afterCost_exact score.index]; exact score.fits.1
    bytesFit := by rw [← cached.afterCost_exact score.index]; exact score.fits.2}
  gain := score.gain,positive := score.positive,charge := score.charge}

def score? (prior : Selection p) (cached : Evaluation prior) (seen : Known prior)
    (index : Fin p.offers.size) : Option (Score prior cached) :=
  letI : Decidable (index ∉ prior.selected) := seen.fresh index
  if fresh : index ∉ prior.selected then
    let after := cached.afterCost index
    if fits : after.1 ≤ p.limit.1 ∧ after.2 ≤ p.limit.2 then
      let gain := cached.afterBenefit index-cached.beforeBenefit
      if positive : 0 < gain then
        some ⟨index,fresh,fits,gain,positive,
          max ((after.1-cached.beforeCost.1)*p.limit.2) ((after.2-cached.beforeCost.2)*p.limit.1)⟩
      else none
    else none
  else none

theorem score_exact (cached : Evaluation prior) (seen : Known prior) (index : Fin p.offers.size) :
    (score? prior cached seen index).map Score.proposal = proposalCached? prior cached index := by
  unfold score? proposalCached? extendCached?
  by_cases fresh : index ∉ prior.selected
  · by_cases fits : (cached.afterCost index).1 ≤ p.limit.1 ∧ (cached.afterCost index).2 ≤ p.limit.2
    · by_cases positive : 0 < cached.afterBenefit index-cached.beforeBenefit
      · simp [fresh,fits,positive,Score.proposal]
      · simp [fresh,fits,positive]
    · simp [fresh,fits]
  · simp [fresh]

def betterScore (next previous : Score prior cached) : Bool :=
  if next.charge == 0 then previous.charge != 0 || previous.gain < next.gain
  else if previous.charge == 0 then false
  else previous.gain*next.charge < next.gain*previous.charge

theorem betterScore_exact (next previous : Score prior cached) :
    betterScore next previous = better next.proposal previous.proposal := rfl

def step (prior : Selection p) (cached : Evaluation prior) (seen : Known prior)
    (found : Option (Score prior cached)) (index : Fin p.offers.size) : Option (Score prior cached) :=
  match score? prior cached seen index,found with
  | none,_ => found
  | some next,none => some next
  | some next,some previous => if betterScore next previous then some next else found

def referenceStep (prior : Selection p) (cached : Evaluation prior)
    (found : Option (Proposal prior)) (index : Fin p.offers.size) : Option (Proposal prior) :=
  match proposalCached? prior cached index,found with
  | none,_ => found
  | some next,none => some next
  | some next,some previous => if better next previous then some next else found

theorem step_exact (cached : Evaluation prior) (seen : Known prior)
    (found : Option (Score prior cached)) (index : Fin p.offers.size) :
    (step prior cached seen found index).map Score.proposal =
      referenceStep prior cached (found.map Score.proposal) index := by
  unfold step referenceStep
  rw [← score_exact cached seen index]
  cases current : score? prior cached seen index with
  | none => cases found <;> rfl
  | some next =>
      cases found with
      | none => rfl
      | some previous =>
          cases selected : betterScore next previous <;>
            simp [selected, ← betterScore_exact]

theorem scan_exact (cached : Evaluation prior) (seen : Known prior)
    (pending : List (Fin p.offers.size)) (found : Option (Score prior cached)) :
    (pending.foldl (step prior cached seen) found).map Score.proposal =
      pending.foldl (referenceStep prior cached) (found.map Score.proposal) := by
  induction pending generalizing found with
  | nil => rfl
  | cons head tail ih =>
      simp only [List.foldl_cons,ih,step_exact]

def bestDeferred (prior : Selection p) : Option (Proposal prior) :=
  let cached := evaluation prior
  let seen := known prior
  ((List.finRange p.offers.size).foldl (step prior cached seen) none).map Score.proposal

theorem bestDeferred_exact (prior : Selection p) : bestDeferred prior = best prior := by
  rw [best_cached_compiled]
  unfold bestDeferred bestCached
  rw [scan_exact]
  rfl

def fillDeferred (fuel : Nat) (prior : Selection p) : Selection p :=
  match fuel with
  | 0 => prior
  | fuel+1 => match bestDeferred prior with
    | none => prior
    | some next => fillDeferred fuel next.result

theorem fillDeferred_exact (fuel : Nat) (prior : Selection p) :
    fillDeferred fuel prior = fill fuel prior := by
  induction fuel generalizing prior with
  | zero => rfl
  | succ fuel ih =>
      simp only [fillDeferred,fill,bestDeferred_exact]
      cases best prior with
      | none => rfl
      | some next => exact ih next.result

def chooseDeferred? (p : Problem) : Option (Selection p) := do
  let initial ← empty? p
  pure (prefer (fillDeferred p.offers.size initial) (bestSingleton initial))

@[csimp] theorem choose_deferred_compiled : @choose? = @chooseDeferred? := by
  funext p
  simp only [choose?,chooseFrom,chooseDeferred?,fillDeferred_exact]

end SharedCoverage.Deferred
