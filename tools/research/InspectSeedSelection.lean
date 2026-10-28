import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson

open Lean

private def read (path : String) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

private def rows (value : Json) (name : String) : IO (Array Json) :=
  IO.ofExcept (value.getObjValAs? (Array Json) name)

private def covered (value : Json) (first limit : Nat) : IO Bool := do
  let spans ← IO.ofExcept (fromJson? (α := Array (Nat × Nat)) value)
  let ordered := spans.qsort fun a b => if a.1 == b.1 then a.2 < b.2 else a.1 < b.1
  return limit ≤ ordered.foldl (fun frontier (a,b) =>
    if a ≤ frontier then max frontier b else frontier) first

/-- Join frozen original probes to an already executed plan. These probes
are never passed to the product or used to rerun its selection. -/
def main (args : List String) : IO Unit := do
  let [actualPath,priorPath,receiptPath,priorReceiptPath,output] := args |
    throw (IO.userError "ACTUAL-AUDIT PRIOR-AUDIT TRACE-RECEIPT PRIOR-RECEIPT NEW-OUTPUT")
  unless !(← System.FilePath.pathExists output) do throw (IO.userError "preserve earlier diagnosis")
  let actual ← read actualPath
  let prior ← read priorPath
  let plan := (← read receiptPath).getObjValD "data"
  let previous := (← read priorReceiptPath).getObjValD "data"
  unless actual.getObjValD "frozenEvidence" == prior.getObjValD "frozenEvidence" &&
      actual.getObjValD "sameSourceFacts" == toJson true &&
      actual.getObjValD "samePublishedPagePrefix" == toJson true do
    throw (IO.userError "the frozen original evidence changed")
  for name in ["families","candidateUnits","fixedCost","limit","scale","selected"] do
    unless plan.getObjValD name == previous.getObjValD name do
      throw (IO.userError s!"diagnostics changed the selection: {name}")
  let families ← rows plan "rangeAudit"
  let bindings ← rows actual "originalOutputBindings"
  let mut missing := #[]
  for required in ← rows actual "requirements" do
    if required.getObjValD "bodyDelivered" == toJson true then continue
    let name := required.getObjValD "name"
    let mut origins := #[]
    for row in bindings.filter (fun row => row.getObjValD "name" == name) do
      let binding := (row.getObjValD "read").getObjValD "binding"
      let first ← IO.ofExcept (binding.getObjValAs? Nat "first")
      let limit ← IO.ofExcept (binding.getObjValAs? Nat "limit")
      let matched := families.filter fun family =>
        family.getObjValD "owner" == binding.getObjValD "owner" &&
        family.getObjValD "work" == binding.getObjValD "work"
      let inspected ← matched.mapM fun family => do
        let candidate ← covered (family.getObjValD "candidateRanges") first limit
        let selected ← covered (family.getObjValD "selectedRanges") first limit
        return Json.mkObj ((["id","owner","work","candidateUnits","selectedUnits",
          "positiveBaseOffers","minimumPositiveStandalone","canonicalRows",
          "candidateRanges","selectedRanges"].map fun field =>
            (field,family.getObjValD field)) ++ [
          ("candidateCoversFrozenSpan",toJson candidate),("selectedCoversFrozenSpan",toJson selected)])
      origins := origins.push (Json.mkObj [("first",toJson first),("limit",toJson limit),
        ("families",toJson inspected)])
    missing := missing.push (Json.mkObj [("name",name),("origins",toJson origins)])
  let report := Json.mkObj [("missing",toJson missing),
    ("requiredDelivery",actual.getObjValD "requiredDelivery"),
    ("bodySha256",actual.getObjValD "bodySha256"),
    ("sameSelectionAsUntracedHook",toJson true),
    ("sameBodySha256",toJson (actual.getObjValD "bodySha256" == prior.getObjValD "bodySha256")),
    ("frozenEvidenceUnchanged",toJson true),("actualReceipt",toJson receiptPath),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]
  IO.FS.writeFile output report.pretty
  IO.println (Json.mkObj [("missing",toJson (missing.map (·.getObjValD "name"))),
    ("sameSelectionAsUntracedHook",report.getObjValD "sameSelectionAsUntracedHook"),
    ("sameBodySha256",report.getObjValD "sameBodySha256"),("report",toJson output)]).compress
