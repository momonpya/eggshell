module
public import Std
public import Eggshell.HashDistinct
@[expose] public section

/- Independent evidence closures over a shared, immutable payload basis.
   This module has no Work, Match, Union, IO or completion operation.
   A caller must supply original ranges and their required provenance nodes.
   Selection uses current-search cue weights; it contains no expected answer. -/
namespace SharedCoverage

structure Offer (nodes cues : Nat) where
  closure : List (Fin nodes)
  covers : List (Fin cues)

structure Problem where
  costs : Array (Nat × Nat)
  weights : Array Nat
  offers : Array (Offer costs.size weights.size)
  fixed : Nat × Nat := (0,0)
  limit : Nat × Nat

def nodes (p : Problem) (selected : List (Fin p.offers.size)) : List (Fin p.costs.size) :=
  (selected.flatMap fun index => p.offers[index].closure).eraseDups

def cues (p : Problem) (selected : List (Fin p.offers.size)) : List (Fin p.weights.size) :=
  (selected.flatMap fun index => p.offers[index].covers).eraseDups

def nodesFast (p : Problem) (selected : List (Fin p.offers.size)) : List (Fin p.costs.size) :=
  Eggshell.hashDistinct (selected.flatMap fun index => p.offers[index].closure)

def cuesFast (p : Problem) (selected : List (Fin p.offers.size)) : List (Fin p.weights.size) :=
  Eggshell.hashDistinct (selected.flatMap fun index => p.offers[index].covers)

@[csimp] theorem nodes_compiled : @nodes = @nodesFast := by
  funext p selected
  exact (Eggshell.HashDistinct.reference _).symm

@[csimp] theorem cues_compiled : @cues = @cuesFast := by
  funext p selected
  exact (Eggshell.HashDistinct.reference _).symm

def cost (p : Problem) (selected : List (Fin p.offers.size)) : Nat × Nat :=
  (nodes p selected).foldl (fun total index =>
    (total.1 + p.costs[index].1,total.2 + p.costs[index].2)) p.fixed

def benefit (p : Problem) (selected : List (Fin p.offers.size)) : Nat :=
  ((cues p selected).map fun index => p.weights[index]).sum

/-- Native and byte limits apply to the union, including shared source frames. -/
structure Selection (p : Problem) where
  selected : List (Fin p.offers.size)
  unique : selected.Nodup
  charsFit : (cost p selected).1 ≤ p.limit.1
  bytesFit : (cost p selected).2 ≤ p.limit.2

def empty? (p : Problem) : Option (Selection p) :=
  if fits : p.fixed.1 ≤ p.limit.1 ∧ p.fixed.2 ≤ p.limit.2 then
    some ⟨[],by simp,by simpa [cost,nodes] using fits.1,by simpa [cost,nodes] using fits.2⟩
  else none

def extend? (prior : Selection p) (index : Fin p.offers.size) : Option (Selection p) :=
  if fresh : index ∉ prior.selected then
    let next := prior.selected ++ [index]
    if fits : (cost p next).1 ≤ p.limit.1 ∧ (cost p next).2 ≤ p.limit.2 then
      some ⟨next,by
        apply List.nodup_append.mpr
        refine ⟨prior.unique,by simp,?_⟩
        intro a present b singleton same
        have last : b = index := List.mem_singleton.mp singleton
        exact fresh ((same.trans last) ▸ present),fits.1,fits.2⟩
    else none
  else none

structure Proposal (prior : Selection p) where
  result : Selection p
  gain : Nat
  positive : 0 < gain
  /-- Both limits enter the same denominator. Integer cross-products avoid
  rounding, division and a fitted tuning coefficient. -/
  charge : Nat

def proposal? (prior : Selection p) (index : Fin p.offers.size) : Option (Proposal prior) := do
  let result ← extend? prior index
  let gain := benefit p result.selected - benefit p prior.selected
  if positive : 0 < gain then
    let before := cost p prior.selected
    let after := cost p result.selected
    let charge := max ((after.1-before.1)*p.limit.2) ((after.2-before.2)*p.limit.1)
    pure ⟨result,gain,positive,charge⟩
  else none

