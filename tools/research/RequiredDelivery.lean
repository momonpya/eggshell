import Eggshell.SynapseUsage

open Lean Eggshell.Synapses

namespace Eggshell.Research.RequiredDelivery

/-- Alternatives are fixed before delivery. Each names a complete immutable
file range or original-output range; a path or a summary is not an alternative. -/
structure Requirement where
  name : String
  alternatives : Array Range
  deriving ToJson, FromJson

structure EvidenceUnit where
  names : Array String
  alternatives : Array Range
  deriving ToJson, FromJson

structure Frozen where
  units : Array EvidenceUnit
  initiallyUnavailable : Array String
  deriving ToJson, FromJson

private def spelling (ranges : Array Range) : String := (toJson ranges).compress

private def canonical (ranges : Array Range) : Array Range :=
  (ranges.toList.eraseDups.toArray).qsort (fun a b => (toJson a).compress < (toJson b).compress)

private def overlaps (a b : Range) : Bool :=
  a.subject == b.subject && a.first ≤ b.last && b.first ≤ a.last

/-- Only verified DB ranges may populate `available`. The snapshot, identities
and frozen result are sealed by the IO auditor before a handoff is inspected.
Identical evidence cannot inflate the denominator under different labels.
Overlapping distinct units require an explicit partition before freezing. -/
def freeze (required : Array Requirement) (available : Array Range) : Except String Frozen := do
  unless available.all (·.valid) do throw "invalid DB evidence range"
  let mut units : Array EvidenceUnit := #[]
  let mut absent := #[]
  let mut names : Std.HashSet String := {}
  for item in required do
    unless !item.name.trimAscii.isEmpty && !names.contains item.name &&
        item.alternatives.all (·.valid) do
      throw "invalid or duplicate required evidence identity"
    names := names.insert item.name
    let alternatives := canonical (item.alternatives.filter (fun target => covered target available))
    if alternatives.isEmpty then absent := absent.push item.name; continue
    if let some index := units.findIdx? (fun unit => spelling unit.alternatives == spelling alternatives) then
      units := units.modify index fun unit => {unit with names := unit.names.push item.name}
      continue
    unless units.all (fun unit => !unit.alternatives.any (fun a => alternatives.any (overlaps a))) do
      throw "partition overlapping required evidence before freezing"
    units := units.push ⟨#[item.name],alternatives⟩
  return ⟨units,absent⟩

def reachesTarget (required delivered : Nat) : Bool :=
  0 < required && delivered ≤ required && 19*required ≤ 20*delivered

theorem target_has_nonempty_denominator (required delivered : Nat)
    (met : reachesTarget required delivered = true) : 0 < required ∧ delivered ≤ required := by
  simp only [reachesTarget, Bool.and_eq_true, decide_eq_true_eq] at met
  exact met.1

theorem one_miss_requires_twenty (required : Nat) (positive : 0 < required) :
    reachesTarget required (required-1) = true ↔ 20 ≤ required := by
  simp only [reachesTarget, Bool.and_eq_true, decide_eq_true_eq]
  omega

structure Result where
  eligible : Nat
  delivered : Nat
  missing : Array (Array String)
  initiallyUnavailable : Array String
  targetPercent : Nat := 95
  targetMet : Bool
  deriving ToJson, FromJson

/-- The denominator remains the frozen DB-present units even if a later index
or retrieval stage misses them. `shown` must come from verified original bytes
in the actual hook output, never from nomination, a locator or a claimed ACK. -/
def assess (frozen : Frozen) (shown : Array Range) : Result := Id.run do
  let shown := shown.filter (·.valid)
  let missing := frozen.units.filter (fun unit => !unit.alternatives.any (fun target => covered target shown))
  let eligible := frozen.units.size
  let delivered := eligible-missing.size
  return {
    eligible,delivered,missing := missing.map (·.names)
    initiallyUnavailable := frozen.initiallyUnavailable
    targetMet := reachesTarget eligible delivered }

end Eggshell.Research.RequiredDelivery
