import Main
import Eggshell.ContractAudit
import tools.SharedCoverageInput
import tools.research.CoverageExchange
import tools.research.AvailableDelivery
open Lean Eggshell Eggshell.Research Eggshell.Synapses Eggshell.Synapses.CanonicalSource
#print axioms SharedCoverage.Exchange.strictly_better
#print axioms SharedCoverage.Exchange.keeps_limits
#print axioms SharedCoverage.Exchange.all_exchanges_bounded
namespace CoverageExchangeProbe
def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)
def read (path : String) : IO Json := IO.FS.readFile (.mk path) >>= (IO.ofExcept ∘ Json.parse)
def fixture (costs : Array (Nat × Nat)) (weights : Array Nat)
    (offers : Array SharedCoverage.Input.RawOffer) (limit : Nat × Nat) : IO Unit := do
  let p ← IO.ofExcept (SharedCoverage.Input.RawProblem.mk costs weights offers (0,0) limit).decode
  let some empty := SharedCoverage.empty? p | throw (IO.userError "fixture has no empty selection")
  let some first := (List.finRange p.offers.size)[0]? | throw (IO.userError "fixture first offer missing")
  let some second := (List.finRange p.offers.size)[1]? | throw (IO.userError "fixture second offer missing")
  let some one := SharedCoverage.extend? empty first | throw (IO.userError "fixture first offer does not fit")
  let some prior := SharedCoverage.extend? one second | throw (IO.userError "fixture second offer does not fit")
  let result := SharedCoverage.Exchange.search prior
  check (result.proposal.isSome == result.checked.isSome) "fast exchange failed independent certification"
  let value := (result.checked.map (fun choice => SharedCoverage.benefit p choice.result.selected)).getD
    (SharedCoverage.benefit p prior.selected)
  let mut expected := SharedCoverage.benefit p prior.selected
  for added in List.finRange p.offers.size do
    if prior.selected.contains added then continue
    for dropped in prior.selected do
      let next := prior.selected.filter (· != dropped)++[added]
      let charge := SharedCoverage.cost p next
      if charge.1 ≤ p.limit.1 && charge.2 ≤ p.limit.2 then expected := max expected (SharedCoverage.benefit p next)
  check (value == expected) "counted exchange differs from exhaustive original-objective evaluation"
  check ((SharedCoverage.Exchange.certify? prior value).isSome) "independent all-pairs upper certificate failed"
  if SharedCoverage.benefit p prior.selected < value then
    check ((SharedCoverage.Exchange.certify? prior (SharedCoverage.benefit p prior.selected)).isNone)
      "upper verifier accepted a false no-improvement claim"
def tests : IO Unit := do
  fixture #[(1,1),(1,1),(1,1)] #[1,1,10]
    #[⟨[0],[0]⟩,⟨[1],[1]⟩,⟨[2],[2]⟩] (2,2)
  fixture #[(10,10),(1,1),(1,1),(1,1)] #[2,2,9]
    #[⟨[0,0,1],[0]⟩,⟨[0,2],[1]⟩,⟨[0,3],[2]⟩] (12,12)
  fixture #[(1,1),(1,1),(1,1)] #[3,100,9]
    #[⟨[0],[0,1,1]⟩,⟨[1],[1]⟩,⟨[2],[1,2]⟩] (2,2)
  fixture #[(1,2),(1,2),(1,3)] #[1,2,10^100]
    #[⟨[0],[0]⟩,⟨[1],[1]⟩,⟨[2],[2]⟩] (2,4)
