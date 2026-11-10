module
public import tools.research.CanonicalCodec
public import tools.research.BindingValueCodec
@[expose] public section

namespace Eggshell.Synapses.BindingValueCodec
open DB.Wire

theorem file_canonical : file.Canonical := by
  unfold file
  apply Codec.Canonical.iso
  · exact text_canonical.product (text_canonical.product natural_canonical)
  · rintro ⟨a,b,c⟩; rfl

theorem original_canonical : original.Canonical := by
  unfold original
  apply Codec.Canonical.iso
  · exact text_canonical.product (text_canonical.product natural_canonical)
  · rintro ⟨a,b,c⟩; rfl

theorem subject_canonical : subject.Canonical := by
  unfold subject
  apply Codec.Canonical.iso
  · exact file_canonical.sum original_canonical
  · intro value; cases value <;> rfl

theorem range_canonical : range.Canonical := by
  unfold range
  apply Codec.Canonical.iso
  · exact subject_canonical.product (natural_canonical.product natural_canonical)
  · rintro ⟨a,b,c⟩; rfl

theorem occurrence_canonical : occurrence.Canonical := by
  unfold occurrence
  apply Codec.Canonical.iso
  · exact text_canonical.product (text_canonical.product text_canonical)
  · rintro ⟨a,b,c⟩; rfl

theorem binding_canonical : binding.Canonical := by
  unfold binding
  apply Codec.Canonical.iso
  · exact text_canonical.product (text_canonical.product (text_canonical.product
      (natural_canonical.product natural_canonical)))
  · rintro ⟨a,b,c,d,e⟩; rfl

theorem quotations_canonical : quotations.Canonical := by
  unfold quotations
  apply Codec.Canonical.iso
  · exact text_canonical.list
  · intro values; simp

theorem read_canonical : read.Canonical := by
  unfold read
  apply Codec.Canonical.iso
  · exact occurrence_canonical.product (range_canonical.product
      (binding_canonical.product quotations_canonical))
  · rintro ⟨a,b,c,d⟩; rfl

theorem entry_canonical : entry.Canonical := text_canonical.product read_canonical
#print axioms entry_canonical
end Eggshell.Synapses.BindingValueCodec
