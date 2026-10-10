module

public import Eggshell.Graph

@[expose] public section

namespace Eggshell

/-- A finite executable equality together with the laws the kernel relies on. -/
structure Equality where
  same : Value → Value → Bool
  reflexive : ∀ value, same value value
  symmetric : ∀ {left right}, same left right → same right left
  transitive : ∀ {left middle right}, same left middle → same middle right →
    same left right
  preservesExact : ∀ {left right}, same left right →
    Value.SameExactFootprint left right

namespace Equality

def exact : Equality where
  same left right := decide (left = right)
  reflexive value := by simp
  symmetric := by simp_all
  transitive := by simp_all
  preservesExact := by
    intro left right same
    simp only [decide_eq_true_eq] at same
    subst right
    exact Value.sameExactFootprint_refl left

@[simp]
theorem exact_same_iff {left right} : exact.same left right ↔ left = right := by
  simp [exact]

end Equality

/-- The two positive relations evaluated by the kernel. -/
structure WorkGraph where
  all : List AllEdge := []
  outcomes : List OutcomeEdge := []
  deriving DecidableEq

namespace WorkGraph

/-- Stable quotient deduplication. Equality, not insertion identity, owns the lane. -/
def distinct (equality : Equality) : List Value → List Value
  | values => (values.foldl (fun kept value =>
      if kept.any (equality.same value) then kept else value :: kept) []).reverse

def fromValues (values : List Value) : WorkGraph where
  all := values.filterMap AllEdge.fromValue?
  outcomes := values.filterMap OutcomeEdge.fromValue?

def outcomesFor (graph : WorkGraph) (equality : Equality) (work : Value) :
    List OutcomeEdge :=
  graph.outcomes.filter fun edge => equality.same edge.work work

def decompositionsFor (graph : WorkGraph) (equality : Equality) (parent : Value) :
    List AllEdge :=
  graph.all.filter fun edge => equality.same edge.parent parent

/-- An `All` edge is an AND-set over e-classes, not a bag of spellings. -/
def childrenFor (_graph : WorkGraph) (equality : Equality) (edge : AllEdge) :
    List Value :=
  distinct equality edge.children

/--
Work is reusable completion only when it occupies a child position in the
positive graph. A root Outcome is useful history, but cannot erase a smaller
operation merely because its prose mentions the same words.
-/
def subworks (graph : WorkGraph) : List Value :=
  graph.all.flatMap (·.children) |>.eraseDups

def isSubwork (graph : WorkGraph) (equality : Equality) (work : Value) : Bool :=
  graph.subworks.any (equality.same work)

end WorkGraph

/-
An open handoff is ordinary natural-language data.  The shared constructor only
prevents the turn compiler and matcher from inventing two spellings for the same
continuation, and lets saturation leave an internal remainder open until that
remainder itself becomes the external Demand.
-/
namespace HandoffRemainder

def identityPrefix : String :=
  "Use the selected prior WORK→OUTCOME graph as completed or advisory history. "

def marker : String :=
  identityPrefix ++ "Do not repeat prior work merely to verify it or because evidence is missing. " ++
  "Do not reread evidence for line numbers or citation formatting; cite the " ++
  "recorded source without line numbers when they are unavailable. " ++
  "Missing from this graph is not unavailable evidence. Inspect the smallest " ++
  "accessible source for an unsupported requirement; distinguish unknown " ++
  "external state from rules that available code or documentation can establish. " ++
  "Do not declare exhaustion solely from a missing excerpt or runtime test. " ++
  "Use the smallest useful check for uncovered work. If relevant local and available " ++
  "MCP sources are exhausted, report supported facts and missing evidence, mark the " ++
  "conclusion UNRESOLVED, and stop. Resume only after new evidence, changed inputs " ++
  "or access, or a concrete contradiction. Current uncovered request: "

def text (work : String) : String := marker ++ work

def value (work : String) : Value := .text (text work)

def isValue : Value → Bool
  | .atom bytes =>
      match String.fromUTF8? bytes with
      | some content => content.startsWith identityPrefix
      | none => false
  | .apply _ _ => false

end HandoffRemainder

/-- Runtime delivery judgment; it is never persisted as graph authority. -/
inductive Applicability where
  | completed
  | advisory
  | irrelevant
  deriving Repr, DecidableEq, BEq

inductive CoverageDirection where
  | pastWorkInsideCurrentDemand
  | currentDemandInsidePastWork
  | overlapping
  | ambiguous
  deriving Repr, DecidableEq, BEq

/--
The matcher may be permissive. Only forward containment plus a reusable
outcome may erase small work; every other match remains visible advice.
-/
structure ApplicabilityJudgment where
  direction : CoverageDirection
  reusableOutcome : Bool

namespace ApplicabilityJudgment

def delivery (judgment : ApplicabilityJudgment) : Applicability :=
  if decide (judgment.direction = .pastWorkInsideCurrentDemand) &&
      judgment.reusableOutcome then
    .completed
  else
    .advisory

theorem completed_only_for_forward_reusable {judgment : ApplicabilityJudgment}
    (completed : judgment.delivery = .completed) :
    judgment.direction = .pastWorkInsideCurrentDemand ∧
      judgment.reusableOutcome = true := by
  simp only [delivery] at completed
  split at completed
  · rename_i accepted
    simp only [Bool.and_eq_true, decide_eq_true_eq] at accepted
    exact accepted
  · contradiction

end ApplicabilityJudgment

structure OutcomeAdmission where
  demand : Value
  relation : Value
  judgment : ApplicabilityJudgment

structure OutcomePolicy where
  classify : Value → OutcomeEdge → Applicability

namespace OutcomePolicy

def allCompleted : OutcomePolicy where
  classify _ _ := .completed

def admitted (admissions : List OutcomeAdmission) : OutcomePolicy where
  classify demand edge :=
    match admissions.find? (fun admission =>
        admission.demand == demand && admission.relation == edge.relation) with
    | some admission => admission.judgment.delivery
    | none => .irrelevant

