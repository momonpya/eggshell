module
public import Eggshell.DB.Sidecar
public import Eggshell.DB.Wire
public import Eggshell.Receipt
public import Eggshell.Sha256
public import tools.WindowCentroid

@[expose] public section

namespace Eggshell.VectorMatrix
open Lean DB

/-- Rebuildable numerical hints only. Keys remain original window digests;
neither a matrix row nor its coverage can establish source/Work authority. -/
structure Row where
  key : String
  coverage : String
  offset : Nat
  bytes : Nat
  digest : String
  deriving BEq

def rowCodec := (Wire.text.product (Wire.text.product
  (Wire.natural.product (Wire.natural.product Wire.text)))).iso
    (fun row : Row => (row.key,row.coverage,row.offset,row.bytes,row.digest))
    (fun (key,coverage,offset,bytes,digest) => Row.mk key coverage offset bytes digest)
    (by intro row; cases row; rfl)

def codec := Wire.list rowCodec

theorem directory_roundtrip (rows : List Row) (tail : List UInt8) :
    codec.decode (codec.encode rows ++ tail) = .ok (rows,tail) :=
  codec.roundtrip rows tail

def implementation := Sha256.hex ((include_str "VectorMatrix.lean").toUTF8 ++
  (include_str "../tools/WindowCentroid.lean").toUTF8)

def maxDataBytes : Nat := 512 * 1024 * 1024
def maxDirectoryBytes : Nat := 64 * 1024 * 1024

structure Manifest where
  model : String
  encoder : String
  implementation : String
  rows : Nat
  bytes : Nat
  directoryBytes : Nat
  directoryDigest : String
  deriving FromJson, ToJson

structure Ready where
  metadata : Manifest
  rows : Array Row
  index : Std.HashMap String Row
  handle : FileSystem.ReadHandle
  version : FileSystem.ReadVersion

def folder (root : System.FilePath) := root / "matrix"

/-- Scheduling hint only; search checks the actual directory and every row. -/
def ready (root : System.FilePath) (model encoder : String) : IO Bool := do
  try
    let bytes ← FileSystem.boundedBytes (folder root / "ready.json") 65536
    let record ← IO.ofExcept (Json.parse ((String.fromUTF8? bytes).getD "") >>= fromJson? (α := Manifest))
    return record.model == model && record.encoder == encoder && record.implementation == implementation &&
      0 < record.rows && record.bytes ≤ maxDataBytes && record.directoryBytes ≤ maxDirectoryBytes
  catch _ => return false

def open? (root : System.FilePath) (model encoder : String) : IO (Option Ready) := do
  let path := folder root
  let bytes ← FileSystem.boundedBytes (path / "ready.json") 65536
  let record ← IO.ofExcept (Json.parse ((String.fromUTF8? bytes).getD "") >>= fromJson? (α := Manifest))
  unless record.model == model && record.encoder == encoder && record.implementation == implementation &&
      0 < record.rows && record.bytes ≤ maxDataBytes && record.directoryBytes ≤ maxDirectoryBytes do return none
  let bytes ← FileSystem.boundedBytes (path / "directory") maxDirectoryBytes
  unless bytes.size == record.directoryBytes && Sha256.hex bytes == record.directoryDigest do
    throw (IO.userError "numerical matrix directory digest disagrees")
  let (rows,tail) ← IO.ofExcept (codec.decode bytes.toList)
  unless tail.isEmpty && rows.length == record.rows do throw (IO.userError "invalid numerical matrix directory")
  let mut index : Std.HashMap String Row := {}
  let mut offset := 0
  for row in rows do
    unless Receipt.validId row.key && Receipt.validId row.digest && !index.contains row.key &&
        row.offset == offset && 0 < row.bytes && row.bytes ≤ 4096*8 && row.bytes % 8 == 0 &&
        row.coverage.utf8ByteSize ≤ 4096 do throw (IO.userError "invalid numerical matrix row")
    offset := offset + row.bytes
    index := index.insert row.key row
  unless offset == record.bytes do throw (IO.userError "numerical matrix length disagrees")
  let handle ← FileSystem.openRead (path / "rows").toString
  let version ← FileSystem.readVersion handle
  unless version.bytes == record.bytes do throw (IO.userError "numerical matrix file length disagrees")
  return some ⟨record,rows.toArray,index,handle,version⟩

