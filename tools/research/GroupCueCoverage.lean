module
public import tools.SharedCoverageInput
public import Std.Data.HashMap
public import Std.Data.HashSet
@[expose] public section

/- Isolated advisory experiment. A complete already-bound evidence group is
one retrieval signal, rather than a difference between two per-row maxima.
No observation, Work, Match, Union or authority certificate is constructed. -/
namespace Eggshell.Research.GroupCueCoverage
open SharedCoverage.Input

def normalizedMass (unit value extent : Nat) : Nat := unit*value/extent

theorem normalized_mass_bounded (unit value extent : Nat) :
    normalizedMass unit value extent * extent ≤ unit*value := by
  exact Nat.div_mul_le_self _ _

structure Group where
  closure : List Nat
  mass : Nat
  originals : List Nat
  deriving Lean.ToJson

structure Anchored (group : Group) where
  node : Nat
  present : node ∈ group.closure

theorem complete_group_reaches_anchor (group : Group) (anchor : Anchored group)
    (offer : RawOffer) (complete : ∀ node ∈ group.closure, node ∈ offer.closure) :
    anchor.node ∈ offer.closure := complete anchor.node anchor.present

def complete (group : Group) (paid : Std.HashSet Nat) : Bool := group.closure.all paid.contains

theorem credited_requires_every_original (group : Group) (paid : Std.HashSet Nat)
    (credited : complete group paid = true) (node : Nat) (present : node ∈ group.closure) :
    paid.contains node = true := List.all_eq_true.mp credited node present

structure Prepared where
  groups : Array Group
  anchorNodes : Array Nat
  candidateChecks : Nat
  inputGraphOffers : Nat
  zeroMassOffers : Nat
  problem : RawProblem
  deriving Lean.ToJson

/-- Graph offer bounds come from the actual plan's compiled recipe segment.
`frames` contains only pre-existing structural shells; every other paid atom
is original payload. Physical aliases share one group and the strongest mass.
The unit is the producer's existing search-window width, never fitted to a
question, reference list, or observed benchmark outcome. -/
def prepare (raw : RawProblem) (first last unit : Nat) (frames : Std.HashSet Nat) : Except String Prepared := do
  let _ ← raw.decode
  unless first ≤ last && last ≤ raw.offers.size && raw.weights.size%2 == 0 && 0 < unit do
    throw "invalid compiled group segment or source-window unit"
  let mut directory : Std.HashMap (List Nat) Nat := {}
  let mut groups : Array Group := #[]
  let mut zeroMass := 0
  for index in [first:last] do
    let some offer := raw.offers[index]? | throw "compiled graph offer is missing"
    let closure := (Std.HashSet.ofList (offer.closure.filter fun node =>
      (raw.costs[node]?).any (· != (0,0)))).toArray.qsort (· < ·) |>.toList
    let mut extent := 0
    for node in closure do
      unless frames.contains node do extent := extent+(raw.costs[node]!).1
    let cues := (Std.HashSet.ofList offer.covers).toArray
    let value := cues.foldl (fun total cue => total+raw.weights[cue]!) 0
    let mass := normalizedMass unit value extent
    if closure.isEmpty || extent == 0 || mass == 0 then zeroMass := zeroMass+1; continue
    if let some prior := directory[closure]? then
      let some previous := groups[prior]? | throw "physical group directory is inconsistent"
      groups := groups.set! prior {
        closure := previous.closure
        mass := max previous.mass mass
        originals := previous.originals ++ [index]}
    else
      directory := directory.insert closure groups.size
      groups := groups.push {closure,mass,originals := [index]}
  -- A rare original atom is a complete containment index, not an ANN cutoff.
  let mut frequency : Std.HashMap Nat Nat := {}
  for offer in raw.offers do
    for node in (Std.HashSet.ofList offer.closure).toArray do
      frequency := frequency.insert node (frequency[node]?.getD 0+1)
  let mut postings : Std.HashMap Nat (Array Nat) := {}
  let mut anchors := #[]
  for index in [:groups.size] do
    let some group := groups[index]? | throw "group missing during anchor preparation"
    let some initial := group.closure.attach.head? | throw "empty evidence group"
    let best := group.closure.attach.foldl (fun best candidate =>
      if frequency[candidate.val]?.getD 0 < frequency[best.val]?.getD 0 then candidate else best) initial
    let anchor : Anchored group := ⟨best.val,best.property⟩
    anchors := anchors.push anchor.node
    postings := postings.insert anchor.node (postings[anchor.node]?.getD #[] |>.push index)
  let weights := raw.weights.mapIdx (fun index value => if index%2 == 0 then value else 0) ++ groups.map (·.mass)
  let mut offers := #[]
  let mut checks := 0
  for offer in raw.offers do
    let paid := Std.HashSet.ofList offer.closure
    let possible := paid.toArray.flatMap fun node => postings[node]?.getD #[]
    let mut bonus := []
    for index in possible do
      checks := checks+1
      let some group := groups[index]? | throw "anchor posting names a missing group"
      if complete group paid then bonus := (raw.weights.size+index) :: bonus
    offers := offers.push {offer with covers := offer.covers ++ bonus}
  return {
    groups := groups
    anchorNodes := anchors
    candidateChecks := checks
    inputGraphOffers := last-first
    zeroMassOffers := zeroMass
    problem := {raw with weights,offers}}

theorem prepared_costs_unchanged (raw : RawProblem) (weights : Array Nat) (offers : Array RawOffer) :
    ({raw with weights,offers} : RawProblem).costs = raw.costs := rfl

theorem prepared_wire_limits_unchanged (raw : RawProblem) (weights : Array Nat) (offers : Array RawOffer) :
    ({raw with weights,offers} : RawProblem).limit = raw.limit ∧
    ({raw with weights,offers} : RawProblem).fixed = raw.fixed := ⟨rfl,rfl⟩
end Eggshell.Research.GroupCueCoverage