theorem admitted_delivery_witness {admissions demand edge delivery}
    (classified : (admitted admissions).classify demand edge = delivery)
    (visible : delivery ≠ .irrelevant) :
    ∃ admission ∈ admissions,
      admission.demand = demand ∧ admission.relation = edge.relation ∧
        admission.judgment.delivery = delivery := by
  change (match admissions.find? (fun admission =>
      admission.demand == demand && admission.relation == edge.relation) with
    | some admission => admission.judgment.delivery
    | none => .irrelevant) = delivery at classified
  cases found : admissions.find? (fun admission =>
      admission.demand == demand && admission.relation == edge.relation) with
  | none =>
      simp only [found] at classified
      exact (visible classified.symm).elim
  | some admission =>
      have member := List.mem_of_find?_eq_some found
      have accepted := List.find?_some found
      simp only [Bool.and_eq_true, beq_iff_eq] at accepted
      simp only [found] at classified
      exact ⟨admission, member, accepted.1, accepted.2, classified⟩

end OutcomePolicy

inductive Selection where
  | residual (work : Value) (advisory : List OutcomeEdge)
  | outcomes (work : Value) (completed advisory : List OutcomeEdge)
  | decomposed (work : Value) (edge : AllEdge) (completed advisory : List OutcomeEdge)
      (children : List Selection)
  | handoff (work : Value) (prior : Selection)

namespace Selection

def outcomeUses : Selection → List (Applicability × Value × OutcomeEdge)
  | .residual work advisory =>
      advisory.map fun edge => (.advisory, work, edge)
  | .outcomes work completed advisory =>
      completed.map (fun edge => (.completed, work, edge)) ++
        advisory.map fun edge => (.advisory, work, edge)
  | .decomposed work _ completed advisory children =>
      completed.map (fun edge => (.completed, work, edge)) ++
        advisory.map (fun edge => (.advisory, work, edge)) ++
        children.flatMap outcomeUses
  | .handoff _ prior => prior.outcomeUses

def usesFor (delivery : Applicability) (selection : Selection) :
    List (Value × OutcomeEdge) :=
  selection.outcomeUses.filterMap fun use =>
    if use.1 == delivery then some (use.2.1, use.2.2) else none

def completedUses (selection : Selection) : List (Value × OutcomeEdge) :=
  usesFor .completed selection

def advisoryUses (selection : Selection) : List (Value × OutcomeEdge) :=
  usesFor .advisory selection

def priorOutcomes (selection : Selection) : List Value :=
  selection.completedUses.map (fun use => use.2.outcome)

def completedEdges (selection : Selection) : List OutcomeEdge :=
  selection.completedUses.map Prod.snd

def advisoryOutcomes (selection : Selection) : List Value :=
  selection.advisoryUses.map (fun use => use.2.outcome)

def advisoryEdges (selection : Selection) : List OutcomeEdge :=
  selection.advisoryUses.map Prod.snd

def openWork : Selection → List Value
  | .residual work _ => [work]
  | .outcomes _ _ _ => []
  | .decomposed _ _ _ _ children => children.flatMap openWork
  | .handoff work _ => [work]

/-- Every selected Work node before quotient sharing is applied. -/
def workValues : Selection → List Value
  | .residual work _ | .outcomes work _ _ => [work]
  | .decomposed work _ _ _ children => work :: children.flatMap workValues
  | .handoff work prior => work :: prior.workValues

def decompositionEdges : Selection → List AllEdge
  | .residual _ _ | .outcomes _ _ _ => []
  | .decomposed _ edge _ _ children =>
      edge :: children.flatMap decompositionEdges
  | .handoff _ prior => prior.decompositionEdges

/-- The relation closure is derived from the two structural projections, never re-walked. -/
def relationValues (selection : Selection) : List Value :=
  selection.decompositionEdges.map (·.relation) ++
    selection.outcomeUses.map (·.2.2.relation)

/-- Every Outcome selected for either delivery class remains in the structural handoff. -/
theorem outcomeUse_relation_mem {selection : Selection} {delivery : Applicability}
    {demand : Value} {edge : OutcomeEdge}
    (used : (delivery, demand, edge) ∈ selection.outcomeUses) :
    edge.relation ∈ selection.relationValues := by
  apply List.mem_append_right
  exact List.mem_map.mpr ⟨(delivery, demand, edge), used, rfl⟩

theorem completedEdge_relation_mem {selection : Selection} {edge : OutcomeEdge}
    (used : edge ∈ selection.completedEdges) :
    edge.relation ∈ selection.relationValues := by
  simp only [completedEdges, List.mem_map] at used
  obtain ⟨entry, entryUsed, rfl⟩ := used
  simp only [completedUses, usesFor, List.mem_filterMap] at entryUsed
  obtain ⟨use, useUsed, accepted⟩ := entryUsed
  split at accepted
  · simp only [Option.some.injEq] at accepted
    subst entry
    exact outcomeUse_relation_mem useUsed
  · contradiction

theorem advisoryEdge_relation_mem {selection : Selection} {edge : OutcomeEdge}
    (used : edge ∈ selection.advisoryEdges) :
    edge.relation ∈ selection.relationValues := by
  simp only [advisoryEdges, List.mem_map] at used
  obtain ⟨entry, entryUsed, rfl⟩ := used
  simp only [advisoryUses, usesFor, List.mem_filterMap] at entryUsed
  obtain ⟨use, useUsed, accepted⟩ := entryUsed
  split at accepted
  · simp only [Option.some.injEq] at accepted
    subst entry
    exact outcomeUse_relation_mem useUsed
  · contradiction

/-- Completed Work is removed only while its Outcome remains in the handoff. -/
theorem completedUse_outcome_is_prior {selection : Selection} {demand : Value}
    {edge : OutcomeEdge}
    (used : (demand, edge) ∈ selection.completedUses) :
    edge.outcome ∈ selection.priorOutcomes := by
  exact List.mem_map.mpr ⟨(demand, edge), used, rfl⟩

def containsOutcome (graph : WorkGraph) (edge : OutcomeEdge) : Bool :=
  graph.outcomes.any (fun stored => stored.relation == edge.relation)

def containsAll (graph : WorkGraph) (edge : AllEdge) : Bool :=
  graph.all.any (fun stored => stored.relation == edge.relation)

mutual

/--
An executable proof boundary for Extract.  It checks graph provenance,
classification, and the exact child order of every selected decomposition.
Invalid solver output degrades to one open residual instead of escaping.
-/
def structurallyValidAt (graph : WorkGraph) (equality : Equality) :
    Value → Selection → Bool
  | work, .residual selected _ | work, .outcomes selected _ _ =>
      selected == work
  | work, .decomposed selected edge _ _ children =>
      selected == work && equality.same edge.parent work &&
        structurallyValidChildren graph equality
          (graph.childrenFor equality edge) children
  | work, .handoff selected prior =>
      selected == work && structurallyValidAt graph equality work prior

