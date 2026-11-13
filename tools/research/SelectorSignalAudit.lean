import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
import Eggshell.Sha256
import Std.Data.HashMap
import Std.Data.HashSet
open Lean

namespace SelectorSignalAudit
def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)
def load (path : String) : IO Json := IO.FS.readFile (.mk path) >>= (IO.ofExcept ∘ Json.parse)
def field [FromJson α] (value : Json) (name : String) : IO α :=
  IO.ofExcept (value.getObjValAs? α name)
structure Counts where
  base : Nat := 0
  graph : Nat := 0
  both : Nat := 0
def run (input output : String) : IO Unit := do
  check (!(← System.FilePath.pathExists output)) "preserve selector-signal audit"
  let captured ← load input
  let problem := captured.getObjValD "selectorInput"
  let witness := captured.getObjValD "selectionWitness"
  let weights : Array Nat ← field problem "weights"
  let offers : Array Json ← field problem "offers"
  let pieces : Array (Array Json) ← field witness "pieces"
  let units : Array Json ← field witness "units"
  let nodes : Array (Nat × Json) ← field witness "sourceNodes"
  let chosenNodes : Array Nat ← field witness "selectedSourceNodes"
  let selected := Std.HashSet.ofArray chosenNodes
  let bundles : Nat ← field (captured.getObjValD "jointBindings") "preparedBundles"
  check (units.size+bundles ≤ offers.size && weights.size%2 == 0) "invalid captured input dimensions"
  let mut counts : Std.HashMap Nat Counts := {}
  let mut positiveBase := 0
  let mut positiveGraph := 0
  let mut graphOnly := 0
  let mut direct : Std.HashMap Nat (Nat × Nat × Nat) := {}
  for piece in pieces do
    let base ← IO.ofExcept (fromJson? (α := Nat) (piece[3]?.getD Json.null))
    let total ← IO.ofExcept (fromJson? (α := Nat) (piece[4]?.getD Json.null))
    check (base ≤ total) "captured total weight is below its base"
    if base > 0 then positiveBase := positiveBase+1
    if total > base then positiveGraph := positiveGraph+1
    if total > 0 && base == 0 then graphOnly := graphOnly+1
    if let some id := (fromJson? (α := Nat) (piece[5]?.getD Json.null)).toOption then
      let prior := direct[id]?.getD (0,0,0)
      direct := direct.insert id (max prior.1 base,max prior.2.1 total,prior.2.2+1)
  let mut bundlePositiveGraph := 0
  let mut bundleWithoutPositiveGraph := 0
  for (offer,index) in offers.zipIdx do
    let covers : Array Nat ← field offer "covers"
    let closure : Array Nat ← field offer "closure"
    let base := covers.any (fun cue => cue%2 == 0 && (weights[cue]?.getD 0) > 0)
    let graph := covers.any (fun cue => cue%2 == 1 && (weights[cue]?.getD 0) > 0)
    for cue in covers do check (cue < weights.size) "captured offer names a missing cue"
    if units.size ≤ index && index < units.size+bundles then
      if graph then bundlePositiveGraph := bundlePositiveGraph+1
      else bundleWithoutPositiveGraph := bundleWithoutPositiveGraph+1
    for atom in closure do
      let prior := counts[atom]?.getD {}
      counts := counts.insert atom ⟨prior.base+(if base then 1 else 0),
        prior.graph+(if graph then 1 else 0),prior.both+(if base && graph then 1 else 0)⟩
  let reports := nodes.map fun (id,key) =>
    let count := counts[id]?.getD {}
    let hint := direct[id]?.getD (0,0,0)
    Json.mkObj [("node",toJson id),("key",key),("selected",toJson (selected.contains id)),
      ("baseOffers",toJson count.base),("graphOffers",toJson count.graph),("bothOffers",toJson count.both),
      ("directPieces",toJson hint.2.2),("hasDirectGraphBonus",toJson (decide (hint.1 < hint.2.1))),
      ("directBaseWeight",toJson (toString hint.1)),("directTotalWeight",toJson (toString hint.2.1))]
  let positiveOdd := weights.zipIdx.countP (fun (value,index) => index%2 == 1 && value > 0)
  IO.FS.writeFile (.mk output) (Json.mkObj [
    ("input",toJson input),("pieces",toJson pieces.size),("positiveBasePieces",toJson positiveBase),
    ("graphRaisesPieces",toJson positiveGraph),("graphOnlyPieces",toJson graphOnly),
    ("distinctGraphBonuses",toJson positiveOdd),("publishedUnits",toJson units.size),
    ("preparedBundles",toJson bundles),("bundlesWithPositiveGraphBonus",toJson bundlePositiveGraph),
    ("bundlesWithoutPositiveGraphBonus",toJson bundleWithoutPositiveGraph),("nodes",toJson reports),
    ("queryOrModelCalled",toJson false),("productChanged",toJson false),("adopted",toJson false)]).compress
