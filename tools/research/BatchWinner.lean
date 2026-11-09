module
public import tools.StableWinnerIndex
@[expose] public section

namespace StableWinnerIndex.Batch

/-- A sparse set of replacement leaves. Building it performs no comparisons
of candidate ratings; applying it rebuilds each changed ancestor once. -/
inductive Patch (α : Type) : Nat → Type
  | keep : Patch α depth
  | write (value : Option α) : Patch α 0
  | branch (left right : Patch α depth) : Patch α (depth+1)

def Patch.lookup : {depth : Nat} → Patch α depth → Nat → Option (Option α)
  | _,.keep,_ => none
  | _,.write value,_ => some value
  | depth+1,.branch left right,index =>
    if index < 2^depth then left.lookup index else right.lookup (index-2^depth)

def Patch.insert : {depth : Nat} → Patch α depth → Nat → Option α → Patch α depth
  | 0,_,_,value => .write value
  | depth+1,.keep,index,value =>
    if index < 2^depth then .branch (Patch.insert .keep index value) .keep
    else .branch .keep (Patch.insert .keep (index-2^depth) value)
  | depth+1,.branch left right,index,value =>
    if index < 2^depth then .branch (left.insert index value) right
    else .branch left (right.insert (index-2^depth) value)

def applyTree {order : Preference α} : {depth : Nat} → {best : Option α} →
    Tree order depth best → Patch α depth → Cache order depth
  | _,_,.leaf old,patch => match patch with
    | .keep => ⟨old,.leaf old⟩
    | .write value => ⟨value,.leaf value⟩
  | _,_,@Tree.branch _ _ childDepth leftBest rightBest oldLeft oldRight,patch =>
    match patch with
    | .keep => ⟨_,.branch oldLeft oldRight⟩
    | .branch left right => join (applyTree oldLeft left) (applyTree oldRight right)

def Patch.apply {order : Preference α} (patch : Patch α depth) (tree : Tree order depth best) :
    Cache order depth := applyTree tree patch

theorem Patch.insert_lookup (patch : Patch α depth) (index query : Nat) (value : Option α)
    (bounded : index < 2^depth) (queryBounded : query < 2^depth) :
    (patch.insert index value).lookup query =
      if index = query then some value else patch.lookup query := by
  induction depth generalizing index query with
  | zero =>
    have i : index = 0 := by simpa using bounded
    have q : query = 0 := by simpa using queryBounded
    cases patch <;> simp [insert,lookup,i,q]
  | succ depth ih =>
    have limit : 2^(depth+1) = 2^depth+2^depth := by simp [Nat.pow_succ,Nat.mul_two]
    cases patch with
    | keep =>
      by_cases i : index < 2^depth <;> by_cases q : query < 2^depth
      all_goals simp only [insert,lookup,i,q,↓reduceIte]
      · rw [ih _ _ _ i q]; rfl
      · have ne : index ≠ query := by omega
        simp [ne]
      · have ne : index ≠ query := by omega
        simp [ne]
      · have ib : index-2^depth < 2^depth := by omega
        have qb : query-2^depth < 2^depth := by omega
        rw [ih _ _ _ ib qb]
        have equal : index-2^depth = query-2^depth ↔ index = query := by omega
        simp [equal,lookup]
    | branch left right =>
      by_cases i : index < 2^depth <;> by_cases q : query < 2^depth
      all_goals simp only [insert,lookup,i,q,↓reduceIte]
      · rw [ih _ _ _ i q]
      · have ne : index ≠ query := by omega
        simp [ne]
      · have ne : index ≠ query := by omega
        simp [ne]
      · have ib : index-2^depth < 2^depth := by omega
        have qb : query-2^depth < 2^depth := by omega
        rw [ih _ _ _ ib qb]
        have equal : index-2^depth = query-2^depth ↔ index = query := by omega
        simp [equal]

theorem Patch.apply_lookup {order : Preference α} (patch : Patch α depth)
    (tree : Tree order depth best) (query : Nat) (bounded : query < 2^depth) :
    (patch.apply tree).tree.values[query]? =
      match patch.lookup query with
      | some value => some value
      | none => tree.values[query]? := by
  induction patch generalizing best query with
  | keep => cases tree <;> rfl
  | write value =>
    have q : query = 0 := by simpa using bounded
    cases tree
    simp [Patch.apply,applyTree,lookup,Tree.values,q]
  | @branch depth left right ihl ihr =>
    cases tree with
    | branch oldLeft oldRight =>
      change ((left.apply oldLeft).tree.values ++ (right.apply oldRight).tree.values)[query]? =
        match (if query < 2^depth then left.lookup query else right.lookup (query-2^depth)) with
        | some value => some value
        | none => (oldLeft.values ++ oldRight.values)[query]?
      by_cases q : query < 2^depth
      · rw [if_pos q]
        rw [List.getElem?_append_left (by simpa [Tree.values_length] using q),
          List.getElem?_append_left (by simpa [Tree.values_length] using q)]
        exact ihl oldLeft query q
      · have after : query-2^depth < 2^depth := by
          simp only [Nat.pow_succ,Nat.mul_two] at bounded
          omega
        rw [if_neg q]
        rw [List.getElem?_append_right (by simpa [Tree.values_length] using Nat.le_of_not_gt q),
          List.getElem?_append_right (by simpa [Tree.values_length] using Nat.le_of_not_gt q)]
        simp only [Tree.values_length]
        exact ihr oldRight (query-2^depth) after

