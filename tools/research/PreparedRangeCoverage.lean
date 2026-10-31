module
public import Eggshell.OriginalStructure
@[expose] public section

namespace Eggshell.Research.PreparedRangeCoverage
open Eggshell.Plugin

/-- Shared source geometry is prepared independently of a query family ID. -/
def validCoverage (ranges : List (Nat × Nat)) : List DeliveryInterval :=
  ranges.filterMap fun (first,last) =>
    if ordered : first < last then some ⟨first,last,ordered⟩ else none

structure CoverageIndex (ranges : List (Nat × Nat)) where
  intervals : List DeliveryInterval
  exact : ∀ position,(∃ part ∈ intervals,part.covers position) ↔
    ∃ part ∈ validCoverage ranges,part.covers position

def CoverageIndex.prepare (ranges : List (Nat × Nat)) : CoverageIndex ranges :=
  ⟨DeliveryInterval.coalesce (validCoverage ranges),DeliveryInterval.coalesce_covers _⟩

end Eggshell.Research.PreparedRangeCoverage
