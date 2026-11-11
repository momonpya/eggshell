module
public import Eggshell.Handoff
public import tools.research.HashedCueKeys
@[expose] public section

namespace Eggshell.Plugin.SharedRangeAdapter.CitationGate
open Eggshell.Research.PreparedRangeCoverage
open Eggshell.Synapses

/-- Each original choice keeps its own union. Joining different choices could
manufacture support across two incomplete alternatives, so it is forbidden. -/
structure Choice where
  original : AdvisoryBundles.Choice
  coverage : CoverageIndex original.spans

def Choice.prepare (original : AdvisoryBundles.Choice) : Choice :=
  ⟨original,CoverageIndex.prepare original.spans⟩

def Choice.covers (choice : Choice) (first last : Nat) : Bool :=
  (⟨0,choice.original.spans,choice.coverage⟩ : UnitShape).coversPrepared first last

theorem Choice.covers_exact (choice : Choice) (first last : Nat) :
    choice.covers first last = SharedRangeAdapter.covers choice.original.spans first last :=
  UnitShape.prepared_covers_exact _ _ _

def choices (bundle : AdvisoryBundles.Bundle) : Array AdvisoryBundles.Choice :=
  bundle.members.flatMap (·.choices)

def compiled (bundle : AdvisoryBundles.Bundle) : Array Choice :=
  (choices bundle).map Choice.prepare

def owner (choice : Choice) : String := choice.original.owner
abbrev Prepared (bundle : AdvisoryBundles.Bundle) := KeyPostings.Index owner (compiled bundle)

/-- Prepared once per bundle, outside the cue and unit traversals. -/
@[noinline] def prepare (bundle : AdvisoryBundles.Bundle) : Prepared bundle :=
  KeyPostings.prepare owner (compiled bundle)

def supportsOwner (prepared : Prepared bundle) (key : String) (first last : Nat) : Bool :=
  (prepared.lookup key).any (fun choice => choice.covers first last)

theorem supportsOwner_exact (bundle : AdvisoryBundles.Bundle) (prepared : Prepared bundle)
    (key : String) (first last : Nat) :
    supportsOwner prepared key first last =
      bundle.members.any (fun member => member.choices.any fun choice =>
        choice.owner == key && SharedRangeAdapter.covers choice.spans first last) := by
  unfold supportsOwner
  rw [KeyPostings.Index.lookup_exact]
  apply Bool.eq_iff_iff.mpr
  simp only [Array.any_eq_true',
    Array.mem_filterMap,compiled,Array.mem_map,choices,Array.mem_flatMap,
    Bool.and_eq_true,beq_iff_eq]
  constructor
  · rintro ⟨choice,⟨ready,⟨raw,⟨member,memberIn,rawIn⟩,rfl⟩,accepted⟩,covered⟩
    split at accepted
    next same =>
      cases Option.some.inj accepted
      exact ⟨member,memberIn,raw,rawIn,(by simpa [owner,Choice.prepare] using same),
        by simpa [Choice.covers_exact,Choice.prepare] using covered⟩
    next => contradiction
  · rintro ⟨member,memberIn,raw,rawIn,same,covered⟩
    refine ⟨Choice.prepare raw,?_,?_⟩
    · refine ⟨Choice.prepare raw,⟨raw,⟨member,memberIn,rawIn⟩,rfl⟩,?_⟩
      simp [owner,Choice.prepare,same]
    · simpa [Choice.covers_exact,Choice.prepare] using covered

def supported (keys : Array String) (prepared : Prepared bundle) (entry : CuePiece × Nat) : Bool :=
  match keys[entry.1.family]? with
  | none => false
  | some key => supportsOwner prepared key entry.1.first entry.1.last

def referenceSupport (keys : Array String) (bundle : AdvisoryBundles.Bundle) (entry : CuePiece × Nat) : Bool :=
  bundle.members.any fun member => member.choices.any fun bound =>
    keys[entry.1.family]? == some bound.owner && SharedRangeAdapter.covers bound.spans entry.1.first entry.1.last

theorem supported_exact (keys : Array String) (prepared : Prepared bundle) (entry : CuePiece × Nat) :
    supported keys prepared entry = referenceSupport keys bundle entry := by
  cases found : keys[entry.1.family]? with
  | none => simp [supported,referenceSupport,found]
  | some key =>
    simp only [supported,found,supportsOwner_exact,referenceSupport]
    apply congrArg (fun predicate => bundle.members.any predicate)
    funext member
    apply congrArg (fun predicate => member.choices.any predicate)
    funext bound
    apply congrArg (fun value => value && SharedRangeAdapter.covers bound.spans entry.1.first entry.1.last)
    apply Bool.eq_iff_iff.mpr
    simp only [beq_iff_eq,Option.some.injEq]
    exact eq_comm

