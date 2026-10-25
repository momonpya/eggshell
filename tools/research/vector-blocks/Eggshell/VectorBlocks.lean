module
public import Eggshell.VectorRoute

@[expose] public section
namespace Eggshell.VectorBlocks
open Lean DB

def maxBlockBytes : Nat := VectorRoute.leafLimit*VectorMatrix.maxRowBytes
def maxCachedBlocks : Nat := 1024

structure Block where
  offset : Nat
  bytes : Nat
  rows : Nat
  checksum : String
  deriving DecidableEq

def blockCodec := (Wire.natural.product (Wire.natural.product (Wire.natural.product Wire.text))).iso
  (fun block : Block => (block.offset,block.bytes,block.rows,block.checksum))
  (fun (offset,bytes,rows,checksum) => Block.mk offset bytes rows checksum)
  (by intro block; cases block; rfl)

theorem block_roundtrip (block : Block) (tail : List UInt8) :
    blockCodec.decode (blockCodec.encode block ++ tail) = .ok (block,tail) := blockCodec.roundtrip block tail

/-- Prefix immutability is the storage premise. This says nothing about
arbitrary overwrites of a previously committed file. -/
theorem committed_block_preserved_by_append (before added : ByteArray) (block : Block)
    (committed : block.offset+block.bytes ≤ before.size) :
    (before++added).extract block.offset (block.offset+block.bytes) =
      before.extract block.offset (block.offset+block.bytes) :=
  PageMap.blob_bytes_preserved_by_append before added ⟨block.offset,block.bytes,block.checksum⟩ committed

structure Entry where
  block : Nat
  row : Nat
  coverage : String

def entryCodec := (Wire.natural.product (Wire.natural.product Wire.text)).iso
  (fun entry : Entry => (entry.block,entry.row,entry.coverage))
  (fun (block,row,coverage) => Entry.mk block row coverage)
  (by intro entry; cases entry; rfl)

structure Manifest where
  matrix : PageMap.Head
  route : PageMap.Head
  offset : Nat
  rows : Nat
  rowBytes : Nat
  blocks : Nat
  deriving ToJson, FromJson

def implementation := Sha256.hex (include_str "VectorBlocks.lean").toUTF8
def contract (model encoder : String) := Sha256.hex (toJson
  [model,encoder,implementation,VectorMatrix.contract model encoder,VectorRoute.contract model encoder]).compress.toUTF8
def authority (model encoder : String) := "eggshell.vector-blocks:"++contract model encoder
def folder (root : System.FilePath) (model encoder : String) := root / "blocks" / contract model encoder

structure Ready where
  snapshot : PageMap.Snapshot
  manifest : Manifest

def open? (root : System.FilePath) (model encoder : String) (matrix : VectorMatrix.Ready)
    (route : VectorRoute.Ready) : IO (Option Ready) := do
  let some snapshot ← PageMap.open? (folder root model encoder) | return none
  unless snapshot.head.authority == authority model encoder do throw (IO.userError "foreign vector blocks")
  let some bytes ← snapshot.get "ready" | return none
  let some text := String.fromUTF8? bytes | throw (IO.userError "invalid block manifest")
  let manifest : Manifest ← IO.ofExcept (Json.parse text >>= fromJson?)
  unless manifest.matrix == matrix.snapshot.head && manifest.route == route.snapshot.head do return none
  unless route.manifest.matrix == matrix.snapshot.head && manifest.rows == matrix.metadata.rows &&
      manifest.rows == route.manifest.points && 0 < manifest.rowBytes &&
      manifest.rowBytes ≤ VectorMatrix.maxRowBytes && manifest.rowBytes%8 == 0 &&
      0 < manifest.blocks && manifest.blocks == route.manifest.leaves &&
      manifest.offset+manifest.rows*manifest.rowBytes ≤ snapshot.head.bytes &&
      snapshot.head.root.any (·.rows == manifest.rows+manifest.blocks+1) do
    throw (IO.userError "vector block coverage disagrees with its publication")
  return some ⟨snapshot,manifest⟩

