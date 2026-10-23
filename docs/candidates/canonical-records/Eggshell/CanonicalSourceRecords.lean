module
public import Eggshell.CanonicalSource
@[expose] public section

namespace Eggshell.Synapses.CanonicalSource.Records
open Lean

def indentation (text : String) : Nat :=
  (text.toList.takeWhile fun char => char == ' ' || char == '\t').length

/-- A source record has contiguous original line numbers in one fingerprint
and observed boundaries: a paragraph or an entry followed by indented data.
This is a bounded layout closure, not a parser or a semantic judgment. -/
def valid (rows : Array StoredRow) (indices : List (Fin rows.size))
    (before : Option (Fin rows.size)) (after : Fin rows.size) : Bool :=
  match indices.head? with
  | none => false
  | some first =>
    let file := rows[first].key.file
    let start := rows[first].key.line
    let adjacent := match before with
      | none => start == 1
      | some previous => rows[previous].key.file == file &&
          rows[previous].key.line+1 == start
    let paragraph := before.all (fun previous => rows[previous].code.trimAscii.isEmpty) &&
      rows[after].code.trimAscii.isEmpty
    let level := indentation rows[first].code
    let indented := 1 < indices.length &&
      indices.tail.all (fun index => level < indentation rows[index].code) &&
      (rows[after].code.trimAscii.isEmpty || indentation rows[after].code ≤ level)
    adjacent && (paragraph || indented) && file.valid &&
      (indices.zipIdx.all fun (index,offset) => rows[index].key.file == file &&
        rows[index].key.line == start+offset && !rows[index].code.trimAscii.isEmpty) &&
      rows[after].key.file == file && rows[after].key.line == start+indices.length &&
      (indices.map fun index => rows[index].code.length+1).sum ≤ 2048

structure Record (rows : Array StoredRow) where
  indices : List (Fin rows.size)
  before : Option (Fin rows.size)
  after : Fin rows.size
  checked : valid rows indices before after = true

def check? (rows : Array StoredRow) (indices : List (Fin rows.size))
    (before : Option (Fin rows.size)) (after : Fin rows.size) : Option (Record rows) :=
  if checked : valid rows indices before after = true then some ⟨indices,before,after,checked⟩ else none

def prepare (rows : Array StoredRow) : List (Record rows) := Id.run do
  let order := (List.finRange rows.size).mergeSort fun a b =>
    if rows[a].key.file == rows[b].key.file then rows[a].key.line ≤ rows[b].key.line
    else (toJson rows[a].key.file).compress ≤ (toJson rows[b].key.file).compress
  let mut result := []
  let mut previous : Option (Fin rows.size) := none
  let mut before : Option (Fin rows.size) := none
  let mut pending := []
  for index in order do
    let row := rows[index]
    let adjacent := previous.any fun prior => rows[prior].key.file == row.key.file &&
      rows[prior].key.line+1 == row.key.line
    if !adjacent then
      before := none
      pending := []
    if row.code.trimAscii.isEmpty then
      if let some record := check? rows pending before index then result := result ++ [record]
      pending := []
      before := some index
    else pending := pending ++ [index]
    previous := some index
  -- A condition can span several numbered lines without a blank separator.
  -- Consider only an observed entry followed by more-indented original rows;
  -- its next same-or-less-indented row is the observed closing boundary.
  -- Bound the scan by the same source-record limit, not by a line heuristic.
  let ordered := order.toArray
  for position in List.finRange ordered.size do
    let index := ordered[position]
    if rows[index].code.trimAscii.isEmpty then continue
    let level := indentation rows[index].code
    let mut indices := [index]
    let mut chars := rows[index].code.length+1
    let mut cursor := position.val+1
    let mut priorIndex := index
    while cursor < ordered.size && chars ≤ 2048 do
      let some next := ordered[cursor]? | break
      if rows[next].key.file != rows[index].key.file ||
          rows[priorIndex].key.line+1 != rows[next].key.line then break
      if rows[next].code.trimAscii.isEmpty || indentation rows[next].code ≤ level then
        let entryBefore := if position.val == 0 then none else ordered[position.val-1]?
        if let some record := check? rows indices entryBefore next then result := result ++ [record]
        break
      indices := indices ++ [next]
      chars := chars+rows[next].code.length+1
      priorIndex := next
      cursor := cursor+1
  return result

/-- Selection cannot purchase a proper prefix of an admitted bounded record.
Unobserved lines, read gaps, a different fingerprint and unbounded paragraphs
supply no additional row. The original requested rows are always retained. -/
def closeIndices (records : List (Record rows)) (requested : List (Fin rows.size)) : List (Fin rows.size) :=
  hashDistinct (requested ++ (records.filter fun record =>
    record.indices.any requested.contains).flatMap (·.indices))

theorem requested_retained (records : List (Record rows)) (requested : List (Fin rows.size))
    (index : Fin rows.size) (present : index ∈ requested) : index ∈ closeIndices records requested := by
  rw [closeIndices,HashDistinct.reference]
  exact List.mem_eraseDups.mpr (List.mem_append_left _ present)

theorem complete_record_retained (records : List (Record rows)) (requested : List (Fin rows.size))
    (record : Record rows) (admitted : record ∈ records)
    (witness : Fin rows.size) (hint : witness ∈ requested) (inside : witness ∈ record.indices)
    (index : Fin rows.size) (member : index ∈ record.indices) : index ∈ closeIndices records requested := by
  rw [closeIndices,HashDistinct.reference]
  apply List.mem_eraseDups.mpr
  apply List.mem_append_right
  apply List.mem_flatMap.mpr
  refine ⟨record,List.mem_filter.mpr ⟨admitted,?_⟩,member⟩
  exact List.any_eq_true.mpr ⟨witness,inside,by simpa using hint⟩

def close (rows : Array StoredRow) (records : List (Record rows))
    (requested : List (Fin rows.size)) : Array StoredRow :=
  ((closeIndices records requested).map fun index => rows[index]).toArray

theorem closed_row_is_original (rows : Array StoredRow) (records : List (Record rows))
    (requested : List (Fin rows.size)) (row : StoredRow) (member : row ∈ close rows records requested) :
    row ∈ rows := by
  simp only [close,List.mem_toArray,List.mem_map] at member
  obtain ⟨index,_,equal⟩ := member
  subst row
  exact Array.getElem_mem index.isLt

end Eggshell.Synapses.CanonicalSource.Records
