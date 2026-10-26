import Eggshell.Handoff
open Lean Eggshell

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

/-- Three useful records share one expensive source envelope. Comparing
single records alone never opens it, even though their union is preferable. -/
private def setupTrap : SharedCoverage.Problem := {
  costs := #[(80,80),(8,8),(8,8),(8,8),(60,60)]
  weights := #[40,40,40,60]
  offers := #[
    {closure := [⟨0,by decide⟩,⟨1,by decide⟩],covers := [⟨0,by decide⟩]},
    {closure := [⟨0,by decide⟩,⟨2,by decide⟩],covers := [⟨1,by decide⟩]},
    {closure := [⟨0,by decide⟩,⟨3,by decide⟩],covers := [⟨2,by decide⟩]},
    {closure := [⟨4,by decide⟩],covers := [⟨3,by decide⟩]}]
  limit := (110,110) }

def main : IO Unit := do
  let p := setupTrap
  let available := (List.finRange p.offers.size).take 3
  let some activation := ClosedCoverage.activation? p ⟨0,by decide⟩ available |
    throw (IO.userError "shared setup proposal was lost")
  check (activation.recipe.parts.length == 3 && activation.recipe.bonus.isEmpty)
    "activation manufactured a cue or failed to amortize its setup"
  let some baseline := SharedCoverage.choose? p | throw (IO.userError "baseline failed")
  let recipes := ClosedCoverage.original p |>.push activation.recipe
  let augmented := ClosedCoverage.compile p recipes
  let some selected := SharedCoverage.choose? augmented | throw (IO.userError "augmented failed")
  let original := ClosedCoverage.expand p recipes selected.selected
  check (SharedCoverage.benefit p baseline.selected == 60 &&
      SharedCoverage.benefit p original == 120) "shared setup trap did not improve"
  check (SharedCoverage.cost p original == (104,104) &&
      SharedCoverage.cost augmented selected.selected == SharedCoverage.cost p original)
    "shared setup was discounted from the actual cost"
  let noneFound := ClosedCoverage.activation? p ⟨4,by decide⟩ available
  check noneFound.isNone "a proposal crossed an unrelated setup"
  let some duplicated := ClosedCoverage.activation? p ⟨0,by decide⟩ (available++available) |
    throw (IO.userError "duplicate input lost activation")
  check (SharedCoverage.benefit p duplicated.recipe.parts == 120 &&
      SharedCoverage.cost p duplicated.recipe.parts == (104,104))
    "duplicated observations manufactured votes or costs"
  IO.println (Json.mkObj [("sharedSetupTrap",toJson true),("noBonus",toJson true),
    ("originalOffersOnly",toJson true),("exactUnionCost",toJson true),
    ("duplicateInvariant",toJson true),("unrelatedSetupRejected",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("productionAdoption",toJson false)]).compress
