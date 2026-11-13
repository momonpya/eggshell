import Eggshell.Sha256
import Lean.Data.Json.Parser
import tools.SharedCoverageInput
import Std.Data.HashMap
import Std.Data.HashSet
open Lean
namespace SelectionMembershipAudit
private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= (IO.ofExcept ∘ Json.parse)
private def array (json : Json) : IO (Array Json) := IO.ofExcept json.getArr?
private def nat (json : Json) : IO Nat := IO.ofExcept (fromJson? json)
private def text (json : Json) : IO String := IO.ofExcept json.getStr?
private def optionalNat (json : Json) : IO (Option Nat) := IO.ofExcept (fromJson? json)
private def spanCovered (ranges : Json) (first stop : Nat) : IO Bool := do
  let mut covered := false
  for range in ← array ranges do
    let values ← array range
    check (values.size == 2) "range is not a half-open pair"
    let a ← nat values[0]!
    let b ← nat values[1]!
    check (a ≤ b) "range endpoints reversed"
    if a ≤ first && stop ≤ b then covered := true
  return covered
private def sourceKey (file : Json) (line : Nat) : String :=
  (Json.arr #[file,toJson line]).compress
structure Context where
  ranges : Std.HashMap String Json
  originals : Std.HashMap String String
  nodes : Std.HashMap String Nat
  candidate : Std.HashSet Nat
  selected : Std.HashSet Nat
private def originalKey (work content : String) (chars : Nat) :=
  (toJson (work,content,chars)).compress
private def context (selection originals : Json) : IO Context := do
  let raw ← IO.ofExcept (fromJson? (α := SharedCoverage.Input.RawProblem) (selection.getObjValD "selectorInput"))
  let _ ← IO.ofExcept raw.decode
  let mut ranges : Std.HashMap String Json := {}
  for entry in ← array (selection.getObjValD "rangeAudit") do
    let owner ← text (entry.getObjValD "owner")
    check (!(ranges.contains owner)) "duplicate owner in range receipt"
    ranges := ranges.insert owner entry
  let mut identities : Std.HashMap String String := {}
  for document in ← array (originals.getObjValD "documents") do
    let owner ← text (document.getObjValD "owner")
    let work ← text (document.getObjValD "work")
    let body ← text (document.getObjValD "source")
    let key := originalKey work (Eggshell.Sha256.hex body.toUTF8) body.length
    if let some previous := identities[key]? then
      check (previous == owner) "ambiguous exact original identity"
    identities := identities.insert key owner
  let witness := selection.getObjValD "selectionWitness"
  let mut nodes : Std.HashMap String Nat := {}
  for row in ← array (witness.getObjValD "sourceNodes") do
    let row ← array row
    check (row.size == 2) "canonical node entry is malformed"
    let some id ← optionalNat row[0]! | continue
    check (id < raw.costs.size) "source node outside checked selector domain"
    let key := row[1]!
    let key := sourceKey (key.getObjValD "file") (← nat (key.getObjValD "line"))
    check (!(nodes.contains key)) "duplicate canonical file/line"
    nodes := nodes.insert key id
  let mut candidate : Std.HashSet Nat := {}
  for offer in raw.offers do
    for id in offer.closure do candidate := candidate.insert id
  let mut selected : Std.HashSet Nat := {}
  for id in ← array (witness.getObjValD "selectedSourceNodes") do
    if let some id ← optionalNat id then selected := selected.insert id
  return ⟨ranges,identities,nodes,candidate,selected⟩
private def footprint (ctx : Context) (target : Json) : IO Json := do
  let first ← nat (target.getObjValD "first")
  let last ← nat (target.getObjValD "last")
  check (0 < first && first ≤ last && last-first ≤ 1000000) "invalid independently frozen range"
  let subject := target.getObjValD "subject"
  if let .ok file := subject.getObjVal? "file" then
    let file := file.getObjValD "file"
    let mut absent := #[]
    let mut unselected := #[]
    for line in [first:last+1] do
      match ctx.nodes[sourceKey file line]? with
      | none => absent := absent.push line; unselected := unselected.push line
      | some node =>
        unless ctx.candidate.contains node do absent := absent.push line
        unless ctx.selected.contains node do unselected := unselected.push line
    return Json.mkObj [("subject",toJson "file-lines"),("candidate",toJson absent.isEmpty),
      ("selected",toJson unselected.isEmpty),("missingCandidateLines",toJson absent),
      ("missingSelectedLines",toJson unselected)]
  let original := (subject.getObjValD "original").getObjValD "original"
  let work ← text (original.getObjValD "work")
  let content ← text (original.getObjValD "content")
  let chars ← nat (original.getObjValD "chars")
  check (last ≤ chars) "original range exceeds exact saved payload"
  let key := originalKey work content chars
  let some owner := ctx.originals[key]? | throw (IO.userError "frozen original does not match exported immutable bytes")
  let some entry := ctx.ranges[owner]? | return Json.mkObj [
    ("subject",toJson "original"),("owner",toJson owner),("candidate",toJson false),("selected",toJson false),
    ("reason",toJson "owner-not-in-selector-domain")]
  -- Original footprints are one-based closed; receipt positions are zero-based
  -- half-open. File footprints above use line numbers, never character widths.
  return Json.mkObj [("subject",toJson "original"),("owner",toJson owner),
    ("candidate",toJson (← spanCovered (entry.getObjValD "candidateRanges") (first-1) last)),
    ("selected",toJson (← spanCovered (entry.getObjValD "selectedRanges") (first-1) last)),
    ("candidateUnits",entry.getObjValD "candidateUnits"),("selectedUnits",entry.getObjValD "selectedUnits"),
    ("positiveBaseOffers",entry.getObjValD "positiveBaseOffers")]
def run (directory originalPath output : String) : IO Unit := do
  let root : System.FilePath := .mk directory
  let path : System.FilePath := .mk output
  check (!(← path.pathExists)) "preserve prior membership audit"
  let originals ← read (.mk originalPath)
  let before ← read (root/"before-delivery.json")
  check (originals.getObjValD "head" == before.getObjValD "originalHead") "original export belongs to another source head"
  let frozen ← array (before.getObjValD "topics")
  let queries ← array ((← read (root/"result.json")).getObjValD "queries")
  let mut results := #[]
  let mut consistent := true
  for topic in frozen do
    let number ← nat (topic.getObjValD "topic")
    let directory := root/(if number == 1 then "diagnostic" else s!"diagnostic-topic-{number}")
    check ((← read (directory/"validation.json")).getObjValD "sameOrdinaryBody" == toJson true)
      "captured selector does not explain the actual ordinary body"
    let selection ← read (directory/"selection.json")
    let ctx ← context selection originals
    let some query := queries.find? (fun row => row.getObjValD "pass" == toJson (0 : Nat) &&
        row.getObjValD "topic" == toJson number) | throw (IO.userError "ordinary query missing")
    let delivery := (query.getObjValD "assessment").getObjValD "availableDelivery"
    let missing : Array (Array String) ← IO.ofExcept (fromJson? (delivery.getObjValD "missing"))
    let mut units := #[]
    let mut delivered := 0
    for unit in ← array ((topic.getObjValD "frozen").getObjValD "units") do
      let names : Array String ← IO.ofExcept (fromJson? (unit.getObjValD "names"))
      let mut alternatives := #[]
      for alternative in ← array (unit.getObjValD "alternatives") do
        let inspected ← (← array alternative).mapM (footprint ctx)
        alternatives := alternatives.push (Json.mkObj [("footprints",toJson inspected),
          ("candidate",toJson (inspected.all (·.getObjValD "candidate" == toJson true))),
          ("selected",toJson (inspected.all (·.getObjValD "selected" == toJson true)))])
      let candidate := alternatives.any (·.getObjValD "candidate" == toJson true)
      let selected := alternatives.any (·.getObjValD "selected" == toJson true)
      let actual := !(names.any fun name => missing.any (·.contains name))
      if actual then delivered := delivered+1
      if actual && !selected then consistent := false
      let stage := if actual then "delivered" else if selected then "selected-not-in-body"
        else if candidate then "candidate-not-selected" else "not-in-candidate-union"
      units := units.push (Json.mkObj [("names",toJson names),("candidate",toJson candidate),
        ("selected",toJson selected),("actual",toJson actual),("stage",toJson stage),
        ("alternatives",toJson alternatives)])
    check (toJson delivered == delivery.getObjValD "delivered") "actual-delivery labels do not match frozen unit groups"
    results := results.push (Json.mkObj [("topic",toJson number),("units",toJson units),
      ("families",selection.getObjValD "families"),("candidateUnits",selection.getObjValD "candidateUnits")])
  IO.FS.writeFile path (Json.mkObj [("topics",toJson results),("allActualEvidenceHasPlannedFootprint",toJson consistent),
    ("candidateMeansUnionNotFeasiblePacket",toJson true),("productOrModelCalled",toJson false)]).compress
  check consistent "range receipt does not explain all actual deliveries; do not classify losses from it"
end SelectionMembershipAudit
def main : List String → IO Unit
  | [directory,originals,output] => SelectionMembershipAudit.run directory originals output
  | _ => throw (IO.userError "SelectionMembershipAudit CAPTURED-DIRECTORY ORIGINAL-EXPORT NEW-REPORT")