def run (diagnostic evidence output : String) : IO Unit := do
  check (!(← System.FilePath.pathExists output)) "preserve the fixed-objective exchange audit"
  tests
  let capture := (← read diagnostic).getObjValD "signals/diagnostic/selection.json"
  let raw : SharedCoverage.Input.RawProblem ← IO.ofExcept (capture.getObjValAs? _ "selectorInput")
  let p ← IO.ofExcept raw.decode
  let witness := capture.getObjValD "selectionWitness"
  let sourceNodes : Array (Nat × Key) ← IO.ofExcept (witness.getObjValAs? _ "sourceNodes")
  let actual : Array Nat ← IO.ofExcept (witness.getObjValAs? _ "selectedSourceNodes")
  let some baseline := SharedCoverage.OwnedAdvance.chooseOwned p | throw (IO.userError "captured problem has no selection")
  let selectedRows := fun indices => Id.run do
    let membership := Std.HashSet.ofList ((SharedCoverage.nodes p indices).map (·.val))
    return sourceNodes.filterMap fun (node,key) => if membership.contains node then some key else none
  let before := selectedRows baseline.selected
  let actualSet := Std.HashSet.ofArray actual
  let beforeIds := Std.HashSet.ofList ((SharedCoverage.nodes p baseline.selected).map (·.val))
  check (before.size == actualSet.size && actual.all beforeIds.contains) "baseline differs from actual source atoms"
  let started ← IO.monoMsNow
  let result ← IO.lazyPure fun _ => SharedCoverage.Exchange.search baseline
  let elapsed := (← IO.monoMsNow)-started
  check (result.proposal.isSome == result.checked.isSome) "best exchange failed independent full recomputation"
  let next := (result.checked.map (·.result.selected)).getD baseline.selected
  let after := selectedRows next
  let verifying ← IO.monoMsNow
  let certificate ← IO.lazyPure fun _ => SharedCoverage.Exchange.certify? baseline (SharedCoverage.benefit p next)
  let verificationMs := (← IO.monoMsNow)-verifying
  check certificate.isSome "independent all-pairs verification found a higher original-objective value"
  -- The labels are unavailable to the exhaustive objective search above.
  let frozen : AvailableDelivery.Frozen ← IO.ofExcept
    ((((← read evidence).getObjValD "llvm/before-delivery.json").getObjValD "topics").getArr? >>= fun topics =>
      (topics[0]?.getD Json.null).getObjValAs? _ "frozen")
  let ranges := fun (rows : Array Key) => rows.map fun key => (⟨.file key.file,key.line,key.line⟩ : Range)
  let proposal := result.proposal.map fun choice => Json.mkObj [("dropped",toJson choice.dropped.val),
    ("added",toJson choice.added.val),("cost",toJson choice.cost),("benefit",toJson (toString choice.value))]
  IO.FS.writeFile (.mk output) (Json.mkObj [("pairs",toJson result.pairs),("feasible",toJson result.feasible),
    ("exchangeMs",toJson elapsed),("certified",toJson result.checked.isSome),("proposal",toJson proposal),
    ("independentUpperBoundCertified",toJson certificate.isSome),("verificationMs",toJson verificationMs),
    ("pureEvaluationTimedInsideIO",toJson true),
    ("before",toJson (AvailableDelivery.assess frozen (ranges before))),
    ("after",toJson (AvailableDelivery.assess frozen (ranges after))),
    ("beforeCost",toJson (SharedCoverage.cost p baseline.selected)),("afterCost",toJson (SharedCoverage.cost p next)),
    ("beforeBenefit",toJson (toString (SharedCoverage.benefit p baseline.selected))),
    ("afterBenefit",toJson (toString (SharedCoverage.benefit p next))),
    ("baselineActualNodesReproduced",toJson true),("independentFixtureChecks",toJson (4 : Nat)),
    ("originalProblemUnchanged",toJson true),("labelsReadAfterSelection",toJson true),
    ("productChanged",toJson false),("queryOrModelCalled",toJson false),("adopted",toJson false)]).compress
end CoverageExchangeProbe
def main : List String → IO Unit
  | [diagnostic,evidence,output] => CoverageExchangeProbe.run diagnostic evidence output
  | _ => throw (IO.userError "CoverageExchangeProbe DIAGNOSTIC EVIDENCE OUTPUT")
