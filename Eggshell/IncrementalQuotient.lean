module
public import Eggshell.AtomQuotient
public import Eggshell.QuotientAuthority
public import Eggshell.CongruenceSound
@[expose] public section
namespace Eggshell.IncrementalQuotient
open QuotientBuilder Partition AtomQuotient

def atomWork (graph : WorkGraph) : Bool :=
  graph.outcomes.all (fun edge => isAtom edge.work) &&
    graph.all.all (fun edge => isAtom edge.parent && edge.children.all isAtom)

def Atoms (graph : WorkGraph) : Prop :=
  (∀ edge ∈ graph.outcomes, isAtom edge.work = true) ∧
    ∀ edge ∈ graph.all, isAtom edge.parent = true ∧ ∀ child ∈ edge.children, isAtom child = true

theorem atomWork_exact (graph : WorkGraph) : atomWork graph = true ↔ Atoms graph := by
  simp [atomWork, Atoms, List.all_eq_true]

def Agree (first second : Equality) : Prop :=
  ∀ left, isAtom left = true → ∀ right, first.same left right = second.same left right

theorem small_agrees (roots : List Value) (edges : List UnionEdge) (kinds : HomogeneousEdges edges)
    (small full : Quotient) (smallBuilt : certify (mergeExplicit [] edges) = some small)
    (fullBuilt : build? roots [] edges = some full) : Agree small.toEquality full.toEquality := by
  intro left atom right
  cases left with
  | apply operator arguments => cases atom
  | atom bytes =>
    apply Bool.eq_iff_iff.mpr
    rw [Quotient.same_iff_canonical_eq,
      certify_lookup (explicit_valid valid_nil edges) smallBuilt,
      certify_lookup (explicit_valid valid_nil edges) smallBuilt,
      heads_equal (explicit_valid valid_nil edges)]
    exact (build_aliases roots edges kinds full fullBuilt bytes right).symm

theorem outcomes_equal (graph : WorkGraph) (atoms : Atoms graph) (first second : Equality)
    (agree : Agree first second) (work : Value) :
    graph.outcomesFor first work = graph.outcomesFor second work := by
  apply List.filter_congr
  intro edge member
  exact agree edge.work (atoms.1 edge member) work

theorem decompositions_equal (graph : WorkGraph) (atoms : Atoms graph) (first second : Equality)
    (agree : Agree first second) (work : Value) :
    graph.decompositionsFor first work = graph.decompositionsFor second work := by
  apply List.filter_congr
  intro edge member
  exact agree edge.parent (atoms.2 edge member).1 work

theorem distinct_equal (first second : Equality) (agree : Agree first second) (values : List Value)
    (atoms : ∀ value ∈ values, isAtom value = true) :
    WorkGraph.distinct first values = WorkGraph.distinct second values := by
  have fold (kept : List Value) :
      values.foldl (fun current value => if current.any (first.same value) then current else value :: current) kept =
        values.foldl (fun current value => if current.any (second.same value) then current else value :: current) kept := by
    induction values generalizing kept with
    | nil => rfl
    | cons head tail ih =>
      have same : first.same head = second.same head := funext (agree head (atoms head (by simp)))
      simp only [List.foldl_cons, same]
      exact ih (fun value member => atoms value (by simp [member])) _
  exact congrArg List.reverse (fold [])

theorem children_equal (graph : WorkGraph) (atoms : Atoms graph) (first second : Equality)
    (agree : Agree first second) (edge : AllEdge) (member : edge ∈ graph.all) :
    graph.childrenFor first edge = graph.childrenFor second edge :=
  distinct_equal first second agree edge.children (atoms.2 edge member).2

private theorem filterMap_equal (items : List α) (first second : α → Option β)
    (same : ∀ item ∈ items, first item = second item) : items.filterMap first = items.filterMap second := by
  induction items with
  | nil => rfl
  | cons head tail ih =>
    simp only [List.filterMap_cons, same head (by simp)]
    rw [ih (fun item member => same item (by simp [member]))]

