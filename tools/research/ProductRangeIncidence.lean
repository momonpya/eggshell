module
public import tools.research.RangeIncidence
public import Eggshell.Handoff
@[expose] public section
namespace Eggshell.Research.ProductRangeIncidence
open Eggshell.Plugin Eggshell.Plugin.SharedRangeAdapter
open Eggshell.Research.RangeIncidence

/-- Families are local to this checked query view. A service may retain the
tree only with this view; persistent cross-view keys must include DB/source
identity. This bridge does not introduce a second mutable project cache. -/
def base (units : Array ServiceUnit) :=
  resolveBase (List.finRange units.size) (fun unit => units[unit].shape.family)
    (fun unit => units[unit].shape.ranges)

def baseAccept (units : Array ServiceUnit) (unit : Fin units.size) (coordinate : Coordinate Nat) : Bool :=
  coordinate.scope == units[unit].shape.family &&
    units[unit].shape.ranges.any (fun (first,last) => first ≤ coordinate.first && coordinate.last ≤ last)

theorem base_exact (units : Array ServiceUnit) (unit : Fin units.size) (coordinate : Coordinate Nat) :
    unit ∈ (base units).neighbors coordinate ↔ baseAccept units unit coordinate = true := by
  rw [Resolver.exact]
  simp [RangeIncidence.baseAccept,baseAccept]

/-- Bonus coverage is the union predicate from the existing selector. Adjacent
raw intervals cannot be replaced by a single raw-interval containment test. -/
def unionAccept (units : Array ServiceUnit) (unit : Fin units.size) (coordinate : Coordinate Nat) : Bool :=
  coordinate.scope == units[unit].shape.family &&
    units[unit].shape.coversPrepared coordinate.first coordinate.last

def firstPoint (coordinate : Coordinate Nat) : Coordinate Nat := {coordinate with last := coordinate.first}

theorem union_has_first (units : Array ServiceUnit) (unit : Fin units.size) (coordinate : Coordinate Nat)
    (covered : unionAccept units unit coordinate = true) :
    RangeIncidence.baseAccept (List.finRange units.size) (fun i => units[i].shape.family)
      (fun i => units[i].shape.ranges) unit (firstPoint coordinate) = true := by
  have pair := Bool.and_eq_true_iff.mp covered
  have covered := pair.2
  have ordered : coordinate.first < coordinate.last := by
    by_cases h : coordinate.first < coordinate.last
    · exact h
    · simp [UnitShape.coversPrepared,h] at covered
  have whole : covers units[unit].shape.ranges coordinate.first coordinate.last = true := by
    simpa only [UnitShape.prepared_covers_exact] using covered
  obtain ⟨span,present,inside⟩ := covers_position units[unit].shape.ranges coordinate.first coordinate.last
    coordinate.first whole ⟨Nat.le_refl _,ordered⟩
  simp only [RangeIncidence.baseAccept,firstPoint]
  apply Bool.and_eq_true_iff.mpr
  refine ⟨Bool.and_eq_true_iff.mpr ⟨by simp,pair.1⟩,?_⟩
  apply List.any_eq_true.mpr
  refine ⟨span,present,?_⟩
  change (decide (span.1 ≤ coordinate.first) && decide (coordinate.first ≤ span.2)) = true
  simp [inside.1,Nat.le_of_lt inside.2]

def union (units : Array ServiceUnit) : Resolver (Fin units.size) (Coordinate Nat) (unionAccept units) :=
  ((base units).comap firstPoint).refine (unionAccept units) (union_has_first units)

theorem union_exact (units : Array ServiceUnit) (unit : Fin units.size) (coordinate : Coordinate Nat) :
    unit ∈ (union units).neighbors coordinate ↔ unionAccept units unit coordinate = true :=
  (union units).exact coordinate unit

/-- Every request value is kept. Repeated cues remain repeated and inactive
weights are filtered before projection, exactly as in problemFromView. -/
def requests (pieces : List (CuePiece × Nat)) := pieces.map fun entry =>
  ({coordinate := ⟨entry.1.family,entry.1.first,entry.1.last⟩,
    active := entry.1.baseWeight > 0,value := entry} : FactoredIncidence.Request (Coordinate Nat) (CuePiece × Nat))

def matching (units : Array ServiceUnit) (pieces : List (CuePiece × Nat)) (unit : Fin units.size) :=
  (((base units).project (requests pieces)).lookup unit).map FactoredIncidence.Request.value

theorem matching_exact (units : Array ServiceUnit) (pieces : List (CuePiece × Nat)) (unit : Fin units.size) :
    matching units pieces unit = pieces.filter (fun entry =>
      entry.1.baseWeight > 0 && entry.1.family == units[unit].shape.family &&
        units[unit].shape.ranges.any (fun (first,last) => first ≤ entry.1.first && entry.1.last ≤ last)) := by
  rw [matching,Resolver.project_exact]
  simp only [requests,RangeIncidence.baseAccept,List.mem_finRange,decide_true,Bool.true_and]
  induction pieces with
  | nil => rfl
  | cons entry rest ih =>
    simp only [List.map_cons,List.filter_cons]
    simp only [Bool.and_assoc] at *
    split <;> simp_all

#print axioms base_exact
#print axioms union_exact
#print axioms matching_exact
end Eggshell.Research.ProductRangeIncidence
