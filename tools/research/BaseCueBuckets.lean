import Eggshell.Handoff
open Lean Eggshell Eggshell.Plugin

namespace Eggshell.Plugin.SharedRangeAdapter.BaseCueBuckets

/-- Keep the original acceptance predicate, including degenerate inputs. -/
def accept (shape : UnitShape) (entry : CuePiece × Nat) : Bool :=
  entry.1.baseWeight > 0 && entry.1.family == shape.family &&
    shape.ranges.any (fun (a,b) => a ≤ entry.1.first && entry.1.last ≤ b)

def exceptional (family : Nat) : String := toString family ++ ":nonpositive"

def key (entry : CuePiece × Nat) : String :=
  if entry.1.first < entry.1.last then cueBucketKey entry else exceptional entry.1.family

def keys (shape : UnitShape) : List String :=
  exceptional shape.family :: shape.bucketKeys cueBucketWidth

theorem accepted_key (shape : UnitShape) (entry : CuePiece × Nat)
    (accepted : accept shape entry = true) : key entry ∈ keys shape := by
  have family : entry.1.family = shape.family := by
    have facts := accepted
    simp only [accept,Bool.and_eq_true,beq_iff_eq] at facts
    exact facts.1.2
  by_cases ordered : entry.1.first < entry.1.last
  · have inside := accepted
    simp only [accept,Bool.and_eq_true] at inside
    obtain ⟨⟨first,limit⟩,member,bounds⟩ := List.any_eq_true.mp inside.2
    simp only [Bool.and_eq_true,decide_eq_true_eq] at bounds
    have point : first ≤ entry.1.first ∧ entry.1.first < limit := ⟨bounds.1,by omega⟩
    simp only [key,if_pos ordered,keys,List.mem_cons,UnitShape.bucketKeys,cueBucketKey,cueFamilyKey,family]
    exact Or.inr (List.mem_flatMap.mpr ⟨(first,limit),member,
      PointBuckets.key_mem_keys cueBucketWidth (toString shape.family) first limit entry.1.first point⟩)
  · simp only [key,if_neg ordered,keys,family,List.mem_cons,true_or]

def pieces (entries : Array (CuePiece × Nat))
    (prepared : PreparedCueIndex.Prepared key entries) (shape : UnitShape) : List (CuePiece × Nat) :=
  prepared.many (keys shape) (accept shape)

theorem pieces_exact (entries : Array (CuePiece × Nat))
    (prepared : PreparedCueIndex.Prepared key entries) (shape : UnitShape) :
    pieces entries prepared shape = entries.toList.filter (accept shape) := by
  exact prepared.many_exact (keys shape) (accept shape) (accepted_key shape)

theorem family_exact (entries : Array (CuePiece × Nat)) (shape : UnitShape) :
    (PreparedCueIndex.prepare cueFamilyKey entries).one (toString shape.family)
      (fun entry => entry.1.baseWeight > 0 && entry.1.family == shape.family &&
        shape.ranges.any (fun (a,b) => a ≤ entry.1.first && entry.1.last ≤ b)) =
      entries.toList.filter (accept shape) := by
  apply PreparedCueIndex.Prepared.one_exact
  intro entry accepted
  simp only [Bool.and_eq_true,beq_iff_eq] at accepted
  simp only [cueFamilyKey,accepted.1.2]

/-- Only the necessary-condition index changes. The exact predicate, original
IDs, input order, duplicate handling and all costs/weights remain unchanged. -/
def problem (query : ServiceQuery) (source : Synapses.PreparedSourceView.Domain)
    (units : Array ServiceUnit) (cues : List CuePiece) : Option SharedCoverage.Problem := do
  let costs := source.costs ++ query.genericCosts
  let directory := cueDirectory cues
  let weights := directory.2.flatMap fun (base,total) => #[base,total-base]
  let indexedPieces := cues.zipIdx.toArray
  let pieceIndex := PreparedCueIndex.prepare key indexedPieces
  let offers ← units.mapM fun unit => do
    let mut closure := [unit.shape.family]
    if let some id := unit.generic then
      let input ← query.generic[id]?
      closure := closure ++ input.payloads.map (source.costs.size+·)
    else
      for sourceKey in unit.sourceKeys do
        let file ← source.fileIds[sourceKey.file]?
        let payload ← source.rowIds[sourceKey]?
        closure := file :: payload :: closure
    let typedClosure ← closure.mapM fun id =>
      if h : id < costs.size then some (⟨id,h⟩ : Fin costs.size) else none
    let matching := pieces indexedPieces pieceIndex unit.shape
    let covers ← matching.mapM fun (_,id) => do
      let cue ← directory.1[id]?
      if h : cue*2 < weights.size then some (⟨cue*2,h⟩ : Fin weights.size) else none
    return ({closure := typedClosure,covers} : SharedCoverage.Offer costs.size weights.size)
  return {costs,weights,offers,fixed := query.fixed,limit := query.ceiling}

theorem problem_exact (query : ServiceQuery) (source : Synapses.PreparedSourceView.Domain)
    (units : Array ServiceUnit) (cues : List CuePiece) :
    problem query source units cues = problemFromView query source units cues := by
  simp only [problem,problemFromView,pieces_exact,family_exact]
  rfl

#print axioms accepted_key
#print axioms pieces_exact
#print axioms problem_exact

end Eggshell.Plugin.SharedRangeAdapter.BaseCueBuckets