def accept (keys : Array String) (units : Array UnitShape)
    (plan : BundlePlan keys units) (prepared : Prepared plan.projected) (entry : CuePiece × Nat) : Bool :=
  if entry.1.baseWeight < entry.1.weight then
    if supported keys prepared entry then
      plan.indices.any fun index =>
        units[index].family == entry.1.family && units[index].coversPrepared entry.1.first entry.1.last
    else false
  else false

theorem reference_factored (keys : Array String) (units : Array UnitShape)
    (plan : BundlePlan keys units) (entry : CuePiece × Nat) :
    bonusPieceAccept keys units plan entry =
      (entry.1.baseWeight < entry.1.weight &&
        (plan.indices.any fun index =>
          units[index].family == entry.1.family && units[index].coversPrepared entry.1.first entry.1.last) &&
        referenceSupport keys plan.projected entry) := by
  apply Bool.eq_iff_iff.mpr
  simp only [bonusPieceAccept,referenceSupport,Bool.and_eq_true,List.any_eq_true]
  constructor
  · rintro ⟨positive,index,present,covered,bound⟩
    have family : units[index.val].family = entry.1.family := by
      simpa only [Fin.getElem_fin] using (beq_iff_eq.mp covered.1)
    exact ⟨⟨positive,index,present,covered⟩,by simpa only [Fin.getElem_fin,family] using bound⟩
  · rintro ⟨⟨positive,index,present,covered⟩,bound⟩
    have family : units[index.val].family = entry.1.family := by
      simpa only [Fin.getElem_fin] using (beq_iff_eq.mp covered.1)
    exact ⟨positive,index,present,covered,by simpa only [Fin.getElem_fin,family] using bound⟩

theorem accept_exact (keys : Array String) (units : Array UnitShape)
    (plan : BundlePlan keys units) (prepared : Prepared plan.projected) (entry : CuePiece × Nat) :
    accept keys units plan prepared entry = bonusPieceAccept keys units plan entry := by
  rw [reference_factored,← supported_exact keys prepared entry]
  by_cases positive : entry.1.baseWeight < entry.1.weight <;>
    simp [accept,positive,Bool.and_comm]

def bonusPieces (keys : Array String) (units : Array UnitShape)
    (entries : Array (CuePiece × Nat)) (index : PreparedCueIndex.Prepared cueBucketKey entries)
    (plan : BundlePlan keys units) : List (CuePiece × Nat) :=
  let prepared := prepare plan.projected
  index.many (plan.indices.flatMap fun i => units[i].bucketKeys cueBucketWidth) (accept keys units plan prepared)

theorem bonusPieces_exact : @bonusPieces = @bonusPiecesPrepared := by
  funext keys units entries index plan
  simp only [bonusPieces]
  rw [show accept keys units plan (prepare plan.projected) = bonusPieceAccept keys units plan from
    funext (accept_exact keys units plan (prepare plan.projected))]
  rfl

def bonusPiecesHashed (keys : Array String) (units : Array UnitShape)
    (entries : Array (CuePiece × Nat)) (index : PreparedCueIndex.Prepared cueBucketKey entries)
    (plan : BundlePlan keys units) : List (CuePiece × Nat) :=
  let prepared := prepare plan.projected
  Eggshell.Research.HashedCueKeys.many index
    (plan.indices.flatMap fun i => units[i].bucketKeys cueBucketWidth) (accept keys units plan prepared)

theorem bonusPiecesHashed_exact : @bonusPiecesHashed = @bonusPiecesPrepared := by
  funext keys units entries index plan
  simp only [bonusPiecesHashed,Eggshell.Research.HashedCueKeys.many_exact]
  exact congrFun (congrFun (congrFun (congrFun (congrFun bonusPieces_exact keys) units) entries) index) plan

#print axioms Choice.covers_exact
#print axioms supportsOwner_exact
#print axioms supported_exact
#print axioms accept_exact
#print axioms bonusPieces_exact
#print axioms bonusPiecesHashed_exact

end Eggshell.Plugin.SharedRangeAdapter.CitationGate
