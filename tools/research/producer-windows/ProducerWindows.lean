module
public import Eggshell.CanonicalSourceRecipe
public import tools.research.PublishedPlanMetadata
public import tools.SourceWindow
@[expose] public section
namespace Eggshell.Synapses.ProducerWindows
open Lean CanonicalSource

/-- The producer's own scalar window selects original row identities. It
does not parse a tool name, consult a question or read an external file. -/
def requested (owner : String) (rows : Array StoredRow) (workChars sourceChars position : Nat) :
    List (Fin rows.size) :=
  match SourceWindow.project sourceChars (workChars+1) position with
  | none => []
  | some window => (List.finRange rows.size).filter fun index =>
      rows[index].origins.any fun origin => origin.binding.owner == owner &&
        window.first < origin.binding.limit && origin.binding.first < window.last

def group (owner : String) (rows : Array StoredRow) (layout : Recipe.Checked rows)
    (workChars sourceChars position : Nat) : List (Fin rows.size) :=
  Records.closeIndices layout.records (requested owner rows workChars sourceChars position)

theorem producer_row_retained (owner : String) (rows : Array StoredRow) (layout : Recipe.Checked rows)
    (workChars sourceChars position : Nat) (index : Fin rows.size)
    (present : index ∈ requested owner rows workChars sourceChars position) :
    index ∈ group owner rows layout workChars sourceChars position :=
  Records.requested_retained layout.records (requested owner rows workChars sourceChars position) index present

/-- An observed bounded record closes together with the window that touches
it. This is an advisory payload dependency, never a Work completion. -/
theorem producer_record_retained (owner : String) (rows : Array StoredRow) (layout : Recipe.Checked rows)
    (workChars sourceChars position : Nat) (record : Records.Record rows) (admitted : record ∈ layout.records)
    (witness : Fin rows.size) (touches : witness ∈ requested owner rows workChars sourceChars position)
    (inside : witness ∈ record.payload) (index : Fin rows.size) (member : index ∈ record.payload) :
    index ∈ group owner rows layout workChars sourceChars position :=
  Records.complete_payload_retained layout.records (requested owner rows workChars sourceChars position)
    record admitted witness touches inside index member

def windows (owner : String) (rows : Array StoredRow) (layout : Recipe.Checked rows)
    (workChars sourceChars count : Nat) : List (List (Fin rows.size)) :=
  ((List.range count).map (group owner rows layout workChars sourceChars)).filter (!·.isEmpty)

/-- Whole producer windows are the base choices. A stored row outside that
producer's domain retains its original record; it is never made unavailable. -/
def catalogue (owner : String) (rows : Array StoredRow) (layout : Recipe.Checked rows)
    (workChars sourceChars count : Nat) : List (List (Fin rows.size)) :=
  let coupled := windows owner rows layout workChars sourceChars count
  let covered := Std.HashSet.ofList coupled.flatten
  coupled ++ layout.catalogue.filter (fun record => record.any (fun index => !covered.contains index))

theorem catalogue_complete (owner : String) (rows : Array StoredRow) (layout : Recipe.Checked rows)
    (workChars sourceChars count : Nat) (index : Fin rows.size) :
    index ∈ (catalogue owner rows layout workChars sourceChars count).flatten := by
  unfold catalogue
  simp only [List.flatten_append]
  by_cases present : index ∈ (windows owner rows layout workChars sourceChars count).flatten
  · exact List.mem_append_left _ present
  · apply List.mem_append_right
    have original := Recipe.Checked.catalogue_complete layout index
    obtain ⟨record,member,inside⟩ := List.mem_flatten.mp original
    apply List.mem_flatten.mpr
    refine ⟨record,List.mem_filter.mpr ⟨member,?_⟩,inside⟩
    apply List.any_eq_true.mpr
    refine ⟨index,inside,?_⟩
    simp [Std.HashSet.contains_ofList,present]

def units (owner : String) (stored : Recipe.Stored) (layout : Recipe.Checked stored.rows)
    (workChars sourceChars count : Nat) : Array (PublishedPlanMetadata.Unit) :=
  ((catalogue owner stored.rows layout workChars sourceChars count).map fun indices =>
    ⟨indices.map Fin.val,PreparedFileUnits.bindings owner ((indices.map fun index => stored.rows[index]).toArray)⟩).toArray

theorem selected_row_is_original (rows : Array StoredRow) (index : Fin rows.size) : rows[index] ∈ rows :=
  Array.getElem_mem index.isLt

/-- A prerequisite always names a real unit containing its original row. -/
structure Basis (units : Array PublishedPlanMetadata.Unit) (row : Nat) where
  index : Fin units.size
  member : row ∈ (units[index.val]'index.isLt).indices

def basis? (units : Array PublishedPlanMetadata.Unit) (row : Nat) (index : Fin units.size) :
    Option (Basis units row) :=
  if member : row ∈ (units[index.val]'index.isLt).indices then some ⟨index,member⟩ else none

def chooseBasis (units : Array PublishedPlanMetadata.Unit) (charges : Array (Nat × Nat))
    (row : Nat) : Option (Basis units row) :=
  (List.finRange units.size).foldl (fun (best : Option (Basis units row)) (index : Fin units.size) =>
    match basis? units row index with
    | none => best
    | some next =>
      match best with
      | none => some next
      | some prior =>
          let a := charges[index.val]?.getD (0,0)
          let b := charges[prior.index.val]?.getD (0,0)
          if a.1 < b.1 || (a.1 == b.1 && a.2 < b.2) then some next else best
    ) none

theorem chosen_basis_contains_row (units : Array PublishedPlanMetadata.Unit) (charges : Array (Nat × Nat))
    (row : Nat) (basis : Basis units row) (_chosen : chooseBasis units charges row = some basis) :
    row ∈ units[basis.index].indices := basis.member

/-- Prepared once with the immutable row costs. Citation and other graph
groups reuse these row prerequisites instead of introducing fragments that
bypass the published base groups. A missing basis is rejected by decoding. -/
def prerequisites (costs : Array (Nat × Nat)) (units : Array PublishedPlanMetadata.Unit) : Array Nat :=
  let charges := units.map fun unit => unit.indices.foldl (fun total index =>
    let next := costs[index]?.getD (0,0)
    (total.1+next.1,total.2+next.2)) (0,0)
  (Array.range costs.size).map fun row =>
    ((chooseBasis units charges row).map (·.index.val)).getD units.size
end Eggshell.Synapses.ProducerWindows
