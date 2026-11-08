import Eggshell.Handoff
import Eggshell.CanonicalSourceCache

open Lean Eggshell Eggshell.Plugin Eggshell.Plugin.SharedRangeAdapter
open Eggshell.Synapses Eggshell.Synapses.CanonicalSource

namespace SelectorStructure

def check (valid : Bool) (message : String) : IO Unit :=
  unless valid do throw (IO.userError message)

def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= (IO.ofExcept ∘ Json.parse)

def sourceFiles (root : System.FilePath) : IO (Array (String × String)) := do
  let entries := (← root.readDir).qsort (fun a b => a.fileName < b.fileName)
  entries.mapM fun entry => do
    check ((← entry.path.metadata).type == .file) "expected a source-only frozen project"
    let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",entry.path.toString]}
    check (result.exitCode == 0) "cannot hash original source"
    return (entry.fileName,(result.stdout.splitOn " ").headD "")

/-- Logical cardinalities only. They are neither live heap bytes nor a
native benchmark. Do not encode the large problem just to count its entries. -/
def counts (p : SharedCoverage.Problem) : Json :=
  Json.mkObj [("costs",toJson p.costs.size),("weights",toJson p.weights.size),
    ("offers",toJson p.offers.size),
    ("closureEntries",toJson (p.offers.foldl (fun n offer => n+offer.closure.length) 0)),
    ("coverEntries",toJson (p.offers.foldl (fun n offer => n+offer.covers.length) 0)),
    ("maxClosure",toJson (p.offers.foldl (fun n offer => max n offer.closure.length) 0)),
    ("maxCovers",toJson (p.offers.foldl (fun n offer => max n offer.covers.length) 0))]

@[noinline, nospecialize] def inspect (choose : Bool) (expected : ServiceChoice)
    (query : ServiceQuery) (units : Array ServiceUnit) (pieces : List CuePiece)
    (source : PreparedSourceView.Domain) : Option Json := do
  let p ← problemFromView query source units pieces
  let shapes := units.map (·.shape)
  let reach := ownerReach query.owners shapes
  let mut candidates : Std.HashMap Synapses.Range (List (List (Fin shapes.size))) := {}
  for projected in query.bundles do
    for member in projected.members do
      unless candidates.contains member.source do
        candidates := candidates.insert member.source (memberChoices query.owners shapes reach member)
  let directory := cueDirectory pieces
  let entries := pieces.zipIdx.toArray
  let index := PreparedCueIndex.prepare cueBucketKey entries
  let recipe := bundleRecipeIndexed? query.owners shapes entries index directory p
  let recipes := ClosedCoverage.original p ++ (query.bundles.filterMap fun bundle =>
    (bundlePlan? query.owners shapes p candidates bundle).bind recipe)
  let compiled := ClosedCoverage.compile p recipes
  let bound ← PreparedSourceView.bind source p
  let scopes ← PreparedSourceView.prepareScopes source compiled query.owners.size
    ⟨bound.sourceRows,bound.frames⟩
  let selection ← if choose then do
      let chosen ← SharedCoverage.choose? scopes.problem
      let selectedRecipes := chosen.selected.filterMap fun index =>
        if h : index.val < compiled.offers.size then some (⟨index.val,h⟩ : Fin compiled.offers.size) else none
      let expanded := (ClosedCoverage.expand p recipes selectedRecipes).map (·.val) |>.eraseDups
      let requiredRows := bound.selectedRows ((SharedCoverage.nodes scopes.problem chosen.selected).map (·.val))
      let mut selectedKeys := Std.HashSet.ofArray (requiredRows.map (·.key))
      let mut generic := #[]
      for index in expanded do
        let unit ← units[index]?
        if let some id := unit.generic then generic := generic.push id
        else for key in unit.sourceKeys do selectedKeys := selectedKeys.insert key
      let sourceKeys := source.rows.filterMap fun row => if selectedKeys.contains row.key then some row.key else none
      pure (Json.mkObj [("selectedOffers",toJson chosen.selected.length),
        ("expandedOffers",toJson expanded.length),("genericUnits",toJson generic.size),
        ("sourceKeys",toJson sourceKeys.size),
        ("matchesSavedChoice",toJson (generic == expected.generic && sourceKeys == expected.sourceKeys))])
    else pure Json.null
  return Json.mkObj [("units",toJson units.size),("pieces",toJson pieces.length),
    ("unitRangeEntries",toJson (units.foldl (fun n unit => n+unit.shape.ranges.length) 0)),
    ("unitSourceKeys",toJson (units.foldl (fun n unit => n+unit.sourceKeys.size) 0)),
    ("sourceRows",toJson source.rows.size),("files",toJson source.files.size),
    ("base",counts p),("compiled",counts compiled),("conditioned",counts scopes.problem),
    ("selection",selection)]

