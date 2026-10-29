import tools.research.OriginalPayloadBasis
import tools.SharedCoverageInput
import tools.VerifiedWinnerCoverage
import tools.research.NativeTrialAudit
import Lean.Data.Json.Parser
open Lean Eggshell Eggshell.Synapses Eggshell.Synapses.CanonicalSource

private def read (path : String) : IO Json := IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

/-- Diagnose the recorded selector after it has run. Reference labels never
enter the selector, change its objective, or nominate an owner. No DB writes. -/
private def missing (args : List String) : IO Unit := do
  let [originalsPath,inputPath,inventoryPath,familyCountText,output] := args |
    throw (IO.userError "ORIGINALS SELECTOR-INPUT INVENTORY FAMILY-COUNT NEW-OUTPUT")
  let some familyCount := familyCountText.toNat? | throw (IO.userError "invalid family count")
  unless !(← System.FilePath.pathExists output) do throw (IO.userError "preserve prior diagnostic")
  let rawRows : Array StoredRow ← IO.ofExcept ((← read originalsPath).getObjValAs? _ "canonicalRows")
  let rows ← IO.ofExcept (Delivery.merge rawRows)
  let raw ← IO.ofExcept (fromJson? (α := SharedCoverage.Input.RawProblem)
    (((← read inputPath).getObjValD "data").getObjValD "selectorInput"))
  let problem ← IO.ofExcept raw.decode
  let some basis := Eggshell.Research.OriginalPayloadBasis.prepare familyCount rows problem |
    throw (IO.userError "canonical originals do not match recorded payload costs")
  let some chosen := SharedCoverage.choose? problem | throw (IO.userError "recorded selector failed")
  let paid := Std.HashSet.ofList (SharedCoverage.nodes problem chosen.selected)
  let chosenCues := Std.HashSet.ofList (SharedCoverage.cues problem chosen.selected)
  let price := SharedCoverage.cost problem chosen.selected
  let incidence := SharedCoverage.Deferred.Sparse.incidence
    (fun index : Fin problem.offers.size => problem.offers[index].closure)
  let sources := (basis.sourceRows.map fun (row,_) => row.key.file.relative).toList.eraseDups
  let mut byFile := #[]
  for path in sources do
    let fileRows := basis.sourceRows.filter fun (row,_) => row.key.file.relative == path
    let ids := hashDistinct (fileRows.toList.flatMap fun (_,atom) => incidence.lookup atom)
    let nominating := ids.map fun index => problem.offers[index]
    let touchingCues := hashDistinct (nominating.flatMap (·.covers))
    let selectedRows := fileRows.filter fun (_,atom) => paid.contains atom
    byFile := byFile.push (Json.mkObj [("path",toJson path),("indexedRows",toJson fileRows.size),
      ("selectedRows",toJson selectedRows.size),("nominatingOffers",toJson nominating.length),
      ("cues",toJson touchingCues.length),("positiveCues",toJson (touchingCues.countP fun cue => 0 < problem.weights[cue])),
      ("totalCueWeight",toJson (touchingCues.foldl (fun total cue => total+problem.weights[cue]) 0)),
      ("coveredCueWeight",toJson (touchingCues.foldl
        (fun total cue => if chosenCues.contains cue then total+problem.weights[cue] else total) 0))])
  let targets ← IO.ofExcept ((((← read inventoryPath).getObjValD "source").getObjValD "required").getArr?)
  let mut reports := #[]
  for target in targets do
    let path ← IO.ofExcept (target.getObjValAs? String "path")
    let first ← IO.ofExcept (target.getObjValAs? Nat "first")
    let last ← IO.ofExcept (target.getObjValAs? Nat "last")
    let wanted := basis.sourceRows.filter fun (row,_) =>
      row.key.file.relative == path && first ≤ row.key.line && row.key.line ≤ last
    let mut missing := #[]
    for (row,atom) in wanted do
      if paid.contains atom then continue
      let offers := (hashDistinct (incidence.lookup atom)).map fun index => problem.offers[index]
      let positive := offers.countP fun offer => offer.covers.any (fun cue => 0 < problem.weights[cue])
      let cues := hashDistinct (offers.flatMap (·.covers))
      missing := missing.push (Json.mkObj [("line",toJson row.key.line),("offers",toJson offers.length),
        ("positiveOffers",toJson positive),("cues",toJson cues.length),
        ("uncoveredCues",toJson (cues.countP fun cue => !chosenCues.contains cue))])
    reports := reports.push (Json.mkObj [("target",target),("indexedRows",toJson wanted.size),
      ("selectedRows",toJson (wanted.size-missing.size)),("missingIndexedRows",toJson missing)])
  let result := Json.mkObj [("sourceCostBasisChecked",toJson true),("selectedOffers",toJson chosen.selected.length),
    ("cost",toJson price),("byFile",toJson byFile),("targets",toJson reports),
    ("labelsUsedBySelector",toJson false),("answeringModelCalls",toJson (0 : Nat))]
  IO.FS.writeFile output result.pretty
  IO.println (Json.mkObj [("selectedOffers",toJson chosen.selected.length),("cost",toJson price),
    ("files",toJson sources.length),("diagnosticTargets",toJson targets.size)]).compress

