/-- Rank coefficients depend on the producer rank, not on the source row.
Prepare them once; do not divide large normalization integers for every
row/cue pair, including pairs whose original ranges do not overlap. -/
def rankCoefficients (scale familyIndex : Nat) (cues : List RankedCue) : List (RankedCue × Nat) :=
  let ownerWeight := scale/(61+familyIndex)
  cues.map fun cue => (cue,ownerWeight+scale/(61+cue.priority))

def evaluateCoefficients (first last : Nat) (weighted : List (RankedCue × Nat)) : Nat :=
  weighted.foldl (fun weight pair =>
    let overlap := min last pair.1.last - max first pair.1.first
    if overlap = 0 then weight else max weight (overlap*pair.2)) 0

theorem evaluateCoefficients_exact (scale familyIndex first last : Nat) (cues : List RankedCue) :
    evaluateCoefficients first last (rankCoefficients scale familyIndex cues) =
      cues.foldl (fun weight cue =>
        let overlap := min last cue.last - max first cue.first
        max weight (overlap*(scale/(61+familyIndex)+scale/(61+cue.priority)))) 0 := by
  simp only [evaluateCoefficients,rankCoefficients,List.foldl_map]
  apply congrArg (fun update : Nat → RankedCue → Nat => cues.foldl update 0)
  funext weight cue
  split
  · rename_i noOverlap
    simp [noOverlap]
  · rfl

def cachedCuePiecesPrepared (scale familyIndex : Nat) (family : Family) : List CuePiece :=
  let owner := relationKey family.owner.relation
  let base := rankCoefficients scale familyIndex (rankedCues {family with synapticRanges := []})
  let all := rankCoefficients scale familyIndex (rankedCues family)
  family.cached.toList.flatMap fun row =>
    let ranges := cachedBindings owner #[row]
    ranges.filterMap fun (first,last) =>
      let baseWeight := evaluateCoefficients first last base
      let weight := max baseWeight (evaluateCoefficients first last all)
      if weight == 0 then none else
        some {family := familyIndex,first,last,weight,baseWeight,sourceKey := some row.key}

@[csimp] theorem cached_cue_coefficients_compiled : @cachedCuePieces = @cachedCuePiecesPrepared := by
  funext scale familyIndex family
  simp only [cachedCuePieces,cachedCuePiecesPrepared,evaluateCoefficients_exact]
