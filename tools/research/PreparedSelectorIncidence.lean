module
public import tools.research.ProductRangeIncidence
public import Std.Data.HashSet.Lemmas
@[expose] public section

namespace Eggshell.Research.PreparedSelectorIncidence
open Eggshell.Plugin Eggshell.Plugin.SharedRangeAdapter
open Eggshell.Research.RangeIncidence

/-- This catalogue belongs to one checked view. Geometry sharing neither
merges its Work/cost nodes nor supplies cross-snapshot identity. -/
def geometry (unit : ServiceUnit) : Geometry Nat := ⟨unit.shape.family,unit.shape.ranges⟩

def catalogue (units : Array ServiceUnit) : List (Geometry Nat) :=
  (Std.HashSet.ofList (units.toList.map geometry)).toList

theorem catalogue_mem (units : Array ServiceUnit) (unit : ServiceUnit) (present : unit ∈ units) :
    geometry unit ∈ catalogue units := by
  simp only [catalogue,Std.HashSet.mem_toList,Std.HashSet.mem_ofList,List.contains_iff_mem]
  exact List.mem_map.mpr ⟨unit,by simpa using present,rfl⟩

abbrev Entry := CuePiece × Nat

def accept (unit : ServiceUnit) (entry : Entry) : Bool :=
  entry.1.baseWeight > 0 && entry.1.family == unit.shape.family &&
    unit.shape.ranges.any (fun (first,last) => first ≤ entry.1.first && entry.1.last ≤ last)

def BaseRelation (units : Array ServiceUnit) :=
  RangeIncidence.baseAccept (catalogue units) (fun shape => shape.scope) (fun shape => shape.ranges)

/-- Forward postings are prepared once for the whole cue list. In particular,
matching below never builds an interval tree or reverses a posting. -/
structure Base (units : Array ServiceUnit) (entries : List Entry) where
  forward : Forward (BaseRelation units) (ProductRangeIncidence.requests entries)

def baseResolver (units : Array ServiceUnit) :
    Resolver (Geometry Nat) (Coordinate Nat) (BaseRelation units) :=
  resolveBase (catalogue units) (·.scope) (·.ranges)

/-- The caller lends an already prepared structural index. This function
cannot rebuild it from the request's weights. -/
def prepareBase (index : Resolver (Geometry Nat) (Coordinate Nat) (BaseRelation units))
    (entries : List Entry) : Base units entries :=
  ⟨index.finish (ProductRangeIncidence.requests entries)⟩

def Base.matching (ready : Base units entries) (unit : ServiceUnit) : List Entry :=
  (ready.forward.table.getD (geometry unit) []).map FactoredIncidence.Request.value

theorem Base.matching_exact (ready : Base units entries) (unit : ServiceUnit) (present : unit ∈ units) :
    ready.matching unit = entries.filter (accept unit) := by
  rw [Base.matching,Forward.exact]
  clear ready
  have admitted := catalogue_mem units unit present
  simp only [geometry] at admitted
  simp only [ProductRangeIncidence.requests,BaseRelation,RangeIncidence.baseAccept,
    geometry,admitted,decide_true,Bool.true_and]
  induction entries with
  | nil => rfl
  | cons entry rest ih =>
    simp only [List.map_cons,List.filter_cons]
    simp only [accept,Bool.and_assoc] at *
    split <;> simp_all

/-- A pointwise refinement is required on every original unit, including
generic observations. No top-K subset can discharge this premise. -/
theorem mapM_equal_on [Monad m] [LawfulMonad m] (xs : Array α) (f g : α → m β)
    (same : ∀ x ∈ xs,f x = g x) : xs.mapM f = xs.mapM g := by
  have lists : ∀ values : List α,(∀ x ∈ values,f x = g x) → values.mapM f = values.mapM g := by
    intro values
    induction values with
    | nil => intro _; rfl
    | cons first rest ih =>
      intro same
      simp only [List.mapM_cons,same first (by simp),ih (by
        intro x present
        exact same x (by simp [present]))]
  rw [Array.mapM_eq_mapM_toList,Array.mapM_eq_mapM_toList]
  exact congrArg (List.toArray <$> ·) (lists xs.toList (by simpa using same))

