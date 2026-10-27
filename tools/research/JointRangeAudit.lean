import Eggshell.Handoff
open Lean Eggshell Eggshell.Plugin Eggshell.Plugin.SharedRangeAdapter Eggshell.Synapses Eggshell.Synapses.Extraction

#print axioms covers_position
#print axioms member_covered_positions
#print axioms Plan.keeps_control
#print axioms Plan.within_budget
#print axioms BundlePlan.members_kept

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def fixture : IO Bundles.Projected := do
  let work := Value.text "mcp/fixture\n{\"resource\":\"opaque\"}"
  let output := Value.text "alpha\nbeta\ngamma\n"
  let event := Value.applyList .occurrence [Ref.semantic output,Ref.semantic work,
    Ref.exact (.text "gate"),Ref.exact (.text "turn"),Ref.exact (.text "call")]
  let edge := OutcomeEdge.make work output [event] (by simp) (by simp [maxOutcomeObservations])
  let owner : Transport.Owner := ⟨"fixture",edge,[]⟩
  let document ← IO.ofExcept owner.document
  let some original := ObservationContext.OriginalOwner.prepare? document |
    throw (IO.userError "no native original owner")
  let source := Range.original original.identity 0 10
  let some bound := (original.bind "fixture" source)[0]? |
    throw (IO.userError "cannot bind opaque output")
  let claim : Claim := ⟨"fixture","answer",0,10⟩
  let support ← IO.ofExcept (Support.checked bound.read source claim)
  let fact := Fact.supports support
  let some offer := Recommend.Offer.check? (.range source) 0 fact ⟨Index.contentKey fact,rfl⟩ |
    throw (IO.userError "invalid fixture support")
  let hints : Array Routing.Store.Hint := #[{
    target := offer.target,priority := offer.priority,evidence := Index.contentKey fact,
    kind := Routing.Store.kind fact,group := some (.claim claim)}]
  let located := Routed.locate hints #[bound.read]
  let plan : Transport.Plan := {
    results := #[{hints}]
    owners := #[⟨edge,document,located,#[]⟩]}
  let some projected := (Bundles.project plan)[0]? | throw (IO.userError "unlocated support")
  return projected

def main (args : List String) : IO Unit := do
  let [output] := args | throw (IO.userError "new output required")
  let root := System.FilePath.mk output
  check (!(← root.pathExists)) "preserve previous joint binding audit"
  IO.FS.createDir root
  let projected ← fixture
  let some member := projected.members[0]? | throw (IO.userError "no member")
  let some bound := member.choices[0]? | throw (IO.userError "no bound")
  let keys := #[bound.owner,"unrelated-owner"]
  let slice : TransportSlice := {keys := [],text := "original",members := [],visibleKeys := []}
  let make := fun (family : Nat) (first last : Nat) =>
    ({family,slice,ranges := [(first,last)]} : UnitPlan)
  let split := #[make 0 0 5,make 0 5 10]
  let indices := List.finRange split.size
  check (!indices.any (fun index => memberCovered keys split [index] member))
    "the regression fixture was already covered by a singleton"
  check (memberCovered keys split indices member) "adjacent original fragments did not form a complete member"
  let choices := memberChoices keys split (ownerReach keys split) member
  check (choices.length == 1 && choices[0]!.length == 2)
    "indexed binding did not return both required fragments"
  let gap := #[make 0 0 4,make 0 5 10]
  check ((memberChoices keys gap (ownerReach keys gap) member).isEmpty &&
    !memberCovered keys gap (List.finRange gap.size) member) "a missing character was silently filled"
  let mixed := #[make 0 0 5,make 1 5 10]
  check ((memberChoices keys mixed (ownerReach keys mixed) member).isEmpty &&
    !memberCovered keys mixed (List.finRange mixed.size) member) "another owner's bytes completed a binding"
  let offers : Array (SharedCoverage.Offer 2 1) := #[{closure := [0],covers := []},{closure := [1],covers := []}]
  let p : SharedCoverage.Problem := {costs := #[(1,1),(1,1)],weights := #[10],offers,limit := (10,10)}
  let candidates := ({} : Std.HashMap Range (List (List (Fin split.size)))).insert member.source choices
  let some complete := bundlePlan? keys split p candidates projected | throw (IO.userError "fragmented bundle was rejected")
  check (complete.indices.length == 2 && projected.members.all (memberCovered keys split complete.indices))
    "an admitted bundle omitted an original fragment"
  let entries := (List.range 96).toArray.map fun i =>
    ({first := (i*17)%131,limit := (i*17)%131+1+(i*11)%23,value := i} : RangeReach.Entry Nat)
  let reach := RangeReach.prepare entries
  for point in List.range 170 do
    let expected := entries.foldl (fun best entry =>
      if entry.first ≤ point && point < entry.limit then
        match best with | none => some entry.limit | some old => some (max old entry.limit)
      else best) none
    check ((reach.lookup? point).map (·.limit) == expected) "prefix reach diverged from complete scan"
  let mut probes := 0
  for first in List.range 150 do
    for width in List.range 24 do
      let last := first+width+1
      let expected := (List.range (last-first)).all fun offset =>
        entries.any fun entry => entry.first ≤ first+offset && first+offset < entry.limit
      let found := reach.cover? first last
      check (found.isSome == expected) "interval assembly missed a reachable span or crossed a gap"
      if let some values := found then
        check ((List.range (last-first)).all fun offset => entries.any fun entry =>
          values.contains entry.value && entry.first ≤ first+offset && first+offset < entry.limit)
          "returned identifiers did not contain the requested original bytes"
      probes := probes+1
  IO.FS.writeFile (root / "result.json") (Json.mkObj [("fragmentedMemberAccepted",toJson true),
    ("singletonRegressionConfirmed",toJson true),("gapRejected",toJson true),("mixedOwnerRejected",toJson true),
    ("opaqueMcpObservation",toJson true),("reachLookupProbes",toJson (170 : Nat)),
    ("reachCoverProbes",toJson probes),("modelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
