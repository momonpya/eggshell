module
public import tools.research.CursorCodec
public import Eggshell.SynapseIndex
import all Init.System.IO
import all Init.System.ST
@[expose] public section
namespace Eggshell.Synapses.CursorBinding
open DB.CursorCodec

def file : Reader BindingValueCodec.file :=
  (text.product (text.product natural)).iso
    (fun (value : File) => (value.relative,value.fingerprint,value.bytes))
    (fun (relative,fingerprint,bytes) => ⟨relative,fingerprint,bytes⟩)
    (by intro value; cases value; rfl)

def original : Reader BindingValueCodec.original :=
  (text.product (text.product natural)).iso
    (fun (value : Original) => (value.work,value.content,value.chars))
    (fun (work,content,chars) => ⟨work,content,chars⟩)
    (by intro value; cases value; rfl)

def subject : Reader BindingValueCodec.subject :=
  (file.sum original).iso
    (fun (value : Subject) => match value with | .file value => .inl value | .original value => .inr value)
    (fun value => match value with | .inl value => .file value | .inr value => .original value)
    (by intro value; cases value <;> rfl)

def range : Reader BindingValueCodec.range :=
  (subject.product (natural.product natural)).iso
    (fun (value : Range) => (value.subject,value.first,value.last))
    (fun (subject,first,last) => ⟨subject,first,last⟩)
    (by intro value; cases value; rfl)

def occurrence : Reader BindingValueCodec.occurrence :=
  (text.product (text.product text)).iso
    (fun (value : Occurrence) => (value.session,value.turn,value.useId))
    (fun (session,turn,useId) => ⟨session,turn,useId⟩)
    (by intro value; cases value; rfl)

def binding : Reader BindingValueCodec.binding :=
  (text.product (text.product (text.product (natural.product natural)))).iso
    (fun (value : Binding) => (value.database,value.owner,value.work,value.first,value.limit))
    (fun (database,owner,work,first,limit) => ⟨database,owner,work,first,limit⟩)
    (by intro value; cases value; rfl)

def quotations : Reader BindingValueCodec.quotations :=
  text.list.iso Array.toList List.toArray (by intro value; simp)

def read : Reader BindingValueCodec.read :=
  (occurrence.product (range.product (binding.product quotations))).iso
    (fun (value : Read) => (value.occurrence,value.source,value.binding,value.quotations))
    (fun (occurrence,source,binding,quotations) => ⟨occurrence,source,binding,quotations⟩)
    (by intro value; cases value; rfl)

def entry : Reader Index.bindingCodec :=
  (text.product read).iso
    (fun (value : Index.StoredBinding) => (value.fact,value.read))
    (fun (fact,read) => ⟨fact,read⟩)
    (by intro value; cases value; rfl)

def decode (bytes : ByteArray) : IO Index.StoredBinding := do
  unless bytes.size ≤ 32768 do throw (IO.userError "stored binding exceeds its metadata bound")
  IO.ofExcept (entry.payload bytes "noncanonical binary binding")

theorem payload_exact (bytes : ByteArray) :
    entry.payload bytes "noncanonical binary binding" =
      Index.bindingCodec.payload bytes "noncanonical binary binding" := entry.payload_exact bytes _

private theorem io_ok_bind (value : α) (next : α → IO β) :
    ((pure value : IO α) >>= next) = next value := rfl
private theorem io_error_bind (error : IO.Error) (next : α → IO β) :
    ((throw error : IO α) >>= next) = (throw error : IO β) := rfl
private theorem except_ok_bind (value : α) (next : α → Except String β) :
    ((Except.ok value : Except String α) >>= next) = next value := rfl
private theorem except_error_bind (error : String) (next : α → Except String β) :
    ((Except.error error : Except String α) >>= next) = Except.error error := rfl
private theorem except_error_map (error : String) (f : α → β) :
    f <$> (Except.error error : Except String α) = Except.error error := rfl
private theorem except_pure (value : α) : (pure value : Except String α) = Except.ok value := rfl
private theorem except_throw (error : String) : (throw error : Except String α) = Except.error error := rfl
attribute [local simp] io_ok_bind io_error_bind except_ok_bind except_error_bind except_error_map except_pure except_throw

theorem decode_exact (bytes : ByteArray) : decode bytes = Index.CanonicalDecoder.decodeWithoutEncode bytes := by
  unfold decode Index.CanonicalDecoder.decodeWithoutEncode
  rw [payload_exact]
  cases parsed : Index.bindingCodec.decode bytes.toList with
  | error message => simp [DB.Wire.Codec.payload,parsed,IO.ofExcept]
  | ok pair =>
    rcases pair with ⟨value,rest⟩
    cases rest <;> simp [DB.Wire.Codec.payload,parsed,IO.ofExcept] <;> rfl

#print axioms payload_exact
#print axioms decode_exact
end Eggshell.Synapses.CursorBinding