def structurallyValidChildren (graph : WorkGraph) (equality : Equality) :
    List Value → List Selection → Bool
  | work :: works, child :: children =>
      structurallyValidAt graph equality work child &&
        structurallyValidChildren graph equality works children
  | [], [] => true
  | _, _ => false

end

mutual

theorem structurallyValidAt_same_topology (selection : Selection)
    (left right : WorkGraph) (equality : Equality) (work : Value) :
    selection.structurallyValidAt left equality work =
      selection.structurallyValidAt right equality work := by
  cases selection with
  | residual _ _ | outcomes _ _ _ => rfl
  | handoff _ prior =>
      simp only [structurallyValidAt,
        structurallyValidAt_same_topology prior left right equality work]
  | decomposed _ edge _ _ children =>
      simp only [structurallyValidAt, WorkGraph.childrenFor,
        structurallyValidChildren_same_topology children left right equality]

theorem structurallyValidChildren_same_topology (children : List Selection)
    (left right : WorkGraph) (equality : Equality) (works : List Value) :
    structurallyValidChildren left equality works children =
      structurallyValidChildren right equality works children := by
  cases children with
  | nil => cases works <;> rfl
  | cons child tail =>
      cases works with
      | nil => rfl
      | cons work rest =>
          simp only [structurallyValidChildren,
            structurallyValidAt_same_topology child left right equality work,
            structurallyValidChildren_same_topology tail left right equality rest]

end

def validFor (graph : WorkGraph) (equality : Equality)
    (policy : OutcomePolicy) (work : Value) (selection : Selection) : Bool :=
  (selection.structurallyValidAt graph equality work &&
    selection.decompositionEdges.all (containsAll graph)) &&
    (selection.completedUses.all fun use =>
      containsOutcome graph use.2 && equality.same use.2.work use.1 &&
        decide (policy.classify use.1 use.2 = .completed)) &&
    (selection.advisoryUses.all fun use =>
      containsOutcome graph use.2 && equality.same use.2.work use.1 &&
        decide (policy.classify use.1 use.2 = .advisory))

/-- Exact graph membership of every selected edge, including all descendants.
This is independent of the policy and the executable rejection gate. -/
structure Provenance (graph : WorkGraph) (selection : Selection) : Prop where
  decompositions : ∀ edge ∈ selection.decompositionEdges, edge ∈ graph.all
  outcomes : ∀ use ∈ selection.outcomeUses, use.2.2 ∈ graph.outcomes

theorem Provenance.residual (graph : WorkGraph) (work : Value) (advisory : List OutcomeEdge)
    (present : ∀ edge ∈ advisory, edge ∈ graph.outcomes) :
    Provenance graph (.residual work advisory) := by
  constructor
  · simp [decompositionEdges]
  · intro use member
    simp only [outcomeUses, List.mem_map] at member
    obtain ⟨edge, member, rfl⟩ := member
    exact present edge member

theorem Provenance.completed (graph : WorkGraph) (work : Value)
    (completed advisory : List OutcomeEdge)
    (first : ∀ edge ∈ completed, edge ∈ graph.outcomes)
    (second : ∀ edge ∈ advisory, edge ∈ graph.outcomes) :
    Provenance graph (.outcomes work completed advisory) := by
  constructor
  · simp [decompositionEdges]
  · intro use member
    simp only [outcomeUses, List.mem_append, List.mem_map] at member
    rcases member with ⟨edge, member, rfl⟩ | ⟨edge, member, rfl⟩
    · exact first edge member
    · exact second edge member

theorem Provenance.decomposed (graph : WorkGraph) (work : Value) (edge : AllEdge)
    (completed advisory : List OutcomeEdge) (children : List Selection)
    (parent : edge ∈ graph.all)
    (first : ∀ owner ∈ completed, owner ∈ graph.outcomes)
    (second : ∀ owner ∈ advisory, owner ∈ graph.outcomes)
    (descendants : ∀ child ∈ children, Provenance graph child) :
    Provenance graph (.decomposed work edge completed advisory children) := by
  constructor
  · intro chosen member
    simp only [decompositionEdges, List.mem_cons, List.mem_flatMap] at member
    rcases member with rfl | ⟨child, member, used⟩
    · exact parent
    · exact (descendants child member).decompositions chosen used
  · intro use member
    simp only [outcomeUses, List.mem_append, List.mem_map, List.mem_flatMap] at member
    rcases member with (⟨owner, member, rfl⟩ | ⟨owner, member, rfl⟩) | ⟨child, member, used⟩
    · exact first owner member
    · exact second owner member
    · exact (descendants child member).outcomes use used

theorem Provenance.used_owner (known : Provenance graph selection)
    (delivery : Applicability) (use : Value × OutcomeEdge)
    (member : use ∈ selection.usesFor delivery) : use.2 ∈ graph.outcomes := by
  simp only [usesFor, List.mem_filterMap] at member
  obtain ⟨entry, member, chosen⟩ := member
  split at chosen
  · simp only [Option.some.injEq] at chosen
    subst use
    exact known.outcomes entry member
  · contradiction

/-- The real final provenance checker agrees after demand pruning, not just
the recursive solver. Both graphs must contain the actually selected edges;
policy and structural checks are retained verbatim. -/
theorem validFor_provenance_congr (selected : Selection) (left right : WorkGraph)
    (equality : Equality) (policy : OutcomePolicy) (root : Value)
    (first : Provenance left selected) (second : Provenance right selected) :
    selected.validFor left equality policy root = selected.validFor right equality policy root := by
  have allPresent (graph : WorkGraph) (known : Provenance graph selected) :
      selected.decompositionEdges.all (containsAll graph) = true := by
    apply List.all_eq_true.mpr
    intro edge member
    apply List.any_eq_true.mpr
    exact ⟨edge, known.decompositions edge member, by simp⟩
  have uses (delivery : Applicability) :
      (selected.usesFor delivery).all (fun use =>
        containsOutcome left use.2 && equality.same use.2.work use.1 &&
          decide (policy.classify use.1 use.2 = delivery)) =
      (selected.usesFor delivery).all (fun use =>
        containsOutcome right use.2 && equality.same use.2.work use.1 &&
          decide (policy.classify use.1 use.2 = delivery)) := by
    apply Bool.eq_iff_iff.mpr
    simp only [List.all_eq_true]
    apply forall_congr'
    intro use
    apply forall_congr'
    intro member
    have present (graph : WorkGraph) (known : Provenance graph selected) :
        containsOutcome graph use.2 = true :=
      List.any_eq_true.mpr ⟨use.2, known.used_owner delivery use member, by simp⟩
    rw [present left first, present right second]
  simp only [validFor, completedUses, advisoryUses, allPresent left first,
    allPresent right second, uses, structurallyValidAt_same_topology selected left right equality root]

