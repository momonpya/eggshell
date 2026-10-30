module
public import Eggshell.CanonicalSourceRecords
public import tools.OwnerUnitPostings
public import tools.SharedCoverageInput
@[expose] public section

namespace Eggshell.Research.CanonicalRecordDomain
open Lean Eggshell.Synapses.CanonicalSource

/- A display partition, not equality of the displayed lines or a Work Union.
The only links are already checked bounded records on one original basis. -/
def aligned (label : Fin n → String) : List (Fin n) → Bool
  | [] => true
  | first :: rest => rest.all fun row => label row == label first

theorem aligned_same (label : Fin n → String) (indices : List (Fin n))
    (checked : aligned label indices = true) (a b : Fin n)
    (ha : a ∈ indices) (hb : b ∈ indices) : label a = label b := by
  cases indices with
  | nil => simp at ha
  | cons first rest =>
    have every : ∀ row ∈ first :: rest, label row = label first := by
      intro row present
      rcases List.mem_cons.mp present with same | later
      · simp [same]
      · exact beq_iff_eq.mp ((List.all_eq_true.mp checked) row later)
    exact (every a ha).trans (every b hb).symm

structure Checked (rows : Array StoredRow) (records : List (Records.Record rows)) where
  label : Fin rows.size → String
  compatible : records.all (fun record => aligned label record.indices) = true
  index : OwnerUnitPostings.Index (fun row => some (label row))

def Checked.members (domain : Checked rows records) (row : Fin rows.size) : List (Fin rows.size) :=
  domain.index.postings[domain.label row]?.getD []

theorem Checked.member_exact (domain : Checked rows records) (a b : Fin rows.size) :
    a ∈ domain.members b ↔ domain.label a = domain.label b := by
  rw [Checked.members,domain.index.exact]
  simp

def Checked.close (domain : Checked rows records) (requested : List (Fin rows.size)) : List (Fin rows.size) :=
  hashDistinct (requested.flatMap domain.members)

theorem Checked.close_exact (domain : Checked rows records) (requested : List (Fin rows.size))
    (row : Fin rows.size) : row ∈ domain.close requested ↔
      ∃ original ∈ requested, domain.label row = domain.label original := by
  simp only [Checked.close,HashDistinct.reference,List.mem_eraseDups,List.mem_flatMap]
  simp only [domain.member_exact]

theorem Checked.requested_retained (domain : Checked rows records) (requested : List (Fin rows.size))
    (row : Fin rows.size) (present : row ∈ requested) : row ∈ domain.close requested :=
  (domain.close_exact requested row).mpr ⟨row,present,rfl⟩

/-- Even a row added through another alias cannot split an admitted record. -/
theorem Checked.complete_record (domain : Checked rows records) (requested : List (Fin rows.size))
    (record : Records.Record rows) (admitted : record ∈ records)
    (a b : Fin rows.size) (ha : a ∈ record.indices) (hb : b ∈ record.indices)
    (selected : a ∈ domain.close requested) : b ∈ domain.close requested := by
  obtain ⟨original,present,same⟩ := (domain.close_exact requested a).mp selected
  have compatible := (List.all_eq_true.mp domain.compatible) record admitted
  have equal := aligned_same domain.label record.indices compatible b a hb ha
  exact (domain.close_exact requested b).mpr ⟨original,present,equal.trans same⟩

theorem Checked.close_idempotent_members (domain : Checked rows records)
    (requested : List (Fin rows.size)) (row : Fin rows.size) :
    row ∈ domain.close (domain.close requested) ↔ row ∈ domain.close requested := by
  constructor
  · intro selected
    obtain ⟨a,ha,same⟩ := (domain.close_exact _ row).mp selected
    obtain ⟨b,hb,prior⟩ := (domain.close_exact _ a).mp ha
    exact (domain.close_exact _ row).mpr ⟨b,hb,same.trans prior⟩
  · intro selected
    exact domain.requested_retained _ row selected

/-- Restoring a published partition checks its original domain and every
record constraint. The ordered posting index is built once for that view. -/
def check (rows : Array StoredRow) (records : List (Records.Record rows))
    (labels : Array Nat) : Except String (Checked rows records) := do
  if bounds : labels.size = rows.size then
    let label := fun row : Fin rows.size => toString (labels[row.val]'(by omega))
    if compatible : records.all (fun record => aligned label record.indices) = true then
      return ⟨label,compatible,OwnerUnitPostings.prepare (fun row => some (label row))⟩
    else throw "published display partition splits a checked record"
  else throw "published display partition crossed its original basis"

/-- Publication-side finite work list. Query-time close is a posting lookup;
it does not rescan records or parse original text. -/
def compile (rows : Array StoredRow) (records : List (Records.Record rows)) :
    Except String (Array Nat × Checked rows records) := do
  let entries := records.toArray
  let mut byRow : Std.HashMap (Fin rows.size) (List Nat) := {}
  for record in List.finRange entries.size do
    for row in entries[record].indices do
      byRow := byRow.insert row (record.val :: byRow[row]?.getD [])
  let mut labels := Array.replicate rows.size 0
  let mut seen : Std.HashSet (Fin rows.size) := {}
  for start in List.finRange rows.size do
    if seen.contains start then continue
    seen := seen.insert start
    let mut queue := #[start]
    let mut cursor := 0
    let mut visitedRecords : Std.HashSet Nat := {}
    while cursor < queue.size do
      let some current := queue[cursor]? | throw "invalid finite display work list"
      cursor := cursor+1
      labels := labels.setIfInBounds current.val start.val
      for recordId in byRow[current]?.getD [] do
        if visitedRecords.contains recordId then continue
        visitedRecords := visitedRecords.insert recordId
        let some record := entries[recordId]? | throw "invalid display record index"
        for row in record.indices do
          unless seen.contains row do
            seen := seen.insert row
            queue := queue.push row
  return (labels,← check rows records labels)

end Eggshell.Research.CanonicalRecordDomain
