module
public import PartitionBuild

@[expose] public section
namespace Eggshell.ClusterBlocks
open Lean DB

def rowsPerBlock : Nat := 32
def bufferCapacity : Nat := 64*1024*1024
def implementation := Sha256.hex (include_str "ClusterBlocks.lean").toUTF8
def contract (model encoder : String) := Sha256.hex (toJson
  [model,encoder,implementation,VectorPartition.implementation]).compress.toUTF8
def folder (root : System.FilePath) (model encoder : String) := root / "clustered" / contract model encoder
def authority (model encoder : String) := "eggshell.clustered-vectors:"++contract model encoder

def check (value : Bool) (message : String) : IO Unit :=
  unless value do throw (IO.userError message)

structure Member where
  key : String
  coverage : String

/-- Only original bytes enter the buffer. The cell changes physical placement,
never the value, coverage, source key or scoring primitive. -/
structure Buffer (width : Nat) where
  members : Array Member
  raw : ByteArray
  exact : raw.size = members.size*width
  bounded : members.size ≤ rowsPerBlock

def Buffer.empty (width : Nat) : Buffer width := ⟨#[],{},by simp,by simp [rowsPerBlock]⟩

def Buffer.push (buffer : Buffer width) (member : Member) (bytes : ByteArray)
    (sized : bytes.size = width) (room : buffer.members.size < rowsPerBlock) : Buffer width :=
  ⟨buffer.members.push member,buffer.raw++bytes,by
    simp only [ByteArray.size_append,Array.size_push,buffer.exact,sized,Nat.add_mul,Nat.one_mul],
    by simp only [Array.size_push]; omega⟩

theorem Buffer.original_byte_count (buffer : Buffer width) :
    buffer.raw.size = buffer.members.size*width := buffer.exact

theorem Buffer.bytes_bounded (buffer : Buffer width) :
    buffer.raw.size ≤ rowsPerBlock*width := by
  rw [buffer.exact]
  exact Nat.mul_le_mul_right width buffer.bounded

structure Header where
  partition : PageMap.Head
  input : PageMap.Head
  manifest : VectorBlocks.Manifest
  cells : Nat
  deriving ToJson, FromJson

def open? (root : System.FilePath) (model encoder : String) (matrix : VectorMatrix.Ready)
    (partition : VectorPartition.Ready) : IO (Option VectorBlocks.Ready) := do
  unless partition.header.basis.matrix == matrix.snapshot.head do return none
  let some snapshot ← PageMap.open? (folder root model encoder) | return none
  unless snapshot.head.authority == authority model encoder do throw (IO.userError "foreign clustered vector authority")
  let some raw ← snapshot.get "ready" | return none
  check (raw.size ≤ 65536) "oversized clustered readiness"
  let some text := String.fromUTF8? raw | throw (IO.userError "invalid clustered readiness")
  let header : Header ← IO.ofExcept (Json.parse text >>= fromJson?)
  let manifest := header.manifest
  unless header.partition == partition.snapshot.head && header.input == partition.header.basis.blocks &&
      manifest.matrix == matrix.snapshot.head && manifest.route == partition.snapshot.head do return none
  check (manifest.rows == matrix.metadata.rows && manifest.rowBytes == partition.header.basis.width*8 &&
    0 < manifest.rowBytes && manifest.rowBytes ≤ VectorMatrix.maxRowBytes &&
    0 < manifest.blocks && manifest.offset+manifest.rows*manifest.rowBytes ≤ snapshot.head.bytes &&
    header.cells == partition.header.cells &&
    snapshot.head.root.any (·.rows == manifest.rows+2*manifest.blocks+1))
    "clustered vector coverage disagrees with its publication"
  return some ⟨snapshot,manifest⟩

