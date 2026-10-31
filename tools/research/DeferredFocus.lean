module
@[expose] public section
namespace Eggshell.Research.DeferredFocus

/-- `ready` includes a final rejection as `some none` when the result itself
is optional. Only absence of an early result evaluates the fallback. -/
def eager (focus : Unit → β) (ready : Option α) (fallback : β → α) : α :=
  let hint := focus ()
  match ready with
  | some result => result
  | none => fallback hint

def deferred (focus : Unit → β) (ready : Option α) (fallback : β → α) : α :=
  match ready with
  | some result => result
  | none => fallback (focus ())

theorem branch_result_unchanged (focus : Unit → β) (ready : Option α) (fallback : β → α) :
    eager focus ready fallback = deferred focus ready fallback := by
  cases ready <;> rfl

theorem rejection_unchanged (focus : Unit → β) (fallback : β → Option α) :
    deferred focus (some none) fallback = none := rfl

theorem fallback_unchanged (focus : Unit → β) (fallback : β → α) :
    deferred focus none fallback = fallback (focus ()) := rfl

end Eggshell.Research.DeferredFocus
