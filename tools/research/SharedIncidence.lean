module
public import tools.research.FactoredIncidence
@[expose] public section
namespace Eggshell.Research.FactoredIncidence
variable {U C A : Type} [BEq U] [LawfulBEq U] [Hashable U]
  [BEq C] [LawfulBEq C] [Hashable C]

/-- Materialize each ordered posting once. Reusing a coverage class returns
the same immutable list, instead of reversing a posting for every unit. -/
structure Forward (keys : U → List C) (units : List U) (requests : List (Request C A)) where
  table : Std.HashMap U (List (Request C A))
  exact : ∀ unit,table.getD unit [] = reference keys units requests unit

def finish {keys : U → List C} {units : List U} (ready : Static keys units)
    (requests : List (Request C A)) : Forward keys units requests :=
  let index := project ready requests
  ⟨index.table.map (fun _ rows => rows.reverse),by
    intro unit
    have exact := lookup_reference ready requests unit
    unfold OrderedIncidence.Index.lookup at exact
    change (index.table.getD unit []).reverse = _ at exact
    rw [Std.HashMap.getD_eq_getD_getElem?] at exact
    simp only [Std.HashMap.getD_eq_getD_getElem?,Std.HashMap.getElem?_map]
    cases found : index.table[unit]? with
    | none => simpa [found] using exact
    | some rows => simpa [found] using exact⟩

structure Sharing (keys : U → List C) (units : List U) where
  classOf : U → Nat
  coordinates : Array (List C)
  admitted : ∀ unit ∈ units,classOf unit < coordinates.size
  same : ∀ unit ∈ units,∀ coordinate,
    coordinate ∈ coordinates[classOf unit]?.getD [] ↔ coordinate ∈ keys unit
  topology : Static (fun group => coordinates[group]?.getD []) (List.range coordinates.size)

/-- Check exact structural identity once. Sharing never equates Work, payloads,
costs, relevance weights, or completion authority. It has no query input. -/
def Sharing.checkUsing (canonical : List C → List C)
    (members : ∀ input coordinate,coordinate ∈ canonical input ↔ coordinate ∈ input)
    (keys : U → List C) (units : List U) (classOf : U → Nat)
    (coordinates : Array (List C)) : Option (Sharing keys units) :=
  if valid : units.all (fun unit => decide (classOf unit < coordinates.size) &&
      (coordinates[classOf unit]?.getD [] == canonical (keys unit))) = true then
    some {
      classOf,coordinates
      admitted := by
        intro unit present
        exact of_decide_eq_true ((Bool.and_eq_true_iff.mp (List.all_eq_true.mp valid unit present)).1)
      same := by
        intro unit present coordinate
        have same := beq_iff_eq.mp ((Bool.and_eq_true_iff.mp (List.all_eq_true.mp valid unit present)).2)
        rw [same]
        exact members _ _
      topology := compile (fun group => coordinates[group]?.getD []) (List.range coordinates.size) }
  else none

def Sharing.check (keys : U → List C) (units : List U) (classOf : U → Nat)
    (coordinates : Array (List C)) : Option (Sharing keys units) :=
  Sharing.checkUsing id (fun _ _ => Iff.rfl) keys units classOf coordinates

def Sharing.project {keys : U → List C} {units : List U} (ready : Sharing keys units)
    (requests : List (Request C A)) := finish ready.topology requests

def Sharing.rows {keys : U → List C} {units : List U} (ready : Sharing keys units)
    {requests : List (Request C A)}
    (query : Forward (fun group => ready.coordinates[group]?.getD []) (List.range ready.coordinates.size) requests)
    (unit : U) (_present : unit ∈ units) : List (Request C A) :=
  query.table.getD (ready.classOf unit) []

omit [Hashable U] in
theorem Sharing.rows_exact {keys : U → List C} {units : List U} (ready : Sharing keys units)
    {requests : List (Request C A)}
    (query : Forward (fun group => ready.coordinates[group]?.getD []) (List.range ready.coordinates.size) requests)
    (unit : U) (present : unit ∈ units) :
    ready.rows query unit present = reference keys units requests unit := by
  rw [Sharing.rows,query.exact]
  have admitted : ready.classOf unit ∈ List.range ready.coordinates.size := List.mem_range.mpr (ready.admitted unit present)
  simp only [reference,if_pos admitted,if_pos present]
  apply List.filter_congr
  intro request _
  simp only [ready.same unit present request.coordinate]

#print axioms finish
#print axioms Sharing.rows_exact
end Eggshell.Research.FactoredIncidence
