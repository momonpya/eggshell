module

@[expose] public section

namespace Eggshell.Plugin.Worker.Lifetime

/-- Closure is terminal. Removing an owned resource never opens this cell. -/
inductive Cell (α : Type) where
  | open (value : α)
  | closed

instance : Inhabited (Cell α) := ⟨.closed⟩

def close : Cell α → Cell α × Option α
  | .open value => (.closed, some value)
  | .closed => (.closed, none)

inductive Admission (α : Type) where
  | refused
  | reuse (value : α)
  | spawn

def admit : Cell (Option α) → Admission α
  | .closed => .refused
  | .open none => .spawn
  | .open (some value) => .reuse value

/-- Transfer ownership to the retiring caller before it performs blocking IO. -/
def release (predicate : α → Bool) : Cell (Option α) → Cell (Option α) × Option α
  | .open (some value) => if predicate value then (.open none, some value)
      else (.open (some value), none)
  | other => (other, none)

theorem close_is_closed (state : Cell α) : (close state).1 = .closed := by
  cases state <;> rfl

theorem closed_retains_no_owner : close (.closed : Cell α) = (.closed, none) := rfl

theorem close_cannot_admit (state : Cell (Option α)) :
    admit (close state).1 = .refused := by
  rw [close_is_closed]; rfl

theorem release_cannot_reopen (predicate : α → Bool) :
    release predicate .closed = (.closed, none) := rfl

theorem second_close_has_no_owner (state : Cell α) :
    (close (close state).1).2 = none := by
  rw [close_is_closed]; rfl

end Eggshell.Plugin.Worker.Lifetime
