module
public import tools.research.CursorCodec
public import Eggshell.DB.PageMap
@[expose] public section
namespace Eggshell.DB.PageMap.CursorReader
open CursorCodec

def row : Reader rowCodec := text.product byteBlob.optional

def reference : Reader refCodec :=
  (natural.product (natural.product (text.product
    (text.product (text.product (natural.product natural)))))).iso
    (fun (r : Ref) => (r.offset,r.bytes,r.checksum,r.first,r.last,r.height,r.rows))
    (fun (offset,bytes,checksum,first,last,height,rows) => ⟨offset,bytes,checksum,first,last,height,rows⟩)
    (by intro value; cases value; rfl)

def page : Reader pageCodec :=
  (row.list.sum reference.list).iso
    (fun (value : Page) => match value with | .leaf rows => .inl rows | .branch children => .inr children)
    (fun value => match value with | .inl rows => .leaf rows | .inr children => .branch children)
    (by intro value; cases value <;> rfl)

def decode (bytes : ByteArray) : Except String Page := page.payload bytes "trailing bytes in index page"

theorem decode_exact (bytes : ByteArray) : decode bytes = CanonicalDecoder.decodeWithoutEncode bytes :=
  page.payload_exact bytes _

#print axioms decode_exact
def load (snapshot : Snapshot) (ref : Ref) : IO (Loaded ref) := do
  unless 0 < ref.bytes && ref.bytes ≤ 65536 && magic.size ≤ ref.offset &&
      ref.offset + ref.bytes ≤ snapshot.head.bytes do
    throw (IO.userError "index page is outside its pinned committed extent")
  if let some loaded ← snapshot.cached? ref then return loaded
  let mut bytes := ByteArray.empty
  while bytes.size < ref.bytes do
    let count := min 4096 (ref.bytes - bytes.size)
    let part ← FileSystem.readPage snapshot.handle (ref.offset + bytes.size).toUInt64
      ⟨count, Nat.min_le_left _ _⟩
    unless part.size == count do throw (IO.userError "truncated DB page")
    bytes := bytes ++ part
  snapshot.reads.modify (· + 1)
  snapshot.readBytes.modify (· + bytes.size)
  unless digest bytes == ref.checksum do throw (IO.userError "corrupted DB page")
  let page ← IO.ofExcept (decode bytes)
  if valid : agrees ref page = true then
    let loaded : Loaded ref := ⟨page, valid⟩
    snapshot.cachePage ⟨ref,loaded⟩
    pure loaded
  else throw (IO.userError "DB page differs from its directory descriptor")

theorem load_exact (snapshot : Snapshot) (ref : Ref) : load snapshot ref = snapshot.load ref := by
  unfold load Snapshot.load
  rw [show decode = Eggshell.DB.PageMap.decode from funext fun bytes =>
    (decode_exact bytes).trans (CanonicalDecoder.decode_without_encode_exact bytes)]
  rfl

@[csimp] theorem compiled_load : @Snapshot.load = @load := by
  funext snapshot ref
  exact (load_exact snapshot ref).symm

#print axioms load_exact
end Eggshell.DB.PageMap.CursorReader
