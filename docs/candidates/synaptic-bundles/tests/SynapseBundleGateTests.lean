import Eggshell.Handoff
import Eggshell.SynapseBundles
import tools.ClosedCoverage

open Lean Eggshell Eggshell.Plugin Eggshell.Synapses Eggshell.Synapses.Extraction

private def check (value : Bool) (message : String) : IO Unit :=
  unless value do throw (IO.userError message)

private def original (name : String) (line : Nat) : Transport.Owner := Id.run do
  let work := Value.text ("shell\n" ++ (Json.mkObj [
    ("command",toJson s!"nl -ba src/source.cpp | sed -n '{line},{line}p'")]).compress)
  let output := Value.text s!"  {line}\tSYMBOL_{name}\n"
  let event := Value.applyList .occurrence [Ref.semantic output,Ref.semantic work,
    Ref.exact (.text "gate"),Ref.exact (.text "turn"),Ref.exact (.text name)]
  let owner := OutcomeEdge.make work output [event] (by simp) (by simp [maxOutcomeObservations])
  return ⟨"database",owner,[{
    workspace := "/fixture",complete := true
    files := [⟨"src/source.cpp",some ⟨1000,String.ofList (List.replicate 64 'c')⟩⟩]}]⟩

private def fixture : IO Bundles.Projected := do
  let a := original "A" 11
  let b := original "B" 21
  let aDoc ← IO.ofExcept a.document
  let bDoc ← IO.ofExcept b.document
  let aRows ← IO.ofExcept (recordedRows "database" aDoc)
  let bRows ← IO.ofExcept (recordedRows "database" bDoc)
  let claim : Claim := ⟨"database","answer",0,10⟩
  let aSupport ← IO.ofExcept (Support.checked aRows[0]! aRows[0]!.source claim)
  let bSupport ← IO.ofExcept (Support.checked bRows[0]! bRows[0]!.source claim)
  let mut offers := #[]
  for support in #[aSupport,bSupport] do
    let fact := Fact.supports support
    let some offer := Recommend.Offer.check? support.source 0 fact ⟨Index.contentKey fact,rfl⟩ |
      throw (IO.userError "invalid fixture support")
    offers := offers.push offer
  let plan : Transport.Plan := {
    results := #[{offers}]
    owners := #[⟨a.original,Recommend.locate offers aRows⟩,⟨b.original,Recommend.locate offers bRows⟩]}
  let some joint := (Bundles.project plan)[0]? | throw (IO.userError "no two-owner dependency")
  return joint

private def run (projected : Bundles.Projected) (full independent : Bool) : IO Unit := do
  let mut families : Array SharedRangeAdapter.Family := #[]
  let mut units : Array SharedRangeAdapter.UnitPlan := #[]
  let mut pieces : List SharedRangeAdapter.CuePiece := []
  for member in projected.members do
    let some bound := member.choices[0]? | throw (IO.userError "unlocated fixture")
    let some source := Matcher.atomText? bound.original.outcome | throw (IO.userError "no original scalar")
    let slice : TransportSlice := {
      owner := some bound.original.relation,keys := [],text := source,members := [],visibleKeys := []}
    let family := families.size
    families := families.push {owner := bound.original,template := slice,windows := []}
    units := units.push {family,slice,ranges := bound.spans}
    for (first,last) in bound.spans do
      pieces := pieces ++ [{family,first,last,weight := 100,baseWeight := if independent && family == 0 then 100 else 0}]
  let keys := families.map fun family => relationKey family.owner.relation
  let limit := if full then (10000,10000) else match units[0]? with
    | none => (0,0)
    | some first => (first.slice.text.length+1,first.slice.text.utf8ByteSize+1)
  let some p := SharedRangeAdapter.problem families.toList units.toList pieces (0,0) limit |
    throw (IO.userError "could not construct source costs")
  let candidates := projected.members.foldl (fun known member => known.insert member.source
    ((List.finRange units.size).filter fun index => SharedRangeAdapter.memberCovered keys units [index] member))
    ({} : Std.HashMap Range (List (Fin units.size)))
  let some plan := SharedRangeAdapter.bundlePlan? keys units p candidates projected |
    throw (IO.userError "no complete production bundle")
  let some recipe := SharedRangeAdapter.bundleRecipe? keys units pieces p plan |
    throw (IO.userError "could not bind dependency to original cue atoms")
  let recipes := ClosedCoverage.original p ++ #[recipe,recipe]
  let compiled := ClosedCoverage.compile p recipes
  let some chosen := SharedCoverage.choose? compiled | throw (IO.userError "empty evidence frame failed")
  let expanded := ClosedCoverage.expand p recipes chosen.selected
  let expected := if full then 200 else if independent then 100 else 0
  check (SharedCoverage.benefit compiled chosen.selected == expected)
    "production adapter credited an incomplete relation or lost independent current-search evidence"
  check ((expanded.map (·.val)).eraseDups.length == (if full then 2 else if independent then 1 else 0))
    "production relation did not expand to the exact original owners"
  check (SharedCoverage.cost compiled chosen.selected == SharedCoverage.cost p expanded)
    "production recipe cost changed during expansion"

def main : IO Unit := do
  let projected ← fixture
  check (projected.members.size == 2) "fixture did not cross original owners"
  run projected true false
  run projected false false
  run projected false true
  IO.println "Lean production bundle gate passed: complete two-owner relation, no partial graph bonus, independent numerical base, duplicate relation and exact expansion cost"
