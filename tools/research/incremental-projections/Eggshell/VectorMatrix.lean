module
public import Eggshell.DB.Sidecar
public import Eggshell.DB.Wire
public import Eggshell.Receipt
public import Eggshell.Sha256
public import tools.WindowCentroid

@[expose] public section

namespace Eggshell.VectorMatrix
open Lean DB

/-- Numerical hints only. Original observation and Work authority remain
outside this store, even when identical inputs share a projection. -/
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

/-- Reuse the original committed byte references, not a copied old matrix.
Append-only IO is an explicit premise, not a claim about arbitrary file writes. -/
theorem row_chunks_preserved_by_append (row : Row) (before added : ByteArray)
    (committed : ∀ blob ∈ row.chunks, blob.offset + blob.bytes ≤ before.size) :
    ∀ blob ∈ row.chunks,
      (before ++ added).extract blob.offset (blob.offset + blob.bytes) =
        before.extract blob.offset (blob.offset + blob.bytes) := by
  intro blob member
  exact PageMap.blob_bytes_preserved_by_append before added blob (committed blob member)

def implementation := Sha256.hex ((include_str "VectorMatrix.lean").toUTF8 ++
  (include_str "../tools/WindowCentroid.lean").toUTF8)

def maxRowBytes : Nat := 4096*8

def contract (model encoder : String) :=
  Sha256.hex (toJson [model,encoder,implementation]).compress.toUTF8

def authority (model encoder : String) := "eggshell.projected-matrix:" ++ contract model encoder

def folder (root : System.FilePath) (model encoder : String) :=
  root / "projections" / contract model encoder

/-- Counts and directory share one atomic PageMap publication. -/
structure Stats where
  rows : Nat := 0
  bytes : Nat := 0
  deriving ToJson

def statsCodec := (Wire.natural.product Wire.natural).iso
  (fun stats : Stats => (stats.rows,stats.bytes))
  (fun (rows,bytes) => Stats.mk rows bytes)
  (by intro stats; cases stats; rfl)

theorem stats_roundtrip (stats : Stats) (tail : List UInt8) :
    statsCodec.decode (statsCodec.encode stats ++ tail) = .ok (stats,tail) := statsCodec.roundtrip stats tail

structure Manifest where
  rows : Nat
  bytes : Nat

structure Ready where
  metadata : Manifest
  snapshot : PageMap.Snapshot

def statistics (snapshot : PageMap.Snapshot) : IO Stats := do
  if snapshot.head.root.isNone then return {}
  let some encoded ← snapshot.get "stats" | throw (IO.userError "missing projection statistics")
  let (stats,tail) ← IO.ofExcept (statsCodec.decode encoded.toList)
  unless tail.isEmpty && (statsCodec.encode stats).toByteArray == encoded &&
      0 < stats.rows && 0 < stats.bytes &&
      snapshot.head.root.any (·.rows == stats.rows+1) do
    throw (IO.userError "projection statistics disagree with publication")
  return stats

/-- One head and one bounded directory path, never the complete population. -/
def open? (root : System.FilePath) (model encoder : String) : IO (Option Ready) := do
  let some snapshot ← PageMap.open? (folder root model encoder) | return none
  unless snapshot.head.authority == authority model encoder do
    throw (IO.userError "foreign projection authority")
  if snapshot.head.root.isNone then return none
  let stats ← statistics snapshot
  return some ⟨⟨stats.rows,stats.bytes⟩,snapshot⟩

def ready (root : System.FilePath) (model encoder : String) : IO Bool := do
  try return (← open? root model encoder).isSome catch _ => return false

def decodeRow (encoded : ByteArray) : IO Row := do
  let (row,tail) ← IO.ofExcept (rowCodec.decode encoded.toList)
  unless tail.isEmpty && (rowCodec.encode row).toByteArray == encoded &&
      0 < row.bytes && row.bytes ≤ maxRowBytes && row.bytes % 8 == 0 &&
      row.coverage.utf8ByteSize ≤ 4096 && row.chunks.length == (row.bytes+4095)/4096 do
    throw (IO.userError "invalid numerical projection row")
  return row

def readRow (snapshot : PageMap.Snapshot) (row : Row) : IO (String × String) := do
  unless (← FileSystem.readVersion snapshot.handle).bytes ≥ snapshot.head.bytes do
    throw (IO.userError "projection committed prefix was truncated")
  let mut bytes := ByteArray.empty
  for chunk in row.chunks do
    unless chunk.bytes == min 4096 (row.bytes-bytes.size) do
      throw (IO.userError "invalid projection chunk shape")
    bytes := bytes ++ (← snapshot.readBlob chunk)
  unless bytes.size == row.bytes &&
      (← FileSystem.readVersion snapshot.handle).bytes ≥ snapshot.head.bytes do
    throw (IO.userError "projection committed prefix changed")
  return (row.coverage,Blake3.hex bytes)

/-- Pinned heads never gain references to a concurrent/unpublished suffix. -/
def read (ready : Ready) (key : String) : IO (Option (String × String)) := do
  unless Receipt.validId key do throw (IO.userError "invalid projection key")
  let some encoded ← ready.snapshot.get ("row:" ++ key) | return none
  some <$> readRow ready.snapshot (← decodeRow encoded)

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
  requested : Nat := 0
  produced : Nat := 0
  added : Nat := 0
  reused : Nat := 0
  writtenBytes : Nat := 0
  deriving ToJson