private def pieceSummary (pieces : Array (Array Json)) : IO Json := do
  let mut basePositive := 0
  let mut raised := 0
  let mut canonical := 0
  let mut maxBase := 0
  let mut maxTotal := 0
  for piece in pieces do
    check (piece.size == 6) "unexpected captured cue-piece shape"
    let base ← IO.ofExcept (fromJson? (α := Nat) piece[3]!)
    let total ← IO.ofExcept (fromJson? (α := Nat) piece[4]!)
    check (base ≤ total) "graph lowered a base cue"
    if 0 < base then basePositive := basePositive+1
    if base < total then raised := raised+1
    if piece[5]! != Json.null then canonical := canonical+1
    maxBase := max maxBase base
    maxTotal := max maxTotal total
  return Json.mkObj [("pieces",toJson pieces.size),("positiveBasePieces",toJson basePositive),
    ("graphRaisedPieces",toJson raised),("canonicalPieces",toJson canonical),
    ("maximumBase",toJson maxBase),("maximumTotal",toJson maxTotal)]

/-- Explain a separately frozen reference in an actual captured query. Golden
references are consumed only by this diagnostic, never by the product or ranker. -/
private def targetSignals (selection signal originals target : Json) : IO Json := do
  let first : Nat ← field target "first"
  let last : Nat ← field target "last"
  check (0 < first && first ≤ last) "invalid frozen evidence coordinates"
  let subject := target.getObjValD "subject"
  if let .ok wrapper := subject.getObjVal? "file" then
    let file := wrapper.getObjValD "file"
    let nodes : Array Json ← field signal "nodes"
    let nodes := nodes.filter fun row =>
      let key := row.getObjValD "key"
      key.getObjValD "file" == file &&
      ((fromJson? (α := Nat) (key.getObjValD "line")).toOption.any fun line => first ≤ line && line ≤ last)
    return Json.mkObj [("subject",toJson "file-lines"),("first",toJson first),("last",toJson last),
      ("file",file),("nodes",toJson nodes)]
  let original := (subject.getObjValD "original").getObjValD "original"
  let work : String ← field original "work"
  let content : String ← field original "content"
  let chars : Nat ← field original "chars"
  let documents : Array Json ← field originals "documents"
  let mut found : Array String := #[]
  for document in documents do
    if document.getObjValD "work" != toJson work then continue
    let source : String ← field document "source"
    if source.length == chars && Eggshell.Sha256.hex source.toUTF8 == content then
      found := found.push (← field document "owner")
  check (found.size == 1 && last ≤ chars) "frozen original identity is absent or ambiguous"
  let owner := found[0]!
  let witness := selection.getObjValD "selectionWitness"
  let owners : Array String ← field witness "owners"
  let some family := owners.findIdx? (· == owner) | throw (IO.userError "frozen original has no captured family")
  let pieces : Array (Array Json) ← field witness "pieces"
  let touching := pieces.filter fun piece =>
    piece[0]? == some (toJson family) &&
    ((fromJson? (α := Nat) (piece[1]?.getD Json.null)).toOption.any (· < last)) &&
    ((fromJson? (α := Nat) (piece[2]?.getD Json.null)).toOption.any (first-1 < ·))
  let ranges : Array Json ← field selection "rangeAudit"
  let some range := ranges.find? (·.getObjValD "owner" == toJson owner) |
    throw (IO.userError "captured family has no range audit")
  return Json.mkObj [("subject",toJson "original"),("owner",toJson owner),
    ("first",toJson (first-1)),("stop",toJson last),("overlappingCueSignal",← pieceSummary touching),
    ("overlappingPieces",toJson touching),("family",range)]