/-- Stable ties retain the earlier declared offer. Zero-charge novel evidence
precedes charged evidence, without giving a duplicate cue another vote. -/
def better (next previous : Proposal prior) : Bool :=
  if next.charge == 0 then previous.charge != 0 || previous.gain < next.gain
  else if previous.charge == 0 then false
  else previous.gain*next.charge < next.gain*previous.charge

def best (prior : Selection p) : Option (Proposal prior) :=
  (List.finRange p.offers.size).foldl (fun found index =>
    match proposal? prior index,found with
    | none,_ => found
    | some next,none => some next
    | some next,some previous => if better next previous then some next else found) none


theorem removeAll_distinct [BEq α] [LawfulBEq α] (left right : List α) :
    left.removeAll right.eraseDups = left.removeAll right := by
  simp [List.removeAll, List.elem_eq_contains, List.contains_eq_mem]

theorem nodes_append_one (p : Problem) (selected : List (Fin p.offers.size))
    (index : Fin p.offers.size) :
    nodes p (selected ++ [index]) = nodes p selected ++
      (p.offers[index].closure.removeAll (nodes p selected)).eraseDups := by
  simp only [nodes, List.flatMap_append, List.flatMap_singleton, List.eraseDups_append]
  rw [removeAll_distinct]

theorem cues_append_one (p : Problem) (selected : List (Fin p.offers.size))
    (index : Fin p.offers.size) :
    cues p (selected ++ [index]) = cues p selected ++
      (p.offers[index].covers.removeAll (cues p selected)).eraseDups := by
  simp only [cues, List.flatMap_append, List.flatMap_singleton, List.eraseDups_append]
  rw [removeAll_distinct]

structure Evaluation (prior : Selection p) where
  nodeIndex : Std.HashMap (Fin p.costs.size) Unit
  nodesExact : Eggshell.HashDistinct.Seen nodeIndex (nodes p prior.selected)
  cueIndex : Std.HashMap (Fin p.weights.size) Unit
  cuesExact : Eggshell.HashDistinct.Seen cueIndex (cues p prior.selected)
  beforeCost : Nat × Nat
  costExact : beforeCost = cost p prior.selected
  beforeBenefit : Nat
  benefitExact : beforeBenefit = benefit p prior.selected

def evaluation (prior : Selection p) : Evaluation prior := {
  nodeIndex := (nodes p prior.selected).foldl (fun known node => known.insert node ()) {}
  nodesExact := by intro query; simp [Eggshell.HashDistinct.fold_contains]
  cueIndex := (cues p prior.selected).foldl (fun known cue => known.insert cue ()) {}
  cuesExact := by intro query; simp [Eggshell.HashDistinct.fold_contains]
  beforeCost := cost p prior.selected
  costExact := rfl
  beforeBenefit := benefit p prior.selected
  benefitExact := rfl}

variable {p : Problem} {prior : Selection p}

def Evaluation.afterCost (cached : Evaluation prior) (index : Fin p.offers.size) : Nat × Nat :=
  let fresh := Eggshell.hashDistinct (p.offers[index].closure.filter fun node => !cached.nodeIndex.contains node)
  fresh.foldl (fun total node => (total.1+p.costs[node].1,total.2+p.costs[node].2)) cached.beforeCost

def Evaluation.afterBenefit (cached : Evaluation prior) (index : Fin p.offers.size) : Nat :=
  let fresh := Eggshell.hashDistinct (p.offers[index].covers.filter fun cue => !cached.cueIndex.contains cue)
  cached.beforeBenefit + (fresh.map fun cue => p.weights[cue]).sum

theorem Evaluation.afterCost_exact (cached : Evaluation prior) (index : Fin p.offers.size) :
    cached.afterCost index = cost p (prior.selected ++ [index]) := by
  unfold Evaluation.afterCost cost
  rw [nodes_append_one, List.foldl_append, Eggshell.HashDistinct.reference, cached.costExact]
  simp only [List.removeAll, List.elem_eq_contains, cached.nodesExact _]
  rfl

