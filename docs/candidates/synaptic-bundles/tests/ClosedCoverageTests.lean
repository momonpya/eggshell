import tools.ClosedCoverage

open SharedCoverage ClosedCoverage

private def check (value : Bool) (message : String) : IO Unit :=
  unless value do throw (IO.userError message)

private def problem (limit : Nat × Nat) : Problem := {
  costs := #[(10,12),(20,22),(4,4)]
  weights := #[1,1,100]
  offers := #[{closure := [⟨0,by decide⟩,⟨2,by decide⟩],covers := [⟨0,by decide⟩]},
    {closure := [⟨1,by decide⟩,⟨2,by decide⟩],covers := [⟨1,by decide⟩]}]
  limit}

private def run (limit : Nat × Nat) (full : Bool) : IO Unit := do
  let p := problem limit
  let joint : Recipe p := {
    parts := [⟨0,by simp [p,problem]⟩,⟨1,by simp [p,problem]⟩]
    bonus := [⟨2,by simp [p,problem]⟩]}
  let recipes := original p ++ #[joint,joint]
  let compiled := compile p recipes
  let some chosen := choose? compiled | throw (IO.userError "empty source frame could not fit")
  let expanded := expand p recipes chosen.selected
  if full then
    check (benefit compiled chosen.selected == 102 && cost compiled chosen.selected == (34,38) &&
      (expanded.map (·.val)).eraseDups.length == 2)
      "joint graph value was not accompanied by both owners or shared framing was charged twice"
  else
    check (benefit compiled chosen.selected == 1 &&
      (expanded.map (·.val)).eraseDups.length == 1)
      "part of the evidence earned joint graph value or independent numerical evidence vanished"
  check (cost compiled chosen.selected == cost p expanded) "recipe expansion changed actual shared costs"

def main : IO Unit := do
  run (34,38) true
  run (25,38) false
  run (34,37) false
  run (14,16) false
  IO.println "Lean closed coverage passed: two-owner dependency, no partial bonus, independent base evidence, duplicate cue, shared frame and both budgets"
