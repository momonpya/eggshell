module
public import Std.Data.HashSet.Lemmas
@[expose] public section

namespace Eggshell.Research.MemoGroupFold

variable {α β κ ε : Type} [BEq α] [Hashable α] [LawfulBEq α]
  [BEq κ] [Hashable κ] [LawfulBEq κ]

structure Output (β κ : Type) [BEq κ] [Hashable κ] where
  values : Array β
  keys : Std.HashSet κ

def emit (key : β → κ) (out : Output β κ) (item : Option β) : Output β κ :=
  match item with
  | none => out
  | some value =>
    if out.keys.contains (key value) then out
    else ⟨out.values.push value,out.keys.insert (key value)⟩

def Accepted (key : β → κ) (out : Output β κ) (item : Option β) : Prop :=
  ∀ value, item = some value → out.keys.contains (key value) = true

theorem emit_keeps (key : β → κ) (out : Output β κ) (item : Option β)
    (prior : out.keys.contains query = true) :
    (emit key out item).keys.contains query = true := by
  cases item with
  | none => exact prior
  | some value =>
    simp only [emit]
    split
    · exact prior
    · simp [Std.HashSet.contains_insert,prior]

theorem emit_accepts (key : β → κ) (out : Output β κ) (item : Option β) :
    Accepted key (emit key out item) item := by
  intro value same
  subst item
  simp only [emit]
  split
  · exact ‹out.keys.contains (key value) = true›
  · simp

omit [LawfulBEq κ] in
theorem emit_already (key : β → κ) (out : Output β κ) (item : Option β)
    (accepted : Accepted key out item) : emit key out item = out := by
  cases item with
  | none => rfl
  | some value => simp [emit,accepted value rfl]

/-- Runtime storage contains only encountered inputs, output keys and the
original output array. Previously calculated payloads live only in this
erased certificate, so memoization cannot retain a second result catalogue. -/
structure State (make : α → Except ε (Option β)) (key : β → κ) where
  out : Output β κ
  inputs : Std.HashSet α
  checked : ∀ input, inputs.contains input = true →
    ∃ item, make input = .ok item ∧ Accepted key out item

def initial (make : α → Except ε (Option β)) (key : β → κ)
    (out : Output β κ) : State make key :=
  ⟨out,{},by intro input present; simp at present⟩

def referenceStep (make : α → Except ε (Option β)) (key : β → κ)
    (out : Output β κ) (input : α) : Except ε (Output β κ) := do
  return emit key out (← make input)

variable {make : α → Except ε (Option β)} {key : β → κ}

def State.step (state : State make key) (input : α) : Except ε (State make key) :=
  if state.inputs.contains input then .ok state
  else match produced : make input with
    | .error error => .error error
    | .ok item => .ok {
        out := emit key state.out item
        inputs := state.inputs.insert input
        checked := by
          intro other present
          have alternatives : input = other ∨ state.inputs.contains other = true := by
            simpa only [Std.HashSet.contains_insert,Bool.or_eq_true,beq_iff_eq] using present
          rcases alternatives with same | prior
          · subst other
            exact ⟨item,produced,emit_accepts key state.out item⟩
          · obtain ⟨previous,calculated,accepted⟩ := state.checked other prior
            refine ⟨previous,calculated,?_⟩
            intro value same
            exact emit_keeps key state.out item (accepted value same) }

/-- Exact state transition, including first-error behavior and stable output
order. No injectivity of the output key or positivity of a range is assumed. -/
theorem State.step_exact (state : State make key) (input : α) :
    (state.step input).map (·.out) = referenceStep make key state.out input := by
  unfold State.step referenceStep
  split
  · obtain ⟨item,calculated,accepted⟩ := state.checked input ‹_›
    simp only [calculated]
    change Except.ok state.out = Except.ok (emit key state.out item)
    rw [emit_already key state.out item accepted]
  · split <;> rename_i result produced <;> simp only [produced] <;> rfl

def reference (make : α → Except ε (Option β)) (key : β → κ)
    (out : Output β κ) : List α → Except ε (Output β κ)
  | [] => .ok out
  | input :: rest => do
    reference make key (← referenceStep make key out input) rest

def State.loop (state : State make key) : List α → Except ε (Output β κ)
  | [] => .ok state.out
  | input :: rest => do
    let next ← state.step input
    next.loop rest

theorem State.loop_exact (state : State make key) (inputs : List α) :
    state.loop inputs = reference make key state.out inputs := by
  induction inputs generalizing state with
  | nil => rfl
  | cons input rest ih =>
    have transition := state.step_exact input
    cases next : state.step input with
    | error error =>
      simp only [next,Except.map] at transition
      simp only [State.loop,reference,next,← transition]
      rfl
    | ok after =>
      simp only [next,Except.map] at transition
      simp only [State.loop,reference,next,← transition]
      change after.loop rest = reference make key after.out rest
      exact ih after

def run (make : α → Except ε (Option β)) (key : β → κ)
    (out : Output β κ) (inputs : List α) : Except ε (Output β κ) :=
  (initial make key out).loop inputs

theorem run_exact (make : α → Except ε (Option β)) (key : β → κ)
    (out : Output β κ) (inputs : List α) :
    run make key out inputs = reference make key out inputs :=
  (initial make key out).loop_exact inputs

end Eggshell.Research.MemoGroupFold