def cohort (directory originalPath membershipPath output : String) : IO Unit := do
  check (!(← System.FilePath.pathExists output)) "preserve cohort signal diagnosis"
  let root := System.FilePath.mk directory
  let originals ← load originalPath
  let before ← load (root/"before-delivery.json").toString
  check (originals.getObjValD "head" == before.getObjValD "originalHead") "original export and frozen snapshot differ"
  let membership ← load membershipPath
  check (membership.getObjValD "allActualEvidenceHasPlannedFootprint" == toJson true)
    "range capture does not explain actual ordinary delivery"
  let membershipTopics : Array Json ← field membership "topics"
  let topics : Array Json ← field before "topics"
  let mut results := #[]
  for topic in topics do
    let number : Nat ← field topic "topic"
    let name := if number == 1 then "diagnostic" else s!"diagnostic-topic-{number}"
    let capture := root/name
    check ((← load (capture/"validation.json").toString).getObjValD "sameOrdinaryBody" == toJson true)
      "instrumentation changed the actual ordinary body"
    let selection ← load (capture/"selection.json").toString
    let signalPath := capture/"signal.json"
    run (capture/"selection.json").toString signalPath.toString
    let signal ← load signalPath.toString
    let some classified := membershipTopics.find? (·.getObjValD "topic" == toJson number) |
      throw (IO.userError "topic is absent from membership audit")
    let classifications : Array Json ← field classified "units"
    let units : Array Json ← field (topic.getObjValD "frozen") "units"
    let mut reports := #[]
    for unit in units do
      let names := unit.getObjValD "names"
      let some classified := classifications.find? (·.getObjValD "names" == names) |
        throw (IO.userError "frozen unit is absent from membership audit")
      let alternatives : Array (Array Json) ← field unit "alternatives"
      let alternatives ← alternatives.mapM fun alternative => alternative.mapM (targetSignals selection signal originals)
      reports := reports.push (Json.mkObj [("names",names),("stage",classified.getObjValD "stage"),
        ("alternatives",toJson alternatives)])
    results := results.push (Json.mkObj [("topic",toJson number),("units",toJson reports),
      ("graphRaisesPieces",signal.getObjValD "graphRaisesPieces"),
      ("preparedBundles",signal.getObjValD "preparedBundles"),
      ("bundlesWithPositiveGraphBonus",signal.getObjValD "bundlesWithPositiveGraphBonus"),
      ("bundlesWithoutPositiveGraphBonus",signal.getObjValD "bundlesWithoutPositiveGraphBonus")])
  IO.FS.writeFile output (Json.mkObj [("topics",toJson results),("queryOrModelCalled",toJson false),
    ("goldenUsedOnlyByDiagnostic",toJson true),("productChanged",toJson false),("adopted",toJson false)]).compress
end SelectorSignalAudit
def main : List String → IO Unit
  | ["cohort",directory,originals,membership,output] => SelectorSignalAudit.cohort directory originals membership output
  | [input,output] => SelectorSignalAudit.run input output
  | _ => throw (IO.userError "SelectorSignalAudit SELECTION OUTPUT")
