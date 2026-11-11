module
public import tools.research.PreparedSelectorIncidence
@[expose] public section
namespace Eggshell.Research.PreparedViewSelector
open Lean Eggshell.Plugin Eggshell.Plugin.SharedRangeAdapter

def selectUsing (query : ServiceQuery) (units : Array ServiceUnit)
    (pieces : List CuePiece) (source : Synapses.PreparedSourceView.Domain)
    (build : Option SharedCoverage.Problem)
    (makeRecipe : (directory : Array Nat × Array (Nat × Nat)) →
      (p : SharedCoverage.Problem) → BundlePlan query.owners (units.map (·.shape)) → Option (ClosedCoverage.Recipe p)) :
    Option ServiceChoice := do
  let p ← build
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
  let recipe := makeRecipe cueIndex p
  let recipes := ClosedCoverage.original p ++ (query.bundles.filterMap fun projected =>
    (bundlePlan? keys shapes p candidates projected).bind recipe)
  let compiled := ClosedCoverage.compile p recipes
  let bound ← Synapses.PreparedSourceView.bind source p
  let requirements := bound
  let scopes ← Synapses.PreparedSourceView.prepareScopes source compiled query.owners.size ⟨bound.sourceRows,bound.frames⟩
  let conditioned := scopes.problem
  let chosen ← SharedCoverage.OwnedAdvance.chooseOwned conditioned
  let selectedRecipes := chosen.selected.filterMap fun index =>
    if h : index.val < compiled.offers.size then some (⟨index.val,h⟩ : Fin compiled.offers.size) else none
  let expanded := (ClosedCoverage.expand p recipes selectedRecipes).map (·.val) |>.eraseDups
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
    ("jointBindings",Json.mkObj [("sourceDomainAudit",Json.null),("sources",toJson candidates.size),
      ("fragmentedAlternatives",toJson fragmented),("uncoveredSources",toJson uncovered),
      ("projectedBundles",toJson query.bundles.size),("preparedBundles",toJson (recipes.size-p.offers.size)),
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
    receipt := receipt.setObjVal! "bindingAudit" (toJson bindingAudit)
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




theorem recipe_function_exact (keys : Array String) (ready : PreparedSelectorIncidence.Bonus shapes entries)
    (reference : PreparedCueIndex.Prepared cueBucketKey entries.toArray)
    (directory : Array Nat × Array (Nat × Nat)) (p : SharedCoverage.Problem) :
    PreparedSelectorIncidence.recipe keys ready directory p =
      bundleRecipeIndexed? keys shapes entries.toArray reference directory p := by
  funext plan
  exact PreparedSelectorIncidence.recipe_exact keys ready reference directory p plan

def referenceRecipes (keys : Array String) (pieces : List CuePiece) (shapes : Array UnitShape)
    (directory : Array Nat × Array (Nat × Nat)) (p : SharedCoverage.Problem) :=
  let entries := pieces.zipIdx.toArray
  let index := PreparedCueIndex.prepare cueBucketKey entries
  bundleRecipeIndexed? keys shapes entries index directory p

def reference (query : ServiceQuery) (units : Array ServiceUnit) (pieces : List CuePiece)
    (source : Synapses.PreparedSourceView.Domain) : Option ServiceChoice :=
  selectUsing query units pieces source (problemFromView query source units pieces)
    (referenceRecipes query.owners pieces (units.map (·.shape)))

theorem reference_exact (query : ServiceQuery) (units : Array ServiceUnit) (pieces : List CuePiece)
    (source : Synapses.PreparedSourceView.Domain) :
    reference query units pieces source = SharedRangeAdapter.selectView query units pieces source := by
  rfl

structure Geometry (units : Array ServiceUnit) where
  base : RangeIncidence.Resolver (RangeIncidence.Geometry Nat) (RangeIncidence.Coordinate Nat)
    (PreparedSelectorIncidence.BaseRelation units)
  bonus : RangeIncidence.Resolver (Fin (units.map (·.shape)).size) (RangeIncidence.Coordinate Nat)
    (PreparedSelectorIncidence.covered (units.map (·.shape)))

def prepareGeometry (units : Array ServiceUnit) : Geometry units :=
  ⟨PreparedSelectorIncidence.baseResolver units,
    PreparedSelectorIncidence.coverageResolver (units.map (·.shape))⟩

def borrowedRecipes (keys : Array String) (shapes : Array UnitShape) (pieces : List CuePiece)
    (bonus : PreparedSelectorIncidence.Bonus shapes pieces.zipIdx)
    (directory : Array Nat × Array (Nat × Nat)) (p : SharedCoverage.Problem) :=
  PreparedSelectorIncidence.recipe keys bonus directory p

theorem borrowed_recipes_exact (keys : Array String) (shapes : Array UnitShape) (pieces : List CuePiece) (bonus) :
    borrowedRecipes keys shapes pieces bonus = referenceRecipes keys pieces shapes := by
  funext directory p
  exact recipe_function_exact _ _ (PreparedCueIndex.prepare cueBucketKey pieces.zipIdx.toArray) _ _

theorem selectUsing_bind (query : ServiceQuery) (units : Array ServiceUnit) (pieces : List CuePiece)
    (source : Synapses.PreparedSourceView.Domain) (build : Option SharedCoverage.Problem) (makeRecipe) :
    (do let p ← build; selectUsing query units pieces source (some p) makeRecipe) =
      selectUsing query units pieces source build makeRecipe := by
  cases build <;> rfl

/-- A service lends geometry tied to this checked view. This path builds
only query-weighted postings, never the structural trees. -/
def chooseWith (query : ServiceQuery) (units : Array ServiceUnit) (pieces : List CuePiece)
    (source : Synapses.PreparedSourceView.Domain) (geometry : Geometry units) : Option ServiceChoice := do
  let base := PreparedSelectorIncidence.prepareBase geometry.base pieces.zipIdx
  let p ← PreparedSelectorIncidence.problem query source units pieces base
  -- A factory returning a function can be eta-expanded through its final
  -- Plan argument. Pass the prepared data across that boundary instead.
  let bonus := PreparedSelectorIncidence.prepareBonus geometry.bonus pieces.zipIdx
  selectUsing query units pieces source (some p)
    (borrowedRecipes query.owners (units.map (·.shape)) pieces bonus)

theorem chooseWith_exact (query : ServiceQuery) (units : Array ServiceUnit) (pieces : List CuePiece)
    (source : Synapses.PreparedSourceView.Domain) (geometry : Geometry units) :
    chooseWith query units pieces source geometry = SharedRangeAdapter.selectView query units pieces source := by
  dsimp only [chooseWith]
  rw [PreparedSelectorIncidence.problem_exact]
  simp only [borrowed_recipes_exact]
  rw [selectUsing_bind]
  exact reference_exact query units pieces source

#print axioms reference_exact
#print axioms borrowed_recipes_exact
#print axioms chooseWith_exact
end Eggshell.Research.PreparedViewSelector
