module
public import Lean.Data.Json.FromToJson
public import Std
@[expose] public section
open Lean

/- Model-free counterfactual only. Cue identities, recipe order and stable
ratio comparisons come from the frozen problem. A meter changes wire costs,
not rewards, prerequisites, admission or certification. -/
namespace MeasuredCoverage

abbrev Cost := Nat × Nat
structure Delta where
  body : Cost
  slices : Nat
  deriving Inhabited, BEq, ToJson

structure Meter (State : Type) where
  initial : State
  prepare : State → State
  cost : State → Cost
  quote : State → Nat → Option Delta
  afterCost : State → Nat → Delta → Cost
  advance : State → Nat → Option State
  affected : State → State → Nat → Array Nat
  verify : State → List Nat → Bool

structure Problem where
  weights : Array Nat
  cues : Array (Array Nat)
  limit : Cost

structure Trace where
  offer : Nat
  gain : Nat
  before : Cost
  after : Cost
  deriving ToJson

structure Result where
  selected : List Nat
  benefit : Nat
  cost : Cost
  steps : Array Trace
  checkedPrefixes : Nat
  singleton : Bool
  deriving ToJson

def fits (limit cost : Cost) : Bool := cost.1 ≤ limit.1 && cost.2 ≤ limit.2
def charge (limit before after : Cost) : Nat :=
  max ((after.1-before.1)*limit.2) ((after.2-before.2)*limit.1)
def better (gain charge oldGain oldCharge : Nat) : Bool :=
  if charge == 0 then oldCharge != 0 || oldGain < gain
  else if oldCharge == 0 then false
  else oldGain*charge < gain*oldCharge

def postings (problem : Problem) : Array (Array Nat) := Id.run do
  let mut rows := Array.replicate problem.weights.size #[]
  for index in [:problem.cues.size] do
    for cue in problem.cues[index]!.toList.eraseDups do
      if cue < rows.size then rows := rows.modify cue (·.push index)
  return rows

def best (problem : Problem) (meter : Meter State) (state : State)
    (gains : Array Nat) (quotes : Array (Option Delta)) : Option (Nat × Nat × Cost) := Id.run do
  let before := meter.cost state
  let mut winner := none
  let mut previousGain := 0
  let mut previousCharge := 0
  for index in [:problem.cues.size] do
    let gain := gains[index]!
    if gain == 0 then continue
    let some delta := quotes[index]! | continue
    let after := meter.afterCost state index delta
    if !fits problem.limit after then continue
    let charged := charge problem.limit before after
    if winner.isNone || better gain charged previousGain previousCharge then
      winner := some (index,gain,after)
      previousGain := gain
      previousCharge := charged
  return winner

def finish (problem : Problem) (meter : Meter State) (initial : State)
    (single : Option (Nat × Nat × Cost)) (state : State) (selected : List Nat)
    (benefit : Nat) (steps : Array Trace) (checked : Nat) : Option Result := do
  let (state,selected,benefit,singleton,checked) ← match single.filter (fun row => benefit < row.2.1) with
    | some (index,gain,_) => do
      let state ← meter.advance initial index
      let state := meter.prepare state
      if !meter.verify state [index] then none else
        some (state,[index],gain,true,checked+1)
    | none => some (state,selected.reverse,benefit,false,checked)
  if !fits problem.limit (meter.cost state) then none else
    some ⟨selected,benefit,meter.cost state,steps,checked,singleton⟩

def fill (problem : Problem) (meter : Meter State) (incidence : Array (Array Nat))
    (initial : State) (single : Option (Nat × Nat × Cost)) (fuel : Nat)
    (state : State) (covered : Std.HashSet Nat) (gains : Array Nat)
    (quotes : Array (Option Delta)) (selected : List Nat) (benefit : Nat)
    (steps : Array Trace) (checked : Nat) : Option Result := do
  match fuel with
  | 0 => finish problem meter initial single state selected benefit steps checked
  | fuel+1 =>
    let some (index,gain,after) := best problem meter state gains quotes |
      finish problem meter initial single state selected benefit steps checked
    let before := meter.cost state
    let next ← meter.advance state index
    let next := meter.prepare next
    let selected := index :: selected
    if meter.cost next != after || !meter.verify next selected.reverse then none else do
      let mut covered := covered
      let mut gains := gains
      for cue in problem.cues[index]!.toList.eraseDups do
        if covered.contains cue then continue
        covered := covered.insert cue
        for offer in incidence[cue]! do
          gains := gains.modify offer (· - problem.weights[cue]!)
      gains := gains.set! index 0
      let mut quotes := quotes
      for offer in meter.affected state next index do
        quotes := quotes.set! offer (meter.quote next offer)
      fill problem meter incidence initial single fuel next covered gains quotes selected
        (benefit+gain) (steps.push ⟨index,gain,before,after⟩) (checked+1)

def choose? (problem : Problem) (meter : Meter State) : Option Result := do
  if problem.cues.any (fun row => row.any (· ≥ problem.weights.size)) then none else do
    let initial := meter.prepare meter.initial
    if !fits problem.limit (meter.cost initial) || !meter.verify initial [] then none else do
      let gains := problem.cues.map fun row => row.toList.eraseDups.foldl
        (fun total cue => total+problem.weights[cue]!) 0
      let quotes := problem.cues.mapIdx fun index _ => meter.quote initial index
      let mut singleton := none
      for index in [:problem.cues.size] do
        let some delta := quotes[index]! | continue
        let cost := meter.afterCost initial index delta
        if gains[index]! > 0 && fits problem.limit cost then
          if singleton.all (fun previous => previous.2.1 < gains[index]!) then
            singleton := some (index,gains[index]!,cost)
      fill problem meter (postings problem) initial singleton problem.cues.size initial {}
        gains quotes [] 0 #[] 1

/-- This gate is independent of the recommendation meter. The caller still
checks the actual final rendering, never a static surrogate budget. -/
def checked? (renderCost : List Nat → Cost) (limit : Cost) (selected : List Nat) :
    Option {indices : List Nat // (renderCost indices).1 ≤ limit.1 ∧ (renderCost indices).2 ≤ limit.2} :=
  if h : (renderCost selected).1 ≤ limit.1 ∧ (renderCost selected).2 ≤ limit.2 then
    some ⟨selected,h⟩ else none

theorem checked_within_budget (renderCost : List Nat → Cost) (limit : Cost)
    (selected : List Nat)
    (result : {indices : List Nat // (renderCost indices).1 ≤ limit.1 ∧ (renderCost indices).2 ≤ limit.2})
    (_accepted : checked? renderCost limit selected = some result) :
    (renderCost result.val).1 ≤ limit.1 ∧ (renderCost result.val).2 ≤ limit.2 := result.property

end MeasuredCoverage
