module
public import tools.VerifiedWinnerCoverage
@[expose] public section
namespace SharedCoverage.OwnedAdvance
variable {p : Problem} {prior : Selection p}

/-- All reads of the old membership maps finish before either map is extended.
Proof references to the old evaluator are erased from the executable. -/
def evaluation (cached : Evaluation prior) (next : Selection p) (index : Fin p.offers.size)
    (extension : next.selected = prior.selected++[index]) : Evaluation next :=
  let freshNodes := cached.freshNodes index
  let freshCues := cached.freshCues index
  let totalCost := cached.afterCost index
  let totalBenefit := cached.afterBenefit index
  let nodes := cached.nodeIndex
  let cues := cached.cueIndex
  {nodeIndex := freshNodes.foldl (fun known node => known.insert node ()) nodes
   nodesExact := (cached.advance next index extension).nodesExact
   cueIndex := freshCues.foldl (fun known cue => known.insert cue ()) cues
   cuesExact := (cached.advance next index extension).cuesExact
   beforeCost := totalCost
   costExact := (cached.advance next index extension).costExact
   beforeBenefit := totalBenefit
   benefitExact := (cached.advance next index extension).benefitExact}

theorem evaluation_exact (cached : Evaluation prior) (next : Selection p) (index : Fin p.offers.size)
    (extension : next.selected = prior.selected++[index]) :
    evaluation cached next index extension = cached.advance next index extension := by
  rfl

/-- Resolve affected postings against the old evaluator before constructing
the next evaluator. No old map is required by subsequent runtime expressions. -/
def values (stored : Deferred.Sparse.Values prior) (layout : Deferred.Sparse.Layout p)
    (next : Selection p) (winner : Fin p.offers.size)
    (extension : next.selected = prior.selected++[winner]) : Deferred.Sparse.Values next :=
  let before := stored.base
  let changedNodes := layout.nodes.changed before.nodeIndex p.offers[winner].closure
  let changedCues := layout.cues.changed before.cueIndex p.offers[winner].covers
  let costs := stored.costs
  let gains := stored.gains
  let after := evaluation before next winner extension
  have same : after = before.advance next winner extension := evaluation_exact ..
  {base := after
   baseExact := same.trans (before.advance_exact next winner extension stored.baseExact)
   costs := Deferred.Sparse.patch costs (Deferred.Sparse.rawCost after) changedNodes
   gains := Deferred.Sparse.patch gains (Deferred.Sparse.rawGain after) changedCues
   costsExact := by
     intro index
     change (Deferred.Sparse.patch costs (Deferred.Sparse.rawCost after) changedNodes)[index] = _
     rw [same]
     exact (stored.advance layout next winner extension).costsExact index
   gainsExact := by
     intro index
     change (Deferred.Sparse.patch gains (Deferred.Sparse.rawGain after) changedCues)[index] = _
     rw [same]
     exact (stored.advance layout next winner extension).gainsExact index}

theorem values_exact (stored : Deferred.Sparse.Values prior) (layout : Deferred.Sparse.Layout p)
    (next : Selection p) (winner : Fin p.offers.size)
    (extension : next.selected = prior.selected++[winner]) :
    values stored layout next winner extension = stored.advance layout next winner extension := by
  rfl

#print axioms evaluation_exact
#print axioms values_exact

open Deferred Deferred.VerifiedWinner
variable {stored : Sparse.Values prior} {treeDepth : Nat}

