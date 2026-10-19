import tools.PilotSimilarityControl

open Eggshell

deriving instance BEq for Matcher.WorkAlignment
deriving instance BEq for Matcher.ContextAlignment
deriving instance BEq for Matcher.Match

private def require (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private def fixture (child : Bool) : WorkGraph × OutcomeEdge := Id.run do
  let work := Value.text "alpha beta gamma"
  let result := Value.text "observed original result"
  let occurrence := Value.applyList .occurrence [Ref.semantic result, Ref.semantic work]
  let owner := OutcomeEdge.make work result [occurrence] (by simp) (by simp [maxOutcomeObservations])
  let frame := AllEdge.make (.applyList .inquiry []) [work] (by simp) (by
    simp [work, Value.text, Value.applyList])
  return ({all := if child then [frame] else [], outcomes := [owner]}, owner)

private def discover (child semantic enabled : Bool) : IO Matcher.Discovery := do
  let (graph, owner) := fixture child
  let text := "delta epsilon zeta"
  let current := Value.text text
  let corpus := Matcher.Corpus.build LogicalText.logicalNormalizer graph
  let nominations : Matcher.SemanticNominations := {
    related := if semantic then [owner.relation] else [] }
  let some result ← Matcher.discoverUsingM? () graph.all (fun _ => graph.outcomes)
      (fun _ => graph.all.map (·.relation) ++ graph.outcomes.map (·.relation)) (fun _ _ => none)
      (fun state view tasks => pure (state,
        (Matcher.demandedMatches LogicalText.logicalNormalizer corpus view current none
          nominations false tasks).map (PilotSimilarityControl.promote enabled)))
      current [] text 32 true |
    throw (IO.userError "similarity-control fixture did not converge")
  pure result

def main (args : List String) : IO Unit := do
  let normal ← discover true true false
  require normal.view.localUnions.isEmpty "ordinary semantic recommendation created equality"
  require (Matcher.extraction normal).selection.completedUses.isEmpty
    "ordinary semantic recommendation omitted Work"
  let control ← discover true true true
  require (!control.view.localUnions.isEmpty) "semantic control did not create an actual run-local union"
  require (!(Matcher.extraction control).selection.completedUses.isEmpty)
    "semantic control did not admit completed child Work"
  let parent ← discover false true true
  require (Matcher.extraction parent).selection.completedUses.isEmpty
    "semantic control bypassed the original child-role guard"
  let absent ← discover true false true
  require (absent.hits.isEmpty && absent.view.localUnions.isEmpty)
    "semantic control invented an un-nominated match"
  let some nominated := normal.hits.find? (·.retrieved) |
    throw (IO.userError "semantic fixture did not retain its retrieved Match")
  let promoted := PilotSimilarityControl.promote true nominated
  require (promoted.work == nominated.work && promoted.edge == nominated.edge &&
    promoted.context == nominated.context && promoted.demand == nominated.demand && !promoted.retrieved)
    "semantic control changed more than the retrieval admission lane"
  let intrinsic := {nominated with retrieved := false}
  require (PilotSimilarityControl.promote true intrinsic == intrinsic &&
    PilotSimilarityControl.promote false nominated == nominated)
    "semantic control changed intrinsic or lexical-only matches"
  let exactValue := Value.applyList .occurrence [Ref.exact (.text "different authority")]
  let exactGuard := {promoted with work := {promoted.work with currentFragment := exactValue}}
  require (Matcher.localUnion? normal.view.quotient (.text "inquiry") exactGuard).isNone
    "semantic control crossed an Exact footprint"
  if args == ["record"] then
    require ((← PilotSimilarityControl.apply false [nominated]) == [nominated])
      "lexical-only IO path changed its matches"
    require ((← PilotSimilarityControl.apply true [nominated]) == [promoted])
      "IO adapter did not apply the declared admission transformation"
  else
    require args.isEmpty "unknown control-test argument"
    let rejected ← try
      let _ ← PilotSimilarityControl.apply false []
      pure false
    catch _ => pure true
    require rejected "experimental IO adapter ran without its marker"
  IO.println "PASS semantic admission, real union/completion, parent guard, absent nominations, unchanged fields/intrinsic/lexical, Exact guard"
