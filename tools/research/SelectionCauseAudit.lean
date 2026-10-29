import tools.research.OriginalPayloadBasis
import tools.research.OriginalEvidence
import tools.SharedCoverageInput
import tools.VerifiedWinnerCoverage
import Eggshell.ContentMetadata
import Eggshell.SynapseBuild
open Lean Eggshell Eggshell.Synapses Eggshell.Synapses.CanonicalSource

private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def check (value : Bool) (message : String) : IO Unit :=
  unless value do throw (IO.userError message)

private def originals (study root : System.FilePath) : IO (DB.PageMap.Snapshot × Array StoredRow × Array Extraction.Document) := do
  let source ← DB.PageMap.pin (study / "r0/stage1/history/source.egg")
  let baseline ← read (study / "seed-originals.json")
  check (baseline.getObjValD "sourceHead" == toJson source.head) "saved source changed"
  let initial : Array StoredRow ← IO.ofExcept (baseline.getObjValAs? _ "canonicalRows")
  let refinement ← read (root / "anchored-capture/seed-refinement.json")
  check (refinement.getObjValD "source" == toJson source.head) "supplement source changed"
  let extras : Array (Nat × String × ContentCapture.Supplement) ← IO.ofExcept (refinement.getObjValAs? _ "supplements")
  let reader ← Persistence.Store.NodeReader.new source
  let mut additions := #[]
  let mut documents := #[]
  let byId := Std.HashMap.ofArray (extras.map fun (id,owner,extra) => (id,(owner,extra)))
  for entry in ← Build.entries source do
    let mut doc ← Build.document reader entry.id
    if let some parent ← ContentMetadata.load? source entry.id doc then
      let files := parent.inputs.filterMap fun input => input.content.map fun content =>
        (⟨input.relative,content.root,content.bytes⟩ : File)
      if let some (owner,extra) := byId[entry.id]? then
        check (owner == doc.owner) "supplement owner changed"
        if extra.sealed then
          let catalog ← IO.ofExcept (ContentMetadata.catalogSupplement source.head.identity doc parent extra)
          for located in catalog.located do
            let some file := located.read.source.file? | throw (IO.userError "supplement lost source coordinates")
            let origins := doc.occurrences.map fun occurrence => (⟨occurrence,located.read.binding⟩ : Origin)
            additions := additions.push ⟨⟨file,located.read.source.first⟩,located.text,origins⟩
      doc := {doc with files := (hashDistinct (doc.files.toList ++ files.toList)).toArray}
    documents := documents.push doc
  let rows ← IO.ofExcept (Delivery.merge (initial ++ additions))
  check (rows.size == 8276) "prepared source basis changed"
  return (source,rows,documents)

private structure Charge where
  id : Nat
  standalone : Nat × Nat
  marginal : Nat × Nat
  base : Nat
  graph : Nat
  uncoveredBase : Nat
  uncoveredGraph : Nat
  baseCues : Nat
  graphCues : Nat
  deriving ToJson, Inhabited

private def charge (p : SharedCoverage.Problem) (paid : Std.HashSet (Fin p.costs.size))
    (known : Std.HashSet (Fin p.weights.size)) (id : Fin p.offers.size) : Charge := Id.run do
  let offer := p.offers[id]
  let nodes := hashDistinct offer.closure
  let cues := hashDistinct offer.covers
  let total := nodes.foldl (fun total atom => (total.1+p.costs[atom].1,total.2+p.costs[atom].2)) p.fixed
  let fresh := nodes.filter (!paid.contains ·)
  let marginal := fresh.foldl (fun total atom => (total.1+p.costs[atom].1,total.2+p.costs[atom].2)) (0,0)
  let base := cues.filter (fun cue => cue.val%2 == 0)
  let graph := cues.filter (fun cue => cue.val%2 == 1)
  let weight := fun (cues : List (Fin p.weights.size)) => cues.foldl (fun total cue => total+p.weights[cue]) 0
  return ⟨id.val,total,marginal,weight base,weight graph,weight (base.filter (!known.contains ·)),
    weight (graph.filter (!known.contains ·)),base.countP (fun cue => 0 < p.weights[cue]),
    graph.countP (fun cue => 0 < p.weights[cue])⟩