/-- Reconstruct the same single-source, immutable coordinate domain consumed
by selectSourcePlan. No model, ranking, authority or product hook is invoked. -/
def runObserved (observe : Bool → ServiceChoice → ServiceQuery → Array ServiceUnit → List CuePiece →
    PreparedSourceView.Domain → IO (Option Json))
    (choose : Bool) (project fixture output : System.FilePath) : IO Unit := do
  check (!(← output.pathExists)) "preserve the structure observation"
  let before ← sourceFiles project
  let original ← DB.PageMap.pin project
  let directory ← Cache.directory original .user
  let current ← DB.PageMap.pin (directory/"recipes")
  let recipes := (← PreparedRoot.select? original current).getD current
  let some header ← Cache.header? recipes | throw (IO.userError "prepared original metadata missing")
  check (← Index.sameSources original header.source) "prepared original source changed"
  let examples ← IO.ofExcept ((← read fixture).getArr?)
  check (examples.size == 3) "all three saved queries required"
  let mut owners : Std.HashMap String PreparedSourceView.OwnerReady := {}
  let mut observations := #[]
  for (sampleRow,ordinal) in examples.zipIdx do
    let heads ← IO.ofExcept (sampleRow.getObjValAs? (Array DB.PageMap.Head) "heads")
    check (heads.size == 1 && heads[0]? == some original.head) "diagnostic supports this exact single-source fixture"
    let query ← IO.ofExcept (fromJson? (sampleRow.getObjValD "query") : Except String ServiceQuery)
    let expected ← IO.ofExcept (fromJson? (sampleRow.getObjValD "choice") : Except String ServiceChoice)
    check (query.valid && !query.captureInput) "preserve the saved selector input"
    let families := Std.HashMap.ofArray (query.files.map fun file => (file.family,file))
    let generic := KeyPostings.prepare (fun entry : GenericUnit × Nat => entry.1.family) query.generic.zipIdx
    let genericPieces := KeyPostings.prepare (fun piece : CuePiece => piece.family) query.pieces.toArray
    let mut units := #[]
    let mut pieces := []
    let mut rows := #[]
    let mut headers : Std.HashMap Synapses.File PreparedSourceView.FileReady := {}
    for family in [:query.owners.size] do
      if let some file := families[family]? then
        let ready ← match owners[file.owner]? with
          | some ready => pure ready
          | none => PreparedSourceView.readOwner recipes original.head.identity file.owner
        owners := owners.insert file.owner ready
        for source in ready.stored.descriptor.files do
          unless headers.contains source do headers := headers.insert source (PreparedSourceView.fileReady source)
        for (source,extents) in ready.stored.scopes do
          let some header := headers[source]? | throw (IO.userError "scope lacks published file header")
          headers := headers.insert source (header.addExtents extents)
        let joined ← IO.ofExcept (PreparedSourceView.join ready.rows headers)
        let prepared ← IO.ofExcept (PreparedSourceView.federatedUnits file.owner #[ready] joined file.groups)
        for unit in prepared do
          units := units.push {shape := {family,ranges := unit.ranges,coverage := unit.coverage},sourceKeys := unit.keys}
        pieces := pieces ++ viewPieces query.scale file joined
        rows := rows ++ joined
      else pieces := pieces ++ (genericPieces.lookup family).toList
      for (unit,index) in generic.lookup family do
        units := units.push {shape := {family,ranges := unit.ranges},generic := some index,contextual := unit.contextual}
    let joined ← IO.ofExcept (PreparedSourceView.join rows headers)
    let source ← IO.ofExcept (PreparedSourceView.domain joined headers query.frameCosts)
    let allocated ← IO.getNumHeartbeats
    let began ← IO.monoNanosNow
    let some observation ← observe choose expected query units pieces source |
      throw (IO.userError "saved query did not produce its problem domains")
    let elapsed := (← IO.monoNanosNow)-began
    let allocationDelta := (← IO.getNumHeartbeats)-allocated
    if choose then
      check ((observation.getObjValD "selection").getObjValD "matchesSavedChoice" == toJson true)
        "the current selector differs from the saved complete choice"
    observations := observations.push (Json.mkObj [("query",toJson (ordinal+1)),("structure",observation),
      ("inspectNanos",toJson elapsed),("inspectHeartbeatDeltaNotBytes",toJson allocationDelta)])
  check ((← sourceFiles project) == before) "structure inspection changed the frozen project"
  IO.FS.writeFile output (Json.mkObj [("queries",toJson observations),("sourceFiles",toJson before),
    ("originalSourceUnchanged",toJson true),("execution",toJson "matching native core; logical counts only"),
    ("actualNewHookCalls",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat)),
    ("selectionExecuted",toJson choose),("fullHookOrAdoptionClaim",toJson false),
    ("singleDiagnosticPairNotLatencyDistribution",toJson true),("adopted",toJson false)]).compress

def run (choose : Bool) (project fixture output : System.FilePath) : IO Unit :=
  runObserved (fun choose expected query units pieces source => pure (inspect choose expected query units pieces source))
    choose project fixture output

end SelectorStructure
