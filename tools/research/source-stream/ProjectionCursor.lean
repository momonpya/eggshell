module
public import Eggshell.VectorMatrix

@[expose] public section
namespace Eggshell.ProjectionCursor
open Lean DB

structure Row where
  key : String
  value : VectorMatrix.Row
  bounded : value.bytes ≤ VectorMatrix.maxRowBytes

structure Raw (row : Row) where
  bytes : ByteArray
  exact : bytes.size = row.value.bytes

theorem Raw.actual_bytes_bounded (raw : Raw row) : raw.bytes.size ≤ VectorMatrix.maxRowBytes := by
  rw [raw.exact]
  exact row.bounded

def implementation := Sha256.hex (include_str "ProjectionCursor.lean").toUTF8

def checked (key : String) (encoded : ByteArray) : IO Row := do
  unless Receipt.validId key do throw (IO.userError "invalid projection cursor key")
  let value ← VectorMatrix.decodeRow encoded
  if bounded : value.bytes ≤ VectorMatrix.maxRowBytes then return ⟨key,value,bounded⟩
  else throw (IO.userError "projection row exceeds cursor budget")

def checkExtent (snapshot : PageMap.Snapshot) : IO Unit := do
  unless (← FileSystem.readVersion snapshot.handle).bytes ≥ snapshot.head.bytes do
    throw (IO.userError "projection cursor committed prefix was truncated")

/-- Each chunk is authenticated against this pinned head. No hexadecimal
value or query-by-source score catalogue is constructed. -/
def readPayload (matrix : VectorMatrix.Ready) (row : Row) : IO (Raw row) := do
  let mut bytes := ByteArray.empty
  for chunk in row.value.chunks do
    unless chunk.bytes == min 4096 (row.value.bytes-bytes.size) do
      throw (IO.userError "projection cursor chunk shape differs")
    bytes := bytes ++ (← matrix.snapshot.readBlob chunk)
  if exact : bytes.size = row.value.bytes then return ⟨bytes,exact⟩
  else throw (IO.userError "projection cursor row size differs")

def read (matrix : VectorMatrix.Ready) (row : Row) : IO (Raw row) := do
  checkExtent matrix.snapshot
  let value ← readPayload matrix row
  checkExtent matrix.snapshot
  return value

structure Catalogue where
  matrix : VectorMatrix.Ready
  rows : Array Row
  rowBytes : Nat

def width (matrix : VectorMatrix.Ready) : IO Nat := do
  let bytes := matrix.metadata.bytes/matrix.metadata.rows
  unless matrix.metadata.rows > 0 && matrix.metadata.rows*bytes == matrix.metadata.bytes &&
      0 < bytes && bytes ≤ VectorMatrix.maxRowBytes && bytes%8 == 0 do
    throw (IO.userError "projection column dimensions disagree")
  return bytes

/-- Full explicit maintenance enumerates only the immutable row directory.
Its canonical key order is independent of an earlier physical router. -/
def catalogue (matrix : VectorMatrix.Ready) : IO Catalogue := do
  let rowBytes ← width matrix
  let rows ← matrix.snapshot.foldRange ⟨"row:","row;"⟩ (fun rows (key,raw) => do
    let some raw := raw | throw (IO.userError "retired projection cursor row")
    let row ← checked (String.ofList (key.toList.drop 4)) raw
    unless row.value.bytes == rowBytes do throw (IO.userError "projection cursor dimensions vary")
    return rows.push row) #[]
  unless rows.size == matrix.metadata.rows do throw (IO.userError "incomplete projection cursor directory")
  return ⟨matrix,rows,rowBytes⟩

/-- Initial preparation traverses one checked descriptor at a time. The
consumer, rather than an unbounded directory array, controls what is retained.
All live descriptors and the final population are still checked. -/
def fold (matrix : VectorMatrix.Ready) (consume : α → Row → IO α) (initial : α) : IO α := do
  checkExtent matrix.snapshot
  let rowBytes ← width matrix
  let (result,count) ← matrix.snapshot.foldRange ⟨"row:","row;"⟩ (fun (state,count) (key,raw) => do
    let some raw := raw | throw (IO.userError "retired projection cursor row")
    let row ← checked (String.ofList (key.toList.drop 4)) raw
    unless row.value.bytes == rowBytes do throw (IO.userError "projection cursor dimensions vary")
    return (← consume state row,count+1)) (initial,0)
  unless count == matrix.metadata.rows do throw (IO.userError "incomplete projection cursor directory")
  checkExtent matrix.snapshot
  return result

/-- A delta request performs point lookups for its own keys. It cannot open
the complete directory or silently replace missing input with a current row. -/
def select (matrix : VectorMatrix.Ready) (keys : List String) : IO Catalogue := do
  let rowBytes ← width matrix
  let ordered := keys.mergeSort (· ≤ ·)
  let mut previous : Option String := none
  let mut rows := #[]
  for key in ordered do
    unless previous.all (· < key) do throw (IO.userError "duplicate projection cursor request")
    let some encoded ← matrix.snapshot.get ("row:"++key) | throw (IO.userError "requested projection is absent")
    let row ← checked key encoded
    unless row.value.bytes == rowBytes do throw (IO.userError "selected projection dimensions vary")
    rows := rows.push row
    previous := some key
  return ⟨matrix,rows,rowBytes⟩

def walk (source : Catalogue) (positions : Array Nat)
    (visit : Nat → Row → ByteArray → IO Unit) : IO Unit := do
  checkExtent source.matrix.snapshot
  for position in positions do
    let some row := source.rows[position]? | throw (IO.userError "foreign projection cursor position")
    let raw ← readPayload source.matrix row
    visit position row raw.bytes
  checkExtent source.matrix.snapshot

end Eggshell.ProjectionCursor
