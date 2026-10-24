import Eggshell.WindowOwners
import Lean

namespace Eggshell.WindowOwners
open Persistence.Store

/-- Completeness complements entries_original: every original window position
has a reverse posting, even when several positions have identical text. -/
theorem entries_complete (document : SearchDocument) (ordinal position : Nat)
    (key : String) (original : document.windows[position]? = some key) :
    (key,Occurrence.mk document.owner document.work ordinal position) ∈ entries document ordinal := by
  apply List.mem_map.mpr
  exact ⟨(key,position),List.mk_mem_zipIdx_iff_getElem?.mpr original,rfl⟩

/-- Identical window contents at different original positions do not collapse
their source coordinates in the nomination relation. Content sharing is not an
equality assertion about their Work or their observations. -/
theorem distinct_positions (document : SearchDocument) (ordinal left right : Nat)
    (_different : left ≠ right) :
    Occurrence.mk document.owner document.work ordinal left ≠
      Occurrence.mk document.owner document.work ordinal right := by
  intro same
  exact _different (congrArg Occurrence.position same)

open Lean in
run_meta do
  for name in #[``entries_complete, ``distinct_positions,
      ``entries_original, ``occurrence_roundtrip,
      ``Slice.consume_conserves, ``lookup_rows_bounded] do
    for dependency in ← Lean.collectAxioms name do
      unless #[``propext, ``Classical.choice, ``Quot.sound].contains dependency do
        throwError "Unapproved reverse-owner proof dependency: {name}, {dependency}"
  logInfo "Reverse-owner soundness/completeness, original positions and physical quota checked"

end Eggshell.WindowOwners
