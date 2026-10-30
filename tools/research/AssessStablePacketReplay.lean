import Eggshell.SynapseUsage
import Lean.Data.Json.Parser
open Lean Eggshell.Synapses

private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

/- Post-hoc assessment only. The fixed requirements are never read by the
residual selector. The native replay separately checked every row and origin
against the immutable original basis; this assessor decodes the rendered file
frames instead of treating nominated positions as delivered source data. -/
private def assess (units : Array Json) (body : String) : IO Json := do
  let shown := Extraction.sharedSpellings body
  let mut missing := #[]
  for unit in units do
    let alternatives : Array (Array Range) ← IO.ofExcept (unit.getObjValAs? _ "alternatives")
    let accepted := alternatives.any fun parts => !parts.isEmpty && parts.all fun part =>
      match part.file? with
      | none => false
      | some file => (List.range (part.last+1-part.first)).all fun offset =>
          shown.any fun row => row.file == file && row.number == part.first+offset && !row.origins.isEmpty
    unless accepted do missing := missing.push (unit.getObjValD "names")
  return Json.mkObj [("eligible",toJson units.size),("delivered",toJson (units.size-missing.size)),
    ("missing",toJson missing)]

def main (args : List String) : IO Unit := do
  let [output] := args | throw (IO.userError "fresh assessment output required")
  let path : System.FilePath := .mk output
  unless !(← path.pathExists) do throw (IO.userError "keep previous assessment")
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot/stable-packet-replay-out"
  let resumed := project / "docs/candidates/prepared-bindings/resumed"
  let frozen ← IO.ofExcept ((← read (resumed / "trial/frozen-before-delivery.json")).getArr?)
  let some topic := frozen[0]? | throw (IO.userError "missing frozen topic")
  unless topic.getObjValD "topic" == toJson (1 : Nat) do throw (IO.userError "frozen topic order changed")
  let units : Array Json ← IO.ofExcept ((topic.getObjValD "available").getObjValAs? _ "units")
  let original ← IO.FS.readFile (resumed / "trial/baseline/rep-0/topic-1/body.txt")
  let counterfactual ← IO.FS.readFile (root / "counterfactual-body.txt")
  let result ← read (root / "result.json")
  unless result.getObjValD "actualHookDelivery" == toJson false &&
      result.getObjValD "allAcceptedRowsAndOriginsRetained" == toJson true &&
      result.getObjValD "allProvenanceFramesUnchanged" == toJson true do
    throw (IO.userError "counterfactual original-body verification missing")
  let before ← assess units original
  let after ← assess units counterfactual
  IO.FS.writeFile path (Json.mkObj [("counterfactualOnly",toJson true),
    ("assessment",toJson "frozen file alternatives decoded from verified rendered packets"),
    ("topic",toJson (1 : Nat)),("baseline",before),("candidate",after),
    ("requiredPartialRangeRetainedInDenominator",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("newActualHookCalls",toJson (0 : Nat)),
    ("adopted",toJson false)]).pretty
