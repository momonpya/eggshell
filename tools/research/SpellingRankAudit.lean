import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson

open Lean

private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun body => IO.ofExcept (Json.parse body)

private def field [FromJson α] (value : Json) (name : String) : IO α :=
  IO.ofExcept (value.getObjValAs? α name)

def main (args : List String) : IO Unit := do
  let [baselinePath,candidatePath,output] := args |
    throw (IO.userError "BASELINE-SELECTION CANDIDATE-SELECTION NEW-OUTPUT")
  unless !(← System.FilePath.pathExists output) do throw (IO.userError "preserve prior audit")
  let baseline := (← read (.mk baselinePath)).getObjValD "data"
  let candidate := (← read (.mk candidatePath)).getObjValD "data"
  let oldRows : Array Json ← field baseline "rangeAudit"
  let newRows : Array Json ← field candidate "rangeAudit"
  let originalKeys := ["owner","work","workChars","canonicalRows","candidateUnits",
    "candidateOriginalRanges","candidateSharedRanges","candidateRanges","frameCost"]
  let domainSame := oldRows.size == newRows.size && oldRows.all fun prior =>
    newRows.any fun next => originalKeys.all fun key => prior.getObjValD key == next.getObjValD key
  let oldInput := baseline.getObjValD "selectorInput"
  let newInput := candidate.getObjValD "selectorInput"
  let oldOffers : Array Json ← field oldInput "offers"
  let newOffers : Array Json ← field newInput "offers"
  let rows := [
    ("candidateUnitDomainSame",toJson domainSame),
    ("bindingAuditSame",toJson (baseline.getObjValD "bindingAudit" == candidate.getObjValD "bindingAudit")),
    ("jointBindingsSame",toJson (baseline.getObjValD "jointBindings" == candidate.getObjValD "jointBindings")),
    ("fixedCostSame",toJson (oldInput.getObjValD "fixed" == newInput.getObjValD "fixed")),
    ("limitSame",toJson (oldInput.getObjValD "limit" == newInput.getObjValD "limit")),
    ("payloadCostsSame",toJson (oldInput.getObjValD "costs" == newInput.getObjValD "costs")),
    ("compiledClosuresSame",toJson (oldOffers.map (·.getObjValD "closure") == newOffers.map (·.getObjValD "closure"))),
    ("weightsSame",toJson (oldInput.getObjValD "weights" == newInput.getObjValD "weights")),
    ("selectedUnitsSame",toJson (baseline.getObjValD "selected" == candidate.getObjValD "selected")),
    ("baselineOffers",toJson oldOffers.size),("candidateOffers",toJson newOffers.size),
    ("candidateUnits",candidate.getObjValD "candidateUnits"),
    ("exactLeanJsonComparison",toJson true),("answeringModelCalls",toJson (0 : Nat)),
    ("productionAdoption",toJson false)]
  IO.FS.writeFile output (Json.mkObj rows).pretty
  IO.println (Json.mkObj rows).compress
