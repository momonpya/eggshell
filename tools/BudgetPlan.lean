module

public import Std

@[expose] public section
namespace Eggshell

/-- Materialize budget-independent preparation before evaluating alternatives.
The two real cases retain a constructor boundary in native compilation;
returning a curried function lets arity expansion repeat preparation. -/
inductive BudgetPlan (α : Type) where
  | constant (value : Option α)
  | sized (render : Nat → Option α)

def BudgetPlan.eval (plan : BudgetPlan α) (budget : Nat) : Option α :=
  match plan with
  | .constant value => value
  | .sized render => render budget

def BudgetPlan.map (f : α → β) : BudgetPlan α → BudgetPlan β
  | .constant value => .constant (value.map f)
  | .sized render => .sized fun budget => (render budget).map f

theorem BudgetPlan.eval_map (f : α → β) (plan : BudgetPlan α) (budget : Nat) :
    (plan.map f).eval budget = (plan.eval budget).map f := by
  cases plan <;> rfl

end Eggshell