/-- Only the base incidence lookup changes. All source/generic cost closures,
duplicate entries, directory IDs and failure paths are retained verbatim. -/
def problem (query : ServiceQuery) (source : Synapses.PreparedSourceView.Domain)
    (units : Array ServiceUnit) (pieces : List CuePiece) (ready : Base units pieces.zipIdx) :
    Option SharedCoverage.Problem := do
  let costs := source.costs ++ query.genericCosts
  let directory := cueDirectory pieces
  let weights := directory.2.flatMap fun (base,total) => #[base,total-base]
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
    let covers ← (ready.matching unit).mapM fun (_,id) => do
      let cue ← directory.1[id]?
      if h : cue*2 < weights.size then some (⟨cue*2,h⟩ : Fin weights.size) else none
    return ({closure := typedClosure,covers} : SharedCoverage.Offer costs.size weights.size)
  return {costs,weights,offers,fixed := query.fixed,limit := query.ceiling}

theorem reference_matching (entries : Array Entry)
    (index : PreparedCueIndex.Prepared cueFamilyKey entries) (unit : ServiceUnit) :
    index.one (toString unit.shape.family) (accept unit) = entries.toList.filter (accept unit) := by
  apply PreparedCueIndex.Prepared.one_exact
  intro entry accepted
  simp only [accept,Bool.and_eq_true,beq_iff_eq] at accepted
  simp only [cueFamilyKey,accepted.1.2]

theorem problem_exact (query : ServiceQuery) (source : Synapses.PreparedSourceView.Domain)
    (units : Array ServiceUnit) (pieces : List CuePiece) (ready : Base units pieces.zipIdx) :
    problem query source units pieces ready = problemFromView query source units pieces := by
  unfold problem problemFromView
  dsimp only
  congr 1
  apply mapM_equal_on
  intro unit present
  rw [ready.matching_exact unit present]
  rw [show (fun entry : Entry => entry.1.baseWeight > 0 && entry.1.family == unit.shape.family &&
      unit.shape.ranges.any (fun (a,b) => a ≤ entry.1.first && entry.1.last ≤ b)) = accept unit from rfl]
  rw [reference_matching,List.toList_toArray]
  rfl

/-- The citation-side predicate depends on the cue family, not on whichever
unit happens to establish coverage. It can be evaluated once per bundle/cue. -/
def supported (keys : Array String) (plan : BundlePlan keys shapes) (entry : Entry) : Bool :=
  plan.projected.members.any fun member => member.choices.any fun bound =>
    keys[entry.1.family]? == some bound.owner && covers bound.spans entry.1.first entry.1.last

def unitCovered (shapes : Array UnitShape) (entry : Entry) (index : Fin shapes.size) : Bool :=
  shapes[index].family == entry.1.family && shapes[index].coversPrepared entry.1.first entry.1.last

theorem bonus_factored (keys : Array String) (shapes : Array UnitShape)
    (plan : BundlePlan keys shapes) (entry : Entry) :
    bonusPieceAccept keys shapes plan entry =
      (entry.1.baseWeight < entry.1.weight &&
        plan.indices.any (unitCovered shapes entry) && supported keys plan entry) := by
  apply Bool.eq_iff_iff.mpr
  simp only [bonusPieceAccept,unitCovered,supported,Bool.and_eq_true,List.any_eq_true]
  constructor
  · rintro ⟨positive,index,present,covered,bound⟩
    have family : shapes[index.val].family = entry.1.family := beq_iff_eq.mp covered.1
    exact ⟨⟨positive,index,present,covered⟩,by simpa only [Fin.getElem_fin,family] using bound⟩
  · rintro ⟨⟨positive,index,present,covered⟩,bound⟩
    have family : shapes[index.val].family = entry.1.family := beq_iff_eq.mp covered.1
    exact ⟨positive,index,present,covered,by simpa only [Fin.getElem_fin,family] using bound⟩

def covered (shapes : Array UnitShape) (index : Fin shapes.size) (coordinate : Coordinate Nat) : Bool :=
  shapes[index].family == coordinate.scope && shapes[index].coversPrepared coordinate.first coordinate.last

