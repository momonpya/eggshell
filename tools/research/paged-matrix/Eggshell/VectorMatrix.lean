module
public import Eggshell.DB.Sidecar
public import Eggshell.DB.Wire
public import Eggshell.Receipt
public import Eggshell.Sha256
public import tools.WindowCentroid

@[expose] public section

namespace Eggshell.VectorMatrix
open Lean DB

/-- A bounded original projection. Its key remains the original window hash;
this metadata cannot establish source, Work, Match or completion authority. -/
structure Row where
  coverage : String
  bytes : Nat
  chunks : List PageMap.Blob

def rowCodec := (Wire.text.product (Wire.natural.product (Wire.list PageMap.blobCodec))).iso
  (fun row : Row => (row.coverage,row.bytes,row.chunks))
  (fun (coverage,bytes,chunks) => Row.mk coverage bytes chunks)
  (by intro row; cases row; rfl)

theorem row_roundtrip (row : Row) (tail : List UInt8) :
    rowCodec.decode (rowCodec.encode row ++ tail) = .ok (row,tail) := rowCodec.roundtrip row tail

def implementation := Sha256.hex ((include_str "VectorMatrix.lean").toUTF8 ++
  (include_str "../tools/WindowCentroid.lean").toUTF8)

def maxRowBytes : Nat := 4096*8

def authority (model encoder : String) :=
  "eggshell.projected-matrix:" ++ Sha256.hex (toJson [model,encoder,implementation]).compress.toUTF8

structure Manifest where
  model : String
  encoder : String
  implementation : String
  generation : String
  head : PageMap.Head
  rows : Nat
  bytes : Nat
  deriving FromJson, ToJson

structure Ready where
  metadata : Manifest
  snapshot : PageMap.Snapshot

def folder (root : System.FilePath) := root / "matrix-tree"

def manifest (root : System.FilePath) : IO Manifest := do
  let bytes ← FileSystem.boundedBytes (folder root / "ready.json") 16384
  let some text := String.fromUTF8? bytes | throw (IO.userError "invalid numerical matrix readiness")
  IO.ofExcept (Json.parse text >>= fromJson?)

def validManifest (record : Manifest) (model encoder : String) : Bool :=
  record.model == model && record.encoder == encoder && record.implementation == implementation &&
    Receipt.validId record.generation && 0 < record.rows && 0 < record.bytes &&
    record.head.authority == authority model encoder && record.head.root.any (·.rows == record.rows)

/-- Scheduling hint only. The actual open pins the committed tree, and every
consumed page/blob is authenticated against that immutable root. -/
def ready (root : System.FilePath) (model encoder : String) : IO Bool := do
  try return validManifest (← manifest root) model encoder catch _ => return false

/-- Constant-size readiness and root opening. No complete row directory or
projected data file is decoded or materialized here. -/
def open? (root : System.FilePath) (model encoder : String) : IO (Option Ready) := do
  let record ← manifest root
  unless validManifest record model encoder do return none
  let snapshot ← PageMap.pin (folder root / record.generation)
  unless snapshot.head == record.head do throw (IO.userError "numerical matrix publication disagrees")
  let version ← FileSystem.readVersion snapshot.handle
  unless version.bytes == snapshot.head.bytes do throw (IO.userError "numerical matrix extent disagrees")
  return some ⟨record,snapshot⟩

