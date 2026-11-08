import tools.research.BaseCueScanChecks
import tools.research.ContainedCueIndex
open Eggshell Eggshell.Plugin Eggshell.Plugin.SharedRangeAdapter BaseCueScanChecks
namespace ContainedCueAgreement
def coordinates : ContainedCueIndex.Coordinates (CuePiece × Nat) :=
  ⟨(·.1.family),(·.1.first),(·.1.last)⟩

theorem native_key_is_generic : rangeKey = ContainedCueIndex.key cueBucketWidth coordinates := rfl
theorem native_requested_is_generic (shape : UnitShape) :
    requested shape = ContainedCueIndex.keys cueBucketWidth shape.family shape.ranges := rfl
theorem native_predicate_is_generic (shape : UnitShape) :
    accept shape = ContainedCueIndex.accepts coordinates shape.family shape.ranges (fun entry => entry.1.baseWeight > 0) := rfl

/-- This is the exact function called by the measured native component,
including its unchanged acceptance predicate and original input positions. -/
theorem native_rows_exact (entries : Array (CuePiece × Nat))
    (index : PreparedCueIndex.Prepared rangeKey entries) (shape : UnitShape) :
    rangeRows entries index shape = entries.toList.filter (accept shape) := by
  apply index.many_exact
  intro value accepted
  change ContainedCueIndex.key cueBucketWidth coordinates value ∈
    ContainedCueIndex.keys cueBucketWidth shape.family shape.ranges
  exact ContainedCueIndex.accepted_key cueBucketWidth shape.family coordinates shape.ranges
    (fun entry => entry.1.baseWeight > 0) value accepted

#print axioms native_rows_exact
end ContainedCueAgreement
