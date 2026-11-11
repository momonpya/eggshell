module
public import Eggshell.Handoff
@[expose] public section
namespace Eggshell.Research.RealSelectionStages
open Lean Eggshell Plugin SharedRangeAdapter

structure Bundles (p : SharedCoverage.Problem) where
  recipes : Array (ClosedCoverage.Recipe p)
  sources : Nat
  fragmented : Nat
  uncovered : Nat
  bindingAudit : Array Json

def bundleStage (query : ServiceQuery) (units : Array ServiceUnit)
    (pieces : List CuePiece) (p : SharedCoverage.Problem) : Option (Bundles p) := do
  let keys := query.owners
  let shapes := units.map (·.shape)
  let reach := ownerReach keys shapes
  let mut candidates : Std.HashMap Synapses.Range (List (List (Fin shapes.size))) := {}
  let mut fragmented := 0
  let mut uncovered := 0
  let mut bindingAudit := #[]
  for projected in query.bundles do
    for member in projected.members do
      if candidates.contains member.source then continue
      let choices := memberChoices keys shapes reach member
      fragmented := fragmented+choices.countP (fun choice => choice.length > 1)
      if choices.isEmpty then uncovered := uncovered+1
      if query.captureRanges then
        bindingAudit := bindingAudit.push (Json.mkObj [("source",toJson member.source),
          ("owners",toJson (memberOwners member)),("alternatives",toJson (choices.map (·.map (·.val))))])
      candidates := candidates.insert member.source choices
  let cueIndex := cueDirectory pieces
  let indexedPieces := pieces.zipIdx.toArray
  let pieceIndex := PreparedCueIndex.prepare cueBucketKey indexedPieces
  let recipe := bundleRecipeIndexed? keys shapes indexedPieces pieceIndex cueIndex p
  let recipes := ClosedCoverage.original p ++ (query.bundles.filterMap fun projected =>
    (bundlePlan? keys shapes p candidates projected).bind recipe)
  return ⟨recipes,candidates.size,fragmented,uncovered,bindingAudit⟩

structure Ready where
  problem : SharedCoverage.Problem
  finish : SharedCoverage.Selection problem → Option ServiceChoice
  scopes : Nat
  recognized : Nat
  containmentChecks : Nat

