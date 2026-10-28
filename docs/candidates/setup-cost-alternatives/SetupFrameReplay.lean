import tools.research.OriginalPayloadBasis
import tools.SetupAlternatives
import tools.SharedCoverageInput
import tools.VerifiedWinnerCoverage
import Lean.Data.Json.Parser
open Lean Eggshell Eggshell.Synapses Eggshell.Synapses.CanonicalSource

#print axioms SharedCoverage.SetupAlternatives.credit_has_paid_witness
#print axioms SharedCoverage.SetupAlternatives.keeps_original

private def read (path : String) : IO Json := IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def check (value : Bool) (reason : String) : IO Unit :=
  unless value do throw (IO.userError reason)

def main (args : List String) : IO Unit := do
  let [originalsPath,inputPath,expectedPath,inventoryPath,familyText,output] := args |
    throw (IO.userError "ORIGINALS SELECTOR EXPECTED INVENTORY FAMILIES NEW-OUTPUT")
  check (!(← System.FilePath.pathExists output)) "preserve prior setup replay"
  let some families := familyText.toNat? | throw (IO.userError "invalid family count")
  let rawRows : Array StoredRow ← IO.ofExcept ((← read originalsPath).getObjValAs? _ "canonicalRows")
  let rows ← IO.ofExcept (Delivery.merge rawRows)
  let raw ← IO.ofExcept (fromJson? (α := SharedCoverage.Input.RawProblem)
    (((← read inputPath).getObjValD "data").getObjValD "selectorInput"))
  let p ← IO.ofExcept raw.decode
  let some basis := Eggshell.Research.OriginalPayloadBasis.prepare families rows p |
    throw (IO.userError "original row/frame costs differ")
  let some baseline := SharedCoverage.choose? p | throw (IO.userError "baseline selector failed")
  let expected ← IO.ofExcept ((← read expectedPath).getArr?)
  check (toJson (baseline.selected.map Fin.val) == expected[1]!.getObjValD "selected" &&
    toJson (SharedCoverage.cost p baseline.selected) == expected[1]!.getObjValD "cost")
    "baseline differs from actual recorded selection"
  let start ← IO.monoMsNow
  let files := (basis.sourceRows.map fun (row,_) => row.key.file).toList.eraseDups
  let free := (List.finRange p.costs.size).filter fun atom => p.costs[atom] == (0,0)
  let mut groups := #[]
  let mut reports := #[]
  for file in files do
    let body := basis.sourceRows.filter fun (row,_) => row.key.file == file
    let some (_,first) := body[0]? | throw (IO.userError "empty file group")
    let frame := first.val-1
    if bound : frame < p.costs.size then
      let closure := hashDistinct (free ++ (⟨frame,bound⟩ :: body.toList.map Prod.snd))
      let charge := closure.foldl (fun total atom =>
        (total.1+p.costs[atom].1,total.2+p.costs[atom].2)) p.fixed
      if charge.1 ≤ p.limit.1 && charge.2 ≤ p.limit.2 then
        groups := groups.push closure
        reports := reports.push (Json.mkObj [("file",toJson file),("observedRows",toJson body.size),
          ("standaloneCost",toJson charge)])
    else throw (IO.userError "missing file frame")
  let candidate := SharedCoverage.SetupAlternatives.compile p groups
  let construction := (← IO.monoMsNow)-start
  let chosenAt ← IO.monoMsNow
  let forced ← IO.mkRef (SharedCoverage.choose? candidate)
  let some chosen ← forced.get | throw (IO.userError "setup candidate failed")
  let selectionMs := (← IO.monoMsNow)-chosenAt
  let baseNodes := Std.HashSet.ofList (SharedCoverage.nodes p baseline.selected)
  let newNodes := Std.HashSet.ofList (SharedCoverage.nodes candidate chosen.selected)
  let references ← IO.ofExcept ((((← read inventoryPath).getObjValD "source").getObjValD "required").getArr?)
  let mut comparisons := #[]
  for reference in references do
    let path ← IO.ofExcept (reference.getObjValAs? String "path")
    let first ← IO.ofExcept (reference.getObjValAs? Nat "first")
    let last ← IO.ofExcept (reference.getObjValAs? Nat "last")
    let wanted := basis.sourceRows.filter fun (row,_) =>
      row.key.file.relative == path && first ≤ row.key.line && row.key.line ≤ last
    comparisons := comparisons.push (Json.mkObj [("target",reference),("indexedRows",toJson wanted.size),
      ("baselineRows",toJson (wanted.filter fun (_,atom) => baseNodes.contains atom).size),
      ("candidateRows",toJson (wanted.filter fun (_,atom) => newNodes.contains atom).size)])
  IO.FS.writeFile output (Json.mkObj [("sourceCostsChecked",toJson true),("baselineSelectionMatches",toJson true),
    ("groups",toJson reports),("constructionMs",toJson construction),("selectionMs",toJson selectionMs),
    ("baselineCost",toJson (SharedCoverage.cost p baseline.selected)),
    ("candidateCost",toJson (SharedCoverage.cost candidate chosen.selected)),("comparisons",toJson comparisons),
    ("chosenOffers",toJson (chosen.selected.map Fin.val)),("actualDeliveryAsserted",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("productionAdoption",toJson false)]).pretty
  IO.println (Json.mkObj [("groups",toJson groups.size),("constructionMs",toJson construction),
    ("selectionMs",toJson selectionMs),("candidateCost",toJson (SharedCoverage.cost candidate chosen.selected))]).compress