/-- One union-coverage index for the entire checked view, not one per bundle.
The first-point lookup only proposes candidates; the old exact union test
admits them. This includes intervals crossing adjacent raw ranges. -/
def coverageResolver (shapes : Array UnitShape) :
    Resolver (Fin shapes.size) (Coordinate Nat) (covered shapes) :=
  let raw := resolveBase (List.finRange shapes.size) (fun i => shapes[i].family) (fun i => shapes[i].ranges)
  (raw.comap ProductRangeIncidence.firstPoint).refine (covered shapes) (by
    intro index coordinate accepted
    have pair := Bool.and_eq_true_iff.mp accepted
    have ordered : coordinate.first < coordinate.last := by
      by_cases ordered : coordinate.first < coordinate.last
      · exact ordered
      · simp [UnitShape.coversPrepared,ordered] at pair
    have whole : covers shapes[index].ranges coordinate.first coordinate.last = true := by
      simpa only [UnitShape.prepared_covers_exact] using pair.2
    obtain ⟨span,present,inside⟩ := covers_position _ _ _ coordinate.first whole ⟨Nat.le_refl _,ordered⟩
    simp only [RangeIncidence.baseAccept,ProductRangeIncidence.firstPoint,List.mem_finRange,
      decide_true,Bool.true_and]
    apply Bool.and_eq_true_iff.mpr
    refine ⟨by simpa only [beq_iff_eq] using Eq.symm (beq_iff_eq.mp pair.1),?_⟩
    apply List.any_eq_true.mpr
    exact ⟨span,present,by simp [inside.1,Nat.le_of_lt inside.2]⟩)

structure CoveredEntry (shapes : Array UnitShape) where
  entry : Entry
  indices : List (Fin shapes.size)
  exact : ∀ index,index ∈ indices ↔ unitCovered shapes entry index = true

def CoveredEntry.key (row : CoveredEntry shapes) : String := cueBucketKey row.entry

structure Bonus (shapes : Array UnitShape) (entries : List Entry) where
  rows : List (CoveredEntry shapes)
  original : rows.map CoveredEntry.entry = entries
  buckets : PreparedCueIndex.Prepared CoveredEntry.key rows.toArray

def prepareBonus (index : Resolver (Fin shapes.size) (Coordinate Nat) (covered shapes))
    (entries : List Entry) : Bonus shapes entries :=
  let rows := entries.map fun entry => ({
    entry,indices := index.neighbors ⟨entry.1.family,entry.1.first,entry.1.last⟩
    exact := by intro unit; exact index.exact _ unit } : CoveredEntry shapes)
  {rows,original := by simp [rows,Function.comp_def],buckets := PreparedCueIndex.prepare CoveredEntry.key rows.toArray}

def CoveredEntry.accept (keys : Array String) (plan : BundlePlan keys shapes)
    (row : CoveredEntry shapes) : Bool :=
  let selected := Std.HashSet.ofList plan.indices
  row.entry.1.baseWeight < row.entry.1.weight && row.indices.any selected.contains && supported keys plan row.entry

theorem CoveredEntry.accept_exact (keys : Array String) (plan : BundlePlan keys shapes)
    (row : CoveredEntry shapes) : row.accept keys plan = bonusPieceAccept keys shapes plan row.entry := by
  have intersection : row.indices.any (Std.HashSet.ofList plan.indices).contains =
      plan.indices.any (unitCovered shapes row.entry) := by
    apply Bool.eq_iff_iff.mpr
    simp only [List.any_eq_true,Std.HashSet.contains_ofList,List.contains_iff_mem,row.exact]
    constructor
    · rintro ⟨index,covered,present⟩; exact ⟨index,present,covered⟩
    · rintro ⟨index,present,covered⟩; exact ⟨index,covered,present⟩
  rw [CoveredEntry.accept,intersection,bonus_factored]

def bonus (keys : Array String) (ready : Bonus shapes entries) (plan : BundlePlan keys shapes) : List Entry :=
  -- Capture the set outside the predicate closure, once for this bundle.
  let selected := Std.HashSet.ofList plan.indices
  (ready.buckets.many (plan.indices.flatMap fun i => shapes[i].bucketKeys cueBucketWidth)
    (fun row => row.entry.1.baseWeight < row.entry.1.weight && row.indices.any selected.contains &&
      supported keys plan row.entry)).map CoveredEntry.entry