private def actualRows : IO Unit := do
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let records : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/anchored-capture"
  let output := records / "body-row-audit.json"
  unless !(← output.pathExists) do throw (IO.userError "keep original-row audit")
  let trial := root / "anchored-prepared-hook"
  let source ← DB.PageMap.pin (trial / "work.egg")
  let some prepared ← Cache.open? source .database | throw (IO.userError "original rows are not prepared")
  let reader ← Persistence.Store.NodeReader.new source
  let mut docs := #[]
  for entry in ← Build.entries source do
    let mut doc ← Build.document reader entry.id
    if let some captured ← ContentMetadata.load? source entry.id doc then
      let files := captured.inputs.filterMap fun input => input.content.map fun content =>
        (⟨input.relative,content.root,content.bytes⟩ : File)
      doc := {doc with files := (hashDistinct (doc.files.toList ++ files.toList)).toArray}
    docs := docs.push doc
  let workspace : System.FilePath := "/Users/ovm/Code/eggshell-benchmarks/aamas-2027/sources/llvm-project"
  let mut images : Std.HashMap File (Array String) := {}
  let rows := prepared.registry.store
  let mut reads := #[]
  for row in rows do
    let image ← match images[row.key.file]? with
      | some image => pure image
      | none =>
        let image ← Eggshell.Research.OriginalEvidence.load workspace row.key.file
        let lines := (image.text.splitOn "\n").toArray
        images := images.insert row.key.file lines
        pure lines
    unless image[row.key.line-1]? == some row.code do
      throw (IO.userError "prepared row differs from independently hashed source")
    for origin in row.origins do
      let read : Read := {
        occurrence := origin.occurrence
        source := ⟨row.key.file,row.key.line,row.key.line⟩
        binding := origin.binding}
      unless read.valid do throw (IO.userError "prepared row lost original binding")
      reads := reads.push read
  let body ← IO.FS.readFile (trial / "body.txt")
  let shown := Extraction.presented body docs reads
  let input ← read (root.parent.get! / "all-citations-audit-input.json").toString
  let required : Array Eggshell.Research.OriginalEvidence.Reference ←
    IO.ofExcept ((input.getObjValD "source").getObjValAs? _ "required")
  let mut reports := #[]
  for target in required do
    let fileRows := rows.filter fun row => row.key.file.relative == target.path &&
      target.first ≤ row.key.line && row.key.line ≤ target.last && !row.code.trimAscii.isEmpty
    let missing := fileRows.filter fun row => !covered (⟨row.key.file,row.key.line,row.key.line⟩ : Range) shown.ranges
    reports := reports.push (Json.mkObj [("target",toJson target),("storedNonblank",toJson fileRows.size),
      ("deliveredNonblank",toJson (fileRows.size-missing.size)),("missingNonblank",toJson (missing.map (·.key.line)))])
  IO.FS.writeFile output (Json.mkObj [("independentFileFingerprintsChecked",toJson true),
    ("actualBody",toJson true),("sourceHead",toJson source.head),("preparedRows",toJson rows.size),
    ("byTarget",toJson reports),("frozenRangeMetricUnchanged",toJson true),
    ("goalAchieved",toJson false),("productionAdoption",toJson false)]).pretty
  IO.println "Audited prepared original rows against reference images and actual delivery body"

def main (args : List String) : IO Unit := do
  if args == ["body"] then return ← actualRows
  let root := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let records := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/anchored-capture"
  missing [root ++ "/anchored-capture/current-originals.json",records ++ "/selector.json",
    root ++ "/../all-citations-audit-input.json","38",records ++ "/missing-selection.json"]
  let output := records ++ "/benchmark-audit.json"
  unless !(← System.FilePath.pathExists output) do throw (IO.userError "keep benchmark audit")
  let report ← Eggshell.Research.NativeTrialAudit.inspect (root ++ "/anchored-capture/mandatory-audit-input.json")
  IO.FS.writeFile output report.pretty
  IO.println (Json.mkObj [("benchmarkDelivery",report.getObjValD "requiredDelivery")]).compress
