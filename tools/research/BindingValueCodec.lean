module
public import Eggshell.Synapses
public import Eggshell.DB.Wire
@[expose] public section

namespace Eggshell.Synapses.BindingValueCodec
open DB.Wire

/-- The original metadata fields, without JSON object names or escaping.
This is a lossless codec, not a new identity or an authority judgment. -/
def file : Codec File :=
  (text.product (text.product natural)).iso
    (fun value => (value.relative,value.fingerprint,value.bytes))
    (fun (relative,fingerprint,bytes) => ⟨relative,fingerprint,bytes⟩)
    (by intro value; cases value; rfl)

def original : Codec Original :=
  (text.product (text.product natural)).iso
    (fun value => (value.work,value.content,value.chars))
    (fun (work,content,chars) => ⟨work,content,chars⟩)
    (by intro value; cases value; rfl)

def subject : Codec Subject :=
  (sum file original).iso
    (fun value => match value with | .file value => .inl value | .original value => .inr value)
    (fun value => match value with | .inl value => .file value | .inr value => .original value)
    (by intro value; cases value <;> rfl)

def range : Codec Range :=
  (subject.product (natural.product natural)).iso
    (fun value => (value.subject,value.first,value.last))
    (fun (subject,first,last) => ⟨subject,first,last⟩)
    (by intro value; cases value; rfl)

def occurrence : Codec Occurrence :=
  (text.product (text.product text)).iso
    (fun value => (value.session,value.turn,value.useId))
    (fun (session,turn,useId) => ⟨session,turn,useId⟩)
    (by intro value; cases value; rfl)

def binding : Codec Binding :=
  (text.product (text.product (text.product (natural.product natural)))).iso
    (fun value => (value.database,value.owner,value.work,value.first,value.limit))
    (fun (database,owner,work,first,limit) => ⟨database,owner,work,first,limit⟩)
    (by intro value; cases value; rfl)

def quotations : Codec (Array String) :=
  (list text).iso Array.toList List.toArray (by intro value; simp)

def read : Codec Read :=
  (occurrence.product (range.product (binding.product quotations))).iso
    (fun value => (value.occurrence,value.source,value.binding,value.quotations))
    (fun (occurrence,source,binding,quotations) => ⟨occurrence,source,binding,quotations⟩)
    (by intro value; cases value; rfl)

def entry : Codec (String × Read) := text.product read

theorem read_roundtrip (value : Read) (tail : List UInt8) :
    read.decode (read.encode value ++ tail) = .ok (value,tail) := read.roundtrip value tail

theorem entry_roundtrip (value : String × Read) (tail : List UInt8) :
    entry.decode (entry.encode value ++ tail) = .ok (value,tail) := entry.roundtrip value tail

theorem entry_injective : Function.Injective entry.encode := entry.encode_injective

end Eggshell.Synapses.BindingValueCodec
