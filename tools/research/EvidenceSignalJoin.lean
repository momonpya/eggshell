import Eggshell.Handoff
import Eggshell.SynapseBuild
import tools.SharedCoverageInput
import Lean.Data.Json.Parser

open Lean Eggshell Eggshell.Plugin Eggshell.Plugin.SharedRangeAdapter
open Eggshell.Synapses Eggshell.Persistence.Store

namespace Eggshell.Research.EvidenceSignalJoin

private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

private def field [FromJson α] (value : Json) (name : String) : IO α :=
  IO.ofExcept (value.getObjValAs? α name)

private def check (value : Bool) (message : String) : IO Unit :=
  unless value do throw (IO.userError message)

structure Settings where
  database : String
  domain : String
  selection : String
  ranges : String
  input : String
  question : String
  output : String
  index : String
  deriving FromJson

private def receipt (path : String) : IO Json := do
  return (← read (.mk path)).getObjValD "data"

private def minimum (values : List Nat) : Option Nat :=
  values.foldl (fun found next => some (found.map (min next) |>.getD next)) none

private def intervals (source : String) (prefixChars : Nat) (ranks : List (Nat × Nat)) : List RankedCue :=
  ranks.filterMap fun (position,priority) =>
    (meaningContext? source prefixChars position priority).map fun found =>
      {priority,first := found.span.start,last := found.span.stop}

private def coversAll (rows : List (Nat × Nat)) (first last : Nat) : Bool :=
  last ≤ ((rows.mergeSort fun a b => a.1 ≤ b.1).foldl
    (fun frontier (a,b) => if a ≤ frontier then max frontier b else frontier) first)

