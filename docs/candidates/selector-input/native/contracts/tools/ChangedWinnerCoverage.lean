module
public import tools.DeferredCoverage
public import tools.SelectionRating
public import Lean.Data.Json.FromToJson
@[expose] public section

namespace SharedCoverage.Deferred.ChangedWinner
open StableWinnerIndex
variable {p : Problem} {prior : Selection p}

structure Statistics where
  rounds : Nat := 0
  pointUpdates : Nat := 0
  rejectedByCurrentBudget : Nat := 0
  checkedWinners : Nat := 0
  deriving Lean.ToJson

def key (score : Score prior (evaluation prior)) : Rating.Key p.offers.size :=
  ⟨score.index,score.gain,score.charge⟩

def ratingAt (prior : Selection p) (stored : Sparse.Values prior) (seen : Known prior)
    (index : Fin p.offers.size) : Option (Rating.Key p.offers.size) :=
  (Sparse.score? prior stored seen index).map key

/-- Only the changed leaf's ancestors are reconstructed. Other subtrees are
shared; there is no refresh traversal over the remaining candidate leaves. -/
def updateCache {α : Type} {order : Preference α} {depth : Nat}
    (cache : Cache order depth) (index : Fin (2^depth)) (value : Option α) :
    Cache order depth := cache.tree.updated index.val value

theorem updateCache_exact {α : Type} {order : Preference α} {depth : Nat}
    (cache : Cache order depth) (index : Fin (2^depth)) (value : Option α) :
    (updateCache cache index value).tree.values = cache.tree.values.set index.val value :=
  cache.tree.updated_values index.val value index.isLt

/-- Research entry only: no csimp replacement or production caller is installed.
Selection construction retains the existing freshness and dual-budget proofs.
Full ordered-refinement proof is still required before production connection. -/
def choose? (p : Problem) : Option (Selection p × Statistics) := do
  let initial ← empty? p
  let depth := (p.offers.size+1).log2+1
  if capacity : p.offers.size ≤ 2^depth then
    let layout := Sparse.layout p
    let initialValues := Sparse.values initial
    let seen := known initial
    let keys := (List.finRange p.offers.size).map (ratingAt initial initialValues seen) |>.toArray
    let mut tree := StableWinnerIndex.build (Rating.preference p.offers.size) depth keys
    let mut state : (prior : Selection p) × Sparse.Values prior := ⟨initial,initialValues⟩
    let mut stats : Statistics := {}
    let mut stopped := false
    for _ in [:p.offers.size+1] do
      let prior := state.1
      let stored := state.2
      let seen := known prior
      let mut winner : Option (Score prior (evaluation prior)) := none
      for _ in [:p.offers.size+1] do
        let some held := tree.best | break
        stats := {stats with checkedWinners := stats.checkedWinners+1}
        match Sparse.score? prior stored seen held.index with
        | some score =>
            if key score != held then failure
            winner := some score
            break
        | none =>
            let bounded : held.index.val < 2^depth := Nat.lt_of_lt_of_le held.index.isLt capacity
            tree := updateCache tree ⟨held.index.val,bounded⟩ none
            stats := {stats with
              pointUpdates := stats.pointUpdates+1
              rejectedByCurrentBudget := stats.rejectedByCurrentBudget+1}
      let some score := winner | stopped := true; break
      let next := score.proposal.result
      let nodes := layout.nodes.changed stored.base.nodeIndex p.offers[score.index].closure
      let cues := layout.cues.changed stored.base.cueIndex p.offers[score.index].covers
      let changed := Eggshell.hashDistinct (score.index :: nodes ++ cues)
      let updated := stored.advance layout next score.index rfl
      let nextSeen := known next
      for index in changed do
        let bounded : index.val < 2^depth := Nat.lt_of_lt_of_le index.isLt capacity
        tree := updateCache tree ⟨index.val,bounded⟩ (ratingAt next updated nextSeen index)
        stats := {stats with pointUpdates := stats.pointUpdates+1}
      stats := {stats with rounds := stats.rounds+1}
      state := ⟨next,updated⟩
    unless stopped do failure
    return (SharedCoverage.prefer state.1 (SharedCoverage.bestSingleton initial),stats)
  else none

end SharedCoverage.Deferred.ChangedWinner