/-- Keeping every relation which can be admitted preserves the real
provenance checker, not merely the solver's list of selected ids. The keep
predicate is over the entire relation, including Exact evidence positions. -/
theorem validFor_selected (graph : WorkGraph) (keep : Value → Bool)
    (policy : OutcomePolicy) (equality : Equality) (root : Value) (selected : Selection)
    (complete : ∀ work edge, policy.classify work edge ≠ .irrelevant →
      keep edge.relation = true) :
    selected.validFor { graph with outcomes := graph.outcomes.filter (fun edge => keep edge.relation) }
      equality policy root = selected.validFor graph equality policy root := by
  let smaller : WorkGraph := { graph with outcomes := graph.outcomes.filter (fun edge => keep edge.relation) }
  have contained (edge : OutcomeEdge) (kept : keep edge.relation = true) :
      containsOutcome smaller edge = containsOutcome graph edge := by
    simp only [containsOutcome, smaller, List.any_filter]
    apply List.any_congr rfl
    intro stored
    cases same : stored.relation == edge.relation with
    | false => simp
    | true =>
        have equal := beq_iff_eq.mp same
        simp [equal, kept]
  have uses (items : List (Value × OutcomeEdge)) (delivery : Applicability)
      (visible : delivery ≠ .irrelevant) :
      (items.all fun use => containsOutcome smaller use.2 &&
        equality.same use.2.work use.1 && decide (policy.classify use.1 use.2 = delivery)) =
      (items.all fun use => containsOutcome graph use.2 &&
        equality.same use.2.work use.1 && decide (policy.classify use.1 use.2 = delivery)) := by
    apply congrArg (fun predicate => items.all predicate)
    funext use
    by_cases classified : policy.classify use.1 use.2 = delivery
    · rw [contained use.2 (complete use.1 use.2 (by simpa [classified] using visible))]
    · simp [classified]
  change selected.validFor smaller equality policy root = _
  simp only [validFor, structurallyValidAt_same_topology selected smaller graph equality root,
    uses selected.completedUses .completed (by decide),
    uses selected.advisoryUses .advisory (by decide)]
  rfl

theorem completedUse_sound {graph equality policy work selection demand edge}
    (valid : validFor graph equality policy work selection)
    (used : (demand, edge) ∈ selection.completedUses) :
    containsOutcome graph edge = true ∧ equality.same edge.work demand = true ∧
      policy.classify demand edge = .completed := by
  simp only [validFor, Bool.and_eq_true, List.all_eq_true] at valid
  obtain ⟨⟨present, same⟩, classified⟩ := valid.1.2 (demand, edge) used
  exact ⟨present, same, of_decide_eq_true classified⟩

theorem advisoryUse_sound {graph equality policy work selection demand edge}
    (valid : validFor graph equality policy work selection)
    (used : (demand, edge) ∈ selection.advisoryUses) :
    containsOutcome graph edge = true ∧ equality.same edge.work demand = true ∧
      policy.classify demand edge = .advisory := by
  simp only [validFor, Bool.and_eq_true, List.all_eq_true] at valid
  obtain ⟨⟨present, same⟩, classified⟩ := valid.2 (demand, edge) used
  exact ⟨present, same, of_decide_eq_true classified⟩

theorem decompositionEdge_sound {graph equality policy work selection edge}
    (valid : validFor graph equality policy work selection)
    (used : edge ∈ selection.decompositionEdges) :
    containsAll graph edge = true := by
  simp only [validFor, Bool.and_eq_true, List.all_eq_true] at valid
  exact valid.1.1.2 edge used

theorem residual_valid (graph equality policy work) :
    validFor graph equality policy work (.residual work []) := by
  simp [validFor, structurallyValidAt, decompositionEdges,
    completedUses, advisoryUses, usesFor, outcomeUses]

theorem handoff_valid {graph equality policy work selection}
    (valid : validFor graph equality policy work selection) :
    validFor graph equality policy work (.handoff work selection) := by
  simpa [validFor, structurallyValidAt, decompositionEdges,
    completedUses, advisoryUses, usesFor, outcomeUses]
    using valid

end Selection

structure Extraction where
  priorOutcomes : List Value
  advisoryOutcomes : List Value
  residual : List Value
  /-- Open semantic leaves before they are collapsed into one external handoff. -/
  discovery : List Value
  support : List Value
  selection : Selection
  prior_visible : ∀ outcome, outcome ∈ selection.priorOutcomes →
    outcome ∈ priorOutcomes
  one_open_handoff : ∃ work, residual = [work]

namespace Extraction

def finalize (root : Value) (selection : Selection) : Selection :=
  match selection.openWork with
  | [_] => selection
  | _ => .handoff root selection

theorem finalize_valid {graph equality policy root selection}
    (valid : selection.validFor graph equality policy root) :
    (finalize root selection).validFor graph equality policy root := by
  unfold finalize
  cases selection.openWork with
  | nil => exact Selection.handoff_valid valid
  | cons head tail =>
      cases tail with
      | nil => exact valid
      | cons next rest => exact Selection.handoff_valid valid

def fromSelection (root : Value) (selection : Selection) : Extraction :=
  let pending := selection.openWork
  let finalSelection := finalize root selection
  {
    priorOutcomes := finalSelection.priorOutcomes.eraseDups
    advisoryOutcomes := finalSelection.advisoryOutcomes.eraseDups
    residual := finalSelection.openWork
    discovery := if pending.isEmpty then [root] else pending.eraseDups
    support := finalSelection.relationValues.eraseDups
    selection := finalSelection
    prior_visible := fun _ member => List.mem_eraseDups.mpr member
    one_open_handoff := by
      cases pendingEq : selection.openWork with
      | nil =>
          exact ⟨root, by simp [finalSelection, finalize, pendingEq, Selection.openWork]⟩
      | cons head tail =>
          cases tail with
          | nil => exact ⟨head, by simp [finalSelection, finalize, pendingEq]⟩
          | cons next rest =>
              exact ⟨root, by simp [finalSelection, finalize, pendingEq, Selection.openWork]⟩
  }

