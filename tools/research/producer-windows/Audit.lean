import Eggshell.CanonicalSourceCache
open Lean Eggshell.Synapses Eggshell.Synapses.CanonicalSource
namespace ProducerWindowAudit

theorem row_identity_unchanged (owner : String) (stored : Recipe.Stored)
    (layout : Recipe.Checked stored.rows) (focus : Option PreparedFocusFacts.Stored)
    (geometry : Option (Nat × Nat)) :
    (PreparedSourceView.ownerStored owner stored layout focus geometry).descriptor.rows =
      (OwnerPalette.describe stored layout).rows := rfl

#print axioms ProducerWindows.producer_row_retained
#print axioms ProducerWindows.producer_record_retained
#print axioms ProducerWindows.catalogue_complete
#print axioms ProducerWindows.chosen_basis_contains_row
#print axioms PreparedSourceView.owner_stored_costs_for_geometry
#print axioms row_identity_unchanged

run_elab do
  let env ← getEnv
  for (producer,consumer) in [
      (``CanonicalSource.Cache.projectOwner,``PreparedSourceView.publishOwner),
      (``PreparedSourceView.publishOwner,``PreparedSourceView.ownerStored),
      (``PreparedSourceView.ownerStored,``PreparedSourceView.planForOwner),
      (``PreparedSourceView.ownerStored,``ProducerWindows.prerequisites),
      (``PreparedSourceView.planForOwner,``ProducerWindows.units),
      (``ProducerWindows.requested,``SourceWindow.project)] do
    let some body := (env.find? producer).bind (·.value?) | throwError "producer is absent"
    unless body.getUsedConstants.contains consumer do throwError "published producer windows are disconnected"
  let mut pending := [``ProducerWindows.units,``ProducerWindows.prerequisites]
  let mut seen : Std.HashSet Name := {}
  while let name :: rest := pending do
    pending := rest
    if seen.contains name then continue
    seen := seen.insert name
    if let some declaration := env.find? name then
      for dependency in declaration.type.getUsedConstants do
        if ["IO","Eggshell.Matcher.Match","WorkGraph","Eggshell.WorkGraph"].contains dependency.toString then
          throwError "producer metadata depends on execution or authority"
      if let some body := declaration.value? then
        for dependency in body.getUsedConstants do
          if ["IO","Eggshell.Matcher.Match","WorkGraph","Eggshell.WorkGraph"].contains dependency.toString then
            throwError "producer preparation acquired execution or authority"
          if dependency.toString.startsWith "Eggshell.Synapses.ProducerWindows." then
            pending := dependency :: pending
end ProducerWindowAudit
