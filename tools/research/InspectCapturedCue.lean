import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def read (p : System.FilePath) : IO Json := IO.FS.readFile p >>= fun s => IO.ofExcept (Json.parse s)

/- Inspect exact natural-number weights from a completed product plan.
No floating-point JSON conversion, re-ranking, solver call or product edit. -/
def main (args : List String) : IO Unit := do
  let [planPath,unitText,destination] := args | throw (IO.userError "captured plan, base unit id, fresh output")
  let some unit := unitText.toNat? | throw (IO.userError "invalid unit id")
  let output := System.FilePath.mk destination
  check (!(← output.pathExists)) "preserve previous cue inspection"
  let data := (← read (.mk planPath)).getObjValD "data"
  check (data.getObjValD "rangeAuditKind" == toJson "planned-original-positions") "not a product range plan"
  let problem := data.getObjValD "selectorInput"
  let weights : Array Nat ← IO.ofExcept (problem.getObjValAs? _ "weights")
  let costs : Array (Nat × Nat) ← IO.ofExcept (problem.getObjValAs? _ "costs")
  let offers : Array Json ← IO.ofExcept (problem.getObjValAs? _ "offers")
  let selected : Array Nat ← IO.ofExcept (data.getObjValAs? _ "selected")
  let some offer := offers[unit]? | throw (IO.userError "base unit outside captured problem")
  let covers : Array Nat ← IO.ofExcept (offer.getObjValAs? _ "covers")
  let targetNodes : Array Nat ← IO.ofExcept (offer.getObjValAs? _ "closure")
  let mut cues := #[]
  for cue in covers do
    check (cue % 2 == 0) "expected a base relevance cell"
    let some base := weights[cue]? | throw (IO.userError "missing base weight")
    let some graph := weights[cue+1]? | throw (IO.userError "missing graph increment weight")
    let mut recipes := #[]
    for index in [:offers.size] do
      let candidate := offers[index]!
      let cells : Array Nat ← IO.ofExcept (candidate.getObjValAs? _ "covers")
      unless cells.contains (cue+1) do continue
      let nodes : Array Nat ← IO.ofExcept (candidate.getObjValAs? _ "closure")
      let mut chars := 0
      let mut bytes := 0
      for node in nodes.toList.eraseDups do
        let some value := costs[node]? | throw (IO.userError "recipe node outside captured costs")
        chars := chars+value.1
        bytes := bytes+value.2
      recipes := recipes.push (Json.mkObj [("id",toJson index),("standaloneCost",toJson (chars,bytes)),
        ("samePhysicalNodesAsBaseUnit",toJson (nodes.all targetNodes.contains && targetNodes.all nodes.contains)),
        ("nodes",toJson nodes)])
    cues := cues.push (Json.mkObj [("baseCue",toJson cue),("baseWeight",toJson base),
      ("graphIncrementCue",toJson (cue+1)),("graphIncrementWeight",toJson graph),
      ("graphIncrementPositive",toJson (decide (0 < graph))),("incrementToBasePartsPerMillion",toJson (graph*1000000/(max 1 base))),
      ("graphRecipes",toJson recipes)])
  IO.FS.writeFile output (Json.mkObj [("baseUnit",toJson unit),("unitSelected",toJson (selected.contains unit)),
    ("baseUnitNodes",toJson targetNodes),("cues",toJson cues),
    ("exactNaturalNumberArithmetic",toJson true),("actualConditionedSelectionReplayed",toJson false),
    ("marginalCostClaimed",toJson false),("adopted",toJson false),("answeringModelCalls",toJson (0 : Nat))]).pretty
  IO.println s!"Inspected {cues.size} captured relevance cells without a solver or model call"