/-- Original point paths and blob extents, rather than an in-memory copy of
all directory rows. A changed file is unusable; no repair/encoding occurs. -/
def read (ready : Ready) (key : String) : IO (Option (String × String)) := do
  unless Receipt.validId key do throw (IO.userError "invalid numerical matrix key")
  let before ← FileSystem.readVersion ready.snapshot.handle
  unless before.bytes == ready.snapshot.head.bytes do
    throw (IO.userError "numerical matrix extent changed before read")
  let some encoded ← ready.snapshot.get ("row:" ++ key) | return none
  let (row,tail) ← IO.ofExcept (rowCodec.decode encoded.toList)
  unless tail.isEmpty && (rowCodec.encode row).toByteArray == encoded &&
      0 < row.bytes && row.bytes ≤ maxRowBytes && row.bytes % 8 == 0 &&
      row.coverage.utf8ByteSize ≤ 4096 && row.chunks.length == (row.bytes+4095)/4096 do
    throw (IO.userError "invalid numerical matrix row")
  let mut bytes := ByteArray.empty
  for chunk in row.chunks do
    unless chunk.bytes == min 4096 (row.bytes-bytes.size) do
      throw (IO.userError "invalid numerical matrix chunk shape")
    bytes := bytes ++ (← ready.snapshot.readBlob chunk)
  unless bytes.size == row.bytes && (← FileSystem.readVersion ready.snapshot.handle) == before do
    throw (IO.userError "numerical matrix changed during read")
  return some (row.coverage,Blake3.hex bytes)

def decodeHex (encoded : String) : Except String ByteArray := do
  let input := encoded.toUTF8
  unless 0 < input.size && input.size % 16 == 0 && input.size ≤ maxRowBytes*2 do
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

/-- Each level buffers at most 31 refs. A full group is appended once, then
carried upward; construction does not copy a root path per row or publication. -/
structure Level where
  refs : List PageMap.Ref
  bounded : refs.length < 32

def buffered (levels : List Level) : Nat := (levels.map (·.refs.length)).sum

theorem buffered_bound (levels : List Level) : buffered levels ≤ 31*levels.length := by
  induction levels with
  | nil => simp [buffered]
  | cons level rest ih =>
      have := level.bounded
      simp only [buffered,List.map_cons,List.sum_cons,List.length_cons] at *
      omega

def carry (writer : PageMap.Writer) (ref : PageMap.Ref) : List Level → IO (List Level)
  | [] => return [⟨[ref],by simp⟩]
  | level :: rest => do
      if fits : level.refs.length < 31 then
        return ⟨ref :: level.refs,by simp; omega⟩ :: rest
      else
        let parent ← writer.appendPage (.branch (ref :: level.refs).reverse)
        return ⟨[],by simp⟩ :: (← carry writer parent rest)

def flushLeaves (writer : PageMap.Writer) (rows : List PageMap.Row)
    (levels : List Level) : IO (List Level) := do
  if rows.isEmpty then return levels
  let mut levels := levels
  for ref in ← writer.leaves rows.reverse do levels ← carry writer ref levels
  return levels

/-- Close the partial suffix in chronological order, sharing its boundary
with the next level. Only one directory path and the bounded frontier live. -/
def finish (writer : PageMap.Writer) (levels : List Level) : IO PageMap.Ref := do
  let mut pending : Option PageMap.Ref := none
  for (level,index) in levels.zipIdx do
    let children := (pending.toList ++ level.refs).reverse
    if index+1 == levels.length then return ← writer.finishRoots children
    if !children.isEmpty then pending := some (← writer.appendPage (.branch children))
  throw (IO.userError "empty numerical matrix")

def appendRow (writer : PageMap.Writer) (entry : Entry) : IO (PageMap.Row × Nat) := do
  unless Receipt.validId entry.key && entry.coverage.utf8ByteSize ≤ 4096 do
    throw (IO.userError "invalid numerical matrix entry")
  let bytes ← IO.ofExcept (decodeHex entry.projected)
  unless (← writer.extent.get)+bytes.size+65536 < 2^63 do
    throw (IO.userError "numerical matrix exceeds filesystem extent")
  let mut chunks := []
  let mut offset := 0
  while offset < bytes.size do
    let part := bytes.extract offset (min bytes.size (offset+4096))
    if valid : 0 < part.size ∧ part.size ≤ 4096 then
      chunks := (← writer.appendBlob part valid.1 valid.2) :: chunks
    else throw (IO.userError "invalid projected numerical chunk")
    offset := offset+part.size
  let row : Row := ⟨entry.coverage,bytes.size,chunks.reverse⟩
  return (("row:" ++ entry.key,some (rowCodec.encode row).toByteArray),bytes.size)

