module

public import Eggshell.EvidenceReplay

@[expose] public section
namespace Eggshell.Matcher.SurfaceJoin

/-- Product lookup uses only its two occurrence arrays. It never constructs
all occurrence pairs merely to address one existing rank position. -/
theorem product_lookup (outer : List α) (inner : List β) (make : α → β → γ) (i : Nat) :
    (outer.flatMap (fun a => inner.map (make a)))[i]? =
      ((outer[i / inner.length]?).bind fun a => inner[i % inner.length]?.map (make a)) := by
  induction outer generalizing i with
  | nil => simp
  | cons head tail ih =>
    by_cases empty : inner.length = 0
    · have nil : inner = [] := by simpa using empty
      subst inner
      have product : (head :: tail).flatMap (fun a => ([] : List β).map (make a)) = [] :=
        List.flatMap_eq_nil_iff.mpr (by intro a _; rfl)
      rw [product]; simp
    · have positive : 0 < inner.length := by omega
      by_cases first : i < inner.length
      · simp only [List.flatMap_cons]
        rw [List.getElem?_append_left (by simpa using first), List.getElem?_map]
        simp [Nat.div_eq_of_lt first, Nat.mod_eq_of_lt first]
      · have after : inner.length ≤ i := by omega
        simp only [List.flatMap_cons]
        rw [List.getElem?_append_right (by simpa using after), List.length_map, ih]
        have split : i = inner.length + (i - inner.length) := by omega
        conv => rhs; rw [split]
        simp [Nat.add_div_left _ positive, Nat.add_mod_left]

structure Group where
  outer : Array IndexedSpan
  inner : Array IndexedSpan
  queryFirst : Bool

def Group.make (group : Group) (outer inner : IndexedSpan) : Evidence :=
  if group.queryFirst then ⟨outer, inner⟩ else ⟨inner, outer⟩

def Group.items (group : Group) : List Evidence :=
  group.outer.toList.flatMap (fun outer => group.inner.toList.map (group.make outer))

def Group.count (group : Group) : Nat := group.outer.size * group.inner.size

def Group.lookup (group : Group) (i : Nat) : Option Evidence := do
  let outer ← group.outer[i / group.inner.size]?
  let inner ← group.inner[i % group.inner.size]?
  pure (group.make outer inner)

theorem Group.count_exact (group : Group) : group.count = group.items.length := by
  have length (outer : List IndexedSpan) :
      (outer.flatMap (fun a => group.inner.toList.map (group.make a))).length =
        outer.length * group.inner.size := by
    induction outer with
    | nil => simp
    | cons head tail ih => simp [ih, Nat.add_mul, Nat.add_comm]
  simpa [Group.count, Group.items] using (length group.outer.toList).symm

theorem Group.lookup_exact (group : Group) (i : Nat) : group.lookup i = group.items[i]? := by
  rw [Group.items, product_lookup]
  simp [Group.lookup, Option.map_eq_bind, Function.comp_def]

/-- A balanced directory over the current overlapping surface groups. The
stored left count is a proof-carrying address boundary, never an unchecked
offset supplied by the memo row. -/
inductive Directory where
  | leaf (group : Group)
  | branch (left right : Directory) (leftCount : Nat)
  | empty

def Directory.items : Directory → List Evidence
  | .leaf group => group.items
  | .branch left right _ => left.items ++ right.items
  | .empty => []

def Directory.Valid : Directory → Prop
  | .leaf _ | .empty => True
  | .branch left right leftCount =>
      leftCount = left.items.length ∧ left.Valid ∧ right.Valid

def Directory.count : Directory → Nat
  | .leaf group => group.count
  | .branch _ right leftCount => leftCount + right.count
  | .empty => 0

theorem Directory.count_exact (directory : Directory) (valid : directory.Valid) :
    directory.count = directory.items.length := by
  induction directory with
  | leaf group => exact group.count_exact
  | branch left right leftCount _ ih =>
      simp only [Directory.Valid] at valid
      simp [Directory.count, Directory.items, valid.1, ih valid.2.2]
  | empty => rfl

def Directory.lookup : Directory → Nat → Option Evidence
  | .leaf group, i => group.lookup i
  | .branch left right leftCount, i =>
      if i < leftCount then left.lookup i else right.lookup (i - leftCount)
  | .empty, _ => none

theorem Directory.lookup_exact (directory : Directory) (valid : directory.Valid) (i : Nat) :
    directory.lookup i = directory.items[i]? := by
  induction directory generalizing i with
  | leaf group => exact group.lookup_exact i
  | branch left right leftCount ihLeft ihRight =>
      simp only [Directory.Valid] at valid
      simp only [Directory.lookup, Directory.items, valid.1,
        ihLeft valid.2.1, ihRight valid.2.2, List.getElem?_append]
  | empty => rfl

