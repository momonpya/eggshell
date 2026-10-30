module
public import Std
@[expose] public section

namespace Eggshell.Research.ResidualInterval

inductive Reach (edge : α → α → Prop) : α → α → Prop
  | same (node : α) : Reach edge node node
  | step {first prior last : α} : Reach edge first prior → edge prior last → Reach edge first last

def Closed (edge : α → α → Prop) (selected : α → Prop) : Prop :=
  ∀ first last, selected first → edge first last → selected last

theorem reach_preserves (closed : Closed edge selected) (path : Reach edge first last)
    (start : selected first) : selected last := by
  induction path with
  | same => exact start
  | step _ next ih => exact closed _ _ ih next

/-- Every residual-closed source side lies between source reachability and
the complement of sink reachability. This does not identify Work classes. -/
theorem bounds (closed : Closed edge selected) (hasSource : selected source)
    (noSink : ¬selected sink) :
    (∀ node, Reach edge source node → selected node) ∧
      (∀ node, selected node → ¬Reach edge node sink) := by
  constructor
  · intro node path
    exact reach_preserves closed path hasSource
  · intro node inside path
    exact noSink (reach_preserves closed path inside)

end Eggshell.Research.ResidualInterval