/-- This private directory contains rebuildable generations only. Exclusive
maintenance ownership precedes reclamation, including interrupted producers.
Open readers retain their original file descriptors; they need no old path. -/
private def retireOthers (path : System.FilePath) (keep : Option String) : IO Unit := do
  for entry in ← path.readDir do
    if Receipt.validId entry.fileName && keep != some entry.fileName then
      FileSystem.rejectSymlinkAncestors entry.path
      while !(← FileSystem.pruneDirectory entry.path.toString ⟨128,by decide⟩) do pure ()

/-- Source-only streaming preparation, under the DB maintenance claim. The
producer owns one projection at a time. Atomically publish a sealed generation
only after its root is durable; replace/remove only our previous generation.
Existing pinned readers may retain old bytes or miss, never receive a mix. -/
private def writeClaimed (root : System.FilePath) (model encoder : String) (keys : List String)
    (produce : String → IO Entry) : IO Result := do
  let started ← IO.monoMsNow
  unless !keys.isEmpty do throw (IO.userError "empty numerical matrix")
  let path ← Sidecar.childDirectory root "matrix-tree"
  let previous ← try some <$> manifest root catch _ => pure none
  retireOthers path (previous.map (·.generation))
  let generation ← Receipt.fresh
  let directory := path / generation
  let initial ← PageMap.create directory (authority model encoder)
  let published ← IO.mkRef false
  try
    let (bytes,head,_) ← PageMap.withWriter initial fun writer => do
      let mut levels := []
      let mut rows := []
      let mut total := 0
      let mut count := 0
      let mut previous : Option String := none
      for key in keys.mergeSort do
        unless Receipt.validId key && previous.all (· < key) do
          throw (IO.userError "duplicate or invalid numerical matrix key")
        let entry ← produce key
        unless entry.key == key do throw (IO.userError "numerical producer returned a different key")
        let (row,bytes) ← appendRow writer entry
        rows := row :: rows
        total := total+bytes
        count := count+1
        previous := some key
        if count % 64 == 0 then
          levels ← flushLeaves writer rows levels
          rows := []
      levels ← flushLeaves writer rows levels
      writer.root.set (some (← finish writer levels))
      return total
    let record : Manifest := ⟨model,encoder,implementation,generation,head,keys.length,bytes⟩
    unless validManifest record model encoder do throw (IO.userError "numerical matrix root count disagrees")
    IO.setAccessRights (PageMap.dataPath directory head) {user := {read := true},group := {},other := {}}
    FileSystem.atomicExistingBytes (path / "ready.json") (toJson record).compress.toUTF8
    published.set true
    retireOthers path (some generation)
    return ⟨"prepared",keys.length,bytes,(← IO.monoMsNow)-started⟩
  finally
    if !(← published.get) && (← FileSystem.symlinkMetadata? directory).isSome then
      IO.FS.removeDirAll directory

/-- Different DB roots have independent claims. Competing preparers of the
same root fail before producing any row. Readers never acquire this lock. -/
opaque writeUsing (root : System.FilePath) (model encoder : String) (keys : List String)
    (produce : String → IO Entry) : IO Result := do
  let path ← Sidecar.childDirectory root "matrix-tree"
  let lock := path / "writer"
  FileSystem.immutableExistingBytes lock ByteArray.empty
  let guard ← FileSystem.openRead lock.toString
  unless ← FileSystem.tryReadLock guard true do
    throw (IO.userError "numerical matrix preparer is busy")
  try writeClaimed root model encoder keys produce
  finally FileSystem.unlockRead guard

end Eggshell.VectorMatrix
