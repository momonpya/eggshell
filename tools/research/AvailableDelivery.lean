import tools.research.RequiredDelivery
open Lean Eggshell.Synapses

namespace Eggshell.Research.AvailableDelivery

/-- Fragments name only the intersection with an immutable observed range.
Partial availability is a delivery obligation, not a complete semantic result. -/
def fragments (wanted : Range) (observed : Array Range) : Array Range :=
  observed.filterMap wanted.intersection?

theorem fragment_is_observed (wanted : Range) (observed : Array Range) (fragment : Range)
    (present : fragment ∈ fragments wanted observed) :
    ∃ original ∈ observed, fragment.valid = true ∧ wanted.contains fragment = true ∧
      original.contains fragment = true := by
  simp only [fragments,Array.mem_filterMap] at present
  obtain ⟨original,member,matched⟩ := present
  exact ⟨original,member,Range.intersection_within matched⟩

private def canonical (ranges : Array Range) : Array Range :=
  ranges.toList.eraseDups.toArray.qsort fun a b => (toJson a).compress < (toJson b).compress

private def alternatives (parts : Array (Array Range)) : Array (Array Range) :=
  parts.toList.eraseDups.toArray.qsort fun a b => (toJson a).compress < (toJson b).compress

structure Unit where
  names : Array String
  alternatives : Array (Array Range)
  partialNames : Array String
  deriving BEq,ToJson,FromJson

structure Frozen where
  units : Array Unit
  absent : Array String
  deriving BEq,ToJson,FromJson

private def overlaps (a b : Range) : Bool := (a.intersection? b).isSome

/-- Freeze before opening delivery bytes. Fully available alternatives retain
their whole requirement. A partially available requirement retains all saved
pieces; it is never silently moved into the absent bucket. Identical physical
footprints share one unit; other overlaps require an explicit partition. -/
def freeze (required : Array RequiredDelivery.Requirement) (observed : Array Range) : Except String Frozen := do
  unless observed.all (·.valid) do throw "invalid original DB range"
  let mut units : Array Unit := #[]
  let mut absent := #[]
  let mut names : Std.HashSet String := {}
  for requirement in required do
    unless !requirement.name.trimAscii.isEmpty && !names.contains requirement.name &&
        requirement.alternatives.all (·.valid) do throw "invalid or duplicate evidence name"
    names := names.insert requirement.name
    let whole := requirement.alternatives.filter (fun wanted => covered wanted observed)
    let isPartial := whole.isEmpty
    let parts := if isPartial then requirement.alternatives.map (fun wanted => canonical (fragments wanted observed))
      else whole.map (fun wanted => #[wanted])
    let parts := alternatives (parts.filter (!·.isEmpty))
    if parts.isEmpty then absent := absent.push requirement.name; continue
    if let some index := units.findIdx? (fun unit => unit.alternatives == parts) then
      units := units.modify index fun unit => {unit with
        names := unit.names.push requirement.name
        partialNames := if isPartial then unit.partialNames.push requirement.name else unit.partialNames}
      continue
    unless units.all (fun unit => !unit.alternatives.any (fun old => old.any (fun a =>
        parts.any (fun next => next.any (overlaps a))))) do
      throw "partition overlapping available evidence before freezing"
    units := units.push ⟨#[requirement.name],parts,if isPartial then #[requirement.name] else #[]⟩
  return ⟨units,absent⟩

def reachesTarget (required delivered : Nat) : Bool :=
  0 < required && delivered ≤ required && 98*required ≤ 100*delivered

theorem target_has_evidence (required delivered : Nat) (met : reachesTarget required delivered = true) :
    0 < required ∧ delivered ≤ required := by
  simp only [reachesTarget,Bool.and_eq_true,decide_eq_true_eq] at met
  exact met.1

theorem one_miss_requires_fifty (required : Nat) (positive : 0 < required) :
    reachesTarget required (required-1) = true ↔ 50 ≤ required := by
  simp only [reachesTarget,Bool.and_eq_true,decide_eq_true_eq]
  omega

structure Result where
  eligible : Nat
  delivered : Nat
  missing : Array (Array String)
  partialNames : Array String
  absent : Array String
  targetPercent : Nat := 98
  targetMet : Bool
  deriving ToJson,FromJson

def assess (frozen : Frozen) (shown : Array Range) : Result := Id.run do
  let shown := shown.filter (·.valid)
  let missing := frozen.units.filter fun unit =>
    !unit.alternatives.any (fun parts => parts.all (fun wanted => covered wanted shown))
  let delivered := frozen.units.size-missing.size
  return {
    eligible := frozen.units.size
    delivered
    missing := missing.map (·.names)
    partialNames := frozen.units.flatMap (·.partialNames)
    absent := frozen.absent
    targetMet := reachesTarget frozen.units.size delivered}

end Eggshell.Research.AvailableDelivery