def replacements (depth : Nat) (indices : List Nat) (value : Nat → Option α) : Patch α depth :=
  indices.foldl (fun patch index => patch.insert index (value index)) .keep

theorem fold_lookup (patch : Patch α depth) (indices : List Nat) (value : Nat → Option α)
    (bounded : ∀ index ∈ indices, index < 2^depth) (query : Nat) (queryBounded : query < 2^depth) :
    (indices.foldl (fun patch index => patch.insert index (value index)) patch).lookup query =
      if query ∈ indices then some (value query) else patch.lookup query := by
  induction indices generalizing patch with
  | nil => simp
  | cons head tail ih =>
    simp only [List.foldl_cons]
    rw [ih _ (fun index present => bounded index (List.mem_cons_of_mem _ present))]
    by_cases later : query ∈ tail
    · simp [later]
    · rw [if_neg later,Patch.insert_lookup _ head query _ (bounded head (by simp)) queryBounded]
      by_cases same : head = query
      · subst head; simp
      · simp [same,Ne.symm same,later]

theorem replacements_lookup (depth : Nat) (indices : List Nat) (value : Nat → Option α)
    (bounded : ∀ index ∈ indices, index < 2^depth) (query : Nat) (queryBounded : query < 2^depth) :
    (replacements depth indices value).lookup query =
      if query ∈ indices then some (value query) else none := by
  simpa only [replacements,Patch.lookup] using fold_lookup (.keep : Patch α depth) indices value bounded query queryBounded

def update {order : Preference α} (cache : Cache order depth) (indices : List Nat)
    (value : Nat → Option α) : Cache order depth :=
  (replacements depth indices value).apply cache.tree

theorem update_lookup {order : Preference α} (cache : Cache order depth) (indices : List Nat)
    (value : Nat → Option α) (bounded : ∀ index ∈ indices, index < 2^depth) (query : Nat) :
    (update cache indices value).tree.values[query]? =
      if query ∈ indices then some (value query) else cache.tree.values[query]? := by
  by_cases inside : query < 2^depth
  · rw [update,Patch.apply_lookup _ _ query inside,replacements_lookup _ _ _ bounded query inside]
    by_cases present : query ∈ indices <;> simp [present]
  · have absent : query ∉ indices := fun present => inside (bounded query present)
    rw [if_neg absent]
    rw [List.getElem?_eq_none (by simpa [Tree.values_length] using Nat.le_of_not_gt inside),
      List.getElem?_eq_none (by simpa [Tree.values_length] using Nat.le_of_not_gt inside)]

def sequential {order : Preference α} (cache : Cache order depth) (indices : List Nat)
    (value : Nat → Option α) : Cache order depth :=
  indices.foldl (fun cache index => cache.tree.updated index (value index)) cache

theorem sequential_lookup {order : Preference α} (cache : Cache order depth) (indices : List Nat)
    (value : Nat → Option α) (bounded : ∀ index ∈ indices, index < 2^depth) (query : Nat) :
    (sequential cache indices value).tree.values[query]? =
      if query ∈ indices then some (value query) else cache.tree.values[query]? := by
  induction indices generalizing cache with
  | nil => simp [sequential]
  | cons head tail ih =>
    simp only [sequential,List.foldl_cons] at *
    rw [ih _ (fun index present => bounded index (List.mem_cons_of_mem _ present))]
    by_cases later : query ∈ tail
    · simp [later]
    · rw [if_neg later,Tree.updated_values _ _ _ (bounded head (by simp))]
      by_cases same : head = query
      · subst query
        have bound : head < cache.tree.values.length := by simpa [Tree.values_length] using bounded head (by simp)
        simp [List.getElem?_set_self bound]
      · simp [List.getElem?_set_ne same,Ne.symm same,later]

theorem update_values_exact {order : Preference α} (cache : Cache order depth) (indices : List Nat)
    (value : Nat → Option α) (bounded : ∀ index ∈ indices, index < 2^depth) :
    (update cache indices value).tree.values = (sequential cache indices value).tree.values := by
  apply List.ext_getElem?
  intro query
  rw [update_lookup _ _ _ bounded,sequential_lookup _ _ _ bounded]

theorem update_best_exact {order : Preference α} (cache : Cache order depth) (indices : List Nat)
    (value : Nat → Option α) (bounded : ∀ index ∈ indices, index < 2^depth) :
    (update cache indices value).best = (sequential cache indices value).best := by
  rw [← (update cache indices value).tree.best_exact,
    ← (sequential cache indices value).tree.best_exact,update_values_exact _ _ _ bounded]

def Patch.joins : {depth : Nat} → Patch α depth → Nat
  | _,.keep => 0
  | _,.write _ => 0
  | _,.branch left right => 1+left.joins+right.joins

end StableWinnerIndex.Batch
