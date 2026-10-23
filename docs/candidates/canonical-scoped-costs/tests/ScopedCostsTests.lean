import tools.ScopedCosts
import tools.DeferredCoverage
open ScopedCosts SharedCoverage

private def check (value : Bool) (message : String) : IO Unit :=
  unless value do throw (IO.userError message)

private def fixture (limit : Nat := 100) : SharedCoverage.Problem := {
  costs := #[(30,30),(30,30)],weights := #[100,10],fixed := (85,85),limit := (limit,limit)
  offers := #[⟨[⟨0,by decide⟩],[⟨0,by decide⟩]⟩,⟨[⟨1,by decide⟩],[⟨1,by decide⟩]⟩] }

private def render (scope : Scope) : List Charge :=
  (if scope.1.isEmpty then [] else [⟨"graph-frame",5,5⟩]) ++
    scope.1.map fun owner => ⟨toString owner,40,40⟩

def main : IO Unit := do
  let old := fixture
  let some oldSelection := SharedCoverage.choose? old | throw (IO.userError "old fixed reservation could not open")
  check oldSelection.selected.isEmpty "fixture no longer demonstrates reservation of inactive owners"
  let scopes : Array Scope := #[([1],[]),([2],[])]
  let some next := ScopedCosts.prepare? old ([],[]) ([1,2],[]) scopes render |
    throw (IO.userError "could not transfer metadata costs")
  check (next.debit == (85,85) && next.problem.fixed == (0,0)) "fixed debit lost an exact metadata cost"
  check (next.problem.weights == old.weights && next.problem.limit == old.limit) "cost transfer changed relevance or budget"
  let some selected := SharedCoverage.choose? next.problem | throw (IO.userError "shared metadata frame could not open")
  check (selected.selected.map (·.val) == [0]) "an inactive owner prevented useful evidence from fitting"
  check (SharedCoverage.cost next.problem selected.selected == (75,75)) "selected owner or shared graph header was mischarged"
  let all := List.finRange next.problem.offers.size
  check (SharedCoverage.cost next.problem all == SharedCoverage.cost old (List.finRange old.offers.size))
    "full activation changed the existing aggregate charge"
  let duplicate : Array Scope := #[([1,1],[]),([1],[])]
  let some duplicate := ScopedCosts.prepare? (fixture 200) ([],[]) ([1,2],[]) duplicate render |
    throw (IO.userError "repeated owner metadata failed")
  check (SharedCoverage.cost duplicate.problem (List.finRange duplicate.problem.offers.size) == (105,105))
    "one owner or graph header was charged for each observation"
  let some base := ScopedCosts.prepare? old ([1],[]) ([1,2],[]) scopes render |
    throw (IO.userError "could not retain mandatory base metadata")
  check (base.problem.fixed == (45,45)) "base metadata escaped the constant reservation"
  check ((ScopedCosts.prepare? {old with fixed := (0,0)} ([],[]) ([1,2],[]) scopes render).isNone)
    "metadata debit saturated an insufficient fixed reserve"
  let conflict := fun scope : Scope => [⟨"same",scope.1.length,1⟩]
  check ((ScopedCosts.prepare? old ([],[]) ([1,2],[]) scopes conflict).isNone)
    "one metadata identity was accepted at conflicting prices"
  check ((ScopedCosts.prepare? old ([],[]) ([1,2],[]) #[] render).isNone)
    "missing contributor scopes silently changed offer accounting"
  let directory : ScopedCosts.Directory render := {}
  let (first,directory) := directory.get ([1],[])
  let (again,directory) := directory.get ([1],[])
  check (first == again && directory.table.size == 1) "full contributor scopes did not share one immutable rendering"
  IO.println "Lean scoped-cost checks passed: inactive owners free, selected metadata shared, full and base costs conserved, unchanged weights/limits, conflicts rejected"
