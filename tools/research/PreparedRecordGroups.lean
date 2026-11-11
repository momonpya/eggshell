module
public import Eggshell.OrderedIncidence
public import Std.Data.TreeSet.Lemmas
public import Init.Data.List.Nat.Pairwise
@[expose] public section

namespace Eggshell.Research.PreparedRecordGroups

/-- One immutable directory per decoded owner. Record positions, including
duplicate record payloads and invalid row IDs, are retained verbatim. -/
structure Index (records : List (List Nat)) where
  values : Array (List Nat)
  original : values.toList = records
  membership : OrderedIncidence.Index (fun i : Fin values.size => values[i]) (List.finRange values.size)

def prepare (records : List (List Nat)) : Index records :=
  let values := records.toArray
  ⟨values,by simp [values],OrderedIncidence.build (fun i : Fin values.size => values[i]) (List.finRange values.size)⟩

/-- Only incident record IDs enter the ordered union. Sorting IDs preserves
the original record order; equal payloads at different positions survive. -/
def Index.selected (ready : Index records) (requested : List Nat) : Std.TreeSet (Fin ready.values.size) compare :=
  (∅ : Std.TreeSet (Fin ready.values.size) compare).insertMany
    (requested.flatMap ready.membership.lookup)

theorem Index.selected_mem (ready : Index records) (requested : List Nat) (i : Fin ready.values.size) :
    i ∈ (ready.selected requested).toList ↔ (ready.values[i]).any requested.contains = true := by
  simp [Index.selected,OrderedIncidence.Index.lookup_exact,List.mem_flatMap]
  constructor
  · rintro ⟨row,present,inside⟩; exact ⟨row,inside,present⟩
  · rintro ⟨row,inside,present⟩; exact ⟨row,present,inside⟩

theorem Index.selected_exact (ready : Index records) (requested : List Nat) :
    (ready.selected requested).toList =
      (List.finRange ready.values.size).filter (fun i => ready.values[i].any requested.contains) := by
  have distinct : (ready.selected requested).toList.Nodup :=
    (ready.selected requested).distinct_toList.imp (by
      intro a b different same; subst b; exact different (by simp))
  apply List.Perm.eq_of_pairwise (le := fun a b : Fin ready.values.size => a.val ≤ b.val)
  · intro a b _ _ ab ba; exact Fin.ext (Nat.le_antisymm ab ba)
  · exact (ready.selected requested).ordered_toList.imp (by
      intro a b ordered; exact Nat.le_of_lt (Nat.compare_eq_lt.mp ordered))
  · exact (List.pairwise_le_finRange _).filter _
  · apply (List.perm_ext_iff_of_nodup distinct ((List.nodup_finRange _).filter _)).mpr
    intro i
    simpa using ready.selected_mem requested i

def Index.recordsFor (ready : Index records) (requested : List Nat) : List (List Nat) :=
  (ready.selected requested).toList.map (fun i => ready.values[i])

theorem Index.recordsFor_exact (ready : Index records) (requested : List Nat) :
    ready.recordsFor requested = records.filter (fun record => record.any requested.contains) := by
  rw [Index.recordsFor,ready.selected_exact]
  change ((List.finRange ready.values.size).filter
    ((fun record : List Nat => record.any requested.contains) ∘ (fun i => ready.values[i]))).map
      (fun i => ready.values[i]) = _
  rw [← List.filter_map]
  have same : (List.finRange ready.values.size).map (fun i => ready.values[i]) = ready.values.toList := by
    simp only [Fin.getElem_fin]
    simp only [List.finRange,List.map_ofFn,Function.comp_def]
    rw [← Array.toList_ofFn,Array.ofFn_getElem]
  rw [same,ready.original]

/-- Dense requests can scan the original references with constant-time
membership, without constructing a large ordered union of incident IDs. -/
def dense (records : List (List Nat)) (requested : List Nat) : List (List Nat) :=
  let selected := Std.HashSet.ofList requested
  records.filter (fun record => record.any selected.contains)

theorem dense_exact (records : List (List Nat)) (requested : List Nat) :
    dense records requested = records.filter (fun record => record.any requested.contains) := by
  unfold dense
  apply List.filter_congr
  intro record _
  apply congrArg record.any
  funext row
  simp

/-- Count existing posting cells without copying them. When incident cells
already outnumber records, the dense hash scan avoids a larger ordered union.
The decision uses current cardinalities, never a learned query threshold. -/
def Index.chooseRecords (ready : Index records) (requested : List Nat) : List (List Nat) :=
  let keys := hashDistinct requested
  let postings := keys.map ready.membership.lookup
  let incident := postings.foldl (fun count posting => count+posting.length) 0
  if incident < ready.values.size then
    let selected := (∅ : Std.TreeSet (Fin ready.values.size) compare).insertMany postings.flatten
    selected.toList.map (fun i => ready.values[i])
  else dense ready.values.toList requested

theorem Index.chooseRecords_exact (ready : Index records) (requested : List Nat) :
    ready.chooseRecords requested = records.filter (fun record => record.any requested.contains) := by
  unfold chooseRecords
  dsimp only
  split
  · change ready.recordsFor (hashDistinct requested) = _
    rw [ready.recordsFor_exact]
    apply List.filter_congr
    intro record _
    apply congrArg record.any
    funext row
    apply Bool.eq_iff_iff.mpr
    simp only [List.contains_iff_mem,HashDistinct.mem]
  · rw [dense_exact,ready.original]

def Index.expand (ready : Index records) (requested : List Nat) : List Nat :=
  hashDistinct (requested ++ (ready.chooseRecords requested).flatten)

theorem Index.expand_exact (ready : Index records) (requested : List Nat) :
    ready.expand requested =
      hashDistinct (requested ++ (records.filter fun record => record.any requested.contains).flatten) := by
  rw [Index.expand,ready.chooseRecords_exact]

#print axioms Index.selected_exact
#print axioms Index.recordsFor_exact
#print axioms Index.expand_exact
#print axioms dense_exact
#print axioms Index.chooseRecords_exact
end Eggshell.Research.PreparedRecordGroups
