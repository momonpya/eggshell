import Main
import Eggshell.ContractAudit
open Lean Eggshell Eggshell.Plugin SharedRangeAdapter

#print axioms local_choice_has_no_originals
#print axioms original_query_cannot_select_locally
#print axioms invalid_query_cannot_select_locally
#print axioms local_choice_validates_query

private def query (count budget : Nat) (capture : Bool) : ServiceQuery := Id.run do
  let mut generic := #[]
  let mut pieces := []
  let mut costs := #[]
  for family in [:count] do
    for offset in [:2] do
      let payload := costs.size
      costs := costs.push (5+offset,5+offset)
      generic := generic.push {family,ranges := [(offset*4,offset*4+6)],payloads := [payload],contextual := offset == 0}
      pieces := {family,first := offset*4,last := offset*4+6,weight := 100/(family+1)+offset} :: pieces
  return {
    owners := (List.range count).toArray.map fun i => s!"owner-{i}"
    works := (List.range count).toArray.map fun i => (s!"work-{i}",i+1)
    frameCosts := Array.replicate count (2,2)
    scale := 100,genericCosts := costs,generic,pieces := pieces.reverse,files := #[],bundles := #[]
    fixed := (1,1),ceiling := (budget,budget),captureRanges := capture,captureInput := capture}

/-- Independent literal loop from the service's pre-existing generic branch.
No cached helper or genericDomain is used to derive the oracle's unit order. -/
private def oracle (input : ServiceQuery) : Option ServiceChoice := do
  let mut units := #[]
  let mut pieces := []
  for family in List.range input.owners.size do
    pieces := pieces ++ input.pieces.filter (·.family == family)
    for (unit,ordinal) in input.generic.zipIdx do
      if unit.family == family then
        units := units.push {shape := {family,ranges := unit.ranges},generic := some ordinal,contextual := unit.contextual}
  let source ← (Synapses.PreparedSourceView.domain #[] {} input.frameCosts).toOption
  selectView input units pieces source

private def checks : IO Unit := do
  let mut count := 0
  for size in [0,1,4,16,64] do
    for budget in [1,7,16,40,10000] do
      for captured in [false,true] do
        let input := query size budget captured
        let expected := (oracle input).map toJson
        let actual := (selectLocal? input).map (fun selected => toJson selected.choice)
        unless actual == expected do throw (IO.userError s!"generic oracle mismatch size={size},budget={budget}")
        if let some selected := selectLocal? input then
          unless selected.choice.sourceKeys.isEmpty do throw (IO.userError "local choice fetched source rows")
        let foreign := {input with files := #[{family := 0,owner := "owner-0",baseCues := [],allCues := [],groups := []}]}
        unless (selectLocal? foreign).isNone do throw (IO.userError "original-dependent plan bypassed the service")
        count := count+1
  let wellFormed := query 4 40 false
  for malformed in #[{wellFormed with works := #[]},{wellFormed with frameCosts := #[]},
      {wellFormed with genericCosts := #[]},{wellFormed with owners := #[]}] do
    unless !malformed.valid && (selectLocal? malformed).isNone do
      throw (IO.userError "local selector bypassed a service domain bound")
  IO.println (Json.mkObj [("allPassed",toJson true),("cases",toJson count),
    ("completeChoiceEqual",toJson true),("originalDependentQueriesRejected",toJson true),
    ("malformedDomainsRejected",toJson (4 : Nat)),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).compress

def main (args : List String) : IO UInt32 := do
  if args == ["local-selection-checks"] then checks; return 0
  sourceRouteEngine args