theorem Evaluation.afterBenefit_exact (cached : Evaluation prior) (index : Fin p.offers.size) :
    cached.afterBenefit index = benefit p (prior.selected ++ [index]) := by
  unfold Evaluation.afterBenefit benefit
  rw [cues_append_one, List.map_append, List.sum_append, Eggshell.HashDistinct.reference, cached.benefitExact]
  simp only [List.removeAll, List.elem_eq_contains, cached.cuesExact _]
  rfl

def extendCached? (prior : Selection p) (cached : Evaluation prior)
    (index : Fin p.offers.size) : Option (Selection p) :=
  if fresh : index ∉ prior.selected then
    let after := cached.afterCost index
    if fits : after.1 ≤ p.limit.1 ∧ after.2 ≤ p.limit.2 then
      some ⟨prior.selected ++ [index],by
        apply List.nodup_append.mpr
        refine ⟨prior.unique,by simp,?_⟩
        intro a present b singleton same
        have last : b = index := List.mem_singleton.mp singleton
        exact fresh ((same.trans last) ▸ present),
        by rw [← cached.afterCost_exact index]; exact fits.1,
        by rw [← cached.afterCost_exact index]; exact fits.2⟩
    else none
  else none

theorem extendCached_exact (cached : Evaluation prior) (index : Fin p.offers.size) :
    extendCached? prior cached index = extend? prior index := by
  simp only [extendCached?, extend?, Evaluation.afterCost_exact]

def proposalCached? (prior : Selection p) (cached : Evaluation prior)
    (index : Fin p.offers.size) : Option (Proposal prior) := do
  let result ← extendCached? prior cached index
  let gain := cached.afterBenefit index - cached.beforeBenefit
  if positive : 0 < gain then
    let before := cached.beforeCost
    let after := cached.afterCost index
    let charge := max ((after.1-before.1)*p.limit.2) ((after.2-before.2)*p.limit.1)
    pure ⟨result,gain,positive,charge⟩
  else none

theorem proposalCached_exact (cached : Evaluation prior) (index : Fin p.offers.size) :
    proposalCached? prior cached index = proposal? prior index := by
  unfold proposalCached? proposal?
  rw [extendCached_exact]
  by_cases fresh : index ∉ prior.selected
  · by_cases fits : (cost p (prior.selected ++ [index])).1 ≤ p.limit.1 ∧
        (cost p (prior.selected ++ [index])).2 ≤ p.limit.2
    · simp [extend?,fresh,fits,Evaluation.afterBenefit_exact,Evaluation.afterCost_exact,
        cached.costExact,cached.benefitExact]
    · simp [extend?,fresh,fits]
  · simp [extend?,fresh]

def bestCached (prior : Selection p) : Option (Proposal prior) :=
  let cached := evaluation prior
  (List.finRange p.offers.size).foldl (fun found index =>
    match proposalCached? prior cached index,found with
    | none,_ => found
    | some next,none => some next
    | some next,some previous => if better next previous then some next else found) none

@[csimp] theorem best_cached_compiled : @best = @bestCached := by
  funext p prior
  simp only [best,bestCached,proposalCached_exact]


def fill (fuel : Nat) (prior : Selection p) : Selection p :=
  match fuel with
  | 0 => prior
  | fuel+1 => match best prior with
    | none => prior
    | some next => fill fuel next.result

/-- Keep the first selection on equal benefit. Costs and dependency closure
remain certified by Selection; this makes no approximation-ratio claim. -/
def prefer (first second : Selection p) : Selection p :=
  if benefit p first.selected < benefit p second.selected then second else first

theorem prefer_first (first second : Selection p) :
    benefit p first.selected ≤ benefit p (prefer first second).selected := by
  unfold prefer
  split <;> omega

theorem prefer_second (first second : Selection p) :
    benefit p second.selected ≤ benefit p (prefer first second).selected := by
  unfold prefer
  split <;> omega

def singletonScan (initial best : Selection p)
    (pending : List (Fin p.offers.size)) : Selection p :=
  match pending with
  | [] => best
  | index :: tail => singletonScan initial
      (match extend? initial index with
       | none => best
       | some one => prefer best one) tail