structure Verified (block : Block) where
  bytes : ByteArray
  sized : bytes.size = block.bytes
  authenticated : PageMap.digest bytes = block.checksum

structure Slot (block : Block) (rowBytes : Nat) where
  offset : Nat
  inside : offset+rowBytes ≤ block.bytes

def Verified.slice (checked : Verified block) (slot : Slot block rowBytes) : ByteArray :=
  checked.bytes.extract slot.offset (slot.offset+rowBytes)

theorem Verified.slice_size (checked : Verified block) (slot : Slot block rowBytes) :
    (checked.slice slot).size = rowBytes := by
  simp only [slice,ByteArray.size_extract,checked.sized]
  have := slot.inside
  omega

structure Cached where
  scope : String
  id : Nat
  block : Block
  payload : Verified block

def used (entries : List Cached) : Nat := (entries.map (·.payload.bytes.size)).sum

structure State (capacity : Nat) where
  entries : List Cached
  bytes : Nat
  exact : bytes = used entries
  bounded : bytes ≤ capacity
  slotsBounded : entries.length ≤ maxCachedBlocks

theorem State.actual_bytes_bounded (state : State capacity) : used state.entries ≤ capacity := by
  rw [← state.exact]
  exact state.bounded

def State.empty (capacity : Nat) : State capacity := ⟨[],0,rfl,Nat.zero_le _,by simp [maxCachedBlocks]⟩

/-- Clear on capacity pressure. This deliberately simple shared cache bounds
actual retained bytes across DB scopes, not a separate allowance per DB. -/
def State.insert (state : State capacity) (entry : Cached) : State capacity :=
  if fits : entry.payload.bytes.size+state.bytes ≤ capacity ∧ state.entries.length+1 ≤ maxCachedBlocks then
    ⟨entry::state.entries,entry.payload.bytes.size+state.bytes,by simp [used,state.exact],fits.1,
      by simpa only [List.length_cons] using fits.2⟩
  else if fits : entry.payload.bytes.size ≤ capacity then
    ⟨[entry],entry.payload.bytes.size,by simp [used],fits,by simp [maxCachedBlocks]⟩
  else state

structure Cache where
  capacity : Nat
  state : IO.Ref (State capacity)
  hits : IO.Ref Nat
  misses : IO.Ref Nat

def Cache.make (capacity : Nat := 64*1024*1024) : IO Cache :=
  return ⟨capacity,← IO.mkRef (State.empty capacity),← IO.mkRef 0,← IO.mkRef 0⟩

def descriptor (ready : Ready) (id : Nat) : IO Block := do
  let some encoded ← ready.snapshot.get ("block:"++toString id) | throw (IO.userError "missing vector block")
  let (block,tail) ← IO.ofExcept (blockCodec.decode encoded.toList)
  unless tail.isEmpty && (blockCodec.encode block).toByteArray == encoded &&
      0 < block.rows && block.rows ≤ VectorRoute.leafLimit &&
      block.bytes == block.rows*ready.manifest.rowBytes && block.bytes ≤ maxBlockBytes &&
      block.offset ≥ ready.manifest.offset &&
      block.offset+block.bytes ≤ ready.manifest.offset+ready.manifest.rows*ready.manifest.rowBytes &&
      Receipt.validId block.checksum do throw (IO.userError "invalid vector block descriptor")
  return block

