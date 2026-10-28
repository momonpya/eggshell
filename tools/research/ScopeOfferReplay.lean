import tools.research.ReferenceRequirements
import Eggshell.CanonicalSourceCache
import tools.SharedCoverageInput
import tools.VerifiedWinnerCoverage
import Lean.Data.Json.Parser

open Lean Eggshell Eggshell.Synapses Eggshell.Synapses.CanonicalSource
open Eggshell.Research.ReferenceRequirements

private def require (value : Bool) (message : String) : IO Unit := do
  unless value do throw (IO.userError message)

private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

private def field [FromJson α] (value : Json) (name : String) : IO α :=
  IO.ofExcept (value.getObjValAs? α name)

private def covers (ranges : List (Nat × Nat)) (first last : Nat) : Bool :=
  last ≤ ((ranges.mergeSort fun a b => a.1 ≤ b.1).foldl
    (fun frontier (a,b) => if a ≤ frontier then max frontier b else frontier) first)

private def shapes (rows : Array StoredRow) : Array (Block rows.size) := Id.run do
  let order := (List.finRange rows.size).mergeSort fun a b =>
    if rows[a].key.file == rows[b].key.file then rows[a].key.line ≤ rows[b].key.line
    else (toJson rows[a].key.file).compress ≤ (toJson rows[b].key.file).compress
  let mut run : Array (Char × Fin rows.size) := #[]
  let mut previous : Option (Fin rows.size) := none
  let mut tokens := #[]
  let mut runId := 0
  for index in order do
    let row := rows[index]
    if !(previous.any fun prior => rows[prior].key.file == row.key.file && rows[prior].key.line+1 == row.key.line) then
      tokens := tokens ++ lex run runId
      run := #[]
      runId := runId+1
    run := run ++ ((row.code ++ "\n").toList.toArray.map (fun c => (c,index)))
    previous := some index
  blocks (tokens ++ lex run runId)

/-- No query or expected ranges enter construction. Existing cue credit is
available only after paying every atom of its existing conditioned offer. -/
private def alternatives (p : SharedCoverage.Problem) (familyCount : Nat)
    (prepared : Prepared p) : IO (Array (SharedCoverage.Offer p.costs.size p.weights.size) × Json) := do
  let rows := prepared.sourceRows.map Prod.fst
  let sourceAtoms := Std.HashSet.ofArray (prepared.sourceRows.map Prod.snd)
  let mut frames : Std.HashMap File (Fin p.costs.size) := {}
  for (row,atom) in prepared.sourceRows do
    if frames.contains row.key.file then continue
    let index := atom.val-1
    let frame := Packet.fileFrame row.key.file (rows.filter (·.key.file == row.key.file))
    require (0 < atom.val && p.costs[index]? == some
      ((frame.leading ++ frame.trailing).length,(frame.leading ++ frame.trailing).utf8ByteSize))
      "scope frame differs from the actual payload basis"
    if h : index < p.costs.size then frames := frames.insert row.key.file ⟨index,h⟩
    else throw (IO.userError "scope frame outside the payload basis")
  let freeFrames := (List.finRange p.costs.size).filter fun atom =>
    atom.val < familyCount && p.costs[atom] == (0,0)
  let mut byAnchor : Std.HashMap (Fin p.costs.size) (List (Fin p.offers.size)) := {}
  for index in List.finRange p.offers.size do
    if let some anchor := p.offers[index].closure.find? sourceAtoms.contains then
      byAnchor := byAnchor.insert anchor (index :: byAnchor[anchor]?.getD [])
  let candidates := shapes rows
  let mut offers := #[]
  let mut reports := #[]
  let mut inspected := 0
  for shape in candidates do
    let first := rows[shape.first].key
    let last := rows[shape.last].key
    let body := prepared.sourceRows.filter fun (row,_) => row.key.file == first.file &&
      first.line ≤ row.key.line && row.key.line ≤ last.line
    require (body.size == last.line+1-first.line) "a scope crosses a source gap"
    let some frame := frames[first.file]? | throw (IO.userError "scope has no source frame")
    let atoms := frame :: body.toList.map Prod.snd
    let closure := hashDistinct (freeFrames ++ atoms ++ atoms.flatMap
      (fun atom => prepared.dependencies[atom]?.getD []))
    let paid := Std.HashSet.ofList closure
    let possible := hashDistinct (closure.flatMap (fun atom => byAnchor[atom]?.getD []))
    inspected := inspected+possible.length
    let included := possible.filter fun index => p.offers[index].closure.all paid.contains
    let covers := hashDistinct (included.flatMap fun index => p.offers[index].covers)
    if covers.isEmpty then continue
    let charge := closure.foldl (fun total atom =>
      (total.1 + p.costs[atom].1,total.2 + p.costs[atom].2)) p.fixed
    if p.limit.1 < charge.1 || p.limit.2 < charge.2 then continue
    require (included.all fun index => p.offers[index].closure.all paid.contains)
      "a scope obtained credit without the existing payload requirements"
    offers := offers.push {closure,covers}
    reports := reports.push (Json.mkObj [("first",toJson first),("last",toJson last),
      ("rows",toJson body.size),("atoms",toJson closure.length),("standaloneCost",toJson charge),
      ("containedOffers",toJson (included.map (·.val))),("cues",toJson covers.length)])
  return (offers,Json.mkObj [("recognizedScopes",toJson candidates.size),
    ("addedScopes",toJson offers.size),("indexedContainmentChecks",toJson inspected),
    ("creditRequiresFullExistingClosure",toJson true),("scopes",toJson reports)])

