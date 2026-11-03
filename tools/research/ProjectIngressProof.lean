import Eggshell.SynapseJournal

open Eggshell.Synapses

namespace Eggshell.Research.ProjectIngressProof

/-- Projecting source knowledge preserves the native Work, query, occurrence,
output and answer. Only the retained knowledge may differ. -/
theorem projected_payload_preserves_original (original selected : Journal.Entry)
    (database : String) (accepted : original.forSource database = some selected) :
    match original.payload with
    | .start occurrence work query _ =>
        ∃ known, selected.payload = .start occurrence work query known
    | .answer occurrence query text _ =>
        ∃ known, selected.payload = .answer occurrence query text known
    | .finish .. => selected.payload = original.payload := by
  cases original with | mk clock payload received =>
    cases payload with
    | start occurrence work query known =>
      simp only [Journal.Entry.forSource] at accepted
      cases found : known.forSource database with
      | none => simp [found] at accepted
      | some chosen =>
        simp only [found,Option.map_some,Option.some.injEq] at accepted
        rw [← accepted]
        exact ⟨chosen,rfl⟩
    | answer occurrence query text known =>
      simp only [Journal.Entry.forSource] at accepted
      cases found : known.forSource database with
      | none => simp [found] at accepted
      | some chosen =>
        simp only [found,Option.map_some,Option.some.injEq] at accepted
        rw [← accepted]
        exact ⟨chosen,rfl⟩
    | finish occurrence name input response archive =>
      simp only [Journal.Entry.forSource,Option.some.injEq] at accepted
      rw [← accepted]

#print axioms Journal.Knowledge.forSource_identity
#print axioms Journal.Knowledge.forSource_context
#print axioms Journal.Entry.forSource_clock
#print axioms Journal.importEnd_bounded
#print axioms Journal.importEnd_not_backwards
#print axioms projected_payload_preserves_original

end Eggshell.Research.ProjectIngressProof
