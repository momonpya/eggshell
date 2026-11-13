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
private def mergeRanges (ranges : Array (Nat × Nat)) : Array (Nat × Nat) := Id.run do
  let mut result := #[]
  for (first,stop) in ranges.qsort (fun a b => a.1 < b.1) do
    if first ≥ stop then continue
    match result.back? with
    | some (a,b) =>
      if first ≤ b then result := result.pop.push (a,max b stop)
      else result := result.push (first,stop)
    | none => result := result.push (first,stop)
  return result
private def inferPositions (selection : Json) (nodes : Array Nat) : IO Json := do
  let raw ← IO.ofExcept (fromJson? (α := SharedCoverage.Input.RawProblem) (selection.getObjValD "selectorInput"))
  let _ ← IO.ofExcept raw.decode
  check (nodes.all (· < raw.costs.size)) "planned payload node exceeds frozen problem"
  let known := Std.HashSet.ofArray nodes
  let witness := selection.getObjValD "selectionWitness"
  let owners ← IO.ofExcept (witness.getObjValAs? (Array String) "owners")
  let units ← array (witness.getObjValD "units")
  let mut ranges : Std.HashMap Nat (Array (Nat × Nat)) := {}
  for id in [:units.size] do
    let row ← array units[id]!
    let family ← nat row[0]!
    check (family < owners.size) "unit names unknown original owner"
    let sourceNodes ← IO.ofExcept (fromJson? (α := Array (Option Nat)) row[2]!)
    let sourceNodes := sourceNodes.filterMap (fun node => node)
    let some offer := raw.offers[id]? | throw (IO.userError "base unit has no original offer")
    let present := if sourceNodes.isEmpty then offer.closure.all known.contains
      else sourceNodes.all known.contains
    if !present then continue
    let spans ← IO.ofExcept (fromJson? (α := Array (Nat × Nat)) row[1]!)
    ranges := ranges.insert family ((ranges[family]?).getD #[]++spans)
  let mut selectedNodes := #[]
  for entry in ← array (witness.getObjValD "sourceNodes") do
    let row ← array entry
    if let some node ← optionalNat row[0]! then
      if known.contains node then selectedNodes := selectedNodes.push (some node)
  let rangeAudit ← (← array (selection.getObjValD "rangeAudit")).mapM fun row => do
    let id ← nat (row.getObjValD "id")
    return row.setObjVal! "selectedRanges" (toJson (mergeRanges ((ranges[id]?).getD #[])))
  return selection.setObjVal! "rangeAudit" (toJson rangeAudit)
    |>.setObjVal! "selectionWitness" (witness.setObjVal! "selectedSourceNodes" (toJson selectedNodes))
private def selected (ctx : Context) (unit : Json) : IO Bool := do
  let mut satisfied := false
  for alternative in ← array (unit.getObjValD "alternatives") do
    let inspected ← (← array alternative).mapM (footprint ctx)
    if inspected.all (·.getObjValD "selected" == toJson true) then satisfied := true
  return satisfied
def planned (directory originalPath beforePath actualPath planPath output : String)
    (modelDomain : Option String := none) : IO Unit := do
  check (!(← System.FilePath.pathExists output)) "preserve prior packet inference audit"
  let root : System.FilePath := .mk directory
  let originals ← read (.mk originalPath)
  let before ← read (.mk beforePath)
  check (originals.getObjValD "head" == before.getObjValD "originalHead") "frozen packet uses another source head"
  let actual ← array ((← read (.mk actualPath)).getObjValD "queries")
  let plans ← array ((← read (.mk planPath)).getObjValD "topics")
  let judgedDomains ← match modelDomain with
    | none => pure #[]
    | some path => array ((← read (.mk path)).getObjValD "cases")
  let mut reports := #[]
  for topic in ← array (before.getObjValD "topics") do
    let number ← nat (topic.getObjValD "topic")
    let capture := root/(if number == 1 then "diagnostic" else s!"diagnostic-topic-{number}")/"selection.json"
    let selection ← read capture
    let raw ← IO.ofExcept (fromJson? (α := SharedCoverage.Input.RawProblem) (selection.getObjValD "selectorInput"))
    let originalChosen ← IO.ofExcept ((selection.getObjValD "selectionWitness").getObjValAs? (Array Nat) "compiledSelected")
    let mut baselineNodes := #[]
    for index in originalChosen do
      let some offer := raw.offers[index]? | throw (IO.userError "actual choice outside frozen offer domain")
      baselineNodes := baselineNodes++offer.closure.toArray
    let baseline ← context (← inferPositions selection baselineNodes) originals
    let some plan := plans.find? (·.getObjValD "topic" == toJson number) | throw (IO.userError "planned topic missing")
    let candidateNodes ← IO.ofExcept (plan.getObjValAs? (Array Nat) "selectedNodes")
    let candidate ← context (← inferPositions selection candidateNodes) originals
    let domain ← match judgedDomains.find? (·.getObjValD "topic" == toJson number) with
      | none => pure none
      | some domain => do
        let mut nodes := #[]
        for capsule in ← array (domain.getObjValD "capsules") do
          for part in ← IO.ofExcept (capsule.getObjValAs? (Array Nat) "parts") do
            let some offer := raw.offers[part]? | throw (IO.userError "judged capsule exceeds original offer domain")
            nodes := nodes++offer.closure.toArray
        pure (some (← context (← inferPositions selection nodes) originals))
    let some observed := actual.find? (fun row => row.getObjValD "pass" == toJson (0 : Nat) &&
      row.getObjValD "topic" == toJson number) | throw (IO.userError "actual baseline body audit missing")
    let missing ← IO.ofExcept (((observed.getObjValD "assessment").getObjValD "availableDelivery").getObjValAs?
      (Array (Array String)) "missing")
    let mut units := #[]
    for unit in ← array ((topic.getObjValD "frozen").getObjValD "units") do
      let names ← IO.ofExcept (unit.getObjValAs? (Array String) "names")
      let actual := !(names.any fun name => missing.any (·.contains name))
      let baseline ← selected baseline unit
      check (baseline == actual) "node inference fails to reproduce frozen baseline delivery; no candidate claim allowed"
      units := units.push (Json.mkObj [("names",toJson names),("baseline",toJson baseline),
        ("candidatePayloadAvailable",toJson (← selected candidate unit)),
        ("judgedDomainPayloadAvailable",← match domain with
          | none => pure Json.null
          | some domain => toJson <$> selected domain unit)])
    reports := reports.push (Json.mkObj [("topic",toJson number),("units",toJson units)])
  IO.FS.writeFile output (Json.mkObj [("topics",toJson reports),("baselineInferenceMatchesAllFrozenActualLabels",toJson true),
    ("assertsActualCandidateDelivery",toJson false),("scope",toJson "selected original payload availability only; actual candidate rendering and hook still required")]).compress
end SelectionMembershipAudit
def main : List String → IO Unit
  | [directory,originals,output] => SelectionMembershipAudit.run directory originals output
  | ["planned",directory,originals,before,actual,plan,output] => SelectionMembershipAudit.planned directory originals before actual plan output
  | ["planned-model",directory,originals,before,actual,plan,dataset,output] =>
      SelectionMembershipAudit.planned directory originals before actual plan output (some dataset)
  | _ => throw (IO.userError "SelectionMembershipAudit CAPTURED-DIRECTORY ORIGINAL-EXPORT NEW-REPORT")