theorem residual_nonempty (extraction : Extraction) : extraction.residual ≠ [] := by
  rcases extraction.one_open_handoff with ⟨work, equals⟩
  simp [equals]

theorem residual_length (extraction : Extraction) : extraction.residual.length = 1 := by
  rcases extraction.one_open_handoff with ⟨work, equals⟩
  simp [equals]

theorem fromSelection_valid {graph equality policy root selection}
    (valid : selection.validFor graph equality policy root) :
    (fromSelection root selection).selection.validFor graph equality policy root := by
  change (finalize root selection).validFor graph equality policy root
  exact finalize_valid valid

end Extraction

namespace Extract

/-- Open Work dominates; equal frontiers choose the smaller transport surface. -/
structure Cost where
  openCount : Nat
  byteCount : Nat
  nodeCount : Nat
  deriving Repr, DecidableEq

namespace Cost

def LE (left right : Cost) : Prop :=
  left.openCount < right.openCount ∨
    left.openCount = right.openCount ∧
      (left.byteCount < right.byteCount ∨
        left.byteCount = right.byteCount ∧ left.nodeCount ≤ right.nodeCount)

instance : DecidableRel LE := fun _ _ => by
  unfold LE
  infer_instance

theorem le_refl (cost : Cost) : cost.LE cost := by
  simp [LE]

theorem le_total (left right : Cost) : left.LE right ∨ right.LE left := by
  unfold LE
  omega

theorem le_trans {left middle right : Cost}
    (leftMiddle : left.LE middle) (middleRight : middle.LE right) :
    left.LE right := by
  unfold LE at *
  omega

end Cost

structure Solution where
  selection : Selection

namespace Solution

def residual (work : Value) (advisory : List OutcomeEdge := []) : Solution :=
  ⟨.residual work advisory⟩

def outcomes (work : Value) (completed advisory : List OutcomeEdge) : Solution :=
  ⟨.outcomes work completed advisory⟩

def cost (solution : Solution) : Cost :=
  let graph := solution.selection.workValues ++ solution.selection.relationValues
  {
    openCount := solution.selection.openWork.length
    byteCount := graph.foldl (fun total value => total + value.structuralSize) 0
    nodeCount := graph.length
  }

def combine (work : Value) (edge : AllEdge) (completed advisory : List OutcomeEdge)
    (children : List Solution) : Solution :=
  ⟨.decomposed work edge completed advisory
    (children.map (fun child => child.selection))⟩

end Solution

def chooseBetter (left right : Solution) : Solution :=
  if left.cost.LE right.cost then left else right

theorem chooseBetter_le_left (left right : Solution) :
    (chooseBetter left right).cost.LE left.cost := by
  unfold chooseBetter
  split
  · exact Cost.le_refl _
  · rename_i notLeft
    exact (Cost.le_total left.cost right.cost).resolve_left notLeft

theorem chooseBetter_le_right (left right : Solution) :
    (chooseBetter left right).cost.LE right.cost := by
  unfold chooseBetter
  split
  · assumption
  · exact Cost.le_refl _

def chooseBest : List Solution → Option Solution
  | [] => none
  | head :: tail =>
      match chooseBest tail with
      | none => some head
      | some best => some (chooseBetter head best)

@[simp]
theorem chooseBest_eq_none_iff (solutions : List Solution) :
    chooseBest solutions = none ↔ solutions = [] := by
  cases solutions with
  | nil => simp [chooseBest]
  | cons head tail =>
      simp only [chooseBest]
      cases chooseBest tail <;> simp

theorem chooseBest_mem {solutions : List Solution} {best : Solution}
    (found : chooseBest solutions = some best) : best ∈ solutions := by
  induction solutions generalizing best with
  | nil => simp [chooseBest] at found
  | cons head tail ih =>
      simp only [chooseBest] at found
      cases chosen : chooseBest tail with
      | none =>
          rw [chosen] at found
          injection found with equal
          subst best
          exact List.mem_cons_self
      | some later =>
          rw [chosen] at found
          injection found with equal
          subst best
          unfold chooseBetter
          split
          · exact List.mem_cons_self
          · exact List.mem_cons_of_mem head (ih chosen)

/-- The chosen explanation is minimum among the supplied candidate derivations. -/
theorem chooseBest_minimal {solutions : List Solution} {best candidate : Solution}
    (found : chooseBest solutions = some best)
    (present : candidate ∈ solutions) :
    best.cost.LE candidate.cost := by
  induction solutions generalizing best candidate with
  | nil => simp at present
  | cons head tail induction =>
      simp only [chooseBest] at found
      cases tailFound : chooseBest tail with
      | none =>
          rw [tailFound] at found
          have empty : tail = [] := (chooseBest_eq_none_iff tail).mp tailFound
          subst tail
          simp only [List.mem_singleton] at present
          subst candidate
          injection found with found
          subst best
          exact Cost.le_refl _
      | some tailBest =>
          rw [tailFound] at found
          injection found with found
          subst best
          cases present with
          | head => exact chooseBetter_le_left head tailBest
          | tail _ inTail =>
              exact Cost.le_trans (chooseBetter_le_right head tailBest)
                (induction tailFound inTail)

/--
Fuel is a totality witness only. Cycles are cut by `active`; quotient-equivalent
children are visited once before the existing recursive extractor is reused.
-/
def solve (graph : WorkGraph) (equality : Equality) (policy : OutcomePolicy) :
    Nat → List Value → Value → Option Solution
  | 0, _, work => some (Solution.residual work)
  | fuel + 1, active, work =>
      if active.contains work then none
      else
        let outcomes := graph.outcomesFor equality work
        let completed := outcomes.filter fun edge => policy.classify work edge == .completed
        let advisory := outcomes.filter fun edge => policy.classify work edge == .advisory
        let candidates := (graph.decompositionsFor equality work).filterMap fun edge =>
          ((graph.childrenFor equality edge).mapM
            (solve graph equality policy fuel (work :: active))).map
            (Solution.combine work edge completed advisory)
        match chooseBest candidates with
        | some best => some best
        | none =>
            if completed.isEmpty then some (Solution.residual work advisory)
            else some (Solution.outcomes work completed advisory)

