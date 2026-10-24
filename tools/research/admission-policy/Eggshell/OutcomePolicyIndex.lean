module
public import Eggshell.Extract
public import Std.Data.HashMap.Lemmas

@[expose] public section
namespace Eggshell.OutcomePolicyIndex

/-- The first admission's delivery for an exact demand/relation pair wins.
This is an access path over admitted authority, not a source of authority. -/
def table (admissions : List OutcomeAdmission) :
    Std.HashMap (Value × Value) Applicability :=
  admissions.foldr (fun admission known =>
    known.insert (admission.demand, admission.relation) admission.judgment.delivery) {}

theorem table_exact (admissions : List OutcomeAdmission) (demand relation : Value) :
    (table admissions)[(demand, relation)]? =
      (admissions.find? (fun admission =>
        admission.demand == demand && admission.relation == relation)).map
        (·.judgment.delivery) := by
  induction admissions with
  | nil => simp [table]
  | cons admission rest ih =>
      change ((table rest).insert (admission.demand, admission.relation)
        admission.judgment.delivery)[(demand, relation)]? = _
      rw [Std.HashMap.getElem?_insert, List.find?_cons, ih]
      have key : ((admission.demand, admission.relation) == (demand, relation)) =
          (admission.demand == demand && admission.relation == relation) := rfl
      rw [key]
      cases admission.demand == demand && admission.relation == relation <;> rfl

/-- Build once per immutable admission list; classify by full structural keys. -/
def admitted (admissions : List OutcomeAdmission) : OutcomePolicy :=
  let known := table admissions
  { classify := fun demand edge => known[(demand, edge.relation)]?.getD .irrelevant }

theorem classify_exact (admissions : List OutcomeAdmission) (demand : Value)
    (edge : OutcomeEdge) :
    (admitted admissions).classify demand edge =
      (OutcomePolicy.admitted admissions).classify demand edge := by
  simp only [admitted, table_exact, OutcomePolicy.admitted]
  cases admissions.find? (fun admission =>
    admission.demand == demand && admission.relation == edge.relation) <;> rfl

/-- The logical policy and all existing witnesses stay unchanged. The compiler
replaces repeated list searches with this extensionally equal index. -/
@[csimp] theorem admitted_compiled : OutcomePolicy.admitted = admitted := by
  funext admissions
  exact congrArg OutcomePolicy.mk (funext fun demand => funext fun edge =>
    (classify_exact admissions demand edge).symm)

end Eggshell.OutcomePolicyIndex