theorem solve_equal (graph : WorkGraph) (atoms : Atoms graph) (first second : Equality)
    (agree : Agree first second) (policy : OutcomePolicy) (fuel : Nat) (active : List Value) (work : Value) :
    Extract.solve graph first policy fuel active work = Extract.solve graph second policy fuel active work := by
  induction fuel generalizing active work with
  | zero => rfl
  | succ fuel ih =>
    simp only [Extract.solve]
    by_cases cycle : active.contains work = true
    · simp only [cycle, ↓reduceIte]
    · simp only [cycle, outcomes_equal graph atoms first second agree work,
        decompositions_equal graph atoms first second agree work]
      have choices : ∀ edge ∈ graph.decompositionsFor second work,
          ((graph.childrenFor first edge).mapM (Extract.solve graph first policy fuel (work :: active))).map
            (Extract.Solution.combine work edge
              ((graph.outcomesFor second work).filter (fun edge => policy.classify work edge == Applicability.completed))
              ((graph.outcomesFor second work).filter (fun edge => policy.classify work edge == Applicability.advisory))) =
          ((graph.childrenFor second edge).mapM (Extract.solve graph second policy fuel (work :: active))).map
            (Extract.Solution.combine work edge
              ((graph.outcomesFor second work).filter (fun edge => policy.classify work edge == Applicability.completed))
              ((graph.outcomesFor second work).filter (fun edge => policy.classify work edge == Applicability.advisory))) := by
        intro edge member
        rw [children_equal graph atoms first second agree edge (List.mem_filter.mp member).1]
        have visit : Extract.solve graph first policy fuel (work :: active) =
            Extract.solve graph second policy fuel (work :: active) := funext (ih (work :: active))
        rw [visit]
      rw [filterMap_equal _ _ _ choices]

theorem all_fields {left right : AllEdge} (equal : left.relation = right.relation) :
    left.parent = right.parent ∧ left.children = right.children := by
  have encoded := congrArg (fun value => match value with
    | .atom _ => []
    | .apply _ arguments => arguments.toList) equal
  rw [left.relation_eq, right.relation_eq] at encoded
  simp only [Value.applyList, Refs.toList_ofList] at encoded
  have head := (List.cons.inj encoded).1
  have tail := congrArg (List.map Prod.snd) (List.cons.inj encoded).2
  exact ⟨congrArg Prod.snd head, by simpa [List.map_map, Ref.semantic, Function.comp_def] using tail⟩

theorem outcome_work {left right : OutcomeEdge}
    (equal : left.relation = right.relation) : left.work = right.work := by
  have encoded := congrArg (fun value => match value with
    | .atom _ => []
    | .apply _ arguments => arguments.toList) equal
  rw [left.relation_eq, right.relation_eq] at encoded
  simp only [Value.applyList, Refs.toList_ofList] at encoded
  exact congrArg Prod.snd (List.cons.inj encoded).1

def SelectionAtoms (selection : Selection) : Prop :=
  ∀ edge ∈ selection.decompositionEdges,
    isAtom edge.parent = true ∧ ∀ child ∈ edge.children, isAtom child = true

mutual
theorem structural_same (selection : Selection) (atoms : SelectionAtoms selection)
    (graph : WorkGraph) (first second : Equality) (agree : Agree first second) (work : Value) :
    selection.structurallyValidAt graph first work =
      selection.structurallyValidAt graph second work := by
  cases selection with
  | residual selected advisory => rfl
  | outcomes selected completed advisory => rfl
  | handoff selected prior =>
      simp only [Selection.structurallyValidAt]
      rw [structural_same prior (by simpa [SelectionAtoms, Selection.decompositionEdges] using atoms)
        graph first second agree work]
  | decomposed selected edge completed advisory children =>
      have edgeAtoms := atoms edge (by simp [Selection.decompositionEdges])
      simp only [Selection.structurallyValidAt,
        agree edge.parent edgeAtoms.1 work,
        WorkGraph.childrenFor, distinct_equal first second agree edge.children edgeAtoms.2]
      rw [structural_children_same children (by
        intro child member candidate used
        apply atoms candidate
        simp only [Selection.decompositionEdges, List.mem_cons, List.mem_flatMap]
        exact Or.inr ⟨child, member, used⟩) graph first second agree]

theorem structural_children_same (children : List Selection)
    (atoms : ∀ child ∈ children, SelectionAtoms child)
    (graph : WorkGraph) (first second : Equality) (agree : Agree first second)
    (works : List Value) :
    Selection.structurallyValidChildren graph first works children =
      Selection.structurallyValidChildren graph second works children := by
  cases children with
  | nil => cases works <;> rfl
  | cons child children =>
      cases works with
      | nil => rfl
      | cons work works =>
          simp only [Selection.structurallyValidChildren]
          rw [structural_same child (atoms child (by simp)) graph first second agree work,
            structural_children_same children (fun child member => atoms child (by simp [member]))
              graph first second agree works]
end