theorem bonus_exact (keys : Array String) (ready : Bonus shapes entries) (plan : BundlePlan keys shapes)
    (reference : PreparedCueIndex.Prepared cueBucketKey entries.toArray) :
    bonus keys ready plan = bonusPiecesPrepared keys shapes entries.toArray reference plan := by
  unfold bonus
  change (ready.buckets.many _ (CoveredEntry.accept keys plan)).map CoveredEntry.entry = _
  rw [PreparedCueIndex.Prepared.many_exact]
  · rw [List.toList_toArray]
    have same : CoveredEntry.accept keys plan = bonusPieceAccept keys shapes plan ∘ CoveredEntry.entry := by
      funext row
      exact row.accept_exact keys plan
    rw [same]
    rw [← List.filter_map,ready.original,bonus_pieces_exact,List.toList_toArray]
  · intro row accepted
    have accepted' := accepted
    rw [CoveredEntry.accept_exact] at accepted'
    have pair := (Bool.and_eq_true_iff.mp accepted').2
    obtain ⟨index,present,matched⟩ := List.any_eq_true.mp pair
    have matchPair := (Bool.and_eq_true_iff.mp matched).1
    have family := beq_iff_eq.mp (Bool.and_eq_true_iff.mp matchPair).1
    have inside := (Bool.and_eq_true_iff.mp matchPair).2
    apply List.mem_flatMap.mpr
    refine ⟨index,present,?_⟩
    simpa only [CoveredEntry.key,cueBucketKey,cueFamilyKey,family] using
      shapes[index].covered_first_bucket cueBucketWidth row.entry.1.first row.entry.1.last inside

def recipe (keys : Array String) (ready : Bonus shapes entries)
    (directory : Array Nat × Array (Nat × Nat)) (p : SharedCoverage.Problem)
    (plan : BundlePlan keys shapes) : Option (ClosedCoverage.Recipe p) := do
  let parts ← plan.indices.mapM fun i =>
    if h : i.val < p.offers.size then some (⟨i.val,h⟩ : Fin p.offers.size) else none
  let bonus ← (bonus keys ready plan).mapM fun (_,id) => do
    let cue ← directory.1[id]?
    if h : cue*2+1 < p.weights.size then some (⟨cue*2+1,h⟩ : Fin p.weights.size) else none
  pure {parts,bonus}

theorem recipe_exact (keys : Array String) (ready : Bonus shapes entries)
    (reference : PreparedCueIndex.Prepared cueBucketKey entries.toArray)
    (directory : Array Nat × Array (Nat × Nat)) (p : SharedCoverage.Problem) (plan : BundlePlan keys shapes) :
    recipe keys ready directory p plan = bundleRecipeIndexed? keys shapes entries.toArray reference directory p plan := by
  simp only [recipe,bundleRecipeIndexed?,bonus_exact keys ready plan reference]

/-- Source geometry and query-created groups may be indexed separately. Only
the added part needs a new tree; the immutable base and old readers survive.
This proves append-only composition, not arbitrary edits or compaction. -/
def appendResolver [BEq S] [LawfulBEq S] [Hashable S] [BEq U] [LawfulBEq U]
    (prior added : List U) (scope : U → S) (ranges : U → List (Nat × Nat))
    (left : Resolver U (Coordinate S) (RangeIncidence.baseAccept prior scope ranges))
    (right : Resolver U (Coordinate S) (RangeIncidence.baseAccept added scope ranges)) :
    Resolver U (Coordinate S) (RangeIncidence.baseAccept (prior++added) scope ranges) :=
  ⟨(fun coordinate => left.neighbors coordinate ++ right.neighbors coordinate),by
    intro coordinate unit
    rw [List.mem_append,left.exact,right.exact]
    simp only [RangeIncidence.baseAccept,Bool.and_eq_true,decide_eq_true_eq,List.mem_append]
    constructor
    · rintro (⟨⟨present,same⟩,inside⟩ | ⟨⟨present,same⟩,inside⟩)
      · exact ⟨⟨Or.inl present,same⟩,inside⟩
      · exact ⟨⟨Or.inr present,same⟩,inside⟩
    · rintro ⟨⟨present,same⟩,inside⟩
      rcases present with present | present
      · exact Or.inl ⟨⟨present,same⟩,inside⟩
      · exact Or.inr ⟨⟨present,same⟩,inside⟩⟩

theorem appended_projection_exact [BEq S] [LawfulBEq S] [Hashable S]
    [BEq U] [LawfulBEq U] [Hashable U]
    (prior added : List U) (scope : U → S) (ranges : U → List (Nat × Nat))
    (left : Resolver U (Coordinate S) (RangeIncidence.baseAccept prior scope ranges))
    (right : Resolver U (Coordinate S) (RangeIncidence.baseAccept added scope ranges))
    (requests : List (FactoredIncidence.Request (Coordinate S) A)) (unit : U) :
    ((appendResolver prior added scope ranges left right).project requests).lookup unit =
      requests.filter (fun request => request.active &&
        RangeIncidence.baseAccept (prior++added) scope ranges unit request.coordinate) :=
  Resolver.project_exact _ _ _

#print axioms catalogue_mem
#print axioms Base.matching_exact
#print axioms problem_exact
#print axioms bonus_factored
#print axioms coverageResolver
#print axioms CoveredEntry.accept_exact
#print axioms bonus_exact
#print axioms recipe_exact
#print axioms appended_projection_exact
end Eggshell.Research.PreparedSelectorIncidence
