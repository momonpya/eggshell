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

private def originalDimensions (path owner : String) : IO (String × Nat × Nat × Json) := do
  let source ← Eggshell.DB.PageMap.pin (.mk path)
  let reader ← Eggshell.Persistence.Store.NodeReader.new source
  for entry in ← Eggshell.Synapses.Build.entries source do
    let document ← Eggshell.Synapses.Build.document reader entry.id
    if document.owner != owner then continue
    let some work := document.workText | throw (IO.userError "original Work bytes missing")
    let some output := document.source | throw (IO.userError "original output bytes missing")
    unless (← Eggshell.DB.PageMap.pin source.directory).head == source.head do
      throw (IO.userError "source publication changed during read-only explanation")
    return (document.work,work.length,output.length,toJson source.head)
  throw (IO.userError "owner absent from supplied source; absence is not zero relevance")

/-- Explain recorded decisions, without rerunning retrieval, changing source
state, reading an external workspace or passing an oracle to the product. -/
def main (args : List String) : IO Unit := do
  let (owner,receipts,destination,bounds,sourcePath) ← match args with
    | [owner,receipts,destination] => pure (owner,receipts,destination,none,none)
    | [owner,receipts,destination,first,limit] =>
        pure (owner,receipts,destination,some (first,limit),none)
    | [owner,receipts,destination,first,limit,source] =>
        pure (owner,receipts,destination,some (first,limit),some source)
    | _ => throw (IO.userError "DeliveryExplain OWNER RECEIPTS NEW-REPORT [FIRST LIMIT [SOURCE]]")
  let target ← bounds.mapM fun (first,limit) => do
        let some first := first.toNat? | throw (IO.userError "invalid original offset")
        let some limit := limit.toNat? | throw (IO.userError "invalid original limit")
        unless first < limit do throw (IO.userError "empty or reversed original range")
        pure (first,limit)
  unless !owner.isEmpty && !(← (System.FilePath.mk destination).pathExists) do
    throw (IO.userError "owner and a new report required")
  let dimensions ← sourcePath.mapM (originalDimensions · owner)
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
    let familyRow := family.bind fun index => families.bind (·[index]?)
    let hints ← dimensions.mapM fun (work,workChars,sourceChars,head) => do
      let some row := familyRow | throw (IO.userError "no original family to explain")
      unless (row.getObjValAs? String "work").toOption == some work do
        throw (IO.userError "source Work differs from recorded family")
      let windows ← IO.ofExcept (row.getObjValAs? (List Nat) "windows")
      let projected : List (Nat × Nat × Nat × Nat) := windows.zipIdx |>.filterMap fun (window,priority) =>
        (SourceWindow.project sourceChars (workChars+1) window).map fun span =>
          (window,priority,span.first,span.last)
      let touching := projected.filter fun (_,_,a,b) =>
        target.any fun (first,limit) => first < b && a < limit
      return Json.mkObj [("source",head),("workChars",toJson workChars),
        ("sourceChars",toJson sourceChars),("focusWindowsTouchingTarget",toJson touching),
        ("focusCoversTarget",toJson (target.map fun (first,limit) =>
          Eggshell.Plugin.SharedRangeAdapter.covers
            (projected.map fun (part : Nat × Nat × Nat × Nat) => (part.2.2.1,part.2.2.2)) first limit))]
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
      ("originalHintAudit",toJson hints),
      ("units",toJson units),("firstRecordedLoss",toJson firstLoss)])
  unless !output.isEmpty do throw (IO.userError "no traced request: absence is not a candidate miss")
  let report := Json.mkObj [("decisions",toJson output),("rankOrigin",toJson (0 : Nat)),
    ("answeringModelCalls",toJson (0 : Nat)),
    ("sourceWrites",toJson (0 : Nat)),("productionAdoption",toJson false)]
  IO.FS.writeFile (.mk destination) (report.pretty ++ "\n")
  for decision in output do
    IO.println (Json.mkObj ((#["receipt","owner","nominationRank","focusRank","hydrated",
      "unitCount","selectedUnitCount","originalChars","coveredByCandidateUnion",
      "coveredBySelectedUnion","candidateGaps","firstRecordedLoss","originalHintAudit"]).toList.map fun key =>
        (key,decision.getObjValD key))).compress