def readBlock (ready : Ready) (cache : Cache) (id : Nat) (block : Block) : IO (Verified block) := do
  let scope := (toJson ready.snapshot.head).compress
  if let some known := (← cache.state.get).entries.find? (fun entry => entry.scope == scope && entry.id == id) then
    if same : known.block = block then
      cache.hits.modify (·+1)
      return same ▸ known.payload
    else throw (IO.userError "cached vector block descriptor changed")
  cache.misses.modify (·+1)
  unless 0 < block.bytes && block.bytes ≤ maxBlockBytes &&
      block.offset+block.bytes ≤ ready.snapshot.head.bytes &&
      (← FileSystem.readVersion ready.snapshot.handle).bytes ≥ ready.snapshot.head.bytes do
    throw (IO.userError "vector block lies outside its committed prefix")
  let mut bytes := ByteArray.empty
  while bytes.size < block.bytes do
    let count := min 4096 (block.bytes-bytes.size)
    let part ← FileSystem.readPage ready.snapshot.handle (block.offset+bytes.size).toUInt64
      ⟨count,Nat.min_le_left _ _⟩
    unless part.size == count do throw (IO.userError "short vector block read")
    bytes := bytes ++ part
  unless (← FileSystem.readVersion ready.snapshot.handle).bytes ≥ ready.snapshot.head.bytes do
    throw (IO.userError "vector block prefix was truncated")
  if sized : bytes.size = block.bytes then
    if authenticated : PageMap.digest bytes = block.checksum then
      let checked : Verified block := ⟨bytes,sized,authenticated⟩
      cache.state.modify (·.insert ⟨scope,id,block,checked⟩)
      return checked
    else throw (IO.userError "vector block checksum mismatch")
  else throw (IO.userError "invalid vector block byte count")

structure Vector (rowBytes : Nat) where
  coverage : String
  bytes : ByteArray
  sized : bytes.size = rowBytes

/-- Return original binary64 row bytes; no per-row chunk checks or hex coding.
Only the first read of a resident block authenticates that complete block. -/
def read (ready : Ready) (cache : Cache) (key : String) : IO (Vector ready.manifest.rowBytes) := do
  unless Receipt.validId key do throw (IO.userError "invalid blocked vector key")
  let some encoded ← ready.snapshot.get ("row:"++key) | throw (IO.userError "blocked vector is absent")
  let (entry,tail) ← IO.ofExcept (entryCodec.decode encoded.toList)
  unless tail.isEmpty && (entryCodec.encode entry).toByteArray == encoded &&
      entry.row < ready.manifest.rows && entry.coverage.utf8ByteSize ≤ 4096 do
    throw (IO.userError "invalid blocked row location")
  let block ← descriptor ready entry.block
  let absolute := ready.manifest.offset+entry.row*ready.manifest.rowBytes
  unless block.offset ≤ absolute do throw (IO.userError "row precedes its nominated block")
  let relative := absolute-block.offset
  if inside : relative+ready.manifest.rowBytes ≤ block.bytes then
    let checked ← readBlock ready cache entry.block block
    let slot : Slot block ready.manifest.rowBytes := ⟨relative,inside⟩
    return ⟨entry.coverage,checked.slice slot,checked.slice_size slot⟩
  else throw (IO.userError "row exceeds its nominated block")

def original (matrix : VectorMatrix.Ready) (key : String) : IO (String × ByteArray) := do
  let some encoded ← matrix.snapshot.get ("row:"++key) | throw (IO.userError "original vector is absent")
  let row ← VectorMatrix.decodeRow encoded
  let mut bytes := ByteArray.empty
  for chunk in row.chunks do
    unless chunk.bytes == min 4096 (row.bytes-bytes.size) do throw (IO.userError "invalid original vector chunk")
    bytes := bytes ++ (← matrix.snapshot.readBlob chunk)
  unless bytes.size == row.bytes do throw (IO.userError "short original vector")
  return (row.coverage,bytes)

structure Preparation where
  mode : String
  rows : Nat
  blocks : Nat
  writtenBytes : Nat
  elapsedMs : Nat
  deriving ToJson

