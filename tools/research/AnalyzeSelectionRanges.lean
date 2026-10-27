import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
import Std.Data.HashMap
open Lean

private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

private def rows (value : Json) (field : String) : IO (Array Json) :=
  IO.ofExcept (value.getObjValAs? (Array Json) field)

private def covers (ranges : Json) (first limit : Nat) : IO Bool := do
  let spans ← IO.ofExcept (fromJson? (α := Array (Nat × Nat)) ranges)
  unless spans.all (fun (a,b) => a < b) do throw (IO.userError "invalid planned interval")
  return spans.any fun (a,b) => a ≤ first && limit ≤ b

private def unionCovers (ranges : Array (Nat × Nat)) (first limit : Nat) : Bool :=
  let ordered := ranges.qsort fun left right => if left.1 == right.1 then left.2 < right.2 else left.1 < right.1
  limit ≤ ordered.foldl (fun frontier (a,b) => if a ≤ frontier then max frontier b else frontier) first

/-- Independent, model-free explanation. Frozen bindings supply the probes;
the runtime's selector has never seen those probes or expected answers. -/
def main (args : List String) : IO Unit := do
  let [trialPath,outputPath] := args | throw (IO.userError "trial and new output file required")
  let trial := System.FilePath.mk trialPath
  let output := System.FilePath.mk outputPath
  unless !(← output.pathExists) do throw (IO.userError "preserve prior origin explanation")
  let frozen ← read (trial / "frozen-before-delivery.json")
  let audit ← read (trial / "audit.json")
  let result ← read (trial / "result.json")
  unless (audit.getObjValAs? Bool "sameSourceFacts").toOption == some true &&
      (audit.getObjValAs? Bool "samePublishedPagePrefix").toOption == some true do
    throw (IO.userError "source facts or original publication changed")
  let actual ← rows audit "requirements"
  let mut families := #[]
  let mut bindingAudit := #[]
  for entry in ← (trial / "data/receipts").readDir do
    let path := entry.path / "selection-plan.json"
    if !(← path.pathExists) then continue
    let data := (← read path).getObjValD "data"
    unless (data.getObjValAs? Bool "assertsActualDelivery").toOption == some false do
      throw (IO.userError "planned ranges were confused with delivered bytes")
    families := families ++ (← rows data "rangeAudit")
    bindingAudit := bindingAudit ++ (data.getObjValAs? (Array Json) "bindingAudit").toOption.getD #[]
  unless !families.isEmpty do throw (IO.userError "actual selector did not capture range audit")
  let mut requirements := #[]
  for required in ← rows frozen "requirements" do
    let name ← IO.ofExcept ((required.getObjValD "reference").getObjValAs? String "name")
    let stored ← IO.ofExcept (required.getObjValAs? Bool "storedOriginal")
    let some observed := actual.find? (fun row => row.getObjValD "name" == toJson name) |
      throw (IO.userError "actual body audit lacks frozen requirement")
    let delivered ← IO.ofExcept (observed.getObjValAs? Bool "bodyDelivered")
    let mut grouped : Std.HashMap (String × String) (List (Nat × Nat)) := {}
    for original in ← rows required "originalRows" do
      let binding := original.getObjValD "binding"
      let owner ← IO.ofExcept (binding.getObjValAs? String "owner")
      let work ← IO.ofExcept (binding.getObjValAs? String "work")
      let first ← IO.ofExcept (binding.getObjValAs? Nat "first")
      let limit ← IO.ofExcept (binding.getObjValAs? Nat "limit")
      unless first < limit do throw (IO.userError "invalid frozen original binding")
      grouped := grouped.insert (owner,work) ((first,limit) :: grouped[(owner,work)]?.getD [])
    let mut origins := #[]
    for ((owner,work),spans) in grouped.toArray do
      let matching := families.filter fun family =>
        family.getObjValD "owner" == toJson owner && family.getObjValD "work" == toJson work
      let complete := fun field => spans.allM fun (first,limit) => do
        matching.anyM fun family => covers (family.getObjValD field) first limit
      let candidates ← complete "candidateRanges"
      let selected ← complete "selectedRanges"
      let hints := bindingAudit.filter fun hint =>
        let identity := (((hint.getObjValD "source").getObjValD "subject").getObjValD "original").getObjValD "original"
        ((hint.getObjValAs? (Array String) "owners").toOption.getD #[]).contains owner &&
          identity.getObjValD "work" == toJson work
      let ranges ← hints.mapM fun hint => do
        let source := hint.getObjValD "source"
        let first ← IO.ofExcept (source.getObjValAs? Nat "first")
        let last ← IO.ofExcept (source.getObjValAs? Nat "last")
        unless 0 < first && first ≤ last do throw (IO.userError "invalid graph source span")
        let alternatives ← rows hint "alternatives"
        return (first-1,last,alternatives.size)
      let overlap := ranges.filter fun (a,b,_) => spans.any fun (first,last) => a < last && first < b
      let located := ranges.filter (fun (_,_,count) => 0 < count)
      let signal := Json.mkObj [("available",toJson (!bindingAudit.isEmpty)),("hints",toJson hints.size),
        ("overlapping",toJson overlap),("locatedHints",toJson located.size),
        ("coversFrozenSpans",toJson (spans.all fun (a,b) => unionCovers (ranges.map fun (a,b,_) => (a,b)) a b)),
        ("locatedCoversFrozenSpans",toJson (spans.all fun (a,b) => unionCovers (located.map fun (a,b,_) => (a,b)) a b))]
      origins := origins.push (Json.mkObj [
        ("owner",toJson owner),("work",toJson work),("frozenSpans",toJson spans.reverse),
        ("inDomain",toJson (!matching.isEmpty)),("candidateCoversFrozenSpans",toJson candidates),
        ("selectedCoversFrozenSpans",toJson selected),("families",toJson matching),("synaptic",signal)])
    let any := fun field => origins.any fun row => (row.getObjValAs? Bool field).toOption == some true
    let stage := if delivered then "delivered" else if !stored then "not-present-in-frozen-source"
      else if origins.isEmpty then "missing-frozen-binding"
      else if !any "inDomain" then "domain"
      else if !any "candidateCoversFrozenSpans" then "candidate-ranges"
      else if !any "selectedCoversFrozenSpans" then "selection" else "render-or-body-check"
    requirements := requirements.push (Json.mkObj [
      ("name",toJson name),("storedOriginal",toJson stored),("bodyDelivered",toJson delivered),
      ("firstMissingStage",toJson stage),("origins",toJson origins)])
  IO.FS.createDirAll output.parent.get!
  IO.FS.writeFile output (Json.mkObj [
    ("criterion",toJson "all frozen read spans for at least one saved owner"),
    ("requirements",toJson requirements),("requiredDelivery",result.getObjValD "requiredDelivery"),
    ("runtimeSha256",result.getObjValD "runtimeSha256"),("actualHook",toJson true),
    ("diagnosticRangesAreNotDelivery",toJson true),("modelCalls",toJson (0 : Nat))]).pretty
  let missing := requirements.filter fun row => row.getObjValD "storedOriginal" == toJson true &&
    row.getObjValD "bodyDelivered" == toJson false
  let summary ← missing.mapM fun row => do
    let owners ← (← rows row "origins").mapM fun origin => do
      let prices := (← rows origin "families").map fun family => Json.mkObj
        (["id","owner","work","canonicalRows","frameCost","workChars","positiveBaseOffers",
          "minimumPositiveStandalone","candidateUnits","selectedUnits"].map fun name =>
          (name,family.getObjValD name))
      return Json.mkObj [("frozenSpans",origin.getObjValD "frozenSpans"),
        ("candidateCoversFrozenSpans",origin.getObjValD "candidateCoversFrozenSpans"),
        ("selectedCoversFrozenSpans",origin.getObjValD "selectedCoversFrozenSpans"),
        ("synaptic",origin.getObjValD "synaptic"),("prices",toJson prices)]
    return Json.mkObj [("name",row.getObjValD "name"),("firstMissingStage",row.getObjValD "firstMissingStage"),
      ("origins",toJson owners)]
  let compact := Json.mkObj [("requiredDelivery",result.getObjValD "requiredDelivery"),("missing",toJson summary)]
  IO.FS.writeFile (output.withExtension "summary.json") compact.pretty
  IO.println compact.compress