/-- No frozen requirement or expected owner is accepted by this collection
entry. It reconstructs only the existing source domain and observed features;
neither the selector nor the numerical provider is called. -/
def collect (settings : Settings) : IO Unit := do
  let output := System.FilePath.mk settings.output
  check (!(← output.pathExists)) "preserve the earlier signal table"
  let source ← DB.PageMap.pin (.mk settings.database)
  let expected ← IO.ofExcept (fromJson? (α := DB.PageMap.Head) (← read (.mk settings.index)))
  let some shared ← Synapses.Index.openShared? source | throw (IO.userError "prepared source index is unavailable")
  check (shared.index.head == expected) "prepared index differs from the recorded hook"
  let domain ← receipt settings.domain
  let selected ← receipt settings.selection
  let prior ← receipt settings.ranges
  for name in ["candidateUnits","families","fixedCost","limit","scale","selected"] do
    check (selected.getObjValD name == prior.getObjValD name)
      s!"the archived range explanation differs from the actual selection: {name}"
  let rangeRows : Array Json ← field prior "rangeAudit"
  let nominated : Array String ← field domain "nominated"
  let hydrated : Array String ← field domain "hydrated"
  let focused : Array String ← field domain "focusRanking"
  let positions : Array (String × List Nat) ← field domain "focusPositions"
  let canonical : Array (String × Nat) ← field domain "canonicalUsed"
  let chosen : List Nat ← field selected "selected"
  let scale : Nat ← field selected "scale"
  let raw ← IO.ofExcept (fromJson? (α := SharedCoverage.Input.RawProblem) (← read (.mk settings.input)))
  let numeric ← IO.ofExcept raw.decode
  check (SharedCoverage.Input.ofProblem numeric == raw) "numeric input failed its checked round trip"
  check (toJson raw.limit == selected.getObjValD "limit" && toJson raw.fixed == selected.getObjValD "fixedCost")
    "numeric input belongs to a different budget"
  let reader ← NodeReader.new source
  let mut edges : Std.HashMap String OutcomeEdge := {}
  let mut documents : Std.HashMap String Extraction.Document := {}
  let mut provenance : Std.HashMap String (List SourceEvidence.Record) := {}
  for name in hydrated do
    let some id ← Synapses.Build.ownerId? source name | throw (IO.userError "recorded owner is no longer live")
    let edge ← reader.outcome (← reader.locateOutcome id)
    edges := edges.insert name edge
    documents := documents.insert name (← Synapses.Build.document reader id)
    provenance := provenance.insert name (← reader.sources id)
  let all ← reader.topology
  let authority ← Eggshell.Persistence.Store.authority source
  let persistent := (← reader.unions authority).map (·.edge)
  let parents := nominated.toList.zipIdx.filterMap fun (name,rank) => do
    let edge ← edges[name]?
    let text ← Matcher.atomText? edge.outcome
    if all.any (·.parent == edge.work) then some (rank,edge.work,text) else none
  let question ← IO.FS.readFile (.mk settings.question)
  let focusQuestion := evidenceFocusQuestion question
    (all.map fun edge => (Matcher.atomText? edge.parent).getD "")
  let terms := SearchRank.terms focusQuestion
  let some route ← Routing.Store.open? shared | throw (IO.userError "prepared routing is unavailable")
  let answers := nominated.mapIdx fun rank owner => (owner,rank)
  let consumers := hydrated.flatMap fun name =>
    match edges[name]? with
    | none => #[]
    | some edge => (Provenance.identities edge).flatMap fun occurrence => answers.filterMap fun (owner,rank) =>
        if owner == name then some (occurrence,rank) else none
  let roots := (answers.map fun (owner,rank) =>
    (Synapses.Index.Key.answer shared.manifest.source.identity owner,rank)) ++
    (consumers.map fun (occurrence,rank) => (Synapses.Index.Key.consumer occurrence,rank))
  let walked ← Routing.Store.walk route none roots ((← IO.monoMsNow)+120000)
  check walked.complete "the diagnostic graph walk did not complete"
  let hints := Routed.preferOmissions walked.hints
  let mut originOwners : Std.HashMap Original (List String) := {}
  for name in hydrated do
    let some doc := documents[name]? | throw (IO.userError "recorded graph owner was not loaded")
    if let some original := ObservationContext.OriginalOwner.prepare? doc then
      originOwners := originOwners.insert original.identity (name :: (originOwners[original.identity]?.getD []))
  let mut causeTexts : Std.HashMap Group String := {}
  for hint in hints do
    let some group := hint.group | continue
    if causeTexts.contains group then continue
    let text := (do
      let .claim claim := group | none
      let parent ← documents[claim.answer]?
      let text ← parent.source
      some (String.ofList (text.toList.drop claim.first |>.take (claim.limit-claim.first)))).getD ""
    causeTexts := causeTexts.insert group text
  let mut outputRanges : Std.HashMap String (Std.HashMap Range Nat) := {}
  let mut hintsByOwner : Std.HashMap String (List Routing.Store.Hint) := {}
  for hint in hints do
    let some target := hint.target.source? | continue
    let .original identity := target.subject | continue
    if !target.valid || target.last > identity.chars then continue
    for name in originOwners[identity]?.getD [] do
      let old := outputRanges[name]?.getD {}
      outputRanges := outputRanges.insert name (old.insert target (min hint.priority (old[target]?.getD hint.priority)))
      hintsByOwner := hintsByOwner.insert name (hint :: (hintsByOwner[name]?.getD []))
  let mut families := #[]
  let mut unitOffset := 0
  let mut inspectedUnits := 0
  for row in rangeRows do
    let id : Nat ← field row "id"
    let name : String ← field row "owner"
    let count : Nat ← field row "candidateUnits"
    let some doc := documents[name]? | throw (IO.userError "recorded family owner was not loaded")
    let some edge := edges[name]? | throw (IO.userError "recorded family edge was not loaded")
    let focus := (positions.find? (·.1 == name)).map Prod.snd |>.getD []
    let admitted := parents.filterMap fun (rank,work,text) =>
      if (sourceNeighborhood [work] all persistent).any (·.work == edge.work) then some (rank,text) else none
    let references := rankedCitedObservationCoordinates admitted edge (provenance[name]?.getD [])
    let referencePositions := references.map (fun (_,p,_,_) => p) |>.getD []
    let referenceRanks := references.map (fun (_,_,r,_) => r) |>.getD []
    let ranges := (outputRanges[name]?.getD {}).toArray.qsort fun a b =>
      if a.1.first == b.1.first then a.1.last < b.1.last else a.1.first < b.1.first
    let outputs : List Synapses.Transport.OutputRange := ranges.toList.map fun (span,priority) =>
      {priority,first := span.first-1,limit := span.last,path := none}
    let graph := hintsByOwner[name]?.getD []
    let rawText := doc.source.getD ""
    let frame := doc.workText.getD ""
    let direct := intervals rawText (frame.length+1) focus.zipIdx
    let reference := intervals rawText (frame.length+1) referenceRanks
    let common := Json.mkObj [
      ("id",toJson id),("owner",toJson name),("work",toJson doc.work),("native",toJson doc.native),
      ("ownerFocusRank",toJson (focused.toList.idxOf? name)),("focusWindows",toJson focus),
      ("referenceWindows",toJson referenceRanks),("originalGraphRanges",toJson outputs.length),
      ("canonicalRows",toJson ((canonical.find? (·.1 == name)).map Prod.snd |>.getD 0)),
      ("candidateUnits",toJson count),("selectedUnits",row.getObjValD "selectedUnits"),
      ("rawCharacters",toJson rawText.length),("workCharacters",toJson frame.length),
      ("graphHints",toJson (graph.reverse.map fun hint => Json.mkObj [
        ("source",toJson hint.target.source?),("priority",toJson hint.priority),
        ("kind",toJson (Routing.Store.kindName hint.kind)),("cause",toJson hint.group),
        ("rootOwner",toJson ((answers.find? (·.2 == hint.priority)).map Prod.fst)),
        ("causeText",toJson (hint.group.bind (causeTexts[·]?))),
        ("evidence",toJson hint.evidence)]))]
    if canonical.any (·.1 == name) || !doc.native then
      families := families.push (common.setObjVal! "unitAudit" (toJson "not-reconstructed-canonical-or-nonnative"))
      unitOffset := unitOffset+count
      continue
    let some geometry ← ObservedRecordView.geometry? shared.index source.head.identity name ((← IO.monoMsNow)+120000) |
      throw (IO.userError "an original geometry is missing")
    let context : ContextDelivery := {
      owner := name,outcome := relationKey edge.outcome,sourceChars := rawText.length,
      cues := [],leading := "",trailing := "",fragments := []}
    let family : Family := {
      owner := edge,template := {keys := [],text := "",context := some context,members := [],visibleKeys := []},
      windows := focus,references := referencePositions,referenceRanks,outputRanges := outputs,
      original := some geometry.spans}
    let units := (prepare id family).1.toArray
    check (units.size == count) s!"original candidate reconstruction differs for {name}: {units.size}/{count}"
    let allCues := rankedCues family
    let endpoints := ((units.toList.flatMap fun unit => unit.ranges.flatMap fun (a,b) => [a,b]) ++
      allCues.flatMap (fun cue => [cue.first,cue.last])).eraseDups.mergeSort (· ≤ ·)
    let pieces := (endpoints.zip (endpoints.drop 1)).filterMap fun (first,last) => do
      if first ≥ last then none else do
        let cue ← coveringCue? allCues first last
        let weight := (last-first)*(scale/(61+id)+scale/(61+cue.priority))
        some (first,last,cue.priority,weight)
    let texts := rawText.toList.toArray
    let mut unitRows := #[]
    for position in [:units.size] do
      let some unit := units[position]? | throw (IO.userError "missing reconstructed candidate")
      let index := unitOffset+position
      let some offer := numeric.offers[index]? | throw (IO.userError "unit lacks its actual numeric offer")
      let value := offer.covers.eraseDups.foldl (fun total cue => total+numeric.weights[cue]) 0
      let calculated := pieces.foldl (fun total (a,b,_,weight) =>
        if unit.coversPrepared a b then total+weight else total) 0
      check (value == calculated) s!"reconstructed cue value differs for {name}/{position}"
      let cost := offer.closure.eraseDups.foldl (fun total atom =>
        (total.1+numeric.costs[atom].1,total.2+numeric.costs[atom].2)) (0,0)
      let spans := unit.ranges.map fun (first,last) => Id.run do
        let text := String.ofList (texts.extract first last).toList
        return Json.mkObj [("first",toJson first),("limit",toJson last),("original",toJson text),
          ("questionTerms",toJson (terms.filter (SearchRank.terms text).contains)),
          ("directOverlapRanks",toJson (direct.filterMap fun (cue : RankedCue) =>
            if cue.first < last && first < cue.last then some cue.priority else none)),
          ("referenceOverlapRanks",toJson (reference.filterMap fun (cue : RankedCue) =>
            if cue.first < last && first < cue.last then some cue.priority else none))]
      unitRows := unitRows.push (Json.mkObj [("id",toJson index),("ranges",toJson spans),
        ("standaloneCost",toJson cost),("actualValue",toJson (toString value)),
        ("sameReconstructedValue",toJson true),("selected",toJson (chosen.contains index))])
      inspectedUnits := inspectedUnits+1
    let atomRows := pieces.map fun (first,last,priority,weight) =>
      let directRank := (coveringCue? direct first last).map (fun (cue : RankedCue) => cue.priority)
      let referenceRank := (coveringCue? reference first last).map (fun (cue : RankedCue) => cue.priority)
      let graphRank := minimum (outputs.filterMap fun (span : Synapses.Transport.OutputRange) =>
        if span.first ≤ first && last ≤ span.limit then some span.priority else none)
      Json.mkObj [("first",toJson first),("limit",toJson last),("directRank",toJson directRank),
        ("referenceRank",toJson referenceRank),("graphRank",toJson graphRank),
        ("actualBestRank",toJson priority),("actualValue",toJson (toString weight)),
        ("directStrictlyDominated",toJson (directRank.any (priority < ·)))]
    families := families.push (common.setObjVal! "unitAudit" (toJson "exact-original-ranges-and-base-values")
      |>.setObjVal! "units" (toJson unitRows) |>.setObjVal! "atoms" (toJson atomRows))
    unitOffset := unitOffset+count
  let expectedUnits : Nat ← field selected "candidateUnits"
  check (unitOffset == expectedUnits) "candidate family offsets do not cover the actual domain"
  IO.FS.createDirAll output.parent.get!
  IO.FS.writeFile output (Json.mkObj [
    ("source",toJson source.head),("index",toJson shared.index.head),("question",toJson question),
    ("focusQuestion",toJson focusQuestion),("questionTerms",toJson terms),
    ("routing",Json.mkObj [("nodes",toJson walked.nodes),("arcs",toJson walked.arcs),
      ("complete",toJson walked.complete),("hints",toJson hints.size)]),
    ("originalUnitsValueChecked",toJson inspectedUnits),("families",toJson families),
    ("usesFrozenLabels",toJson false),("selectorCalls",toJson (0 : Nat)),
    ("answeringModelCalls",toJson (0 : Nat)),("warmCalls",toJson (0 : Nat)),
    ("productionLatencyClaim",toJson false),("adopted",toJson false)]).compress
  check ((← DB.PageMap.pin (.mk settings.database)).head == source.head) "the read-only diagnosis changed the source"
  IO.println (Json.mkObj [("families",toJson families.size),("originalUnitsValueChecked",toJson inspectedUnits),
    ("routingNodes",toJson walked.nodes),("routingArcs",toJson walked.arcs),("output",toJson settings.output)]).compress

end Eggshell.Research.EvidenceSignalJoin

def main (args : List String) : IO Unit := do
  let [settings] := args | throw (IO.userError "one settings file, without frozen labels")
  Eggshell.Research.EvidenceSignalJoin.collect
    (← IO.ofExcept (Json.parse (← IO.FS.readFile (.mk settings)) >>=
      fromJson? (α := Eggshell.Research.EvidenceSignalJoin.Settings)))