/-- Bulk construction buffers new rows only. -/
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

def finish (writer : PageMap.Writer) (levels : List Level) : IO PageMap.Ref := do
  let mut pending : Option PageMap.Ref := none
  for (level,index) in levels.zipIdx do
    let children := (pending.toList ++ level.refs).reverse
    if index+1 == levels.length then return ← writer.finishRoots children
    if !children.isEmpty then pending := some (← writer.appendPage (.branch children))
  throw (IO.userError "empty numerical projections")

def appendRow (writer : PageMap.Writer) (entry : Entry) : IO (PageMap.Row × Nat) := do
  unless Receipt.validId entry.key && entry.coverage.utf8ByteSize ≤ 4096 do
    throw (IO.userError "invalid numerical projection entry")
  let bytes ← IO.ofExcept (decodeHex entry.projected)
  unless (← writer.extent.get)+bytes.size+65536 < 2^63 do
    throw (IO.userError "projections exceed filesystem extent")
  let mut chunks := []
  let mut offset := 0
  while offset < bytes.size do
    let part := bytes.extract offset (min bytes.size (offset+4096))
    if valid : 0 < part.size ∧ part.size ≤ 4096 then
      chunks := (← writer.appendBlob part valid.1 valid.2) :: chunks
    else throw (IO.userError "invalid numerical projection chunk")
    offset := offset+part.size
  let row : Row := ⟨entry.coverage,bytes.size,chunks.reverse⟩
  return (("row:" ++ entry.key,some (rowCodec.encode row).toByteArray),bytes.size)

private def ensureClaimed (root : System.FilePath) (model encoder : String) (keys : List String)
    (produce : String → IO Entry) (started : Nat) : IO Result := do
  let path := folder root model encoder
  let snapshot ← match ← PageMap.open? path with
    | some snapshot => pure snapshot
    | none => PageMap.create path (authority model encoder)
  unless snapshot.head.authority == authority model encoder do
    throw (IO.userError "foreign projection authority")
  let before ← statistics snapshot
  let initial := snapshot.head.root.isNone
  let ((stats,produced,added),_,written) ← PageMap.withWriter snapshot fun writer => do
    let mut stats := before
    let mut produced := 0
    let mut added := 0
    let mut levels := []
    let mut rows := []
    for key in keys do
      let previous ← (← snapshot.get ("row:" ++ key)).mapM decodeRow
      let valid ← match previous with
        | none => pure false
        | some row => try let _ ← readRow snapshot row; pure true catch _ => pure false
      if valid then continue
      let entry ← produce key
      unless entry.key == key do throw (IO.userError "projection producer returned a different key")
      let (row,bytes) ← appendRow writer entry
      let previousBytes := previous.map (·.bytes) |>.getD 0
      unless previousBytes ≤ stats.bytes do throw (IO.userError "projection byte accounting disagrees")
      stats := ⟨stats.rows+(if previous.isNone then 1 else 0),stats.bytes-previousBytes+bytes⟩
      produced := produced+1
      if previous.isNone then added := added+1
      if initial then
        rows := row :: rows
        if produced % 64 == 0 then
          levels ← flushLeaves writer rows levels
          rows := []
      else
        writer.put row.1 row.2
        if produced % 64 == 0 then writer.flush
    if produced > 0 then
      if initial then
        levels ← flushLeaves writer rows levels
        writer.root.set (some (← finish writer levels))
      writer.put "stats" (some (statsCodec.encode stats).toByteArray)
    return (stats,produced,added)
  let mode := if produced == 0 then "warm" else if initial then "prepared" else "incremental"
  return {
    mode := mode
    rows := stats.rows
    bytes := stats.bytes
    elapsedMs := (← IO.monoMsNow)-started
    requested := keys.length
    produced := produced
    added := added
    reused := keys.length-produced
    writtenBytes := written }

/-- Complete or delta key requests never reproduce valid old projections.
The claim covers creation, suffix recovery, checking and publication. Input
enumeration remains proportional to requested keys; no full owner scan is here. -/
opaque ensureUsing (root : System.FilePath) (model encoder : String) (keys : List String)
    (produce : String → IO Entry) : IO Result := do
  let started ← IO.monoMsNow
  if keys.isEmpty then return {mode := "empty",rows := 0,bytes := 0,elapsedMs := 0}
  let keys := keys.mergeSort
  let mut previous : Option String := none
  for key in keys do
    unless Receipt.validId key && previous.all (· < key) do
      throw (IO.userError "duplicate or invalid numerical projection key")
    previous := some key
  let path ← Sidecar.childDirectory root "projections"
  let lock := path / (contract model encoder ++ ".writer")
  FileSystem.immutableExistingBytes lock ByteArray.empty
  let guard ← FileSystem.openRead lock.toString
  unless ← FileSystem.tryReadLock guard true do throw (IO.userError "projection preparer is busy")
  try ensureClaimed root model encoder keys produce started
  finally FileSystem.unlockRead guard

end Eggshell.VectorMatrix
