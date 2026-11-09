/- Inserted inside SharedRangeAdapter.ReferenceRecords in the isolated source.
These facts quantify over arbitrary records, including empty cue lists,
overlapping cues, duplicates, and cues outside the original record. -/
theorem Record.materializationCues_exact (record : Record) :
    record.materializationCues = record.envelope.cues.filterMap (fun (a,b) =>
      let first := max a record.stored.span.first
      let last := min b record.stored.span.limit
      if first < last then some (first,last) else none) := by
  simp only [Record.materializationCues,record.firstExact,record.lastExact]

/-- Final context and original text are exactly the former eager clipping,
not merely an equal cost or equal set of cues. List order is preserved. -/
theorem Candidate.selected_context_exact (shape : UnitShape) (record : Record) :
    (Candidate.mk shape (.original record)).toDraft =
      {family := shape.family
       payload := .contextual record.template
         {record.envelope with
          cues := record.envelope.cues.filterMap (fun (a,b) =>
            let first := max a record.stored.span.first
            let last := min b record.stored.span.limit
            if first < last then some (first,last) else none)
          fragments := [record.fragment]}
       ranges := shape.ranges
       coverage := shape.coverage} := by
  simp only [Candidate.toDraft,Record.materializationCues_exact]

/-- The selector sees the same price and presentation key whether cue clipping
has happened or remains deferred. -/
theorem parts_cue_independent (shape : UnitShape) (record : Record)
    (cues : List (Nat × Nat)) :
    parts ⟨shape,.original {record with envelope := {record.envelope with cues}}⟩ =
      parts ⟨shape,.original record⟩ := by
  rfl

#print axioms Record.materializationCues_exact
#print axioms Candidate.selected_context_exact
#print axioms parts_cue_independent