private theorem mapM_provenance (items : List α) (f : α → Option β) (results : List β)
    (found : items.mapM f = some results) (property : β → Prop)
    (produced : ∀ item ∈ items, ∀ result, f item = some result → property result) :
    ∀ result ∈ results, property result := by
  induction items generalizing results with
  | nil =>
      change (some [] : Option (List β)) = some results at found
      injection found with equal
      subst results
      simp
  | cons head tail ih =>
      cases first : f head with
      | none => simp [List.mapM_cons, first] at found
      | some value =>
          cases later : tail.mapM f with
          | none => simp [List.mapM_cons, first, later] at found
          | some rest =>
              simp [List.mapM_cons, first, later] at found
              subst results
              intro result member
              rcases List.mem_cons.mp member with equal | member
              · subst result
                exact produced head List.mem_cons_self value first
              · exact ih rest later
                  (fun item member => produced item (List.mem_cons_of_mem head member)) result member

/-- Every edge returned by the real recursive solver belongs to its input
graph. This includes all descendants of the chosen ordered alternative;
neither the later checker nor a storage-loader assertion is a premise. -/
theorem solve_provenance (graph : WorkGraph) (equality : Equality) (policy : OutcomePolicy)
    (fuel : Nat) (active : List Value) (work : Value) (solution : Solution)
    (found : solve graph equality policy fuel active work = some solution) :
    Selection.Provenance graph solution.selection := by
  induction fuel generalizing active work solution with
  | zero =>
      simp only [solve, Option.some.injEq] at found
      subst solution
      exact Selection.Provenance.residual graph work [] (by simp)
  | succ fuel ih =>
      simp only [solve] at found
      split at found
      · contradiction
      · let completed := (graph.outcomesFor equality work).filter
          (fun edge => policy.classify work edge == .completed)
        let advisory := (graph.outcomesFor equality work).filter
          (fun edge => policy.classify work edge == .advisory)
        let candidates := (graph.decompositionsFor equality work).filterMap fun edge =>
          ((graph.childrenFor equality edge).mapM
            (solve graph equality policy fuel (work :: active))).map
            (Solution.combine work edge completed advisory)
        have owners (delivery : Applicability) :
            ∀ edge ∈ (graph.outcomesFor equality work).filter
              (fun edge => policy.classify work edge == delivery), edge ∈ graph.outcomes := by
          intro edge member
          exact (List.mem_filter.mp (List.mem_filter.mp member).1).1
        change (match chooseBest candidates with
          | some best => some best
          | none => if completed.isEmpty then some (Solution.residual work advisory)
              else some (Solution.outcomes work completed advisory)) = some solution at found
        cases chosen : chooseBest candidates with
        | none =>
            rw [chosen] at found
            change (if completed.isEmpty then some (Solution.residual work advisory)
              else some (Solution.outcomes work completed advisory)) = some solution at found
            split at found
            · injection found with equal
              subst solution
              exact Selection.Provenance.residual graph work advisory (owners .advisory)
            · injection found with equal
              subst solution
              exact Selection.Provenance.completed graph work completed advisory
                (owners .completed) (owners .advisory)
        | some best =>
            rw [chosen] at found
            injection found with equal
            subst solution
            have member := chooseBest_mem chosen
            simp only [candidates, List.mem_filterMap] at member
            obtain ⟨edge, parent, produced⟩ := member
            cases childrenFound : (graph.childrenFor equality edge).mapM
                (solve graph equality policy fuel (work :: active)) with
            | none => simp [childrenFound] at produced
            | some children =>
                simp only [childrenFound, Option.map_some, Option.some.injEq] at produced
                subst best
                apply Selection.Provenance.decomposed graph work edge completed advisory
                  (children.map (·.selection)) (List.mem_filter.mp parent).1
                  (owners .completed) (owners .advisory)
                intro child member
                obtain ⟨result, resultMember, rfl⟩ := List.mem_map.mp member
                exact mapM_provenance _ _ children childrenFound
                  (fun result => Selection.Provenance graph result.selection)
                  (fun next _ result recorded => ih (work :: active) next result recorded) result resultMember

private theorem filterMap_on_domain (items : List α) (first second : α → Option β)
    (same : ∀ item ∈ items, first item = second item) :
    items.filterMap first = items.filterMap second := by
  induction items with
  | nil => rfl
  | cons head tail ih =>
      simp only [List.filterMap_cons, same head (by simp)]
      rw [ih (fun item member => same item (by simp [member]))]

private theorem mapM_on_domain (items : List α) (first second : α → Option β)
    (same : ∀ item ∈ items, first item = second item) :
    items.mapM first = items.mapM second := by
  induction items with
  | nil => rfl
  | cons head tail ih =>
      simp only [List.mapM_cons, same head (by simp),
        ih (fun item member => same item (by simp [member]))]

/-- Demand pruning preserves the actual recursive solver, including ordered
alternatives, cycles and open work. The domain must include every child of
every reachable alternative; retaining only previously selected evidence is
not sufficient. This is independent of how the storage index finds edges. -/
theorem solve_demand_exact (left right : WorkGraph) (equality : Equality)
    (policy : OutcomePolicy) (domain : Value → Prop)
    (owners : ∀ work, domain work →
      left.outcomesFor equality work = right.outcomesFor equality work)
    (parents : ∀ work, domain work →
      left.decompositionsFor equality work = right.decompositionsFor equality work)
    (closed : ∀ work, domain work → ∀ edge ∈ left.decompositionsFor equality work,
      ∀ child ∈ left.childrenFor equality edge, domain child)
    (fuel : Nat) (active : List Value) (work : Value) (member : domain work) :
    solve left equality policy fuel active work = solve right equality policy fuel active work := by
  induction fuel generalizing active work with
  | zero => rfl
  | succ fuel ih =>
      simp only [solve]
      by_cases cycle : active.contains work = true
      · simp only [cycle, ↓reduceIte]
      · simp only [cycle, Bool.false_eq_true, ↓reduceIte, owners work member, parents work member]
        have candidates :
            (right.decompositionsFor equality work).filterMap (fun edge =>
              ((left.childrenFor equality edge).mapM (solve left equality policy fuel (work :: active))).map
                (Solution.combine work edge
                  ((right.outcomesFor equality work).filter (fun edge => policy.classify work edge == .completed))
                  ((right.outcomesFor equality work).filter (fun edge => policy.classify work edge == .advisory)))) =
            (right.decompositionsFor equality work).filterMap (fun edge =>
              ((right.childrenFor equality edge).mapM (solve right equality policy fuel (work :: active))).map
                (Solution.combine work edge
                  ((right.outcomesFor equality work).filter (fun edge => policy.classify work edge == .completed))
                  ((right.outcomesFor equality work).filter (fun edge => policy.classify work edge == .advisory)))) := by
          apply filterMap_on_domain
          intro edge edgeMember
          have before : edge ∈ left.decompositionsFor equality work := by
            rw [parents work member]
            exact edgeMember
          have sameChildren : left.childrenFor equality edge = right.childrenFor equality edge := rfl
          rw [sameChildren]
          apply congrArg (Option.map _)
          apply mapM_on_domain
          intro child childMember
          apply ih (work :: active) child
          exact closed work member edge before child childMember
        rw [candidates]

