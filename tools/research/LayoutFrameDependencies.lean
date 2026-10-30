module
public import Eggshell.CanonicalSourceRecords
@[expose] public section

namespace Eggshell.Research.LayoutFrameDependencies
open Eggshell.Synapses.CanonicalSource

/- An observed layout relation, not a semantic prerequisite or Work equality.
Only strictly less-indented preceding rows of the same contiguous original
run can be parents. No language, path, tool, query or reference labels enter. -/
structure Prepared (rows : Array StoredRow) where
  parents : Std.HashMap (Fin rows.size) (Fin rows.size)

def prepare (rows : Array StoredRow) : Prepared rows := Id.run do
  let order := (List.finRange rows.size).mergeSort fun a b =>
    if rows[a].key.file == rows[b].key.file then rows[a].key.line ≤ rows[b].key.line
    else (Lean.toJson rows[a].key.file).compress ≤ (Lean.toJson rows[b].key.file).compress
  let mut parents := {}
  let mut stack : List (Nat × Fin rows.size) := []
  let mut previous : Option (Fin rows.size) := none
  for index in order do
    let row := rows[index]
    unless previous.any (fun prior => rows[prior].key.file == row.key.file &&
        rows[prior].key.line+1 == row.key.line) do stack := []
    previous := some index
    if row.code.trimAscii.isEmpty then continue
    let level := Records.indentation row.code
    stack := stack.dropWhile (fun entry => level ≤ entry.1)
    if let some (_,parent) := stack.head? then parents := parents.insert index parent
    stack := (level,index) :: stack
  return ⟨parents⟩

def closed (prepared : Prepared rows) (selected : List (Fin rows.size)) : Bool :=
  selected.all fun row => (prepared.parents[row]?).all selected.contains

structure Result (prepared : Prepared rows) (requested : List (Fin rows.size)) where
  selected : List (Fin rows.size)
  retained : requested.all selected.contains = true
  complete : closed prepared selected = true

/-- Publication stores parent IDs. A query follows only parents of requested
rows; it neither scans every record nor reparses text. The independent final
check rejects a truncated or malformed work list. -/
def close? (prepared : Prepared rows) (requested : List (Fin rows.size)) :
    Option (Result prepared requested) := Id.run do
  let mut seen := Std.HashSet.ofList requested
  let mut queue := seen.toArray
  let mut cursor := 0
  while cursor < queue.size do
    let some row := queue[cursor]? | return none
    cursor := cursor+1
    if let some parent := prepared.parents[row]? then
      unless seen.contains parent do
        seen := seen.insert parent
        queue := queue.push parent
  let selected := queue.toList
  if retained : requested.all selected.contains = true then
    if complete : closed prepared selected = true then
      return some ⟨selected,retained,complete⟩
  return none

variable {rows : Array StoredRow} {prepared : Prepared rows} {requested : List (Fin rows.size)}

theorem Result.keeps_requested (result : Result prepared requested)
    (row : Fin rows.size) (present : row ∈ requested) : row ∈ result.selected := by
  exact List.contains_iff_mem.mp ((List.all_eq_true.mp result.retained) row present)

theorem Result.keeps_parent (result : Result prepared requested)
    (row parent : Fin rows.size) (present : row ∈ result.selected)
    (edge : prepared.parents[row]? = some parent) : parent ∈ result.selected := by
  have checked := (List.all_eq_true.mp result.complete) row present
  simpa [edge,List.contains_iff_mem] using checked

theorem Result.original (result : Result prepared requested)
    (row : Fin rows.size) (_present : row ∈ result.selected) : rows[row] ∈ rows :=
  Array.getElem_mem row.isLt

end Eggshell.Research.LayoutFrameDependencies
