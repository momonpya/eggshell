import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

namespace SelectorSignalAudit
def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)
def load (path : String) : IO Json := IO.FS.readFile (.mk path) >>= (IO.ofExcept ∘ Json.parse)
def field [FromJson α] (value : Json) (name : String) : IO α :=
  IO.ofExcept (value.getObjValAs? α name)
structure Counts where
  base : Nat := 0
  graph : Nat := 0
  both : Nat := 0
def run (input output : String) : IO Unit := do
  check (!(← System.FilePath.pathExists output)) "preserve selector-signal audit"
  let captured ← load input
  let problem := captured.getObjValD "selectorInput"
  let witness := captured.getObjValD "selectionWitness"
  let weights : Array Nat ← field problem "weights"
  let offers : Array Json ← field problem "offers"
  let pieces : Array (Array Json) ← field witness "pieces"
  let units : Array Json ← field witness "units"
  let nodes : Array (Nat × Json) ← field witness "sourceNodes"
  let chosenNodes : Array Nat ← field witness "selectedSourceNodes"
  let selected := Std.HashSet.ofArray chosenNodes
  let bundles : Nat ← field (captured.getObjValD "jointBindings") "preparedBundles"
  check (units.size+bundles ≤ offers.size && weights.size%2 == 0) "invalid captured input dimensions"
  let mut counts : Std.HashMap Nat Counts := {}
  let mut positiveBase := 0
  let mut positiveGraph := 0
  let mut graphOnly := 0
  let mut direct : Std.HashMap Nat (Nat × Nat × Nat) := {}
  for piece in pieces do
    let base ← IO.ofExcept (fromJson? (α := Nat) (piece[3]?.getD Json.null))
    let total ← IO.ofExcept (fromJson? (α := Nat) (piece[4]?.getD Json.null))
    check (base ≤ total) "captured total weight is below its base"
    if base > 0 then positiveBase := positiveBase+1
    if total > base then positiveGraph := positiveGraph+1
    if total > 0 && base == 0 then graphOnly := graphOnly+1
    if let some id := (fromJson? (α := Nat) (piece[5]?.getD Json.null)).toOption then
      let prior := direct[id]?.getD (0,0,0)
      direct := direct.insert id (max prior.1 base,max prior.2.1 total,prior.2.2+1)
  let mut bundlePositiveGraph := 0
  let mut bundleWithoutPositiveGraph := 0
  for (offer,index) in offers.zipIdx do
    let covers : Array Nat ← field offer "covers"
    let closure : Array Nat ← field offer "closure"
    let base := covers.any (fun cue => cue%2 == 0 && (weights[cue]?.getD 0) > 0)
    let graph := covers.any (fun cue => cue%2 == 1 && (weights[cue]?.getD 0) > 0)
    for cue in covers do check (cue < weights.size) "captured offer names a missing cue"
    if units.size ≤ index && index < units.size+bundles then
      if graph then bundlePositiveGraph := bundlePositiveGraph+1
      else bundleWithoutPositiveGraph := bundleWithoutPositiveGraph+1
    for atom in closure do
      let prior := counts[atom]?.getD {}
      counts := counts.insert atom ⟨prior.base+(if base then 1 else 0),
        prior.graph+(if graph then 1 else 0),prior.both+(if base && graph then 1 else 0)⟩
  let reports := nodes.map fun (id,key) =>
    let count := counts[id]?.getD {}
    let hint := direct[id]?.getD (0,0,0)
    Json.mkObj [("node",toJson id),("key",key),("selected",toJson (selected.contains id)),
      ("baseOffers",toJson count.base),("graphOffers",toJson count.graph),("bothOffers",toJson count.both),
      ("directPieces",toJson hint.2.2),("hasDirectGraphBonus",toJson (decide (hint.1 < hint.2.1))),
      ("directBaseWeight",toJson (toString hint.1)),("directTotalWeight",toJson (toString hint.2.1))]
  let positiveOdd := weights.zipIdx.countP (fun (value,index) => index%2 == 1 && value > 0)
  IO.FS.writeFile (.mk output) (Json.mkObj [
    ("input",toJson input),("pieces",toJson pieces.size),("positiveBasePieces",toJson positiveBase),
    ("graphRaisesPieces",toJson positiveGraph),("graphOnlyPieces",toJson graphOnly),
    ("distinctGraphBonuses",toJson positiveOdd),("publishedUnits",toJson units.size),
    ("preparedBundles",toJson bundles),("bundlesWithPositiveGraphBonus",toJson bundlePositiveGraph),
    ("bundlesWithoutPositiveGraphBonus",toJson bundleWithoutPositiveGraph),("nodes",toJson reports),
    ("queryOrModelCalled",toJson false),("productChanged",toJson false),("adopted",toJson false)]).compress
end SelectorSignalAudit
def main : List String → IO Unit
  | [input,output] => SelectorSignalAudit.run input output
  | _ => throw (IO.userError "SelectorSignalAudit SELECTION OUTPUT")