theorem singletonScan_keeps (initial best : Selection p)
    (pending : List (Fin p.offers.size)) :
    benefit p best.selected ≤ benefit p (singletonScan initial best pending).selected := by
  induction pending generalizing best with
  | nil => exact Nat.le_refl _
  | cons index tail ih =>
    simp only [singletonScan]
    cases extension : extend? initial index with
    | none => exact ih best
    | some one => exact Nat.le_trans (prefer_first best one) (ih _)

theorem singletonScan_covers (initial best : Selection p)
    (pending : List (Fin p.offers.size)) (index : Fin p.offers.size)
    (present : index ∈ pending) (one : Selection p)
    (created : extend? initial index = some one) :
    benefit p one.selected ≤ benefit p (singletonScan initial best pending).selected := by
  induction pending generalizing best with
  | nil => simp at present
  | cons head tail ih =>
    simp only [singletonScan]
    rcases List.mem_cons.mp present with same | later
    · subst head
      rw [created]
      exact Nat.le_trans (prefer_second best one) (singletonScan_keeps initial _ tail)
    · cases extension : extend? initial head with
      | none => exact ih best later
      | some next => exact ih (prefer best next) later

def bestSingleton (initial : Selection p) : Selection p :=
  singletonScan initial initial (List.finRange p.offers.size)

theorem bestSingleton_covers (initial : Selection p) (index : Fin p.offers.size)
    (one : Selection p) (created : extend? initial index = some one) :
    benefit p one.selected ≤ benefit p (bestSingleton initial).selected := by
  exact singletonScan_covers initial initial _ index (List.mem_finRange index) one created

def chooseFrom (initial : Selection p) : Selection p :=
  prefer (fill p.offers.size initial) (bestSingleton initial)

theorem chooseFrom_dominates_greedy (initial : Selection p) :
    benefit p (fill p.offers.size initial).selected ≤ benefit p (chooseFrom initial).selected :=
  prefer_first _ _

theorem chooseFrom_dominates_singleton (initial : Selection p)
    (index : Fin p.offers.size) (one : Selection p)
    (created : extend? initial index = some one) :
    benefit p one.selected ≤ benefit p (chooseFrom initial).selected :=
  Nat.le_trans (bestSingleton_covers initial index one created) (prefer_second _ _)

def choose? (p : Problem) : Option (Selection p) := do
  let initial ← empty? p
  pure (chooseFrom initial)


theorem within_limits (result : Selection p) :
    (cost p result.selected).1 ≤ p.limit.1 ∧ (cost p result.selected).2 ≤ p.limit.2 :=
  ⟨result.charsFit,result.bytesFit⟩

theorem source_node_is_declared (p : Problem) (selected : List (Fin p.offers.size))
    (node : Fin p.costs.size) (present : node ∈ nodes p selected) :
    ∃ index ∈ selected, node ∈ p.offers[index].closure := by
  have member : node ∈ selected.flatMap (fun index => p.offers[index].closure) := by
    simpa [nodes] using present
  exact List.mem_flatMap.mp member

theorem selected_closure_is_complete (p : Problem) (selected : List (Fin p.offers.size))
    (index : Fin p.offers.size) (chosen : index ∈ selected)
    (node : Fin p.costs.size) (required : node ∈ p.offers[index].closure) :
    node ∈ nodes p selected := by
  simp only [nodes,List.mem_eraseDups]
  exact List.mem_flatMap.mpr ⟨index,chosen,required⟩

private theorem erase_nodup [BEq α] [LawfulBEq α] (xs : List α) : xs.eraseDups.Nodup := by
  match xs with
  | [] => simp
  | x :: tail =>
      rw [List.eraseDups_cons,List.nodup_cons]
      constructor
      · simp
      · exact erase_nodup (tail.filter fun y => !y == x)
termination_by xs.length
decreasing_by
  have := List.length_filter_le (fun y => !y == x) tail
  simp only [List.length_cons]
  omega

theorem duplicate_payload_charged_once (p : Problem) (selected : List (Fin p.offers.size)) :
    (nodes p selected).Nodup := by
  exact erase_nodup _

theorem duplicate_cue_scored_once (p : Problem) (selected : List (Fin p.offers.size)) :
    (cues p selected).Nodup := by
  exact erase_nodup _

end SharedCoverage
