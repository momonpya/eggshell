module
public import tools.DeferredCoverage
@[expose] public section

namespace SharedCoverage.Deferred.Sparse
open Eggshell

def remaining [BEq α] [Hashable α] (seen : Std.HashMap α Unit) (features : List α) : List α :=
  hashDistinct (features.filter fun feature => !seen.contains feature)

theorem weighted_partition (measure : α → Nat) (items : List α) (part : α → Bool) :
    weighted measure items = weighted measure (items.filter part) +
      weighted measure (items.filter fun item => !part item) := by
  simp only [weighted_exact]
  induction items with
  | nil => simp
  | cons head tail ih =>
    cases h : part head <;> simp [h,ih,Nat.add_assoc,Nat.add_left_comm]

theorem remaining_discount [BEq α] [LawfulBEq α] [Hashable α]
    (seen : Std.HashMap α Unit) (features added : List α) (measure : α → Nat)
    (unique : added.Nodup) (fresh : ∀ item ∈ added, seen.contains item = false) :
    weighted measure (remaining (added.foldl (fun index item => index.insert item ()) seen) features) =
      weighted measure (remaining seen features) - weighted measure (added.filter features.contains) := by
  let prior := remaining seen features
  let after := remaining (added.foldl (fun index item => index.insert item ()) seen) features
  have afterPerm : after.Perm (prior.filter fun item => !added.contains item) := by
    apply (List.perm_ext_iff_of_nodup (HashDistinct.nodup _) ((HashDistinct.nodup _).filter _)).mpr
    intro item
    simp only [HashDistinct.mem,List.mem_filter,HashDistinct.fold_contains]
    cases a : seen.contains item <;> cases b : added.contains item <;> simp_all
  have paidPerm : (prior.filter added.contains).Perm (added.filter features.contains) := by
    apply (List.perm_ext_iff_of_nodup ((HashDistinct.nodup _).filter _) (unique.filter _)).mpr
    intro item
    simp only [List.mem_filter,HashDistinct.mem,List.contains_iff_mem,Bool.not_eq_true']
    constructor
    · rintro ⟨⟨inside,_⟩,paid⟩; exact ⟨paid,inside⟩
    · rintro ⟨paid,inside⟩; exact ⟨⟨inside,by simp [fresh item paid]⟩,paid⟩
  have afterSum := (afterPerm.map measure).sum_nat
  have paidSum := (paidPerm.map measure).sum_nat
  have split := weighted_partition measure prior (fun item => !added.contains item)
  simp only [Bool.not_not,weighted_exact] at split
  simp only [weighted_exact] at paidSum afterSum ⊢
  rw [afterSum,← paidSum,split,Nat.add_sub_cancel]

def modifyDistinct (values : Vector α n) (indices : List (Fin n)) (change : α → α) : Vector α n :=
  indices.foldl (fun current index => current.set index.val (change current[index]) index.isLt) values

theorem modifyDistinct_get (values : Vector α n) (indices : List (Fin n)) (change : α → α)
    (unique : indices.Nodup) (query : Fin n) :
    (modifyDistinct values indices change)[query] = if query ∈ indices then change values[query] else values[query] := by
  induction indices generalizing values with
  | nil => simp [modifyDistinct]
  | cons head tail ih =>
    have unique := List.nodup_cons.mp unique
    simp only [modifyDistinct,List.foldl_cons] at *
    rw [ih _ unique.2]
    by_cases later : query ∈ tail
    · have different : query.val ≠ head.val := by
        intro equal; have same := Fin.ext equal; exact unique.1 (same ▸ later)
      simp [later,Ne.symm different]
    · by_cases same : query = head
      · subst query; simp [later]
      · have different : query.val ≠ head.val := fun equal => same (Fin.ext equal)
        simp [later,same,Ne.symm different]

def Incidence.discount {n d : Nat} {features : Fin n → List (Fin d)}
    (layout : Incidence features) (values : Vector Nat n)
    (measure : Fin d → Nat) (added : List (Fin d)) : Vector Nat n :=
  added.foldl (fun current feature => modifyDistinct current (hashDistinct (layout.lookup feature))
    (fun value => value-measure feature)) values

theorem discount_fold (features : List α) [BEq α] (measure : α → Nat) (added : List α) (initial : Nat) :
    added.foldl (fun value item => if features.contains item then value-measure item else value) initial =
      initial-weighted measure (added.filter features.contains) := by
  induction added generalizing initial with
  | nil => simp [weighted]
  | cons head tail ih =>
    simp only [List.foldl_cons]
    cases inside : features.contains head <;>
      simp [inside,ih,weighted_exact,Nat.sub_sub]

theorem Incidence.discount_get {n d : Nat} {features : Fin n → List (Fin d)}
    (layout : Incidence features) (values : Vector Nat n)
    (measure : Fin d → Nat) (added : List (Fin d)) (query : Fin n) :
    (layout.discount values measure added)[query] =
      values[query] - weighted measure (added.filter (features query).contains) := by
  have go : ∀ added (values : Vector Nat n),
      (layout.discount values measure added)[query] =
        added.foldl (fun value feature => if (features query).contains feature then value-measure feature else value) values[query] := by
    intro added
    induction added with
    | nil => intro values; rfl
    | cons head tail ih =>
      intro values
      simp only [Incidence.discount,List.foldl_cons] at *
      rw [ih]
      rw [modifyDistinct_get _ _ _ (HashDistinct.nodup _) query]
      simp only [HashDistinct.mem,layout.lookup_exact,List.contains_iff_mem]
  rw [go,discount_fold]

variable {p : Problem} {prior : Selection p}

def Values.discountAdvance (stored : Values prior) (layout : Layout p) (next : Selection p)
    (winner : Fin p.offers.size) (extension : next.selected = prior.selected++[winner]) : Values next :=
  let before := stored.base
  let after := before.advance next winner extension
  have afterExact : after = evaluation next := before.advance_exact next winner extension stored.baseExact
  let added := before.freshCues winner
  {base := after
   baseExact := afterExact
   costs := patch stored.costs (rawCost after) (layout.nodes.changed before.nodeIndex p.offers[winner].closure)
   gains := layout.cues.discount stored.gains (fun cue => p.weights[cue]) added
   costsExact := by
    intro query
    rw [patch_exact]
    split
    · rw [afterExact]
    · rename_i absent
      rw [stored.costsExact]
      simp only [before,stored.baseExact] at absent
      unfold rawCost
      rw [nodeFilter_unchanged prior next winner query extension (layout.nodes.unchanged _ _ _ absent)]
   gainsExact := by
    intro query
    rw [layout.cues.discount_get,stored.gainsExact,← afterExact]
    have fresh : ∀ item ∈ added, before.cueIndex.contains item = false := by
      intro item member
      have member := (HashDistinct.mem item _).mp member
      simpa using (List.mem_filter.mp member).2
    have result := remaining_discount before.cueIndex p.offers[query].covers added
      (fun cue => p.weights[cue]) (HashDistinct.nodup _) fresh
    simpa only [rawGain,remaining,added,after,Evaluation.advance,before,stored.baseExact] using result.symm }

theorem Values.unique (left right : Values prior) : left = right := by
  have base := left.baseExact.trans right.baseExact.symm
  have costs : left.costs = right.costs := by
    apply Vector.ext
    intro index bound
    exact (left.costsExact ⟨index,bound⟩).trans (right.costsExact ⟨index,bound⟩).symm
  have gains : left.gains = right.gains := by
    apply Vector.ext
    intro index bound
    exact (left.gainsExact ⟨index,bound⟩).trans (right.gainsExact ⟨index,bound⟩).symm
  cases left
  cases right
  cases base
  cases costs
  cases gains
  rfl

@[csimp] theorem discountAdvance_exact : @Values.advance = @Values.discountAdvance := by
  funext p prior stored layout next winner extension
  exact Values.unique _ _
end SharedCoverage.Deferred.Sparse