theorem validation_same (graph : WorkGraph) (atoms : Atoms graph)
    (first second : Equality) (agree : Agree first second)
    (selection : Selection) (policy : OutcomePolicy) (work : Value) :
    selection.validFor graph first policy work = selection.validFor graph second policy work := by
  by_cases topology : selection.decompositionEdges.all (Selection.containsAll graph) = true
  · have selected : SelectionAtoms selection := by
      intro edge used
      obtain ⟨stored, member, same⟩ := List.any_eq_true.mp (List.all_eq_true.mp topology edge used)
      have fields := all_fields (beq_iff_eq.mp same)
      rw [← fields.1, ← fields.2]
      exact atoms.2 stored member
    have uses (items : List (Value × OutcomeEdge)) (delivery : Applicability) :
        (items.all fun use => Selection.containsOutcome graph use.2 &&
          first.same use.2.work use.1 && decide (policy.classify use.1 use.2 = delivery)) =
        (items.all fun use => Selection.containsOutcome graph use.2 &&
          second.same use.2.work use.1 && decide (policy.classify use.1 use.2 = delivery)) := by
      apply congrArg (fun predicate => items.all predicate)
      funext use
      by_cases contained : Selection.containsOutcome graph use.2 = true
      · obtain ⟨stored, member, same⟩ := List.any_eq_true.mp contained
        have equal := outcome_work (beq_iff_eq.mp same)
        have atom : isAtom use.2.work = true := equal ▸ atoms.1 stored member
        rw [agree use.2.work atom use.1]
      · have absent : Selection.containsOutcome graph use.2 = false := Bool.eq_false_iff.mpr contained
        simp only [absent, Bool.false_and]
    simp only [Selection.validFor, structural_same selection selected graph first second agree work,
      uses selection.completedUses .completed, uses selection.advisoryUses .advisory]
  · have absent : selection.decompositionEdges.all (Selection.containsAll graph) = false :=
      Bool.eq_false_iff.mpr topology
    simp only [Selection.validFor, absent, Bool.and_false, Bool.false_and]

/-- Complete ordered extraction, including the production provenance checker. -/
theorem extraction_same (graph : WorkGraph) (atoms : Atoms graph)
    (first second : Equality) (agree : Agree first second) (policy : OutcomePolicy) (work : Value) :
    Extract.runWithPolicy graph first policy work = Extract.runWithPolicy graph second policy work := by
  simp only [Extract.runWithPolicy, Extract.runWithPolicyFuel, solve_equal graph atoms first second agree,
    validation_same graph atoms first second agree]

/-- A general view is constructed only from a quotient generated by today's
edges. Both a fresh build and a persisted join plan cross this typed boundary. -/
def generatedView (graph : WorkGraph) (roots : List Value) (persistent runLocal : List UnionEdge)
    (result : Option Quotient) (exact : result = build? roots persistent runLocal) : Option RunView :=
  (CongruenceSound.attach roots persistent runLocal result exact).map fun checked =>
    ⟨graph, checked.quotient, runLocal⟩

theorem generatedView_exact (graph : WorkGraph) (roots : List Value)
    (persistent runLocal : List UnionEdge) (result : Option Quotient)
    (exact : result = build? roots persistent runLocal) :
    generatedView graph roots persistent runLocal result exact =
      RunView.make? graph roots persistent runLocal := by
  have erased := congrArg (Option.map (fun quotient => (⟨graph, quotient, runLocal⟩ : RunView)))
    (CongruenceSound.attach_exact roots persistent runLocal result exact)
  simp only [Option.map_map, Function.comp_def] at erased
  change generatedView graph roots persistent runLocal result exact = _ at erased
  rw [erased, exact]
  unfold RunView.make?
  cases build? roots persistent runLocal <;> rfl

theorem generatedView_sound (graph : WorkGraph) (roots : List Value)
    (persistent runLocal : List UnionEdge) (result : Option Quotient)
    (exact : result = build? roots persistent runLocal) (view : RunView)
    (found : generatedView graph roots persistent runLocal result exact = some view) :
    CongruenceSound.QuotientSound (persistent ++ runLocal) view.quotient := by
  unfold generatedView at found
  cases checked : CongruenceSound.attach roots persistent runLocal result exact with
  | none => simp [checked] at found
  | some certified =>
      simp only [checked, Option.map_some, Option.some.injEq] at found
      cases found
      exact certified.generated

