/-- Receipt intervals are bounded by their original source, not by an
extractor's preferred excerpt width. The packet limit is checked separately. -/
def DeliveryFragment.remainingRanges (fragment : DeliveryFragment)
    (previous : List DeliveryInterval) : List DeliveryInterval :=
  if positive : 0 < fragment.original.length then
    (⟨fragment.first,fragment.first + fragment.original.length,by omega⟩ : DeliveryInterval).subtractAll previous
  else []

theorem DeliveryFragment.remaining_ranges_exact (fragment : DeliveryFragment)
    (previous : List DeliveryInterval) (position : Nat) :
    (∃ part ∈ fragment.remainingRanges previous, part.covers position) ↔
      fragment.first ≤ position ∧ position < fragment.first + fragment.original.length ∧
        ∀ prior ∈ previous, ¬prior.covers position := by
  unfold remainingRanges
  split
  · rw [DeliveryInterval.subtractAll_covers]
    simp only [DeliveryInterval.covers]
    constructor
    · exact fun ⟨⟨first,last⟩,fresh⟩ => ⟨first,last,fresh⟩
    · exact fun ⟨first,last,fresh⟩ => ⟨⟨first,last⟩,fresh⟩
  · simp only [List.not_mem_nil, false_and, exists_false, false_iff]
    omega

def DeliveryFragment.remaining (fragment : DeliveryFragment) (previous : List DeliveryInterval) :
    List DeliveryFragment :=
  if previous.isEmpty then
    if 0 < fragment.original.length then [fragment] else []
  else
    (fragment.remainingRanges previous).map fun part =>
      {fragment with
        first := part.start,
        original := ((fragment.original.drop (part.start - fragment.first)).take (part.stop - part.start)).copy}

/-- No receipt means no slicing, decoding or copy of a selected original. -/
theorem DeliveryFragment.fresh_preserves (fragment : DeliveryFragment)
    (positive : 0 < fragment.original.length) :
    fragment.remaining [] = [fragment] := by
  simp [remaining,positive]
