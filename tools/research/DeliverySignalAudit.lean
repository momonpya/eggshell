import tools.research.RequiredDelivery
import Eggshell.SynapseRecommend
open Lean Eggshell.Synapses Eggshell.Research

private def read (path : System.FilePath) : IO Json := do
  IO.ofExcept (Json.parse (← IO.FS.readFile path))

/-- Retrospective evidence only. The frozen requirements never enter a
product query, graph update, producer nomination or packet selector. -/
def main (args : List String) : IO Unit := do
  let (frozenPath,receiptsPath,destination,sourcePath) ← match args with
    | [a,b,c] => pure (a,b,c,none)
    | [a,b,c,source] => pure (a,b,c,some source)
    | _ => throw (IO.userError "DeliverySignalAudit FROZEN RECEIPTS NEW-REPORT [SOURCE]")
  let frozen ← IO.ofExcept (fromJson? (α := RequiredDelivery.Frozen) (← read (.mk frozenPath)))
  let output := System.FilePath.mk destination
  unless !(← output.pathExists) do throw (IO.userError "keep previous signal audit")
  let mut results := #[]
  for entry in ← (System.FilePath.mk receiptsPath).readDir do
    let path := entry.path / "synaptic-delivery.json"
    if !(← path.pathExists) then continue
    let data := (← read path).getObjValD "data"
    let offers ← IO.ofExcept (data.getObjValAs? (Array Json) "offers")
    let mut sources : Array Range := #[]
    let mut kinds : Std.HashMap String Nat := {}
    for row in offers do
      let offer := row.getObjValD "offer"
      let kind ← IO.ofExcept (offer.getObjValAs? String "kind")
      kinds := kinds.insert kind ((kinds[kind]?.getD 0)+1)
      if let some source ← IO.ofExcept (offer.getObjValAs? (Option Range) "source") then
        sources := sources.push source
    let requirements := frozen.units.map fun unit => Json.mkObj [
      ("names",toJson unit.names),
      ("graphReached",toJson (unit.alternatives.any (fun target => covered target sources))),
      ("overlappingSignals",toJson (sources.filter (fun source => unit.alternatives.any (fun target =>
        target.subject == source.subject && target.first ≤ source.last && source.first ≤ target.last))
        |>.toList.eraseDups.toArray))]
    let rawInputs ← IO.ofExcept (data.getObjValAs? (Array Json) "inputs")
    let inputs := rawInputs.map fun value => Json.mkObj ((#["available","complete","requests","facts","bytes","failure"])
      |>.toList.map fun key => (key,value.getObjValD key))
    let ages ← IO.ofExcept (data.getObjValAs? (Array Json) "observationAges")
    let bundleRows ← IO.ofExcept (data.getObjValAs? (Array Json) "bundles")
    let result := Json.mkObj [
      ("receipt",toJson entry.fileName),("complete",data.getObjValD "complete"),
      ("offers",toJson offers.size),("kinds",Json.mkObj (kinds.toList.map fun (key,n) => (key,toJson n))),
      ("inputs",toJson inputs),("unlocatedFileOwners",data.getObjValD "unlocatedFileOwners"),
      ("locatedNativeOwners",toJson (ages.map fun value => value.getObjValD "owner")),
      ("bundles",toJson bundleRows.size),
      ("locatedBundles",toJson (bundleRows.filter fun row =>
        (row.getObjValAs? Bool "located").toOption == some true).size),
      ("requirements",toJson requirements)]
    results := results.push result
  let stored ← sourcePath.mapM fun path => do
    let source ← Eggshell.DB.PageMap.pin (.mk path)
    let some reader ← Index.open? source .database .shared |
      throw (IO.userError "pinned shared index unavailable; absence is not evidence of missing edges")
    let facts ← Index.allFacts reader.index
    let targets := facts.flatMap fun fact => match fact with
      | .supports support => #[support.source]
      | .coquoted _ range => #[range]
      | .consumed edge => edge.rows
      | .used usage => #[usage.source]
      | .read _ => #[]
    let items := frozen.units.map fun unit => Json.mkObj [
      ("names",toJson unit.names),
      ("coveredByStoredAdvisoryFacts",toJson (unit.alternatives.any (fun target => covered target targets))),
      ("overlappingAdvisoryFacts",toJson (facts.filter fun fact =>
        let ranges := match fact with
          | .supports support => #[support.source]
          | .coquoted _ range => #[range]
          | .consumed edge => edge.rows
          | .used usage => #[usage.source]
          | .read _ => #[]
        ranges.any (fun range => unit.alternatives.any (fun target => range.subject == target.subject &&
          range.first ≤ target.last && target.first ≤ range.last))).size)]
    return Json.mkObj [("source",toJson source.head),("index",toJson reader.index.head),
      ("facts",toJson facts.size),("requirements",toJson items),
      ("rootReachabilityEstablished",toJson false)]
  let report := Json.mkObj [("receipts",toJson results),("allStoredFacts",toJson stored),
    ("answeringModelCalls",toJson (0 : Nat)),("sourceWrites",toJson (0 : Nat)),
    ("productionAdoption",toJson false)]
  IO.FS.writeFile output (report.pretty ++ "\n")
  IO.println report.pretty