theorem generatedView_complete (graph : WorkGraph) (roots : List Value)
    (persistent runLocal : List UnionEdge) (result : Option Quotient)
    (exact : result = build? roots persistent runLocal) (view : RunView)
    (found : generatedView graph roots persistent runLocal result exact = some view)
    (left right : Value) (leftIn : left ∈ kernelValues roots (persistent ++ runLocal))
    (rightIn : right ∈ kernelValues roots (persistent ++ runLocal))
    (equivalent : Eggshell.Equivalent (persistent ++ runLocal) left right) :
    view.quotient.toEquality.same left right = true := by
  unfold generatedView at found
  cases checked : CongruenceSound.attach roots persistent runLocal result exact with
  | none => simp [checked] at found
  | some certified =>
      simp only [checked, Option.map_some, Option.some.injEq] at found
      cases found
      exact certified.complete left leftIn right rightIn equivalent

/-- The dependent index is extended by new Union edges, not replayed. -/
def make? (graph : WorkGraph) (roots : List Value) (persistent runLocal : List UnionEdge)
    (index : Option (Index (persistent ++ runLocal))) : Option RunView :=
  if atomWork graph then do
    match index with
    | some index =>
        let quotient ← certify index.partition
        pure { graph, quotient, localUnions := runLocal }
    | none => generatedView graph roots persistent runLocal (build? roots persistent runLocal) rfl
  else generatedView graph roots persistent runLocal (build? roots persistent runLocal) rfl

/-- Covers the executed Atom extension lane as well as general fresh and
planned builds. A retired edge is usable only if today's edges still derive
the equality independently. -/
theorem make_generated (graph : WorkGraph) (roots : List Value)
    (persistent runLocal : List UnionEdge) (index : Option (Index (persistent ++ runLocal)))
    (view : RunView) (found : make? graph roots persistent runLocal index = some view) :
    CongruenceSound.QuotientSound (persistent ++ runLocal) view.quotient := by
  unfold make? at found
  split at found
  · cases index with
    | none => exact generatedView_sound graph roots persistent runLocal _ rfl view found
    | some index =>
      cases certified : certify index.partition with
      | none => simp [certified] at found
      | some quotient =>
        simp [certified] at found
        subst view
        apply CongruenceSound.certified_sound (persistent ++ runLocal) _ _ certified
        · rw [index.exact]
          exact explicit_valid valid_nil _
        · rw [index.exact]
          exact CongruenceSound.explicit_sound valid_nil (CongruenceSound.empty_sound _) _
            (fun _ member => member)
  · exact generatedView_sound graph roots persistent runLocal _ rfl view found

/-- The computed join generation is advisory metadata beside the exact view.
It is never installed as an old partition. Keeping it here lets the final
observer retain the executed script without rediscovering its signatures. -/
structure ProducedView (graph : WorkGraph) (roots : List Value)
    (persistent runLocal : List UnionEdge)
    (index : Option (Index (persistent ++ runLocal))) where
  val : Option RunView
  property : val = make? graph roots persistent runLocal index
  plan : Option CongruenceMemo.Entry := none

/-- The controller accepts acceleration only through this exact result type.
Persistence code cannot replace a view by an unchecked old quotient. -/
abbrev ViewProvider := (graph : WorkGraph) → (roots : List Value) →
  (persistent runLocal : List UnionEdge) →
  (index : Option (Index (persistent ++ runLocal))) →
  ProducedView graph roots persistent runLocal index

namespace ViewProvider

def reference : ViewProvider := fun graph roots persistent runLocal index =>
  {val := make? graph roots persistent runLocal index, property := rfl}

def withPlan (plan : Option CongruenceMemo.Entry) : ViewProvider :=
  fun graph roots persistent runLocal index =>
    if atoms : atomWork graph then
      match index with
      | some index => reference graph roots persistent runLocal (some index)
      | none =>
          let built := plannedBuild? roots persistent runLocal plan
          {val := generatedView graph roots persistent runLocal built.quotient built.exact
           property := by simp only [make?, atoms, ↓reduceIte, generatedView_exact]
           plan := built.plan}
    else
      let built := plannedBuild? roots persistent runLocal plan
      {val := generatedView graph roots persistent runLocal built.quotient built.exact
       property := by simp only [make?, atoms, Bool.false_eq_true, ↓reduceIte, generatedView_exact]
       plan := built.plan}

theorem result_exact (provider : ViewProvider) (graph : WorkGraph) (roots : List Value)
    (persistent runLocal : List UnionEdge) (index : Option (Index (persistent ++ runLocal))) :
    (provider graph roots persistent runLocal index).val = make? graph roots persistent runLocal index :=
  (provider graph roots persistent runLocal index).property