def scopeStage (query : ServiceQuery) (units : Array ServiceUnit)
    (pieces : List CuePiece) (source : Synapses.PreparedSourceView.Domain)
    (p : SharedCoverage.Problem) (bundles : Bundles p) : Option Ready := do
  let compiled := ClosedCoverage.compile p bundles.recipes
  let bound ← Synapses.PreparedSourceView.bind source p
  let requirements := bound
  let scopes ← Synapses.PreparedSourceView.prepareScopes source compiled query.owners.size ⟨bound.sourceRows,bound.frames⟩
  let conditioned := scopes.problem
  return {
    problem := conditioned
    scopes := scopes.scopes.size
    recognized := scopes.recognized
    containmentChecks := scopes.containmentChecks
    finish := fun chosen => do
      let selectedRecipes := chosen.selected.filterMap fun index =>
        if h : index.val < compiled.offers.size then some (⟨index.val,h⟩ : Fin compiled.offers.size) else none
      let expanded := (ClosedCoverage.expand p bundles.recipes selectedRecipes).map (·.val) |>.eraseDups
      let requiredRows := requirements.selectedRows ((SharedCoverage.nodes conditioned chosen.selected).map (·.val))
      let mut selectedKeys := Std.HashSet.ofArray (requiredRows.map (·.key))
      let mut generic := #[]
      for index in expanded do
        let unit ← units[index]?
        if let some id := unit.generic then generic := generic.push id
        else for key in unit.sourceKeys do selectedKeys := selectedKeys.insert key
      let sourceKeys := source.rows.filterMap fun row => if selectedKeys.contains row.key then some row.key else none
      let mut receipt := Json.mkObj [("families",toJson query.owners.size),("candidateUnits",toJson units.size),
        ("selected",toJson expanded),("fixedCost",toJson p.fixed),("limit",toJson p.limit),
        ("scale",toJson query.scale),("fullCandidateAudit",toJson false),
        ("jointBindings",Json.mkObj [("sourceDomainAudit",Json.null),("sources",toJson bundles.sources),
          ("fragmentedAlternatives",toJson bundles.fragmented),("uncoveredSources",toJson bundles.uncovered),
          ("projectedBundles",toJson query.bundles.size),("preparedBundles",toJson (bundles.recipes.size-p.offers.size)),
          ("selectedBundles",toJson (chosen.selected.countP (fun index => p.offers.size ≤ index.val)))]),
        ("requiredSourceRows",toJson requiredRows.size)]
      if query.captureRanges then
        let selected := Std.HashSet.ofList expanded
        let directory := KeyPostings.prepare (fun entry : ServiceUnit × Nat => entry.1.shape.family) units.zipIdx
        let packed := fun ranges => (CoverageIndex.prepare ranges).intervals.map fun span => (span.start,span.stop)
        let families := query.owners.mapIdx fun id owner => Id.run do
          let entries := (directory.lookup id).toList
          let chosen := entries.filter fun entry => selected.contains entry.2
          let required := requiredRows.toList.flatMap fun row => row.origins.toList.filterMap fun origin =>
            if origin.binding.owner == owner then some (origin.binding.first,origin.binding.limit) else none
          let ranges := fun values => values.flatMap fun entry : ServiceUnit × Nat => entry.1.shape.ranges
          let positive := entries.filterMap fun (_,index) => do
            let offer ← p.offers[index]?
            unless offer.covers.any (fun cue => 0 < p.weights[cue]) do none
            let cost := offer.closure.eraseDups.foldl (fun total node =>
              (total.1+p.costs[node].1,total.2+p.costs[node].2)) (0,0)
            some (index,cost.1,cost.2)
          let charge := fun (_id,chars,bytes) => max (chars*p.limit.2) (bytes*p.limit.1)
          let cheapest := positive.foldl (fun found next => match found with
            | none => some next
            | some previous => if charge next < charge previous then some next else found)
            (none : Option (Nat × Nat × Nat))
          return Json.mkObj [("id",toJson id),("owner",toJson owner),
            ("work",toJson ((query.works[id]?).map Prod.fst |>.getD "")),
            ("canonicalRows",toJson (source.rows.countP (fun row => row.origins.any (·.binding.owner == owner)))),
            ("frameCost",toJson p.costs[id]?),
            ("workChars",toJson ((query.works[id]?).map Prod.snd |>.getD 0)),
            ("positiveBaseOffers",toJson positive.length),("minimumPositiveStandalone",toJson cheapest),
            ("candidateUnits",toJson entries.length),("selectedUnits",toJson chosen.length),
            ("candidateRanges",toJson (packed (ranges entries))),("selectedRanges",toJson (packed (ranges chosen ++ required))),
            ("candidateOriginalRanges",toJson (packed (ranges (entries.filter (·.1.contextual))))),
            ("candidateSharedRanges",toJson (packed (ranges (entries.filter (fun entry => !entry.1.sourceKeys.isEmpty))))),
            ("selectedOriginalRanges",toJson (packed (ranges (chosen.filter (·.1.contextual))))),
            ("selectedSharedRanges",toJson (packed (ranges (chosen.filter (fun entry => !entry.1.sourceKeys.isEmpty)) ++ required)))]
        receipt := receipt.setObjVal! "bindingAudit" (toJson bundles.bindingAudit)
          |>.setObjVal! "rangeAudit" (toJson families)
          |>.setObjVal! "rangeAuditKind" (toJson "planned-original-positions")
          |>.setObjVal! "assertsActualDelivery" (toJson false)
      if query.captureInput then
        let sourceNodes := source.rows.map fun row => (source.rowIds[row.key]?,row.key)
        let unitRows := units.map fun unit => Json.arr #[toJson unit.shape.family,toJson unit.shape.ranges,
          toJson (unit.sourceKeys.map fun key => source.rowIds[key]?),toJson unit.generic]
        let pieceRows := pieces.toArray.map fun piece => Json.arr #[toJson piece.family,toJson piece.first,toJson piece.last,
          toJson piece.baseWeight,toJson piece.weight,toJson (piece.sourceKey.bind (source.rowIds[·]?))]
        receipt := receipt.setObjVal! "selectionWitness" (Json.mkObj [
          ("owners",toJson query.owners),("works",toJson query.works),("sourceNodes",toJson sourceNodes),
          ("selectedSourceNodes",toJson (sourceKeys.map (source.rowIds[·]?))),
          ("units",Json.arr unitRows),("pieces",Json.arr pieceRows),("files",toJson query.files),
          ("compiledSelected",toJson (chosen.selected.map (·.val)))])
      return {
        generic,sourceKeys,receipt
        selectorInput := if query.captureInput then some (SharedCoverage.Input.encode conditioned) else none}
  }

def select (query : ServiceQuery) (units : Array ServiceUnit)
    (pieces : List CuePiece) (source : Synapses.PreparedSourceView.Domain) : Option ServiceChoice := do
  let p ← problemFromView query source units pieces
  let bundles ← bundleStage query units pieces p
  let ready ← scopeStage query units pieces source p bundles
  let chosen ← SharedCoverage.OwnedAdvance.chooseOwned ready.problem
  ready.finish chosen

theorem select_exact : @select = @selectView := by
  funext query units pieces source
  simp only [select,bundleStage,scopeStage,selectView,bind_assoc,pure_bind]
  rfl

#print axioms select_exact
end Eggshell.Research.RealSelectionStages
