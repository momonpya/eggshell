import Main
import Eggshell.ContractAudit
import tools.research.StudyRuntime
import tools.SharedCoverageInput
import tools.research.AvailableDelivery
open Lean Eggshell Eggshell.DB Eggshell.Research Eggshell.Synapses Eggshell.Synapses.CanonicalSource
namespace ScopeUnionProbe
structure Plan where
  source : String
  sourceFiles : Array (String × String)
  owners : Array String
  expectedHead : Json
  diagnostic : String
  evidence : String
  output : String
  deriving FromJson
def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)
def read (path : String) : IO Json := IO.FS.readFile (.mk path) >>= (IO.ofExcept ∘ Json.parse)
def verify (plan : Plan) : IO Unit := do
  for (name,expected) in plan.sourceFiles do
    check ((← ArtifactHash.hex (.mk plan.source/name)) == expected) "original source bytes changed"
def run (input : String) : IO Unit := do
  let plan ← IO.ofExcept (fromJson? (α := Plan) (← read input))
  check (!(← System.FilePath.pathExists plan.output)) "preserve the canonical-scope audit"
  verify plan
  let source ← PageMap.pin (.mk plan.source)
  check (toJson source.head == plan.expectedHead) "pinned original head changed"
  let diagnostic ← read plan.diagnostic
  let captured := diagnostic.getObjValD "signals/diagnostic/selection.json"
  check ((diagnostic.getObjValD "signals/diagnostic/validation.json").getObjValD "sameOrdinaryBody" == toJson true)
    "selector witness is not bound to an actual body"
  let raw : SharedCoverage.Input.RawProblem ← IO.ofExcept (captured.getObjValAs? _ "selectorInput")
  let p ← IO.ofExcept raw.decode
  let witness := captured.getObjValD "selectionWitness"
  let owners : Array String ← IO.ofExcept (witness.getObjValAs? _ "owners")
  check (owners.toList.eraseDups.length == owners.size && owners.size == plan.owners.size &&
    owners.all plan.owners.contains) "query owner domain changed"
  let nodeKeys : Array (Nat × Key) ← IO.ofExcept (witness.getObjValAs? _ "sourceNodes")
  let actualNodes : Array Nat ← IO.ofExcept (witness.getObjValAs? _ "selectedSourceNodes")
  let reader ← Persistence.Store.NodeReader.new source
  let started ← IO.monoMsNow
  let mut merged : Std.HashMap Key StoredRow := {}
  let mut oldExtents : Std.HashSet (File × Nat × Nat) := {}
  let mut observedOwners := 0
  for entry in ← Build.entries source do
    let document ← Build.document reader entry.id
    unless owners.contains document.owner do continue
    observedOwners := observedOwners+1
    let original ← if document.native then do
      let (registry,_) ← addPublishedDocument source entry.id document {} {}
      IO.ofExcept (Recipe.compile registry.store)
    else pure (⟨#[],[]⟩ : Recipe.Stored)
    let layout ← IO.ofExcept (Recipe.check original.rows original.records)
    let metadata := PreparedSourceView.ownerStored document.owner original layout
    for (file,extents) in metadata.scopes do
      for extent in extents do oldExtents := oldExtents.insert (file,extent.first,extent.last)
    for row in original.rows do
      if let some previous := merged[row.key]? then
        check (previous.code == row.code) "original canonical aliases disagree"
        merged := merged.insert row.key {previous with
          origins := (hashDistinct (previous.origins.toList++row.origins.toList)).toArray}
      else merged := merged.insert row.key row
  check (observedOwners == owners.size && merged.size == nodeKeys.size) "source projection differs from actual domain"
  let sourceRows ← nodeKeys.mapM fun (node,key) => do
    let some row := merged[key]? | throw (IO.userError "actual source atom has no original")
    check (p.costs[node]? == some ((Packet.rowText row).length,(Packet.rowText row).utf8ByteSize))
      "original row differs from captured rendering cost"
    if h : node < p.costs.size then return (row,(⟨node,h⟩ : Fin p.costs.size))
    else throw (IO.userError "source atom escaped the finite cost domain")
  let mut firstAtoms : Std.HashMap File Nat := {}
  for (row,node) in sourceRows do
    firstAtoms := firstAtoms.insert row.key.file (min node.val (firstAtoms[row.key.file]?.getD node.val))
  let mut frames : Std.HashMap File (Fin p.costs.size) := {}
  for (file,first) in firstAtoms.toArray do
    let rows := sourceRows.filterMap fun (row,_) => if row.key.file == file then some row else none
    let frame := Packet.fileFrame file rows
    let text := frame.leading++frame.trailing
    check (first > 0 && p.costs[first-1]? == some (text.length,text.utf8ByteSize)) "captured source frame cost differs"
    if h : first-1 < p.costs.size then frames := frames.insert file ⟨first-1,h⟩
    else throw (IO.userError "source frame escaped its finite cost domain")
  let some baseline := SharedCoverage.OwnedAdvance.chooseOwned p | throw (IO.userError "baseline selector rejected")
  let before := Std.HashSet.ofList ((SharedCoverage.nodes p baseline.selected).map (·.val))
  let reproduced := nodeKeys.filterMap fun (node,_) => if before.contains node then some node else none
  let actual := Std.HashSet.ofArray actualNodes
  check (reproduced.size == actual.size && reproduced.all actual.contains) "native replay differs from actual source selection"
  let construction ← IO.monoMsNow
  let some prepared := ScopeAlternatives.prepareUsingFrames p owners.size sourceRows {} frames |
    throw (IO.userError "canonical scope preparation rejected original rows")
  let additional := prepared.scopes.filter fun scope => !oldExtents.contains (scope.first.file,scope.first.line,scope.last.line)
  for scope in additional do
    let paid := Std.HashSet.ofList scope.offer.closure
    check (scope.contained.all fun index => p.offers[index].closure.all paid.contains)
      "new scope obtained credit without original payload conditions"
  let constructionMs := (← IO.monoMsNow)-construction
  let candidate : SharedCoverage.Problem := {p with offers := p.offers++additional.map (·.offer)}
  check ((candidate.offers.extract 0 p.offers.size).map SharedCoverage.Input.ofOffer == raw.offers &&
    candidate.costs == p.costs && candidate.weights == p.weights && candidate.limit == p.limit && candidate.fixed == p.fixed)
    "canonical scope changed original offers, costs, values or bounds"
  let beganChoice ← IO.monoMsNow
  let some chosen := SharedCoverage.OwnedAdvance.chooseOwned candidate | throw (IO.userError "canonical-scope selector rejected")
  let chosenMs := (← IO.monoMsNow)-beganChoice
  let after := Std.HashSet.ofList ((SharedCoverage.nodes candidate chosen.selected).map (·.val))
  let ranges := fun (selected : Std.HashSet Nat) => sourceRows.filterMap fun (row,atom) =>
    if selected.contains atom.val then some (⟨.file row.key.file,row.key.line,row.key.line⟩ : Range) else none
  -- Frozen labels enter only after both deterministic selections finish.
  let evidence ← read plan.evidence
  let frozen : AvailableDelivery.Frozen ← IO.ofExcept
    (((evidence.getObjValD "llvm/before-delivery.json").getObjValD "topics").getArr? >>= fun topics =>
      (topics[0]?.getD Json.null).getObjValAs? _ "frozen")
  let assessedBefore := AvailableDelivery.assess frozen (ranges before)
  let assessedAfter := AvailableDelivery.assess frozen (ranges after)
  let expected := ((evidence.getObjValD "llvm/result.json").getObjValD "queries").getArr?.toOption.getD #[]
  check (toJson assessedBefore == ((expected[0]?.getD Json.null).getObjValD "assessment").getObjValD "availableDelivery")
    "canonical baseline coverage differs from independently audited actual body"
  verify plan
  let newScopes := additional.map fun scope => Json.mkObj [("first",toJson scope.first),("last",toJson scope.last),
    ("rows",toJson scope.rows),("containedOffers",toJson scope.contained.length)]
  IO.FS.writeFile (.mk plan.output) (Json.mkObj [("sourceHead",toJson source.head),
    ("owners",toJson owners.size),("originalRows",toJson merged.size),("ownerExtents",toJson oldExtents.size),
    ("canonicalScopesRecognized",toJson prepared.recognized),("canonicalScopesAffordable",toJson prepared.scopes.size),
    ("additionalScopes",toJson newScopes),("constructionMs",toJson constructionMs),("selectionMs",toJson chosenMs),
    ("baselineActualNodesReproduced",toJson true),("originalProblemUnchanged",toJson true),
    ("before",toJson assessedBefore),("after",toJson assessedAfter),
    ("beforeCost",toJson (SharedCoverage.cost p baseline.selected)),
    ("afterCost",toJson (SharedCoverage.cost candidate chosen.selected)),
    ("selectedNewScopes",toJson (chosen.selected.filter (fun index => p.offers.size ≤ index.val) |>.map (·.val))),
    ("elapsedMs",toJson ((← IO.monoMsNow)-started)),("sourceHashesBeforeAndAfter",toJson true),
    ("actualDeliveryAsserted",toJson false),("queryOrModelCalled",toJson false),("cacheCreated",toJson false),
    ("productChanged",toJson false),("adopted",toJson false)]).compress
end ScopeUnionProbe
def main : List String → IO Unit
  | [input] => ScopeUnionProbe.run input
  | _ => throw (IO.userError "ScopeUnionProbe PLAN")