def runWithPolicyFuel (graph : WorkGraph) (equality : Equality)
    (policy : OutcomePolicy) (fuel : Nat) (root : Value) : Extraction :=
  let solution := (solve graph equality policy fuel [] root).getD (Solution.residual root)
  let checked := if solution.selection.validFor graph equality policy root then
    solution.selection else .residual root []
  .fromSelection root checked

/-- Complete extraction, including the final rejection gate and all evidence
projections, is equal under the same demand-domain observations. The explicit
reference fuel must be retained when pruning source topology or bodies. -/
theorem runWithPolicyFuel_demand_exact (left right : WorkGraph) (equality : Equality)
    (policy : OutcomePolicy) (domain : Value → Prop)
    (owners : ∀ work, domain work →
      left.outcomesFor equality work = right.outcomesFor equality work)
    (parents : ∀ work, domain work →
      left.decompositionsFor equality work = right.decompositionsFor equality work)
    (closed : ∀ work, domain work → ∀ edge ∈ left.decompositionsFor equality work,
      ∀ child ∈ left.childrenFor equality edge, domain child)
    (fuel : Nat) (root : Value) (member : domain root) :
    runWithPolicyFuel left equality policy fuel root = runWithPolicyFuel right equality policy fuel root := by
  have same := solve_demand_exact left right equality policy domain owners parents closed fuel [] root member
  have provenance (graph : WorkGraph) :
      Selection.Provenance graph
        ((solve graph equality policy fuel [] root).getD (Solution.residual root)).selection := by
    cases recorded : solve graph equality policy fuel [] root with
    | none => exact Selection.Provenance.residual graph root [] (by simp)
    | some solution => exact solve_provenance graph equality policy fuel [] root solution recorded
  have other : Selection.Provenance right
      ((solve left equality policy fuel [] root).getD (Solution.residual root)).selection := by
    rw [same]; exact provenance right
  have gate := Selection.validFor_provenance_congr _ left right equality policy root
    (provenance left) other
  unfold runWithPolicyFuel
  rw [← same]
  dsimp only
  rw [gate]

def runWithPolicy (graph : WorkGraph) (equality : Equality)
    (policy : OutcomePolicy) (root : Value) : Extraction :=
  runWithPolicyFuel graph equality policy (graph.all.length + graph.outcomes.length + 1) root

def run (graph : WorkGraph) (equality : Equality) (root : Value) : Extraction :=
  runWithPolicy graph equality .allCompleted root

/-- Before any admission, unrelated Outcome owners cannot create another
Demand. If the complete topology has no decomposition for this root, the
full extraction is exactly one unresolved root, regardless of body count. -/
theorem runWithPolicy_unadmitted_root (graph : WorkGraph) (equality : Equality)
    (root : Value) (noChoice : graph.decompositionsFor equality root = []) :
    runWithPolicy graph equality (.admitted []) root =
      Extraction.fromSelection root (.residual root []) := by
  have drop (edges : List OutcomeEdge) : edges.filter (fun _ => false) = [] :=
    List.filter_eq_nil_iff.mpr (by intro edge member; simp)
  simp [runWithPolicy, runWithPolicyFuel, solve, noChoice, OutcomePolicy.admitted,
    show (Applicability.irrelevant == Applicability.completed) = false from rfl,
    show (Applicability.irrelevant == Applicability.advisory) = false from rfl,
    chooseBest, drop, Solution.residual]

/-- At a root with no decomposition, recursion depth and irrelevant owners
cannot affect extraction. The selected completion/advice lists and their
validation against the original graph completely determine the result. -/
theorem runWithPolicy_terminal_exact (left right : WorkGraph) (equality : Equality)
    (policy : OutcomePolicy) (root : Value)
    (leftChoice : left.decompositionsFor equality root = [])
    (rightChoice : right.decompositionsFor equality root = [])
    (completed : (left.outcomesFor equality root).filter
        (fun edge => policy.classify root edge == .completed) =
      (right.outcomesFor equality root).filter
        (fun edge => policy.classify root edge == .completed))
    (advisory : (left.outcomesFor equality root).filter
        (fun edge => policy.classify root edge == .advisory) =
      (right.outcomesFor equality root).filter
        (fun edge => policy.classify root edge == .advisory))
    (validation : ∀ selected : Selection,
      selected.validFor left equality policy root =
        selected.validFor right equality policy root) :
    runWithPolicy left equality policy root = runWithPolicy right equality policy root := by
  simp only [runWithPolicy, runWithPolicyFuel, solve,
    List.contains_nil, Bool.false_eq_true, ↓reduceIte,
    leftChoice, rightChoice, List.filterMap_nil, chooseBest, completed, advisory]
  simp only [validation]

/-- A terminal root's extraction has no decomposition node. Removing All
edges elsewhere therefore preserves the complete checked Selection, not
only the Outcome lists or the amount of rendered evidence. -/
theorem runWithPolicy_terminal_all_irrelevant (graph : WorkGraph) (equality : Equality)
    (policy : OutcomePolicy) (root : Value)
    (noChoice : graph.decompositionsFor equality root = []) :
    runWithPolicy {graph with all := []} equality policy root =
      runWithPolicy graph equality policy root := by
  have emptyChoice : ({graph with all := []} : WorkGraph).decompositionsFor equality root = [] := rfl
  simp only [runWithPolicy, runWithPolicyFuel, solve, List.contains_nil,
    Bool.false_eq_true, ↓reduceIte, noChoice, emptyChoice,
    List.filterMap_nil, chooseBest, WorkGraph.outcomesFor]
  by_cases missing : ((graph.outcomes.filter fun edge => equality.same edge.work root).filter
    (fun edge => policy.classify root edge == .completed)).isEmpty = true
  all_goals
    simp only [missing, ↓reduceIte, Option.getD_some]
    simp [Solution.residual, Solution.outcomes, Selection.validFor,
      Selection.structurallyValidAt, Selection.decompositionEdges,
      Selection.completedUses, Selection.advisoryUses, Selection.usesFor,
      Selection.outcomeUses, Selection.containsOutcome]

