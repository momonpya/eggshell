module
public import Eggshell.OperationWire
@[expose] public section

namespace Eggshell.Research.SearchReadCut
open Plugin.OperationWire

/-- Only the request owner advances the read phase. Neither phase contains a
mutable deadline, a cache handle, a mutex, or a callback. -/
inductive Frame (α : Type) where
  | ready (identity : Identity)
  | reply (identity : Identity) (value : α)

inductive Next (α : Type) where
  | finished (value : α)
  | final (deadline : Nat)

def first (expected : Identity) (finishReady : Bool) (cutoff arrived : Nat)
    (frame : Frame α) : Except String (Next α) :=
  match frame with
  | .ready actual =>
    if actual == expected && arrived < cutoff then
      .ok (.final (readyDeadline expected actual finishReady cutoff arrived))
    else .error "foreign or expired search progress"
  | .reply actual value =>
    if actual == expected && arrived < cutoff then .ok (.finished value)
    else .error "foreign or expired search reply"

def final (expected : Identity) (cutoff arrived : Nat) (frame : Frame α) : Except String α :=
  match frame with
  | .ready _ => .error "repeated search progress"
  | .reply actual value =>
    if actual == expected && arrived < cutoff then .ok value
    else .error "foreign or expired search reply"

theorem advanced_bounded (expected : Identity) (finishReady : Bool) (cutoff arrived next : Nat)
    (frame : Frame α) (accepted : first expected finishReady cutoff arrived frame = .ok (.final next)) :
    next ≤ expected.deadline := by
  cases frame with
  | ready actual =>
    simp only [first] at accepted
    split at accepted
    · cases accepted
      exact Nat.min_le_left _ _
    · cases accepted
  | reply actual value =>
    simp only [first] at accepted
    split at accepted <;> cases accepted

theorem late_first_refused (expected : Identity) (finishReady : Bool) (cutoff arrived : Nat)
    (frame : Frame α) (late : cutoff ≤ arrived) :
    (first expected finishReady cutoff arrived frame).isOk = false := by
  cases frame <;> simp [first,Nat.not_lt.mpr late,Except.isOk,Except.toBool]

theorem late_final_refused (expected actual : Identity) (cutoff arrived : Nat) (value : α)
    (late : cutoff ≤ arrived) :
    (final expected cutoff arrived (.reply actual value)).isOk = false := by
  simp [final,Nat.not_lt.mpr late,Except.isOk,Except.toBool]

theorem repeated_ready_refused (expected actual : Identity) (cutoff arrived : Nat) :
    final expected cutoff arrived (.ready actual : Frame α) = .error "repeated search progress" := rfl

theorem foreign_first_refused (expected actual : Identity) (finishReady : Bool) (cutoff arrived : Nat)
    (foreign : (actual == expected) = false) :
    (first expected finishReady cutoff arrived (.ready actual : Frame α)).isOk = false := by
  simp [first,foreign,Except.isOk,Except.toBool]

theorem foreign_final_refused (expected actual : Identity) (cutoff arrived : Nat) (value : α)
    (foreign : (actual == expected) = false) :
    (final expected cutoff arrived (.reply actual value)).isOk = false := by
  simp [final,foreign,Except.isOk,Except.toBool]

end Eggshell.Research.SearchReadCut