/-- The old evaluator occurs only in erased specifications here. The runtime
receives an already computed change set and the next values, not old values. -/
def winnerAdvance (state : State prior stored treeDepth) (layout : Sparse.Layout p)
    (next : Selection p) (winner : Fin p.offers.size)
    (extension : next.selected = prior.selected++[winner])
    (updated : Sparse.Values next) (same : updated = stored.advance layout next winner extension)
    (seen : Known next) (changed : List (Fin p.offers.size))
    (changedExact : changed = affected layout stored winner) : State next updated treeDepth :=
  let cache := updateMany state.capacity state.cache changed (ratingAt next updated seen)
  have cacheExact : cache = (state.advanceUsing layout next winner extension updated same seen).cache := by
    dsimp only [cache,State.advanceUsing]
    rw [changedExact]
  {capacity := state.capacity
   cache
   identity := by
     intro position value found
     apply (state.advanceUsing layout next winner extension updated same seen).identity position value
     rw [← cacheExact]
     exact found
   complete := by
     intro position value current
     rw [cacheExact]
     exact (state.advanceUsing layout next winner extension updated same seen).complete position value current}

theorem winnerAdvance_exact (state : State prior stored treeDepth) (layout : Sparse.Layout p)
    (next : Selection p) (winner : Fin p.offers.size)
    (extension : next.selected = prior.selected++[winner])
    (updated : Sparse.Values next) (same : updated = stored.advance layout next winner extension)
    (seen : Known next) (changed : List (Fin p.offers.size))
    (changedExact : changed = affected layout stored winner) :
    winnerAdvance state layout next winner extension updated same seen changed changedExact =
      state.advanceUsing layout next winner extension updated same seen := by
  subst changed
  rfl

def fillOwned (layout : Sparse.Layout p) (fuel : Nat) (prior : Selection p) (stored : Sparse.Values prior)
    (state : State prior stored (depth p)) (seen : Known prior) : Selection p :=
  match fuel with
  | 0 => prior
  | fuel+1 =>
      let resolved := state.resolveWith seen
      match resolved.score with
      | none => prior
      | some score =>
          let next := score.proposal.result
          let changed := affected layout stored score.index
          let updated := values stored layout next score.index rfl
          let nextSeen := advanceKnown seen next score.index rfl
          fillOwned layout fuel next updated
            (winnerAdvance resolved.state layout next score.index rfl updated (values_exact ..) nextSeen changed rfl)
            nextSeen

theorem fillOwned_exact (layout : Sparse.Layout p) (fuel : Nat) (prior : Selection p)
    (stored : Sparse.Values prior) (state : State prior stored (depth p)) (seen : Known prior) :
    fillOwned layout fuel prior stored state seen = SharedCoverage.fill fuel prior := by
  induction fuel generalizing prior with
  | zero => rfl
  | succ fuel ih =>
      rw [SharedCoverage.fill,← Sparse.best_exact stored,← (state.resolveWith seen).exact]
      cases found : (state.resolveWith seen).score with
      | none => simp only [fillOwned,found,Option.map_none]
      | some score =>
          simpa only [fillOwned,found,Option.map_some] using
            (ih score.proposal.result (values stored layout _ score.index rfl)
              (winnerAdvance (state.resolveWith seen).state layout _ score.index rfl
                (values stored layout _ score.index rfl) (values_exact ..) (advanceKnown seen _ score.index rfl)
                (affected layout stored score.index) rfl)
              (advanceKnown seen _ score.index rfl))

#print axioms winnerAdvance_exact
#print axioms fillOwned_exact

def chooseOwned (p : Problem) : Option (Selection p) := do
  let initial ← empty? p
  let layout := Sparse.layout p
  let stored := Sparse.values initial
  let state := State.initial initial stored (depth p) (Nat.le_of_lt Nat.lt_log2_self)
  pure (SharedCoverage.prefer (fillOwned layout p.offers.size initial stored state (known initial))
    (SharedCoverage.bestSingleton initial))

theorem chooseOwned_exact (p : Problem) : chooseOwned p = SharedCoverage.choose? p := by
  calc
    chooseOwned p = Deferred.VerifiedWinner.choose? p := by
      simp only [chooseOwned,Deferred.VerifiedWinner.choose?,fillOwned_exact,fillKnown_exact]
    _ = SharedCoverage.choose? p := (congrFun Deferred.VerifiedWinner.choose_exact p).symm

#print axioms chooseOwned_exact
end SharedCoverage.OwnedAdvance
