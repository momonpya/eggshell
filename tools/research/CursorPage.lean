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
end Eggshell.DB.PageMap.CursorReader