theorem withPlan_generation (plan : Option CongruenceMemo.Entry) (graph : WorkGraph)
    (roots : List Value) (persistent runLocal : List UnionEdge)
    (index : Option (Index (persistent ++ runLocal)))
    (general : atomWork graph = false ∨ index = none) :
    (withPlan plan graph roots persistent runLocal index).plan =
      (plannedBuild? roots persistent runLocal plan).plan := by
  unfold withPlan
  split
  · rename_i atoms
    have absent : index = none := general.resolve_left (by simp [atoms])
    subst index
    rfl
  · rfl

/-- A produced generation advances the current run. The next build still
checks its rows against the new roots and explicit edges; it never imports
the previous quotient partition. Atom views without a general plan retain
their existing provider. -/
def advance (provider : ViewProvider) (plan : Option CongruenceMemo.Entry) : ViewProvider :=
  match plan with
  | none => provider
  | some plan => withPlan (some plan)

theorem advance_none (provider : ViewProvider) : advance provider none = provider := rfl

theorem reference_plan (graph : WorkGraph) (roots : List Value)
    (persistent runLocal : List UnionEdge) (index : Option (Index (persistent ++ runLocal))) :
    (reference graph roots persistent runLocal index).plan = none := rfl

theorem advance_generation (provider : ViewProvider) (plan : CongruenceMemo.Entry)
    (graph : WorkGraph) (roots : List Value) (persistent runLocal : List UnionEdge)
    (index : Option (Index (persistent ++ runLocal)))
    (general : atomWork graph = false ∨ index = none) :
    (advance provider (some plan) graph roots persistent runLocal index).plan =
      (plannedBuild? roots persistent runLocal (some plan)).plan :=
  withPlan_generation (some plan) graph roots persistent runLocal index general

def observed (provider : ViewProvider) := fun graph roots persistent runLocal index =>
  (provider graph roots persistent runLocal index).val

theorem observed_exact (provider : ViewProvider) : observed provider = make? := by
  funext graph roots persistent runLocal index
  exact (provider graph roots persistent runLocal index).property

theorem generated (provider : ViewProvider) (graph : WorkGraph) (roots : List Value)
    (persistent runLocal : List UnionEdge) (index : Option (Index (persistent ++ runLocal)))
    (view : RunView) (found : observed provider graph roots persistent runLocal index = some view) :
    CongruenceSound.QuotientSound (persistent ++ runLocal) view.quotient := by
  rw [observed_exact] at found
  exact make_generated graph roots persistent runLocal index view found

/-- The general lane compares every required term. The Atom acceleration
lane instead has its separate, already proved Atom-left agreement contract. -/
theorem complete (provider : ViewProvider) (graph : WorkGraph) (roots : List Value)
    (persistent runLocal : List UnionEdge) (index : Option (Index (persistent ++ runLocal)))
    (general : atomWork graph = false ∨ index = none) (view : RunView)
    (found : observed provider graph roots persistent runLocal index = some view)
    (left right : Value) (leftIn : left ∈ kernelValues roots (persistent ++ runLocal))
    (rightIn : right ∈ kernelValues roots (persistent ++ runLocal))
    (equivalent : Eggshell.Equivalent (persistent ++ runLocal) left right) :
    view.quotient.toEquality.same left right = true := by
  rw [observed_exact] at found
  unfold make? at found
  split at found
  · rename_i atoms
    have absent : index = none := general.resolve_left (by simp [atoms])
    subst index
    exact generatedView_complete graph roots persistent runLocal _ rfl view found left right leftIn rightIn equivalent
  · exact generatedView_complete graph roots persistent runLocal _ rfl view found left right leftIn rightIn equivalent