private def covered (rows : Array StoredRow) (alternatives : Array Range) : Bool :=
  alternatives.any fun range => match range.subject with
  | .original _ => false
  | .file file => (List.range (range.last+1-range.first)).all fun offset => rows.any fun row =>
      row.key.file == file && row.key.line == range.first+offset

def main (args : List String) : IO Unit := do
  let [database,tracePath,ordinaryPath,output] := args |
    throw (IO.userError "DATABASE ACTUAL-TRACE ORDINARY-REPORTS NEW-OUTPUT")
  require (!(← System.FilePath.pathExists output)) "preserve earlier scope replay"
  let source ← DB.PageMap.pin (.mk database)
  let some ready ← Cache.open? source .database | throw (IO.userError "canonical view is not prepared")
  let mut topics := #[]
  for topic in [1:4] do
    let data := (← read (.mk tracePath / s!"topic-{topic}/selection-plan.json")).getObjValD "data"
    let audit : Array Json ← field data "rangeAudit"
    let names ← audit.mapM fun row => field (α := String) row "owner"
    let owners := Std.HashSet.ofArray names
    let rows ← IO.ofExcept (Delivery.merge (ready.registry.store.filterMap fun row =>
      let origins := row.origins.filter fun origin => owners.contains origin.binding.owner
      if origins.isEmpty then none else some {row with origins}))
    let raw : SharedCoverage.Input.RawProblem ← IO.ofExcept (fromJson? (data.getObjValD "selectorInput"))
    let p ← IO.ofExcept raw.decode
    let mappingStarted ← IO.monoMsNow
    let some prepared := prepare owners.size rows p | throw (IO.userError "actual source atom cost mismatch")
    require ((prepared.offers p.offers).map SharedCoverage.Input.ofOffer == raw.offers)
      "trace offers are not already closed under the frozen reference requirements"
    let mappingMs := (← IO.monoMsNow)-mappingStarted
    let baselineStarted ← IO.monoMsNow
    let some baseline := SharedCoverage.choose? p | throw (IO.userError "baseline selection failed")
    let baselineMs := (← IO.monoMsNow)-baselineStarted
    -- The receipt's `selected` names expanded base units; selectorInput names
    -- compiled recipes. Compare physical original rows in the common basis.
    let mut actualRanges : Std.HashMap String (List (Nat × Nat)) := {}
    for row in audit do
      let owner : String ← field row "owner"
      let shared : List (Nat × Nat) ← field row "selectedSharedRanges"
      let original : List (Nat × Nat) ← field row "selectedOriginalRanges"
      actualRanges := actualRanges.insert owner (shared ++ original)
    let baselineRows := prepared.selectedRows ((SharedCoverage.nodes p baseline.selected).map (·.val))
    let actualKeys := Std.HashSet.ofArray (rows.filterMap fun row =>
      if row.origins.any (fun origin => covers (actualRanges[origin.binding.owner]?.getD [])
          origin.binding.first origin.binding.limit) then some row.key else none)
    let baselineKeys := Std.HashSet.ofArray (baselineRows.map (·.key))
    require (actualKeys.size == baselineKeys.size && actualKeys.toList.all baselineKeys.contains)
      "baseline source payload replay differs from actual original bindings"
    let preparationStarted ← IO.monoMsNow
    let (extra,construction) ← alternatives p owners.size prepared
    let candidate : SharedCoverage.Problem := {p with offers := p.offers ++ extra}
    require ((candidate.offers.extract 0 p.offers.size).map SharedCoverage.Input.ofOffer == raw.offers)
      "original offer order or conditions changed"
    let preparationMs := (← IO.monoMsNow)-preparationStarted
    let candidateStarted ← IO.monoMsNow
    let some chosen := SharedCoverage.choose? candidate | throw (IO.userError "scope alternative selection failed")
    let candidateMs := (← IO.monoMsNow)-candidateStarted
    let selectedRows := prepared.selectedRows ((SharedCoverage.nodes candidate chosen.selected).map (·.val))
    -- Expected evidence is first read after both selections, solely for audit.
    let frozen ← read (.mk ordinaryPath / s!"topic-{topic}/audit-report.json")
    let units : Array Json ← field (frozen.getObjValD "frozenEvidence") "units"
    let actual : Array Json ← field frozen "requirements"
    let requirements ← units.mapM fun unit => do
      let labels : Array String ← field unit "names"
      let ranges : Array Range ← field unit "alternatives"
      require (covered rows ranges) "frozen evidence has no complete file alternative in the source basis"
      let before := covered baselineRows ranges
      require (before == (labels.all fun name => actual.any fun row => row.getObjValD "name" == toJson name &&
        row.getObjValD "bodyDelivered" == toJson true)) "baseline source selection differs from actual delivery"
      return Json.mkObj [("names",toJson labels),("baseline",toJson before),("candidate",toJson (covered selectedRows ranges))]
    topics := topics.push (Json.mkObj [("topic",toJson topic),("actualSourcePayloadMatches",toJson true),
      ("originalOffersUnchanged",toJson true),("mappingMs",toJson mappingMs),("constructionMs",toJson preparationMs),
      ("baselineSelectionMs",toJson baselineMs),("candidateSelectionMs",toJson candidateMs),
      ("baselineCost",toJson (SharedCoverage.cost p baseline.selected)),
      ("candidateCost",toJson (SharedCoverage.cost candidate chosen.selected)),
      ("selectedScopes",toJson (chosen.selected.filter (p.offers.size ≤ ·.val) |>.map (·.val))),
      ("construction",construction),("requirements",toJson requirements),
      ("candidateSourceRows",toJson (selectedRows.map (·.key)))])
    IO.println s!"Completed model-free scope replay for topic {topic}"
  IO.FS.writeFile output (Json.mkObj [("source",toJson source.head),("canonical",toJson ready.metadata),
    ("topics",toJson topics),("actualDeliveryAsserted",toJson false),("productionAdoption",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("warmCalls",toJson (0 : Nat))]).pretty