def geometry (partition : VectorPartition.Ready) : IO VectorPartition.Runtime := do
  let mut nodes := #[]
  for index in [:partition.header.nodes] do
    let some raw ← partition.snapshot.get (s!"node:{index}") | throw (IO.userError "missing assignment node")
    let (node,tail) ← IO.ofExcept (VectorPartition.nodeCodec.decode raw.toList)
    check (tail.isEmpty && (VectorPartition.nodeCodec.encode node).toByteArray == raw) "invalid assignment node"
    nodes := nodes.push node
  IO.ofExcept (VectorPartition.restore ⟨nodes,partition.header.root,partition.header.cells⟩
    partition.header.basis.width)

structure Progress where
  rows : Nat := 0
  blocks : Nat := 0

def flush (writer : PageMap.Writer) (start cell : Nat) (progress : IO.Ref Progress)
    (buffer : Buffer width) : IO Unit := do
  if buffer.members.isEmpty then return
  let before ← progress.get
  let offset ← writer.extent.get
  check (offset == start+before.rows*width && 0 < buffer.raw.size &&
    buffer.raw.size ≤ VectorBlocks.maxBlockBytes) "clustered block shape or offset mismatch"
  let mut position := 0
  while position < buffer.raw.size do
    let part := buffer.raw.extract position (min buffer.raw.size (position+4096))
    if valid : 0 < part.size ∧ part.size ≤ 4096 then
      let chunk ← writer.appendBlob part valid.1 valid.2
      check (chunk.offset == offset+position) "clustered raw bytes were interleaved"
    else throw (IO.userError "empty clustered fragment")
    position := position+part.size
  for (member,index) in buffer.members.toList.zipIdx do
    writer.put ("row:"++member.key)
      (some (VectorBlocks.entryCodec.encode ⟨before.blocks,before.rows+index,member.coverage⟩).toByteArray)
  let block : VectorBlocks.Block := ⟨offset,buffer.raw.size,buffer.members.size,PageMap.digest buffer.raw⟩
  writer.put (s!"block:{before.blocks}") (some (VectorBlocks.blockCodec.encode block).toByteArray)
  writer.put (s!"cell:{before.blocks}") (some (Wire.natural.encode cell).toByteArray)
  progress.set ⟨before.rows+buffer.members.size,before.blocks+1⟩

structure Preparation where
  mode : String
  rows : Nat
  blocks : Nat
  cells : Nat
  peakBufferedBytes : Nat := 0
  writtenBytes : Nat := 0
  elapsedMs : Nat := 0
  deriving ToJson

def coverages (input : VectorBlocks.Ready) (source : PartitionBuild.Catalogue) : IO (Array String) := do
  let mut result := Array.replicate source.rows.size ""
  let listed ← input.snapshot.foldRange ⟨"row:","row;"⟩ (fun rows row => pure (row::rows)) []
  for (key,raw) in listed do
    let some raw := raw | throw (IO.userError "retired original coverage")
    let (entry,tail) ← IO.ofExcept (VectorBlocks.entryCodec.decode raw.toList)
    check (tail.isEmpty && entry.row < source.rows.size &&
      key == "row:"++source.rows[entry.row]!.key) "original coverage coordinate mismatch"
    result := result.set! entry.row entry.coverage
  check (listed.length == source.rows.size) "original coverage directory is incomplete"
  return result

