module
public import tools.KeyPostings
public import Eggshell.HashDistinct
public import Init.Data.List.Nat.Range
@[expose] public section

namespace Eggshell.RecordIncidence

variable {α : Type} [BEq α] [Hashable α] [LawfulBEq α]

def edges (records : List (List α)) : Array (α × Nat) :=
  (records.zipIdx.flatMap fun (rows,ordinal) => rows.map fun row => (row,ordinal)).toArray

def referenceLookup (records : List (List α)) (row : α) : List Nat :=
  ((KeyPostings.prepare Prod.fst (edges records)).lookup row).toList.map Prod.snd

structure Index (records : List (List α)) where
  lookup : α → List Nat
  exact : ∀ row, lookup row = referenceLookup records row

def prepare (records : List (List α)) : Index records :=
  let postings := KeyPostings.prepare Prod.fst (edges records)
  ⟨fun row => (postings.lookup row).toList.map Prod.snd,fun _ => rfl⟩

variable {records : List (List α)}

def Index.affected (index : Index records) (requested : List α) : Std.HashSet Nat :=
  Std.HashSet.ofList (requested.flatMap index.lookup)

def Index.selected (index : Index records) (requested : List α) : List (List α) :=
  ((records.zipIdx).filter fun entry => (index.affected requested).contains entry.2).map Prod.fst

def Index.close (index : Index records) (requested : List α) : List α :=
  hashDistinct (requested ++ (index.selected requested).flatten)

theorem lookup_mem (index : Index records) (row : α) (ordinal : Nat) :
    ordinal ∈ index.lookup row ↔ (row,ordinal) ∈ edges records := by
  rw [index.exact,referenceLookup,KeyPostings.Index.lookup_exact]
  simp only [List.mem_map,Array.mem_toList_iff,Array.mem_filterMap]
  constructor
  · rintro ⟨⟨other,id⟩,⟨⟨saved,j⟩,member,filtered⟩,equal⟩
    split at filtered
    · cases filtered
      simp_all only [beq_iff_eq]
    · cases filtered
  · intro member
    exact ⟨(row,ordinal),⟨(row,ordinal),member,by simp⟩,rfl⟩

omit [BEq α] [Hashable α] [LawfulBEq α] in
theorem edge_mem (records : List (List α)) (row : α) (ordinal : Nat) :
    (row,ordinal) ∈ edges records ↔ ∃ values, (values,ordinal) ∈ records.zipIdx ∧ row ∈ values := by
  simp only [edges,List.mem_toArray,List.mem_flatMap,List.mem_map]
  constructor
  · rintro ⟨⟨values,id⟩,present,other,member,equal⟩
    cases equal
    exact ⟨values,present,member⟩
  · rintro ⟨values,present,member⟩
    exact ⟨(values,ordinal),present,row,member,rfl⟩

theorem Index.affected_exact (index : Index records) (requested : List α)
    (values : List α) (ordinal : Nat) (present : (values,ordinal) ∈ records.zipIdx) :
    (index.affected requested).contains ordinal = values.any requested.contains := by
  apply Bool.eq_iff_iff.mpr
  simp only [Index.affected,Std.HashSet.contains_ofList,List.contains_iff_mem,List.mem_flatMap,
    List.any_eq_true,lookup_mem,edge_mem]
  constructor
  · rintro ⟨row,needed,other,member,found⟩
    have a := List.mk_mem_zipIdx_iff_getElem?.mp present
    have b := List.mk_mem_zipIdx_iff_getElem?.mp member
    have same : other = values := Option.some.inj (b.symm.trans a)
    subst other
    exact ⟨row,found,needed⟩
  · rintro ⟨row,member,needed⟩
    exact ⟨row,needed,values,present,member⟩

theorem Index.selected_exact (index : Index records) (requested : List α) :
    index.selected requested = records.filter (fun values => values.any requested.contains) := by
  unfold Index.selected
  have same := List.filter_congr (l := records.zipIdx)
    (p := fun entry => (index.affected requested).contains entry.2)
    (q := fun entry => entry.1.any requested.contains)
    (fun (values,ordinal) present => index.affected_exact requested values ordinal present)
  rw [same]
  simpa only [Function.comp_def,List.zipIdx_map_fst] using
    (List.filter_map (f := Prod.fst) (p := fun (values : List α) => values.any requested.contains)
      (l := records.zipIdx)).symm

theorem close_exact (index : Index records) (requested : List α) :
    index.close requested = hashDistinct (requested ++
      (records.filter (fun values => values.any requested.contains)).flatten) := by
  rw [Index.close,index.selected_exact]

/-- Publication materializes one bucket per original row. The checked
reader uses that serialized table; it does not reconstruct it per hint. -/
def wire (records : List (List (Fin n))) : Array (List Nat) :=
  let index := prepare records
  Array.ofFn index.lookup

def checkWire (records : List (List (Fin n))) (buckets : Array (List Nat)) :
    Except String (Index records) := do
  if size : buckets.size = n then
    let expected := prepare records
    let lookup := fun (row : Fin n) => buckets[row.val]'(by omega)
    if valid : (List.finRange n).all (fun row => lookup row == expected.lookup row) then
      return ⟨lookup,fun row => by
        have same := List.all_eq_true.mp valid row (List.mem_finRange row)
        exact (beq_iff_eq.mp same).trans (expected.exact row)⟩
    else throw "record incidence differs from its original records"
  else throw "record incidence changed its original row domain"

end Eggshell.RecordIncidence
