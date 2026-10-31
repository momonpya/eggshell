def fileUnits (query : FileQuery) (stored : Synapses.CanonicalSource.Recipe.Stored)
    (layout : Synapses.CanonicalSource.Recipe.Checked stored.rows)
    (base : Synapses.PreparedFileUnits.Ready query.owner stored.rows layout) : Array ServiceUnit :=
  (Synapses.PreparedFileUnits.combine query.owner stored.rows layout base query.groups).filterMap fun unit => do
    if unit.indices.isEmpty then none else some {
      shape := {family := query.family,ranges := unit.ranges}
      sourceKeys := unit.rows.map (·.key) }

def filePieces (scale : Nat) (query : FileQuery) (rows : Array Synapses.CanonicalSource.StoredRow) : List CuePiece :=
  let base := rankCoefficients scale query.family query.baseCues
  let all := rankCoefficients scale query.family query.allCues
  rows.toList.flatMap fun row =>
    (cachedBindings query.owner #[row]).filterMap fun (first,last) =>
      let baseWeight := evaluateCoefficients first last base
      let weight := max baseWeight (evaluateCoefficients first last all)
      if weight == 0 then none else some {
        family := query.family,first,last,weight,baseWeight,sourceKey := some row.key}

def problemFromPrepared (query : ServiceQuery) (source : Eggshell.Research.PreparedSourceCosts.Data)
    (units : Array ServiceUnit) (pieces : List CuePiece) : Option SharedCoverage.Problem := do
  let costs := source.costs ++ query.genericCosts
  let directory := cueDirectory pieces
  let weights := directory.2.flatMap fun (base,total) => #[base,total-base]
  let indexedPieces := pieces.zipIdx.toArray
  let pieceIndex := PreparedCueIndex.prepare cueFamilyKey indexedPieces
  let offers ← units.mapM fun unit => do
    let mut closure := [unit.shape.family]
    if let some id := unit.generic then
      let input ← query.generic[id]?
      closure := closure ++ input.payloads.map (source.costs.size+·)
    else
      for key in unit.sourceKeys do
        let file ← source.fileIds[key.file]?
        let payload ← source.rowIds[key]?
        closure := file :: payload :: closure
    let typedClosure ← closure.mapM fun id =>
      if h : id < costs.size then some (⟨id,h⟩ : Fin costs.size) else none
    let matching := pieceIndex.one (toString unit.shape.family) fun entry =>
      entry.1.baseWeight > 0 && entry.1.family == unit.shape.family &&
        unit.shape.ranges.any (fun (a,b) => a ≤ entry.1.first && entry.1.last ≤ b)
    let covers ← matching.mapM fun (_,id) => do
      let cue ← directory.1[id]?
      if h : cue*2 < weights.size then some (⟨cue*2,h⟩ : Fin weights.size) else none
    return ({closure := typedClosure,covers} : SharedCoverage.Offer costs.size weights.size)
  return {costs,weights,offers,fixed := query.fixed,limit := query.ceiling}

/-- The original selector consumes coordinate/cost stencils. No candidate
tool body or native Match is serialized, and final packet fitting is local. -/
def selectPrepared (query : ServiceQuery) (units : Array ServiceUnit)
    (pieces : List CuePiece) (originalRows : Array Synapses.CanonicalSource.StoredRow) : Option ServiceChoice := do
  let source := (Eggshell.Research.PreparedSourceCosts.prepare originalRows query.frameCosts).data
  let p ← problemFromPrepared query source units pieces
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
  let compiled := ClosedCoverage.compile p recipes
  let bound ← Eggshell.Research.PreparedSourceCosts.bind source p
  let requirements := bound.requirements
  let scopes ← Eggshell.Research.ScopeAlternatives.prepareUsingFrames compiled query.owners.size
    requirements.sourceRows requirements.dependencies bound.frames
  let conditioned := scopes.problem
  let chosen ← SharedCoverage.choose? conditioned
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
  return {
    generic,sourceKeys,receipt
    selectorInput := if query.captureInput then some (SharedCoverage.Input.encode conditioned) else none}