/-- One descriptor serves all window rows. Read only bounded pages and verify
the original directory row digest; replacement/mutation is a cache miss. -/
def read (ready : Ready) (key : String) : IO (Option (String × String)) := do
  let some row := ready.index[key]? | return none
  unless (← FileSystem.readVersion ready.handle) == ready.version do
    throw (IO.userError "numerical matrix mutated before read")
  let mut bytes := ByteArray.empty
  while bytes.size < row.bytes do
    let count := min 4096 (row.bytes - bytes.size)
    let part ← FileSystem.readPage ready.handle (row.offset + bytes.size).toUInt64
      ⟨count,Nat.min_le_left _ _⟩
    unless part.size == count do throw (IO.userError "truncated numerical matrix row")
    bytes := bytes ++ part
  unless (← FileSystem.readVersion ready.handle) == ready.version && Sha256.hex bytes == row.digest do
    throw (IO.userError "numerical matrix row digest disagrees")
  return some (row.coverage,Blake3.hex bytes)

def decodeHex (encoded : String) : Except String ByteArray := do
  let input := encoded.toUTF8
  unless 0 < input.size && input.size % 16 == 0 && input.size ≤ 4096*16 do
    throw "invalid projected numerical shape"
  let mut bytes := ByteArray.empty
  for index in [:input.size / 2] do
    let high ← WindowCentroid.digit input[index*2]!
    let low ← WindowCentroid.digit input[index*2+1]!
    bytes := bytes.push (high*16+low).toUInt8
  return bytes

structure Entry where
  key : String
  coverage : String
  projected : String

structure Result where
  mode : String
  rows : Nat
  bytes : Nat
  elapsedMs : Nat
  deriving ToJson

/-- Called only under the DB maintenance claim, never by a search. Atomic
replacement keeps storage bounded. In-flight readers retain their descriptor;
mixed directory/data generations fail their row digests and use original hints. -/
def write (root : System.FilePath) (model encoder : String) (entries : Array Entry) : IO Result := do
  let started ← IO.monoMsNow
  let mut rows := #[]
  let mut data := ByteArray.empty
  let mut seen : Std.HashSet String := {}
  for entry in entries do
    unless Receipt.validId entry.key && !seen.contains entry.key do
      throw (IO.userError "duplicate or invalid numerical matrix key")
    seen := seen.insert entry.key
    let bytes ← IO.ofExcept (decodeHex entry.projected)
    unless data.size + bytes.size ≤ maxDataBytes do throw (IO.userError "numerical matrix exceeds byte budget")
    rows := rows.push (Row.mk entry.key entry.coverage data.size bytes.size (Sha256.hex bytes))
    data := data ++ bytes
  unless !rows.isEmpty do throw (IO.userError "empty numerical matrix")
  let directory := (codec.encode rows.toList).toByteArray
  unless directory.size ≤ maxDirectoryBytes do throw (IO.userError "numerical matrix directory exceeds byte budget")
  let record : Manifest := ⟨model,encoder,implementation,rows.size,data.size,
    directory.size,Sha256.hex directory⟩
  let path ← Sidecar.childDirectory root "matrix"
  FileSystem.atomicExistingBytes (path / "rows") data
  FileSystem.atomicExistingBytes (path / "directory") directory
  FileSystem.atomicExistingBytes (path / "ready.json") (toJson record).compress.toUTF8
  return ⟨"prepared",rows.size,data.size,(← IO.monoMsNow)-started⟩

end Eggshell.VectorMatrix
