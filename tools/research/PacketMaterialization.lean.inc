/-- Report reconstruction failure without conflating incompatible units with
an actual two-dimensional price violation. The price is evaluated once. -/
def PendingRendering.materializeReport (pending : PendingRendering) (choice : SharedRangeAdapter.ServiceChoice)
    (generic : Array SharedRangeAdapter.UnitPlan) (rows : Array Synapses.CanonicalSource.StoredRow) :
    Except String SharedRangeAdapter.RenderChoice := do
  let some slices := SharedRangeAdapter.materialize generic choice.generic.toList rows |
    throw ("selected original units cannot be combined; generic=" ++
      (toJson (choice.generic.filterMap fun index => generic[index]?.map fun unit =>
        (index,unit.family,unit.slice.context.isSome,unit.slice.shared.isSome))).compress)
  let result := pending.mandatory ++ slices
  let price := pending.cost result
  unless price.1 ≤ pending.ceiling.1 && price.2 ≤ pending.ceiling.2 do
    throw s!"materialized packet price chars={price.1},bytes={price.2} exceeds ceiling chars={pending.ceiling.1},bytes={pending.ceiling.2}"
  return {slices := result,receipt := choice.receipt,selectorInput := choice.selectorInput}

