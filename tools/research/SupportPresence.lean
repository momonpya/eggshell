module
public import Init.Data.List.Lemmas
public import Init.Data.String.Lemmas
@[expose] public section
namespace Eggshell.Research.SupportPresence

def reference (keys shared : List String) (whole prefixKey owner : String) : Bool :=
  keys.eraseDups.contains whole || keys.eraseDups.any (·.startsWith prefixKey) || shared.contains owner

/-- Membership ignores duplicate keys. Shared original ownership is the common
case and does not require searching contextual/whole-owner transport keys. -/
@[noinline] def supported (keys shared : List String) (whole prefixKey owner : String) : Bool :=
  shared.contains owner || keys.contains whole || keys.any (·.startsWith prefixKey)

theorem contains_eraseDups (keys : List String) (value : String) :
    keys.eraseDups.contains value = keys.contains value := by
  simp only [List.contains_eq_mem,List.mem_eraseDups]

theorem any_eraseDups (keys : List String) (predicate : String → Bool) :
    keys.eraseDups.any predicate = keys.any predicate := by
  apply Bool.eq_iff_iff.mpr
  simp only [List.any_eq_true,List.mem_eraseDups]

theorem supported_exact (keys shared : List String) (whole prefixKey owner : String) :
    supported keys shared whole prefixKey owner = reference keys shared whole prefixKey owner := by
  simp only [supported,reference,contains_eraseDups,any_eraseDups]
  simp only [Bool.or_assoc,Bool.or_left_comm,Bool.or_comm]

def selectReference {α : Type} (keys shared : List String) (rows : List α)
    (coordinates : α → String × String × String) : List α :=
  let distinct := keys.eraseDups
  rows.filter fun row =>
    let (whole,prefixKey,owner) := coordinates row
    distinct.contains whole || distinct.any (·.startsWith prefixKey) || shared.contains owner

@[noinline, nospecialize] def select {α : Type} (keys shared : List String) (rows : List α)
    (coordinates : α → String × String × String) : List α :=
  rows.filter fun row =>
    let (whole,prefixKey,owner) := coordinates row
    supported keys shared whole prefixKey owner

theorem select_exact {α : Type} (keys shared : List String) (rows : List α)
    (coordinates : α → String × String × String) :
    select keys shared rows coordinates = selectReference keys shared rows coordinates := by
  unfold select selectReference
  apply List.filter_congr
  intro row _
  exact supported_exact keys shared (coordinates row).1 (coordinates row).2.1 (coordinates row).2.2

#print axioms supported_exact
#print axioms select_exact
end Eggshell.Research.SupportPresence
