import Eggshell.Handoff
open Lean Eggshell Eggshell.Plugin

private def check (test : Bool) (message : String) : IO Unit :=
  unless test do throw (IO.userError message)

private def original (name : String) : OutcomeEdge :=
  let work := Value.text ("observe " ++ name)
  let output := Value.text (String.ofList (List.replicate 29 'x'))
  let event := Value.applyList .occurrence [Ref.semantic output,Ref.semantic work,
    Ref.exact (.text "scope"),Ref.exact (.text "turn"),Ref.exact (.text name)]
  OutcomeEdge.make work output [event] (by simp) (by simp [maxOutcomeObservations])

def main : IO Unit := do
  let owners := #[original "a",original "b"]
  let slices := owners.toList.map fun owner =>
    ({owner := some owner.relation,keys := [],text := (Matcher.atomText? owner.outcome).getD "",
      members := [],visibleKeys := []} : TransportSlice)
  let families := owners.toList.zip slices |>.map fun (owner,template) =>
    ({owner,template,windows := []} : SharedRangeAdapter.Family)
  let scope := fun (parts : List TransportSlice) =>
    ((List.range owners.size).filter (fun index =>
      parts.any (fun part => part.owner == (owners[index]?).map (·.relation))),[])
  let render := fun (scope : ScopedCosts.Scope) =>
    (if scope.1.isEmpty then [] else [({key := "shared-graph",chars := 5,bytes := 5} : ScopedCosts.Charge)]) ++
      scope.1.map (fun owner => ({key := toString owner,chars := 40,bytes := 40} : ScopedCosts.Charge))
  let cost := fun parts : List TransportSlice =>
    let data := parts.foldl (fun sum part => (sum.1+part.text.length+1,sum.2+part.text.utf8ByteSize+1)) (0,0)
    let metadata := ScopedCosts.total (render (scope parts))
    (data.1+metadata.1,data.2+metadata.2)
  let some previous := SharedRangeAdapter.fit (100,100) cost families |
    throw (IO.userError "constant reservation fixture failed")
  check previous.val.isEmpty "old constant reserved inactive owners differently"
  let frames : SharedRangeAdapter.FrameCosts := {scope,render}
  let some result := SharedRangeAdapter.fit (100,100) cost families (frames := some frames) |
    throw (IO.userError "actual fitter rejected shared active metadata")
  check (result.val.length == 1 && result.val[0]?.bind (·.owner) == some (owners[0]'(by decide)).relation)
    "actual fitter failed to recover useful data from inactive metadata reservation"
  check (cost result.val == (75,75)) "actual packet has a different scope or data charge"
  check (result.val.all (fun part => part.members.isEmpty && part.visibleKeys.isEmpty))
    "metadata accounting manufactured native authority"
  IO.println "Lean production scoped frame check passed: useful data fits, actual cost checked, no native member added"
