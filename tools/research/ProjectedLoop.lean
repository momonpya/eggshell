module
public import Std
@[expose] public section

namespace Eggshell.Research.ProjectedLoop

def projectStep (project : State → Value) : ForInStep State → ForInStep Value
  | .done state => .done (project state)
  | .yield state => .yield (project state)

/-- A pure imperative producer may retain descriptions while its reference
constructs full values. This projection preserves the complete loop, including
early return. No commutation or associativity of its producer is assumed. -/
theorem forIn_project (project : State → Value)
    (advance : Input → State → Id (ForInStep State))
    (reference : Input → Value → Id (ForInStep Value))
    (preserves : ∀ input state, projectStep project (advance input state) = reference input (project state))
    (inputs : List Input) (initial : State) :
    project (forIn inputs initial advance) = forIn inputs (project initial) reference := by
  induction inputs generalizing initial with
  | nil => rfl
  | cons input rest ih =>
    have one := preserves input initial
    cases advanced : advance input initial with
    | done state =>
      rw [advanced] at one
      simp only [projectStep] at one
      simp [List.forIn_cons,advanced,← one,Bind.bind]
      rfl
    | yield state =>
      rw [advanced] at one
      simp only [projectStep] at one
      simpa [List.forIn_cons,advanced,← one,Bind.bind] using ih state

theorem array_forIn_project (project : State → Value)
    (advance : Input → State → Id (ForInStep State))
    (reference : Input → Value → Id (ForInStep Value))
    (preserves : ∀ input state, projectStep project (advance input state) = reference input (project state))
    (inputs : Array Input) (initial : State) :
    project (forIn inputs initial advance) = forIn inputs (project initial) reference := by
  simpa only [Array.forIn_toList] using forIn_project project advance reference preserves inputs.toList initial

end Eggshell.Research.ProjectedLoop

#print axioms Eggshell.Research.ProjectedLoop.forIn_project
