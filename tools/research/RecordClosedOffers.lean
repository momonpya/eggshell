module
public import tools.research.CanonicalRecordDomain
@[expose] public section

namespace Eggshell.Research.RecordClosedOffers
open Lean Eggshell.Synapses.CanonicalSource SharedCoverage.Input

def appendClosure (original extra : List Nat) : List Nat := hashDistinct (original ++ extra)

theorem retains_original (original extra : List Nat) (node : Nat) (present : node ∈ original) :
    node ∈ appendClosure original extra := by
  rw [appendClosure,HashDistinct.reference]
  exact List.mem_eraseDups.mpr (List.mem_append_left _ present)

structure Prepared where
  problem : RawProblem
  physicalClasses : Nat
  extendedOffers : Nat

/-- Values, cost atoms and proposal IDs remain fixed. Only the original-byte
closure changes. Physical aliases share their existing cues, without adding
a vote or changing any cue weight. No original or control byte is discarded. -/
def prepare (domain : CanonicalRecordDomain.Checked rows records)
    (sourceAtoms : Array Nat) (raw : RawProblem) : Except String Prepared := do
  let _ ← raw.decode
  unless sourceAtoms.size == rows.size &&
      (Std.HashSet.ofArray sourceAtoms).size == sourceAtoms.size do
    throw "record atom directory is not an injective original basis"
  let _ ← checkedIndices raw.costs.size sourceAtoms.toList
  let mut byAtom : Std.HashMap Nat (Fin rows.size) := {}
  for row in List.finRange rows.size do
    let some atom := sourceAtoms[row.val]? | throw "record atom directory lost an original row"
    byAtom := byAtom.insert atom row
  let mut extended := #[]
  let mut changed := 0
  let mut classes : Std.HashMap (List Nat) Nat := {}
  let mut votes : Array (List Nat) := #[]
  let mut assignments : Array (Option Nat) := #[]
  for offer in raw.offers do
    let requested := offer.closure.filterMap fun atom => byAtom[atom]?
    let extra ← (domain.close requested).mapM fun row => do
      let some atom := sourceAtoms[row.val]? | throw "display closure crossed its original atom directory"
      pure atom
    let closure := appendClosure offer.closure extra
    let before := Std.HashSet.ofList offer.closure
    if closure.any (fun node => !before.contains node) then changed := changed+1
    let key := (Std.HashSet.ofList (closure.filter fun node =>
      (raw.costs[node]?).any (· != (0,0)))).toArray.qsort (· < ·) |>.toList
    let assignment ← if key.isEmpty then pure none else do
      if let some id := classes[key]? then
        let some previous := votes[id]? | throw "record alias directory is inconsistent"
        votes := votes.set! id (offer.covers ++ previous)
        pure (some id)
      else
        let id := votes.size
        classes := classes.insert key id
        votes := votes.push offer.covers
        pure (some id)
    assignments := assignments.push assignment
    extended := extended.push ({closure,covers := offer.covers} : RawOffer)
  let mergedVotes := votes.map hashDistinct
  let mut offers := #[]
  for index in [:extended.size] do
    let some offer := extended[index]? | throw "extended proposal is missing"
    let some assignment := assignments[index]? | throw "record alias assignment is missing"
    let covers ← match assignment with
      | none => pure offer.covers
      | some id => do
          let some values := mergedVotes[id]? | throw "record class lost its existing cues"
          pure values
    offers := offers.push {offer with covers}
  let problem := {raw with offers}
  let _ ← problem.decode
  return ⟨problem,mergedVotes.size,changed⟩

end Eggshell.Research.RecordClosedOffers
