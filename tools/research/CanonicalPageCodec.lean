module
public import tools.research.CanonicalCodec
public import Eggshell.DB.PageMap
@[expose] public section

namespace Eggshell.DB.PageMap
open Wire

theorem row_codec_canonical : rowCodec.Canonical :=
  text_canonical.product byteBlob_canonical.optional

theorem ref_codec_canonical : refCodec.Canonical := by
  unfold refCodec
  apply Codec.Canonical.iso
  · exact natural_canonical.product (natural_canonical.product (text_canonical.product
      (text_canonical.product (text_canonical.product (natural_canonical.product natural_canonical)))))
  · rintro ⟨a,b,c,d,e,f,g⟩; rfl

theorem page_codec_canonical : pageCodec.Canonical := by
  unfold pageCodec
  apply Codec.Canonical.iso
  · exact row_codec_canonical.list.sum ref_codec_canonical.list
  · intro value; cases value <;> rfl

def decodeWithoutEncode (bytes : ByteArray) : Except String Page :=
  pageCodec.payload bytes "trailing bytes in index page"

theorem decode_without_encode_exact (bytes : ByteArray) : decodeWithoutEncode bytes = decode bytes :=
  page_codec_canonical.payload_exact bytes "trailing bytes in index page" "noncanonical index page"

#print axioms page_codec_canonical
#print axioms decode_without_encode_exact
end Eggshell.DB.PageMap