/-- Keep semantic indexing in erased proofs, not recursive constructor
indices: otherwise Lean may retain/evaluate the ghost product lists. -/
abbrev Checked (items : List Evidence) :=
  {directory : Directory // directory.Valid ∧ directory.items = items}

def append (left : Checked leftItems) (right : Checked rightItems) :
    Checked (leftItems ++ rightItems) :=
  ⟨.branch left.val right.val left.val.count,
    ⟨⟨left.val.count_exact left.property.1, left.property.1, right.property.1⟩,
      by simp only [Directory.items, left.property.2, right.property.2]⟩⟩

def balanced (groups : List Group) : Checked (groups.flatMap Group.items) :=
  match groups with
  | [] => ⟨.empty, ⟨True.intro, rfl⟩⟩
  | [group] => ⟨.leaf group, ⟨True.intro, by simp [Directory.items]⟩⟩
  | head :: next :: tail =>
      let all := head :: next :: tail
      let middle := all.length / 2
      let left := balanced (all.take middle)
      let right := balanced (all.drop middle)
      have joined : (all.take middle).flatMap Group.items ++
          (all.drop middle).flatMap Group.items = all.flatMap Group.items := by
        rw [← List.flatMap_append, List.take_append_drop]
      joined ▸ append left right
termination_by groups.length
decreasing_by
  all_goals
    simp_wf
    omega

def ofSpans (queryFirst : Bool) (outer inner : List IndexedSpan) : Group :=
  ⟨outer.reverse.toArray, inner.reverse.toArray, queryFirst⟩

theorem ofSpans_items (queryFirst : Bool) (outer inner : List IndexedSpan) :
    (ofSpans queryFirst outer inner).items =
      (outer.flatMap (fun a => inner.map (fun b =>
        if queryFirst then Evidence.mk a b else Evidence.mk b a))).reverse := by
  simp only [ofSpans, Group.items, List.toList_toArray]
  change outer.reverse.flatMap (fun a => inner.reverse.map (fun b =>
      if queryFirst then Evidence.mk a b else Evidence.mk b a)) = _
  rw [List.reverse_flatMap]
  simp only [Function.comp_def, List.map_reverse]

theorem product_fold (outer inner : List IndexedSpan)
    (make : IndexedSpan → IndexedSpan → Evidence) (before : List Evidence) :
    outer.foldl (fun acc a => inner.foldl (fun acc b => make a b :: acc) acc) before =
      (outer.flatMap (fun a => inner.map (make a))).reverse ++ before := by
  induction outer generalizing before with
  | nil => simp
  | cons head tail ih =>
    rw [List.foldl_cons, ih, List.foldl_flip_cons_eq_append,
      List.flatMap_cons, List.reverse_append]
    simp only [List.append_assoc]

theorem rows_fold (rows : List (String × List IndexedSpan))
    (opposite : String → List IndexedSpan)
    (make : IndexedSpan → IndexedSpan → Evidence) (before : List Evidence) :
    rows.foldl (fun acc row =>
      row.2.foldl (fun acc a => (opposite row.1).foldl
        (fun acc b => make a b :: acc) acc) acc) before =
      (rows.flatMap (fun row => row.2.flatMap (fun a =>
        (opposite row.1).map (make a)))).reverse ++ before := by
  induction rows generalizing before with
  | nil => simp
  | cons row rest ih =>
      rw [List.foldl_cons, ih, product_fold, List.flatMap_cons, List.reverse_append]
      simp only [List.append_assoc]

def fromQuery (query target : Pattern) : List Group :=
  query.surface.toList.reverse.map fun row =>
    ofSpans true row.2 (target.surface.getD row.1 [])

def fromTarget (query target : Pattern) : List Group :=
  target.surface.toList.reverse.map fun row =>
    ofSpans false row.2 (query.surface.getD row.1 [])

theorem fromQuery_reference (query target : Pattern) :
    (fromQuery query target).flatMap Group.items = surfaceEvidenceFromQuery query target := by
  simp only [fromQuery, List.flatMap_map, ofSpans_items, ↓reduceIte]
  have reversed := List.reverse_flatMap (l := query.surface.toList)
    (f := fun row => row.2.flatMap (fun a => (target.surface.getD row.1 []).map (Evidence.mk a)))
  simp only [Function.comp_def] at reversed
  rw [← reversed]
  simp only [surfaceEvidenceFromQuery, Std.HashMap.fold_eq_foldl_toList]
  simpa only [List.append_nil] using
    (rows_fold query.surface.toList (fun gram => target.surface.getD gram []) Evidence.mk []).symm

theorem fromTarget_reference (query target : Pattern) :
    (fromTarget query target).flatMap Group.items = surfaceEvidenceFromTarget query target := by
  simp only [fromTarget, List.flatMap_map, ofSpans_items, Bool.false_eq_true, ↓reduceIte]
  have reversed := List.reverse_flatMap (l := target.surface.toList)
    (f := fun row => row.2.flatMap (fun a => (query.surface.getD row.1 []).map (fun b => Evidence.mk b a)))
  simp only [Function.comp_def] at reversed
  rw [← reversed]
  simp only [surfaceEvidenceFromTarget, Std.HashMap.fold_eq_foldl_toList]
  simpa only [List.append_nil] using
    (rows_fold target.surface.toList (fun gram => query.surface.getD gram [])
      (fun a b => Evidence.mk b a) []).symm

/-- Same complete surface join and original position order as the Matcher.
Only the overlap directory and occurrence arrays are evaluated. The product
list occurs solely in erased specifications; rank replay uses lookup/count. -/
def current (query target : Pattern) : EvidenceReplay.Indexed (surfaceEvidence query target) :=
  if side : query.surface.size ≤ target.surface.size then
    let directory := balanced (fromQuery query target)
    { count := directory.val.count
      lookup := fun i => directory.val.lookup i
      countExact := by
        rw [directory.val.count_exact directory.property.1, directory.property.2, fromQuery_reference]
        simp only [surfaceEvidence, if_pos side]
      lookupExact := by
        intro i
        rw [directory.val.lookup_exact directory.property.1, directory.property.2, fromQuery_reference]
        simp only [surfaceEvidence, if_pos side] }
  else
    let directory := balanced (fromTarget query target)
    { count := directory.val.count
      lookup := fun i => directory.val.lookup i
      countExact := by
        rw [directory.val.count_exact directory.property.1, directory.property.2, fromTarget_reference]
        simp only [surfaceEvidence, if_neg side]
      lookupExact := by
        intro i
        rw [directory.val.lookup_exact directory.property.1, directory.property.2, fromTarget_reference]
        simp only [surfaceEvidence, if_neg side] }

end Eggshell.Matcher.SurfaceJoin
