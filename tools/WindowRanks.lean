module

public import Eggshell.HashDistinct

@[expose] public section

namespace Eggshell.WindowRanks

/-- Ranked hints are bounded by the original source domain. They are not
repair requests: receiving positions does not authorize reading 33+ windows. -/
structure Choices (count : Nat) where
  indices : List Nat
  bounded : indices.length ≤ count
  distinct : indices.eraseDups = indices
  within : indices.all (fun index => decide (index < count)) = true

def Choices.check? (count : Nat) (indices : List Nat) : Option (Choices count) :=
  if valid : indices.length ≤ count ∧ hashDistinct indices = indices ∧
      indices.all (fun index => decide (index < count)) = true then
    some ⟨indices, valid.1, by simpa only [HashDistinct.reference] using valid.2.1, valid.2.2⟩
  else none

def Choices.handles (choices : Choices count) : List (Fin count) :=
  choices.indices.attach.map fun index => ⟨index.val, by
    have valid := (List.all_eq_true.mp choices.within) index.val index.property
    exact of_decide_eq_true valid⟩

theorem Choices.handles_exact (choices : Choices count) :
    choices.handles.map Fin.val = choices.indices := by
  simp [handles]

theorem Choices.handles_bounded (choices : Choices count) :
    choices.handles.length ≤ count := by
  simpa [handles] using choices.bounded

end Eggshell.WindowRanks