private def suffixCandidates (document : Extraction.Document) (expected : Array String) : Nat := Id.run do
  if !document.native || expected.isEmpty then return 0
  let some prepared := ObservationContext.prepare? document | return 0
  let mut views := #[prepared.lines]
  if let some json := prepared.json then
    for leaf in json.leaves do
      if let some text := leaf.scalar.text then views := views.push (Extraction.textLines text)
  let mut count := 0
  for lines in views do
    for first in [:lines.size] do
      if lines.size < first+expected.size then break
      if (List.finRange expected.size).all (fun offset =>
          expected[offset].trimAscii.isEmpty || (lines[first+offset.val]?).any (fun line => line.text.endsWith expected[offset])) then
        count := count+1
  return count

def main (args : List String) : IO Unit := do
  let [destination] := args | throw (IO.userError "SelectionCauseAudit NEW-OUTPUT")
  check (!(← System.FilePath.pathExists destination)) "keep previous causal audit"
  let study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  let root := study / "shared-snapshot"
  let records : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/anchored-capture"
  let started ← IO.monoMsNow
  let (source,rows,documents) ← originals study root
  let input ← read (records / "selector.json")
  let data := input.getObjValD "data"
  let raw : SharedCoverage.Input.RawProblem ← IO.ofExcept (data.getObjValAs? _ "selectorInput")
  let p ← IO.ofExcept raw.decode
  let families ← IO.ofExcept (data.getObjValAs? Nat "families")
  let some basis := Eggshell.Research.OriginalPayloadBasis.prepare families rows p |
    throw (IO.userError "source rows disagree with recorded cost basis")
  let some selected := SharedCoverage.choose? p | throw (IO.userError "selector did not replay")
  check (selected.selected.length == 741 && SharedCoverage.cost p selected.selected == (120000,120002))
    "actual recorded selection did not replay"
  let paid := Std.HashSet.ofList (SharedCoverage.nodes p selected.selected)
  let known := Std.HashSet.ofList (SharedCoverage.cues p selected.selected)
  let incidence := SharedCoverage.Deferred.Sparse.incidence (fun id : Fin p.offers.size => p.offers[id].closure)
  let metrics := (List.finRange p.offers.size).toArray.map (charge p paid known)
  let targets : Array Eggshell.Research.OriginalEvidence.Reference ←
    IO.ofExcept (((← read (study / "all-citations-audit-input.json")).getObjValD "source").getObjValAs? _ "required")
  let mut reports := #[]
  for target in targets do
    let wanted := basis.sourceRows.filter fun (row,_) => row.key.file.relative == target.path &&
      target.first ≤ row.key.line && row.key.line ≤ target.last
    if wanted.all (fun (_,atom) => paid.contains atom) then continue
    let candidates := hashDistinct (wanted.toList.flatMap fun (_,atom) => incidence.lookup atom)
    let values := candidates.toArray.map fun id => metrics[id.val]!
    let least := fun (values : Array Charge) => values.qsort (fun a b =>
      if a.standalone.1 == b.standalone.1 then a.id < b.id else a.standalone.1 < b.standalone.1) |>.extract 0 3
    reports := reports.push (Json.mkObj [("target",toJson target),("rows",toJson wanted.size),
      ("selectedRows",toJson (wanted.countP fun (_,atom) => paid.contains atom)),("offers",toJson values.size),
      ("basePositiveOffers",toJson (values.countP fun value => 0 < value.base)),
      ("graphPositiveOffers",toJson (values.countP fun value => 0 < value.graph)),
      ("standaloneFeasiblePositiveOffers",toJson (values.countP fun value =>
        0 < value.base+value.graph && value.standalone.1 ≤ p.limit.1 && value.standalone.2 ≤ p.limit.2)),
      ("smallestPositive",toJson (least (values.filter fun value => 0 < value.base+value.graph))),
      ("smallestUncovered",toJson (least (values.filter fun value => 0 < value.uncoveredBase+value.uncoveredGraph)))])
  let reference ← read (study / "r0/stage1/preparation/audit-input.json")
  let requested : Array Eggshell.Research.OriginalEvidence.Reference ←
    IO.ofExcept ((reference.getObjValD "source").getObjValAs? _ "required")
  let workspace : System.FilePath := "/Users/ovm/Code/eggshell-benchmarks/aamas-2027/sources/llvm-project"
  let mut allReads := #[]
  for row in rows do
    for origin in row.origins do
      let recorded : Read := {
        occurrence := origin.occurrence
        source := ⟨row.key.file,row.key.line,row.key.line⟩
        binding := origin.binding}
      check recorded.valid "original source binding changed"
      allReads := allReads.push recorded
  let body ← IO.FS.readFile (records / "hook/body.txt")
  let shown := Extraction.presented body documents allReads
  let mut availability := #[]
  let files := Std.HashSet.ofArray (rows.map (·.key.file))
  for requirement in requested do
    let mut found := #[]
    for file in files.toArray.filter (·.relative == requirement.path) do
      let image ← Eggshell.Research.OriginalEvidence.load workspace file
      let expected := (image.text.splitOn "\n").toArray.extract (requirement.first-1) requirement.last
      for document in documents do
        let count := suffixCandidates document expected
        if count > 0 then found := found.push (document.owner,count,document.files.contains file)
    let available := rows.filter fun row => row.key.file.relative == requirement.path &&
      requirement.first ≤ row.key.line && row.key.line ≤ requirement.last && !row.code.trimAscii.isEmpty
    let delivered := available.filter fun row => covered (⟨row.key.file,row.key.line,row.key.line⟩ : Range) shown.ranges
    let atoms := basis.sourceRows.filter fun (row,_) => available.contains row
    let candidateIds := hashDistinct (atoms.toList.flatMap fun (_,atom) => incidence.lookup atom)
    let charges := candidateIds.toArray.map fun id => metrics[id.val]!
    let best := charges.qsort (fun a b =>
      if a.uncoveredBase+a.uncoveredGraph == b.uncoveredBase+b.uncoveredGraph then a.id < b.id
      else a.uncoveredBase+a.uncoveredGraph > b.uncoveredBase+b.uncoveredGraph)
    let selectedAtoms := atoms.filter fun (_,atom) => paid.contains atom
    availability := availability.push (Json.mkObj [("reference",toJson requirement),
      ("storedNonblankLines",toJson (available.map (·.key.line))),
      ("deliveredNonblankLines",toJson (delivered.map (·.key.line))),
      ("selectedNonblankLines",toJson (selectedAtoms.map fun (row,_) => row.key.line)),
      ("offers",toJson charges.size),("positiveOffers",toJson (charges.countP fun value => 0 < value.base+value.graph)),
      ("bestUncoveredOffers",toJson (best.extract 0 3)),
      ("suffixCandidatesOnly",toJson found),("suffixIsCertification",toJson false)])
  check ((← DB.PageMap.pin source.directory).head == source.head) "read-only diagnosis changed source"
  let report := Json.mkObj [("source",toJson source.head),("sourceUnchanged",toJson true),
    ("sourceRows",toJson rows.size),("offers",toJson p.offers.size),("cues",toJson p.weights.size),
    ("selectedOffers",toJson selected.selected.length),("cost",toJson (SharedCoverage.cost p selected.selected)),
    ("missingTargets",toJson reports),("rawReferenceAvailability",toJson availability),
    ("elapsedMs",toJson ((← IO.monoMsNow)-started)),("answeringModelCalls",toJson (0 : Nat)),
    ("changedCandidate",toJson false),("productionAdoption",toJson false)]
  IO.FS.writeFile destination report.pretty
  IO.println (Json.mkObj [("missingTargets",toJson reports.size),("elapsedMs",report.getObjValD "elapsedMs"),
    ("sourceRows",toJson rows.size),("sourceUnchanged",toJson true)]).compress
