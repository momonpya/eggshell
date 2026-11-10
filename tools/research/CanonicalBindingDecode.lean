module
public import tools.research.CanonicalBindings
public import Eggshell.SynapseIndex
import all Init.System.IO
import all Init.System.ST
@[expose] public section

namespace Eggshell.Synapses.Index
open DB.Wire

private theorem io_ok_bind (value : α) (next : α → IO β) :
    ((pure value : IO α) >>= next) = next value := rfl
private theorem io_error_bind (error : IO.Error) (next : α → IO β) :
    ((throw error : IO α) >>= next) = (throw error : IO β) := rfl
private theorem io_ok_map (value : α) (next : α → β) :
    next <$> (pure value : IO α) = pure (next value) := rfl
private theorem io_error_map (error : IO.Error) (next : α → β) :
    next <$> (throw error : IO α) = (throw error : IO β) := rfl
attribute [local simp] io_ok_bind io_error_bind io_ok_map io_error_map

theorem binding_codec_canonical : bindingCodec.Canonical := by
  unfold bindingCodec
  apply Codec.Canonical.iso
  · exact BindingValueCodec.entry_canonical
  · rintro ⟨a,b⟩; rfl

def decodeWithoutEncode (bytes : ByteArray) : IO StoredBinding := do
  unless bytes.size ≤ 32768 do throw (IO.userError "stored binding exceeds its metadata bound")
  let (stored,tail) ← IO.ofExcept (bindingCodec.decode bytes.toList)
  unless tail.isEmpty do throw (IO.userError "noncanonical binary binding")
  return stored

theorem decode_without_encode_exact (bytes : ByteArray) : decodeWithoutEncode bytes = decodeBinding bytes := by
  unfold decodeWithoutEncode decodeBinding
  cases parsed : bindingCodec.decode bytes.toList with
  | error message => simp [IO.ofExcept]
  | ok pair =>
    rcases pair with ⟨value,tail⟩
    cases tail with
    | nil =>
      simp [IO.ofExcept,binding_codec_canonical.full bytes value parsed,byteArray_beq_self]
    | cons byte rest => simp [IO.ofExcept]

#print axioms decode_without_encode_exact
end Eggshell.Synapses.Index
