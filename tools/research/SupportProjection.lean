module
public import tools.research.SupportPresence
@[expose] public section
namespace Eggshell.Research.SupportPresence

@[noinline, nospecialize] def project {α β : Type} (keys shared : List String) (rows : List α)
    (coordinates : α → String × String × String) (value : α → β) : List β :=
  (select keys shared rows coordinates).map value

def referenceProject {α β : Type} (keys shared : List String) (rows : List α)
    (coordinates : α → String × String × String) (value : α → β) : List β :=
  let distinct := keys.eraseDups
  rows.filterMap fun row =>
    let (whole,prefixKey,owner) := coordinates row
    if distinct.contains whole || distinct.any (·.startsWith prefixKey) || shared.contains owner then
      some (value row) else none

theorem map_filter_exact {α β : Type} (rows : List α) (keep : α → Bool) (value : α → β) :
    (rows.filter keep).map value = rows.filterMap (fun row => if keep row then some (value row) else none) := by
  induction rows with
  | nil => rfl
  | cons head tail ih =>
      cases kept : keep head <;> simp [kept,ih]

/-- The complete original payload projection, retaining duplicates and order.
No hash match, approximation or new ownership rule enters the selection. -/
theorem project_exact {α β : Type} (keys shared : List String) (rows : List α)
    (coordinates : α → String × String × String) (value : α → β) :
    project keys shared rows coordinates value = referenceProject keys shared rows coordinates value := by
  unfold project referenceProject
  rw [select_exact]
  unfold selectReference
  exact map_filter_exact rows _ value

@[csimp] theorem reference_project_compiled : @referenceProject = @project := by
  funext α β keys shared rows coordinates value
  exact (project_exact keys shared rows coordinates value).symm

#print axioms project_exact
#print axioms reference_project_compiled
end Eggshell.Research.SupportPresence