/-- One source-order pass, bounded cell buffers and one atomic publication.
All matrix rows, including focus-only projections, use this same layout.
No fallback reader or query-dependent copy is needed in the foreground. -/
def prepare (root : System.FilePath) (model encoder : String) (matrix : VectorMatrix.Ready)
    (input : VectorBlocks.Ready) (partition : VectorPartition.Ready) : IO Preparation := do
  let started ← IO.monoMsNow
  if let some ready ← open? root model encoder matrix partition then
    return {
      mode := "warm"
      rows := ready.manifest.rows
      blocks := ready.manifest.blocks
      cells := partition.header.cells
      elapsedMs := (← IO.monoMsNow)-started }
  check (input.snapshot.head == partition.header.basis.blocks &&
    input.manifest.matrix == matrix.snapshot.head && input.manifest.rows == matrix.metadata.rows)
    "clustered preparation has a foreign original basis"
  let source ← PartitionBuild.catalogue input
  let runtime ← geometry partition
  -- Keep coverage from the exact same original row directory. This is
  -- maintenance metadata, never a foreground catalogue or source body.
  let coverages ← coverages input source
  FileSystem.privateDirectory (root / "clustered")
  let path := folder root model encoder
  let previous ← PageMap.open? path
  let snapshot ← match previous with
    | some snapshot => pure snapshot
    | none => PageMap.create path (authority model encoder)
  check (snapshot.head.authority == authority model encoder) "foreign clustered writer"
  let buffers ← IO.mkRef (Array.replicate partition.header.cells (Buffer.empty input.manifest.rowBytes))
  let kept ← IO.mkRef 0
  let peak ← IO.mkRef 0
  let progress ← IO.mkRef ({} : Progress)
  let (_,_,written) ← PageMap.withWriter snapshot fun writer => do
    writer.root.set none
    let start ← writer.extent.get
    let flushAll := do
      for (buffer,cell) in (← buffers.get).toList.zipIdx do flush writer start cell progress buffer
      buffers.set (Array.replicate partition.header.cells (Buffer.empty input.manifest.rowBytes))
      kept.set 0
    PartitionBuild.walk source (List.range source.rows.size).toArray fun _ row bytes => do
      let values ← IO.ofExcept (VectorPartition.decode bytes)
      let cell ← IO.ofExcept (VectorPartition.assign runtime row.key values)
      check (cell < partition.header.cells) "foreign physical cell"
      if (← kept.get)+bytes.size > bufferCapacity then flushAll
      check ((← kept.get)+bytes.size ≤ bufferCapacity) "clustered buffer budget exceeded"
      let some buffer := (← buffers.get)[cell]? | throw (IO.userError "physical cell buffer is absent")
      if sized : bytes.size = input.manifest.rowBytes then
        if room : buffer.members.size < rowsPerBlock then
          let next := buffer.push ⟨row.key,coverages[row.position]!⟩ bytes sized room
          buffers.modify (·.set! cell next)
          kept.modify (·+bytes.size)
          let buffered ← kept.get
          peak.modify (max · buffered)
          if next.members.size == rowsPerBlock then
            flush writer start cell progress next
            buffers.modify (·.set! cell (Buffer.empty input.manifest.rowBytes))
            kept.modify (·-next.raw.size)
        else throw (IO.userError "unflushed clustered block")
      else throw (IO.userError "original row dimensions changed")
    flushAll
    let finished ← progress.get
    check (finished.rows == matrix.metadata.rows && (← kept.get) == 0 &&
      (← writer.extent.get) == start+finished.rows*input.manifest.rowBytes &&
      (← PageMap.pin matrix.snapshot.directory).head == matrix.snapshot.head &&
      (← PageMap.pin input.snapshot.directory).head == input.snapshot.head &&
      (← PageMap.pin partition.snapshot.directory).head == partition.snapshot.head)
      "original clustered basis changed during preparation"
    let manifest : VectorBlocks.Manifest := ⟨matrix.snapshot.head,partition.snapshot.head,start,
      finished.rows,input.manifest.rowBytes,finished.blocks⟩
    let header : Header := ⟨partition.snapshot.head,input.snapshot.head,manifest,partition.header.cells⟩
    writer.put "ready" (some (toJson header).compress.toUTF8)
  let some ready ← open? root model encoder matrix partition | throw (IO.userError "clustered publication unavailable")
  return {
    mode := if previous.isSome then "replaced" else "prepared"
    rows := ready.manifest.rows
    blocks := ready.manifest.blocks
    cells := partition.header.cells
    peakBufferedBytes := ← peak.get
    writtenBytes := written
    elapsedMs := (← IO.monoMsNow)-started }

end Eggshell.ClusterBlocks