/-- A selected owner projection preserves the classified list in its original
order, including duplicate evidence. This is independent of topology. -/
theorem classified_selected (graph : WorkGraph) (keep : Value → Bool)
    (policy : OutcomePolicy) (equality : Equality) (root : Value)
    (delivery : Applicability) (notIrrelevant : delivery ≠ .irrelevant)
    (complete : ∀ work edge, policy.classify work edge ≠ .irrelevant →
      keep edge.relation = true) :
    (WorkGraph.outcomesFor
        { graph with outcomes := graph.outcomes.filter (fun edge => keep edge.relation) }
        equality root).filter (fun edge => policy.classify root edge == delivery) =
      (graph.outcomesFor equality root).filter (fun edge => policy.classify root edge == delivery) := by
    simp only [WorkGraph.outcomesFor, List.filter_filter]
    apply List.filter_congr
    intro edge member
    cases delivery with
    | irrelevant => contradiction
    | completed =>
        cases classified : policy.classify root edge with
        | irrelevant =>
            simp only [show (Applicability.irrelevant == Applicability.completed) = false from rfl,
              Bool.false_and]
        | advisory =>
            simp only [show (Applicability.advisory == Applicability.completed) = false from rfl,
              Bool.false_and]
        | completed => simp [complete root edge (by simp [classified])]
    | advisory =>
        cases classified : policy.classify root edge with
        | irrelevant =>
            simp only [show (Applicability.irrelevant == Applicability.advisory) = false from rfl,
              Bool.false_and]
        | completed =>
            simp only [show (Applicability.completed == Applicability.advisory) = false from rfl,
              Bool.false_and]
        | advisory => simp [complete root edge (by simp [classified])]
/-- The real recursive solver is insensitive to policy-irrelevant bodies at
the SAME depth. Keeping the depth explicit is necessary for cyclic graphs:
the number of hydrated owners must never shorten the reference traversal. -/
theorem solve_selected (graph : WorkGraph) (keep : Value → Bool)
    (policy : OutcomePolicy) (equality : Equality)
    (complete : ∀ work edge, policy.classify work edge ≠ .irrelevant →
      keep edge.relation = true) (fuel : Nat) (active : List Value) (root : Value) :
    solve { graph with outcomes := graph.outcomes.filter (fun edge => keep edge.relation) }
      equality policy fuel active root = solve graph equality policy fuel active root := by
  induction fuel generalizing active root with
  | zero => rfl
  | succ fuel ih =>
      simp only [solve]
      by_cases cycle : active.contains root = true
      · simp only [cycle, ↓reduceIte]
      · simp only [cycle,
          classified_selected graph keep policy equality root .completed (by decide) complete,
          classified_selected graph keep policy equality root .advisory (by decide) complete]
        have visit : solve
            { graph with outcomes := graph.outcomes.filter (fun edge => keep edge.relation) }
            equality policy fuel (root :: active) = solve graph equality policy fuel (root :: active) :=
          funext (ih (root :: active))
        simp only [WorkGraph.decompositionsFor, WorkGraph.childrenFor, visit]

/-- Complete ordered extraction and provenance validation for arbitrary
All/Union topology, including cycles, at the authoritative traversal depth. -/
theorem runWithPolicyFuel_selected (graph : WorkGraph) (keep : Value → Bool)
    (policy : OutcomePolicy) (equality : Equality) (fuel : Nat) (root : Value)
    (complete : ∀ work edge, policy.classify work edge ≠ .irrelevant →
      keep edge.relation = true) :
    runWithPolicyFuel
      { graph with outcomes := graph.outcomes.filter (fun edge => keep edge.relation) }
      equality policy fuel root = runWithPolicyFuel graph equality policy fuel root := by
  simp only [runWithPolicyFuel, solve_selected graph keep policy equality complete,
    Selection.validFor_selected graph keep policy equality root _ complete]

/-- Removing policy-irrelevant Outcome bodies preserves complete ordered
terminal extraction, including its provenance validation. -/
theorem runWithPolicy_terminal_selected (graph : WorkGraph) (keep : Value → Bool)
    (policy : OutcomePolicy) (equality : Equality) (root : Value)
    (noChoice : graph.decompositionsFor equality root = [])
    (complete : ∀ work edge, policy.classify work edge ≠ .irrelevant →
      keep edge.relation = true) :
    runWithPolicy { graph with outcomes := graph.outcomes.filter (fun edge => keep edge.relation) }
      equality policy root = runWithPolicy graph equality policy root := by
  exact runWithPolicy_terminal_exact _ graph equality policy root noChoice noChoice
    (classified_selected graph keep policy equality root .completed (by decide) complete)
    (classified_selected graph keep policy equality root .advisory (by decide) complete)
    (fun selection => Selection.validFor_selected graph keep policy equality root selection complete)

theorem run_always_hands_off (graph equality root) :
    (run graph equality root).residual.length = 1 :=
  Extraction.residual_length _

theorem run_never_finishes_the_inquiry (graph equality root) :
    (run graph equality root).residual ≠ [] :=
  Extraction.residual_nonempty _

/-- Every edge returned by Extract has passed the general graph/policy checker. -/
theorem runWithPolicyFuel_sound (graph equality policy fuel root) :
    (runWithPolicyFuel graph equality policy fuel root).selection.validFor
      graph equality policy root := by
  simp only [runWithPolicyFuel]
  split
  · exact Extraction.fromSelection_valid (by assumption)
  · apply Extraction.fromSelection_valid
    exact Selection.residual_valid graph equality policy root

theorem runWithPolicy_sound (graph equality policy root) :
    (runWithPolicy graph equality policy root).selection.validFor
      graph equality policy root :=
  runWithPolicyFuel_sound graph equality policy _ root

end Extract

end Eggshell
