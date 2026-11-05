import tools.SharedCoverageInput
import tools.research.SelectionReceipt
import Eggshell.Value
open Lean Eggshell
namespace Eggshell.Research.FrameReserveAudit
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def array (value : Json) (key : String) : IO (Array Json) := IO.ofExcept (value.getObjValAs? (Array Json) key)
def observed (root : System.FilePath) (index : Nat) : IO (System.FilePath × Json) := do
  let expected := toJson s!"selection-{index}"
  let mut found := #[]
  for entry in ← (root/"private/receipts").readDir do
    unless ← (entry.path/"request.json").pathExists do continue
    let request := (← read (entry.path/"request.json")).getObjValD "data"
    if request.getObjValD "session" == expected then found := found.push entry.path
  check (found.size == 1) "selection receipt is missing or ambiguous"
  let some directory := found[0]? | throw (IO.userError "selection receipt missing")
  return (directory,← Receipt.readSelection directory)
def targetWork (index : Nat) : String :=
  let label := s!"case-{index}"
  let input := (Json.mkObj [("case",toJson label),("uri",toJson s!"mcp://support/{label}")]).compress
  "v"++toString (hash (Value.text ("mcp__fixture__inspect\n"++input))).toNat
def coverage (data : Json) (selection : SharedCoverage.Selection p) (family : Nat) : IO Json := do
  let units ← array (data.getObjValD "selectionWitness") "units"
  let chosen := selection.selected.map (·.val)
  let mut ranges : Array (Nat × Nat) := #[]
  let mut unitIds := #[]
  for index in chosen do
    let some unit := units[index]? | throw (IO.userError "selected unit missing")
    let columns ← IO.ofExcept unit.getArr?
    let some owner := columns[0]? | throw (IO.userError "unit family missing")
    if owner == toJson family then
      let some encoded := columns[1]? | throw (IO.userError "unit ranges missing")
      let intervals : Array (Nat × Nat) ← IO.ofExcept (fromJson? encoded)
      ranges := ranges++intervals
      unitIds := unitIds.push index
  let complete := (List.range 5000).all fun position => ranges.any fun (a,b) => a ≤ position && position < b
  return Json.mkObj [("selectedUnits",toJson unitIds),("selectedRanges",toJson ranges),
    ("complete5000ByteOriginal",toJson complete),("cost",toJson (SharedCoverage.cost p selection.selected))]
def run (captured output : System.FilePath) : IO Unit := do
  check (!(← output.pathExists)) "preserve earlier fixed-cost replay"
  IO.FS.createDirAll output
  check (targetWork 0 == "v8530199115547176781") "canonical Work identity differs from frozen evidence"
  let mut reports := #[]
  for index in [0,28] do
    let (directory,data) ← observed captured index
    let raw : SharedCoverage.Input.RawProblem ← IO.ofExcept (fromJson? (data.getObjValD "selectorInput"))
    let problem ← IO.ofExcept raw.decode
    let some baseline := SharedCoverage.choose? problem | throw (IO.userError "original problem rejected")
    let expected : List Nat ← IO.ofExcept ((data.getObjValD "selectionWitness").getObjValAs? (List Nat) "compiledSelected")
    check (baseline.selected.map (·.val) == expected) "independent selector replay differs from actual choice"
    let families ← array data "rangeAudit"
    let some target := families.find? (fun row => row.getObjValD "work" == toJson (targetWork index)) |
      throw (IO.userError "canonical target Work has no original candidate family")
    let family ← IO.ofExcept (target.getObjValAs? Nat "id")
    let optimistic := {raw with fixed := (0,0)}
    let free ← IO.ofExcept optimistic.decode
    let some chosen := SharedCoverage.choose? free | throw (IO.userError "zero fixed-cost replay rejected")
    reports := reports.push (Json.mkObj [("case",toJson index),("receipt",toJson directory.fileName),
      ("canonicalWork",toJson (targetWork index)),("originalFamily",target),
      ("originalFixedCost",toJson raw.fixed),("originalReplayExact",toJson true),
      ("baseline",← coverage data baseline family),("zeroFixed",← coverage data chosen family),
      ("counterfactualIsDeployable",toJson false)])
  IO.FS.writeFile (output/"report.json") (Json.mkObj [("cases",toJson reports),
    ("productChanged",toJson false),("answeringModelCalls",toJson (0 : Nat)),
    ("zeroFixedDoesNotBoundRenderedPacket",toJson true),("adopted",toJson false)]).pretty
end Eggshell.Research.FrameReserveAudit
def main (args : List String) : IO Unit := do
  let [captured,output] := args | throw (IO.userError "captured selection and fresh output required")
  Eggshell.Research.FrameReserveAudit.run (.mk captured) (.mk output)
