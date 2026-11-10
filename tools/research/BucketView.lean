module
public import tools.research.OwnedBuckets
@[expose] public section
namespace Eggshell.Research.BucketView
universe u v w

def finish {κ : Type u} {ν : Type v} {ρ : Type w} [BEq κ] [Hashable κ]
    (table : Std.HashMap κ (Array ν)) (prepare : Array ν → ρ) : Std.HashMap κ ρ :=
  table.toArray.foldl (fun found (key,rows) => found.insert key (prepare rows)) {}

theorem finish_lookup {κ : Type u} {ν : Type v} {ρ : Type w} [BEq κ] [Hashable κ]
    [LawfulBEq κ] [LawfulHashable κ] (table : Std.HashMap κ (Array ν))
    (prepare : Array ν → ρ) (probe : κ) :
    (finish table prepare)[probe]? = table[probe]?.map prepare := by
  let mapped := table.toList.map (fun row => (row.1,prepare row.2))
  have folded : finish table prepare =
      mapped.foldl (fun found row => found.insert row.1 row.2) ({} : Std.HashMap κ ρ) := by
    unfold finish
    rw [← Array.foldl_toList,Std.HashMap.toList_toArray]
    simp only [mapped,List.foldl_map]
  have distinct : mapped.Pairwise (fun a b => (a.1 == b.1) = false) := by
    simpa only [mapped,List.pairwise_map] using (Std.HashMap.distinct_keys_toList (m := table))
  calc
    (finish table prepare)[probe]? = (Std.HashMap.ofList mapped)[probe]? := by
      rw [folded]
      exact (Std.HashMap.Equiv.getElem?_eq (Std.HashMap.ofList_equiv_foldl (l := mapped))).symm
    _ = table[probe]?.map prepare := by
      cases found : table[probe]? with
      | none =>
        have absent : (mapped.map Prod.fst).contains probe = false := by
          simp only [mapped,List.map_map]
          change (table.toList.map Prod.fst).contains probe = false
          rw [Std.HashMap.map_fst_toList_eq_keys,Std.HashMap.contains_keys,
            Std.HashMap.contains_eq_isSome_getElem?,found]
          rfl
        rw [Std.HashMap.getElem?_ofList_of_contains_eq_false absent]
        rfl
      | some value =>
        have present : (probe,value) ∈ table.toList := Std.HashMap.mem_toList_iff_getElem?_eq_some.mpr found
        have mappedPresent : (probe,prepare value) ∈ mapped :=
          List.mem_map.mpr ⟨(probe,value),present,rfl⟩
        rw [Std.HashMap.getElem?_ofList_of_mem (k_beq := by simp) distinct mappedPresent]
        rfl

def referenceLookup {κ : Type u} {ν : Type v} {ρ : Type w} [BEq κ] [Hashable κ]
    [LawfulBEq κ] [LawfulHashable κ] (rows : List (κ × ν)) (prepare : Array ν → ρ) : κ → Option ρ :=
  let ready := finish (OwnedBuckets.reference rows) prepare
  fun key => ready[key]?

def exclusiveLookup {κ : Type u} {ν : Type v} {ρ : Type w} [BEq κ] [Hashable κ]
    [LawfulBEq κ] [LawfulHashable κ] (rows : List (κ × ν)) (prepare : Array ν → ρ) : κ → Option ρ :=
  let ready := (OwnedBuckets.exclusive rows).map (fun _ values => prepare values)
  fun key => ready[key]?

theorem lookup_exact : @referenceLookup.{u,v,w} = @exclusiveLookup.{u,v,w} := by
  funext κ ν ρ equality hashing lawful lawfulHash rows prepare probe
  simp only [referenceLookup,exclusiveLookup,finish_lookup,Std.HashMap.getElem?_map]
  exact congrArg (Option.map prepare) (OwnedBuckets.fold_observes rows {} {} (fun _ => rfl) probe).symm

#print axioms finish_lookup
#print axioms lookup_exact
end Eggshell.Research.BucketView