/-- General indexed and full-source views agree on their common demanded
terms, regardless of irrelevant root additions or arbitrary saved hints.
Both use today's same edges; no result-equality premise is accepted. -/
theorem domain_independent (firstProvider secondProvider : ViewProvider)
    (firstGraph secondGraph : WorkGraph) (roots otherRoots : List Value)
    (persistent runLocal : List UnionEdge)
    (firstIndex secondIndex : Option (Index (persistent ++ runLocal)))
    (firstGeneral : atomWork firstGraph = false ∨ firstIndex = none)
    (secondGeneral : atomWork secondGraph = false ∨ secondIndex = none)
    (first second : RunView)
    (firstBuilt : observed firstProvider firstGraph roots persistent runLocal firstIndex = some first)
    (secondBuilt : observed secondProvider secondGraph otherRoots persistent runLocal secondIndex = some second)
    (left right : Value)
    (firstLeft : left ∈ kernelValues roots (persistent ++ runLocal))
    (firstRight : right ∈ kernelValues roots (persistent ++ runLocal))
    (secondLeft : left ∈ kernelValues otherRoots (persistent ++ runLocal))
    (secondRight : right ∈ kernelValues otherRoots (persistent ++ runLocal)) :
    first.quotient.toEquality.same left right = second.quotient.toEquality.same left right := by
  apply Bool.eq_iff_iff.mpr
  exact ⟨fun same => complete secondProvider secondGraph otherRoots persistent runLocal secondIndex secondGeneral
      second secondBuilt left right secondLeft secondRight
      (generated firstProvider firstGraph roots persistent runLocal firstIndex first firstBuilt left right same),
    fun same => complete firstProvider firstGraph roots persistent runLocal firstIndex firstGeneral
      first firstBuilt left right firstLeft firstRight
      (generated secondProvider secondGraph otherRoots persistent runLocal secondIndex second secondBuilt left right same)⟩

end ViewProvider

theorem regroup (roots : List Value) (persistent runLocal : List UnionEdge) :
    build? roots [] (persistent ++ runLocal) = build? roots persistent runLocal := by
  cases persistent <;> cases runLocal <;> simp [build?, congruenceBuild?]

theorem make_agrees (graph : WorkGraph) (roots : List Value)
    (persistent runLocal : List UnionEdge) (index : Option (Index (persistent ++ runLocal)))
    (small full : RunView) (smallBuilt : make? graph roots persistent runLocal index = some small)
    (fullBuilt : RunView.make? graph roots persistent runLocal = some full) :
    Agree small.quotient.toEquality full.quotient.toEquality := by
  unfold make? at smallBuilt
  simp only [generatedView_exact] at smallBuilt
  split at smallBuilt
  · cases index with
    | none =>
        have same := Option.some.inj (smallBuilt.symm.trans fullBuilt)
        subst small
        intro _ _ _; rfl
    | some index =>
        cases smallQ : certify index.partition with
        | none => simp [smallQ] at smallBuilt
        | some smallQuotient =>
            simp [smallQ] at smallBuilt
            subst small
            cases fullQ : build? roots persistent runLocal with
            | none => simp [RunView.make?, fullQ] at fullBuilt
            | some fullQuotient =>
                simp [RunView.make?, fullQ] at fullBuilt
                subst full
                apply small_agrees roots (persistent ++ runLocal) index.homogeneous
                  smallQuotient fullQuotient
                · simpa only [index.exact] using smallQ
                · rw [regroup]; exact fullQ
  · have same := Option.some.inj (smallBuilt.symm.trans fullBuilt)
    subst small
    intro _ _ _; rfl

theorem make_extraction (graph : WorkGraph) (atoms : Atoms graph) (roots : List Value)
    (persistent runLocal : List UnionEdge) (index : Option (Index (persistent ++ runLocal)))
    (small full : RunView) (smallBuilt : make? graph roots persistent runLocal index = some small)
    (fullBuilt : RunView.make? graph roots persistent runLocal = some full)
    (policy : OutcomePolicy) (work : Value) :
    small.extractWith policy work = full.extractWith policy work := by
  have ordinaryGraph (view : RunView)
      (built : RunView.make? graph roots persistent runLocal = some view) : view.graph = graph := by
    cases quotient : build? roots persistent runLocal with
    | none => simp [RunView.make?, quotient] at built
    | some quotientValue =>
        simp [RunView.make?, quotient] at built
        subst view
        rfl
  have smallGraph : small.graph = graph := by
    unfold make? at smallBuilt
    simp only [generatedView_exact] at smallBuilt
    split at smallBuilt
    · cases index with
      | none => exact ordinaryGraph small smallBuilt
      | some index =>
          cases built : certify index.partition with
          | none => simp [built] at smallBuilt
          | some quotient =>
              simp [built] at smallBuilt
              subst small
              rfl
    · exact ordinaryGraph small smallBuilt
  have fullGraph : full.graph = graph := ordinaryGraph full fullBuilt
  simp only [RunView.extractWith, smallGraph, fullGraph]
  exact extraction_same graph atoms small.quotient.toEquality full.quotient.toEquality
    (make_agrees graph roots persistent runLocal index small full smallBuilt fullBuilt) policy work

end Eggshell.IncrementalQuotient
