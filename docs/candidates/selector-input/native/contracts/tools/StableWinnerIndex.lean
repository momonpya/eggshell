module
public import Std
@[expose] public section

namespace StableWinnerIndex

/-- A strict weak preference. Equal preferences retain the earlier leaf. -/
structure Preference (α : Type) where
  better : α → α → Bool
  trans : ∀ a b c, better a b = true → better b c = true → better a c = true
  negTrans : ∀ a b c, better a b ≠ true → better b c ≠ true → better a c ≠ true

def merge (order : Preference α) : Option α → Option α → Option α
  | none,right => right
  | left,none => left
  | some left,some right => if order.better right left then some right else some left

@[simp] theorem merge_none_left (order : Preference α) (value : Option α) :
    merge order none value = value := rfl

@[simp] theorem merge_none_right (order : Preference α) (value : Option α) :
    merge order value none = value := by cases value <;> rfl

theorem merge_assoc (order : Preference α) (a b c : Option α) :
    merge order (merge order a b) c = merge order a (merge order b c) := by
  cases a with
  | none => rfl
  | some a =>
    cases b with
    | none => rfl
    | some b =>
      cases c with
      | none => simp
      | some c =>
        by_cases ba : order.better b a = true
        · by_cases cb : order.better c b = true
          · have ca := order.trans c b a cb ba
            simp [merge,ba,cb,ca]
          · simp [merge,ba,cb]
        · by_cases cb : order.better c b = true
          · simp [merge,ba,cb]
          · have ca := order.negTrans c b a cb ba
            simp [merge,ba,cb,ca]

def winner (order : Preference α) (values : List (Option α)) : Option α :=
  values.foldl (merge order) none

theorem fold_from (order : Preference α) (values : List (Option α)) (initial : Option α) :
    values.foldl (merge order) initial = merge order initial (winner order values) := by
  induction values generalizing initial with
  | nil => simp [winner]
  | cons head tail ih =>
    simp only [List.foldl_cons,winner]
    rw [ih,ih]
    exact merge_assoc order initial head (winner order tail)

theorem winner_append (order : Preference α) (left right : List (Option α)) :
    winner order (left++right) = merge order (winner order left) (winner order right) := by
  rw [winner,List.foldl_append,fold_from]
  rfl

theorem merge_mem (order : Preference α) (left right : Option α) (value : α)
    (found : merge order left right = some value) : left = some value ∨ right = some value := by
  cases left <;> cases right <;> simp_all [merge]
  split at found <;> simp_all

theorem winner_mem (order : Preference α) (values : List (Option α)) (value : α)
    (found : winner order values = some value) : some value ∈ values := by
  induction values with
  | nil => simp [winner] at found
  | cons head tail ih =>
    rw [winner,List.foldl_cons,fold_from] at found
    rcases merge_mem order head (winner order tail) value found with same | rest
    · simp [same]
    · exact List.mem_cons_of_mem _ (ih rest)

/-- A cached tournament contains the proof of its cached winner in its type.
Depth, rather than a mutable leaf count, fixes the update path. -/
inductive Tree (order : Preference α) : Nat → Option α → Type
  | leaf (value : Option α) : Tree order 0 value
  | branch {depth : Nat} {leftBest rightBest : Option α}
      (left : Tree order depth leftBest) (right : Tree order depth rightBest) :
      Tree order (depth+1) (merge order leftBest rightBest)

structure Cache (order : Preference α) (depth : Nat) where
  best : Option α
  tree : Tree order depth best

variable {α : Type} {order : Preference α} {depth : Nat} {best : Option α}

def Tree.values : {depth : Nat} → {best : Option α} → Tree order depth best → List (Option α)
  | _,_,.leaf value => [value]
  | _,_,.branch left right => left.values ++ right.values

theorem Tree.values_length (tree : Tree order depth best) : tree.values.length = 2^depth := by
  induction tree with
  | leaf => simp [values]
  | branch left right ihl ihr => simp [values,ihl,ihr,Nat.pow_succ,Nat.mul_two]

theorem Tree.best_exact (tree : Tree order depth best) : winner order tree.values = best := by
  induction tree with
  | leaf => simp [winner,values]
  | branch left right ihl ihr => rw [values,winner_append,ihl,ihr]

def join (left right : Cache order depth) : Cache order (depth+1) :=
  ⟨merge order left.best right.best,.branch left.tree right.tree⟩

def Tree.updated : {depth : Nat} → {best : Option α} →
    Tree order depth best → Nat → Option α → Cache order depth
  | _,_,.leaf _,_,value => ⟨value,.leaf value⟩
  | _,_,@Tree.branch _ _ depth _ _ left right,index,value =>
    if index < 2^depth then join (left.updated index value) ⟨_,right⟩
    else join ⟨_,left⟩ (right.updated (index-2^depth) value)

theorem Tree.updated_values (tree : Tree order depth best) (index : Nat) (value : Option α)
    (bounded : index < 2^depth) :
    (tree.updated index value).tree.values = tree.values.set index value := by
  induction tree generalizing index with
  | leaf previous =>
    have : index = 0 := by simpa using bounded
    simp [updated,values,this]
  | @branch depth leftBest rightBest left right ihl ihr =>
    simp only [updated]
    by_cases inside : index < 2^depth
    · rw [if_pos inside]
      simp only [join,values,ihl index inside]
      rw [List.set_append_left index value (by simpa [left.values_length] using inside)]
    · rw [if_neg inside]
      have half := left.values_length
      have rest : index-2^depth < 2^depth := by
        simp only [Nat.pow_succ,Nat.mul_two] at bounded
        omega
      simp only [join,values,ihr (index-2^depth) rest]
      rw [List.set_append_right index value (by omega)]
      rw [half]

def build (order : Preference α) (depth : Nat) (values : Array (Option α)) (first : Nat := 0) :
    Cache order depth :=
  match depth with
  | 0 => let value := values[first]?.getD none; ⟨value,.leaf value⟩
  | depth+1 => join (build order depth values first) (build order depth values (first+2^depth))

theorem build_values (order : Preference α) (depth : Nat) (values : Array (Option α)) (first : Nat) :
    (build order depth values first).tree.values =
      (List.range (2^depth)).map (fun index => values[first+index]?.getD none) := by
  induction depth generalizing first with
  | zero => simp [build,Tree.values]
  | succ depth ih =>
    simp only [build,join,Tree.values,ih,Nat.pow_succ,Nat.mul_two,List.range_add,List.map_append,List.map_map]
    congr 1
    apply List.map_congr_left
    intro index _
    simp [Nat.add_assoc]

end StableWinnerIndex
