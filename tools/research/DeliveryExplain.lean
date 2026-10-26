import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
import Eggshell.Handoff
open Lean

private def read (path : System.FilePath) : IO Json := do
  IO.ofExcept (Json.parse (← IO.FS.readFile path))
private def rank (value : Json) (owner : String) : Option Nat := do
  let rows ← value.getArr?.toOption
  rows.findIdx? (fun row => row.getStr?.toOption == some owner)
private def pairsValue (value : Json) (owner : String) : Option Json := do
  let rows ← value.getArr?.toOption
  let pair ← rows.find? fun row =>
    (row.getArr?.toOption.bind (·[0]?)).bind (fun value => value.getStr?.toOption) == some owner
  (pair.getArr?.toOption).bind (·[1]?)

/-- Explain recorded decisions, without rerunning retrieval, changing source
state, reading an external workspace or passing an oracle to the product. -/
def main (args : List String) : IO Unit := do
  let (owner,receipts,destination,target) ← match args with
    | [owner,receipts,destination] => pure (owner,receipts,destination,none)
    | [owner,receipts,destination,first,limit] =>
        let some first := first.toNat? | throw (IO.userError "invalid original offset")
        let some limit := limit.toNat? | throw (IO.userError "invalid original limit")
        unless first < limit do throw (IO.userError "empty or reversed original range")
        pure (owner,receipts,destination,some (first,limit))
    | _ => throw (IO.userError "DeliveryExplain OWNER RECEIPTS NEW-REPORT [FIRST LIMIT]")
  unless !owner.isEmpty && !(← (System.FilePath.mk destination).pathExists) do
    throw (IO.userError "owner and a new report required")
  let mut output := #[]
  for entry in ← (System.FilePath.mk receipts).readDir do
    let domainPath := entry.path / "delivery-domain.json"
    let planPath := entry.path / "selection-plan.json"
    if !(← domainPath.pathExists) || !(← planPath.pathExists) then continue
    let domain := (← read domainPath).getObjValD "data"
    let plan := (← read planPath).getObjValD "data"
    let hydrated ← IO.ofExcept (domain.getObjValAs? (Array String) "hydrated")
    let families := (plan.getObjValAs? (Array Json) "families").toOption
    let family := families.bind fun rows => rows.findIdx? fun row =>
      (row.getObjValAs? String "owner").toOption == some owner
    let units := ((plan.getObjValAs? (Array Json) "units").toOption.getD #[]).filter fun row =>
      (row.getObjValAs? Nat "family").toOption == family
    let selected := units.filter fun row => (row.getObjValAs? Bool "selected").toOption == some true
    let ranges ← units.mapM fun row => IO.ofExcept (row.getObjValAs? (List (Nat × Nat)) "ranges")
    let selectedRanges ← selected.mapM fun row => IO.ofExcept (row.getObjValAs? (List (Nat × Nat)) "ranges")
    let inCandidates := target.map fun (first,limit) =>
      Eggshell.Plugin.SharedRangeAdapter.covers ranges.toList.flatten first limit
    let inSelected := target.map fun (first,limit) =>
      Eggshell.Plugin.SharedRangeAdapter.covers selectedRanges.toList.flatten first limit
    let candidateGaps := target.map fun (first,limit) =>
      if ordered : first < limit then
        let parts := ranges.toList.flatten.filterMap fun (a,b) =>
          if h : a < b then some (⟨a,b,h⟩ : Eggshell.Plugin.DeliveryInterval) else none
        ((⟨first,limit,ordered⟩ : Eggshell.Plugin.DeliveryInterval).subtractAll parts).map
          (fun (part : Eggshell.Plugin.DeliveryInterval) => (part.start,part.stop))
      else []
    let completeUnits := units.zip ranges |>.filter fun (_,parts) => target.any fun (first,limit) =>
      Eggshell.Plugin.SharedRangeAdapter.covers parts first limit
    let firstLoss := if !hydrated.contains owner then "before-hydration" else
      if families.isNone then "plan-not-recorded-or-rejected" else
      if family.isNone then "before-selector-family" else
      if units.isEmpty then "before-selector-unit" else
      if inCandidates == some false then "candidate-range-domain" else
      if inSelected == some false then "selector" else
      if selected.isEmpty then "selector" else "after-selection-or-partial-range"
    output := output.push (Json.mkObj [
      ("receipt",toJson entry.fileName),("owner",toJson owner),
      ("nominationRank",toJson (rank (domain.getObjValD "nominated") owner)),
      ("focusRank",toJson (rank (domain.getObjValD "focusRanking") owner)),
      ("semanticScore",Json.null),("scoreStatus",toJson "not-recorded"),
      ("hydrated",toJson (hydrated.contains owner)),
      ("focusPositions",toJson (pairsValue (domain.getObjValD "focusPositions") owner)),
      ("canonicalUsedRows",toJson (pairsValue (domain.getObjValD "canonicalUsed") owner)),
      ("family",toJson (family.bind fun index => families.bind (·[index]?))),
      ("unitCount",toJson units.size),("selectedUnitCount",toJson selected.size),
      ("originalChars",toJson target),("coveredByCandidateUnion",toJson inCandidates),
      ("coveredBySelectedUnion",toJson inSelected),
      ("candidateGaps",toJson candidateGaps),
      ("completeUnitChoices",toJson (completeUnits.map fun (unit,_) => unit)),
      ("units",toJson units),("firstRecordedLoss",toJson firstLoss)])
  unless !output.isEmpty do throw (IO.userError "no traced request: absence is not a candidate miss")
  let report := Json.mkObj [("decisions",toJson output),("rankOrigin",toJson (0 : Nat)),
    ("answeringModelCalls",toJson (0 : Nat)),
    ("sourceWrites",toJson (0 : Nat)),("productionAdoption",toJson false)]
  IO.FS.writeFile (.mk destination) (report.pretty ++ "\n")
  for decision in output do
    IO.println (Json.mkObj ((#["receipt","owner","nominationRank","focusRank","hydrated",
      "unitCount","selectedUnitCount","originalChars","coveredByCandidateUnion",
      "coveredBySelectedUnion","candidateGaps","firstRecordedLoss"]).toList.map fun key =>
        (key,decision.getObjValD key))).compress
