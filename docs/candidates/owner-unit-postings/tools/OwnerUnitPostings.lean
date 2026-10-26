module
public import Std.Data.HashMap.Lemmas
public import Std.Data.TreeSet.Lemmas
public import Init.Data.List.Nat.Pairwise

@[expose] public section

namespace Eggshell.OwnerUnitPostings

/-- A unit belongs to exactly the owner named by its original family. The
directory narrows work, while the caller's original predicate still decides. -/
def directory (ownerOf : Fin n → Option String) (indices : List (Fin n)) :
    Std.HashMap String (List (Fin n)) :=
  indices.foldr (fun index found => match ownerOf index with
    | none => found
    | some owner => found.insert owner (index :: found[owner]?.getD [])) {}

theorem directory_exact (ownerOf : Fin n → Option String) (indices : List (Fin n))
    (owner : String) :
    (directory ownerOf indices)[owner]?.getD [] =
      indices.filter (fun index => ownerOf index == some owner) := by
  induction indices with
  | nil => simp [directory]
  | cons index rest ih =>
    cases found : ownerOf index with
    | none => simpa [directory,found] using ih
    | some actual =>
      by_cases same : actual = owner
      · simpa [directory,found,same] using congrArg (List.cons index) ih
      · simpa [directory,found,same,Std.HashMap.getElem?_insert] using ih

structure Index (ownerOf : Fin n → Option String) where
  postings : Std.HashMap String (List (Fin n))
  exact : ∀ owner, postings[owner]?.getD [] =
    (List.finRange n).filter (fun index => ownerOf index == some owner)

def prepare (ownerOf : Fin n → Option String) : Index ownerOf :=
  ⟨directory ownerOf (List.finRange n),directory_exact ownerOf (List.finRange n)⟩

variable {n : Nat} {ownerOf : Fin n → Option String}

/-- Ordered union retains the original ascending unit order, including ties
in the selector. Duplicate owner bindings cannot duplicate a unit. -/
def Index.union (index : Index ownerOf) (owners : List String) :
    Std.TreeSet (Fin n) compare :=
  (∅ : Std.TreeSet (Fin n) compare).insertMany
    (owners.flatMap fun owner => index.postings[owner]?.getD [])

theorem Index.union_mem (index : Index ownerOf) (owners : List String) (unit : Fin n) :
    unit ∈ (index.union owners).toList ↔
      ∃ owner ∈ owners, ownerOf unit = some owner := by
  simp [Index.union,index.exact,List.mem_flatMap]

def Index.select (index : Index ownerOf) (owners : List String)
    (accept : Fin n → Bool) : List (Fin n) :=
  (index.union owners).toList.filter accept

/-- The indexed candidate sequence, not merely its set, is the original full
scan. Thus marginal-cost ties and the later selector see exactly the same input. -/
theorem Index.select_exact (index : Index ownerOf) (owners : List String)
    (accept : Fin n → Bool)
    (necessary : ∀ unit, accept unit = true → ∃ owner ∈ owners, ownerOf unit = some owner) :
    index.select owners accept = (List.finRange n).filter accept := by
  have distinct : (index.union owners).toList.Nodup :=
    (index.union owners).distinct_toList.imp (by
      intro a b differs same
      subst b
      exact differs (by simp))
  have sameMembers : ∀ unit, unit ∈ index.select owners accept ↔
      unit ∈ (List.finRange n).filter accept := by
    intro unit
    simp only [Index.select,List.mem_filter,Index.union_mem,List.mem_finRange,true_and]
    exact ⟨fun h => h.2,fun h => ⟨necessary unit h,h⟩⟩
  apply List.Perm.eq_of_pairwise (le := fun a b : Fin n => a.val ≤ b.val)
  · intro a b _ _ ab ba
    exact Fin.ext (Nat.le_antisymm ab ba)
  · exact ((index.union owners).ordered_toList.imp (by
      intro a b ordered
      exact Nat.le_of_lt (Nat.compare_eq_lt.mp ordered))).filter accept
  · exact (List.pairwise_le_finRange n).filter accept
  · exact (List.perm_ext_iff_of_nodup (distinct.filter accept)
      ((List.nodup_finRange n).filter accept)).mpr sameMembers

end Eggshell.OwnerUnitPostings