/-- One publication holds a dense raw region in routing-leaf order followed
by its key/block directories. All writes are explicit maintenance; no source
DB, source encoding, original projection bits or scoring policy is changed. -/
def prepare (root : System.FilePath) (model encoder : String) (matrix : VectorMatrix.Ready)
    (route : VectorRoute.Ready) : IO Preparation := do
  let started ← IO.monoMsNow
  if let some ready ← open? root model encoder matrix route then
    return ⟨"warm",ready.manifest.rows,ready.manifest.blocks,0,(← IO.monoMsNow)-started⟩
  unless route.manifest.matrix == matrix.snapshot.head do throw (IO.userError "router belongs to another matrix")
  let parent ← Sidecar.childDirectory root "blocks"
  let lock := parent / (contract model encoder++".writer")
  FileSystem.immutableExistingBytes lock ByteArray.empty
  let guard ← FileSystem.openRead lock.toString
  unless ← FileSystem.tryReadLock guard true do throw (IO.userError "vector block preparer is busy")
  try
    let path := folder root model encoder
    let snapshot ← match ← PageMap.open? path with
      | some snapshot => pure snapshot
      | none => PageMap.create path (authority model encoder)
    unless snapshot.head.authority == authority model encoder do throw (IO.userError "foreign vector block writer")
    let ((rows,blocks),_,written) ← PageMap.withWriter snapshot fun writer => do
      writer.root.set none
      let start ← writer.extent.get
      let mut frontier := [route.manifest.root]
      let mut visited : Std.HashSet Nat := {}
      let mut keys : Std.HashSet String := {}
      let mut rows := 0
      let mut blocks := 0
      let mut rowBytes := 0
      while let id::rest := frontier do
        frontier := rest
        unless !visited.contains id && visited.size < route.manifest.nodes do
          throw (IO.userError "routing graph repeats or exceeds its manifest")
        visited := visited.insert id
        match ← VectorRoute.readNode route id with
        | .branch _ _ _ left right => frontier := left::right::frontier
        | .leaf members =>
          let mut bytes := ByteArray.empty
          let first := rows
          let offset ← writer.extent.get
          for key in members do
            unless !keys.contains key do throw (IO.userError "duplicate original vector in routing leaves")
            keys := keys.insert key
            let (coverage,raw) ← original matrix key
            if rowBytes == 0 then rowBytes := raw.size
            unless raw.size == rowBytes do throw (IO.userError "original vector dimensions disagree")
            bytes := bytes ++ raw
            writer.put ("row:"++key) (some (entryCodec.encode ⟨id,rows,coverage⟩).toByteArray)
            rows := rows+1
          unless 0 < bytes.size && bytes.size ≤ maxBlockBytes do throw (IO.userError "invalid vector block shape")
          let mut position := 0
          while position < bytes.size do
            let part := bytes.extract position (min bytes.size (position+4096))
            if valid : 0 < part.size ∧ part.size ≤ 4096 then
              let chunk ← writer.appendBlob part valid.1 valid.2
              unless chunk.offset == offset+position do throw (IO.userError "vector block was interleaved")
            else throw (IO.userError "empty vector block fragment")
            position := position+part.size
          writer.put ("block:"++toString id)
            (some (blockCodec.encode ⟨offset,bytes.size,rows-first,PageMap.digest bytes⟩).toByteArray)
          blocks := blocks+1
      unless rows == matrix.metadata.rows && blocks == route.manifest.leaves &&
          visited.size == route.manifest.nodes &&
          (← writer.extent.get) == start+rows*rowBytes &&
          (← PageMap.pin matrix.snapshot.directory).head == matrix.snapshot.head &&
          (← PageMap.pin route.snapshot.directory).head == route.snapshot.head do
        throw (IO.userError "original matrix or routing coverage changed during block preparation")
      let manifest : Manifest := ⟨matrix.snapshot.head,route.snapshot.head,start,rows,rowBytes,blocks⟩
      writer.put "ready" (some (toJson manifest).compress.toUTF8)
      return (rows,blocks)
    let some _ ← open? root model encoder matrix route | throw (IO.userError "blocked matrix failed to publish")
    return ⟨"prepared",rows,blocks,written,(← IO.monoMsNow)-started⟩
  finally FileSystem.unlockRead guard

end Eggshell.VectorBlocks
