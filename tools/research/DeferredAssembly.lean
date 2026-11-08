module
public import Std
@[expose] public section

namespace Eggshell.Research.DeferredAssembly

/-- A completed view is needed by consumers, not by each contextual merge.
Replacing a view twice keeps only its newest context. These laws allow
rendering, keys and other derived fields to be constructed once at the end. -/
structure Algebra (Slice Context : Type) where
  view : Slice → Option Context
  replace : Slice → Context → Slice
  replace_view : ∀ slice context, view (replace slice context) = some context
  replace_replace : ∀ slice first last, replace (replace slice first) last = replace slice last
  sameAtomic : Slice → Slice → Bool
  merge : Context → Context → Option Context

variable {Slice Context : Type}

def Algebra.eager (algebra : Algebra Slice Context) (prior next : Slice) : Option Slice :=
  match algebra.view prior,algebra.view next with
  | some left,some right => (algebra.merge left right).map (algebra.replace prior)
  | none,none => if algebra.sameAtomic prior next then some prior else none
  | _,_ => none

inductive Pending (Slice Context : Type) where
  | ready (slice : Slice)
  | contextual (template : Slice) (context : Context)

def finish (algebra : Algebra Slice Context) : Pending Slice Context → Slice
  | .ready slice => slice
  | .contextual template context => algebra.replace template context

/-- Keep the first template. Do not retain earlier assembled snapshots and
do not invoke replace while subsequent original contexts are being checked. -/
def step (algebra : Algebra Slice Context) (prior : Pending Slice Context)
    (next : Slice) : Option (Pending Slice Context) :=
  match prior with
  | .ready slice =>
    match algebra.view slice,algebra.view next with
    | some left,some right => (algebra.merge left right).map (.contextual slice)
    | none,none => if algebra.sameAtomic slice next then some prior else none
    | _,_ => none
  | .contextual template left =>
    match algebra.view next with
    | some right => (algebra.merge left right).map (.contextual template)
    | none => none

theorem step_exact (algebra : Algebra Slice Context) (prior : Pending Slice Context)
    (next : Slice) : (step algebra prior next).map (finish algebra) =
      algebra.eager (finish algebra prior) next := by
  cases prior with
  | ready slice =>
    cases left : algebra.view slice with
    | none =>
      cases right : algebra.view next <;>
        simp [step,finish,Algebra.eager,left,right] <;> rfl
    | some context =>
      cases right : algebra.view next with
      | none => simp [step,finish,Algebra.eager,left,right]
      | some incoming =>
        cases merged : algebra.merge context incoming <;>
          simp [step,finish,Algebra.eager,left,right,merged]
  | contextual template context =>
    cases right : algebra.view next with
    | none => simp [step,finish,Algebra.eager,algebra.replace_view,right]
    | some incoming =>
      cases merged : algebra.merge context incoming <;>
        simp [step,finish,Algebra.eager,algebra.replace_view,algebra.replace_replace,right,merged]

def fold (algebra : Algebra Slice Context) (initial : Pending Slice Context)
    (slices : List Slice) : Option (Pending Slice Context) :=
  slices.foldlM (step algebra) initial

def reference (algebra : Algebra Slice Context) (initial : Slice)
    (slices : List Slice) : Option Slice := slices.foldlM algebra.eager initial

/-- Preserve errors, input order, atomic compatibility, and the complete
final value. No associativity or commutativity of contextual merge is assumed. -/
theorem fold_exact (algebra : Algebra Slice Context) (initial : Pending Slice Context)
    (slices : List Slice) : (fold algebra initial slices).map (finish algebra) =
      reference algebra (finish algebra initial) slices := by
  induction slices generalizing initial with
  | nil => rfl
  | cons next rest ih =>
    have one := step_exact algebra initial next
    cases advanced : step algebra initial next with
    | none =>
      rw [advanced] at one
      simp only [Option.map_none] at one
      simp [fold,reference,List.foldlM_cons,advanced,← one]
    | some updated =>
      rw [advanced] at one
      simp only [Option.map_some] at one
      simpa [fold,reference,List.foldlM_cons,advanced,← one] using ih updated

def finishRows (algebra : Algebra Slice Context) (rows : List (Nat × Pending Slice Context)) : List (Nat × Slice) :=
  rows.map fun row => (row.1,finish algebra row.2)

def addRow (algebra : Algebra Slice Context) (rows : List (Nat × Pending Slice Context))
    (family : Nat) (next : Slice) : Option (List (Nat × Pending Slice Context)) :=
  match rows.find? (fun row => row.1 == family) with
  | none => some (rows ++ [(family,.ready next)])
  | some (_,prior) => (step algebra prior next).map fun updated =>
      rows.map fun row => if row.1 == family then (row.1,updated) else row

def referenceRow (algebra : Algebra Slice Context) (rows : List (Nat × Slice))
    (family : Nat) (next : Slice) : Option (List (Nat × Slice)) :=
  match rows.find? (fun row => row.1 == family) with
  | none => some (rows ++ [(family,next)])
  | some (_,prior) => (algebra.eager prior next).map fun updated =>
      rows.map fun row => if row.1 == family then (row.1,updated) else row

private theorem find_finish (algebra : Algebra Slice Context) (rows : List (Nat × Pending Slice Context))
    (family : Nat) :
    (finishRows algebra rows).find? (fun row => row.1 == family) =
      (rows.find? (fun row => row.1 == family)).map (fun row => (row.1,finish algebra row.2)) := by
  simp only [finishRows,List.find?_map,Function.comp_def]

private theorem finish_update (algebra : Algebra Slice Context) (rows : List (Nat × Pending Slice Context))
    (family : Nat) (updated : Pending Slice Context) :
    finishRows algebra (rows.map fun row => if row.1 == family then (row.1,updated) else row) =
      (finishRows algebra rows).map (fun row => if row.1 == family then (row.1,finish algebra updated) else row) := by
  unfold finishRows
  simp only [List.map_map]
  congr 1
  funext row
  simp only [Function.comp_apply]
  split <;> rfl

/-- Interleaved families keep their first position. Even an unusual table
with duplicate family keys has exactly the original find-and-update behavior. -/
theorem addRow_exact (algebra : Algebra Slice Context) (rows : List (Nat × Pending Slice Context))
    (family : Nat) (next : Slice) :
    (addRow algebra rows family next).map (finishRows algebra) =
      referenceRow algebra (finishRows algebra rows) family next := by
  unfold addRow referenceRow
  rw [find_finish]
  cases found : rows.find? (fun row => row.1 == family) with
  | none => simp [finishRows,finish]
  | some prior =>
    rcases prior with ⟨id,current⟩
    have one := step_exact algebra current next
    cases advanced : step algebra current next with
    | none =>
      rw [advanced] at one
      simp only [Option.map_none] at one
      simp [advanced,← one]
    | some updated =>
      rw [advanced] at one
      simp only [Option.map_some] at one
      simp [advanced,← one]
      simpa only [beq_iff_eq] using finish_update algebra rows family updated

def foldRows (algebra : Algebra Slice Context) (rows : List (Nat × Pending Slice Context))
    (inputs : List (Nat × Slice)) : Option (List (Nat × Pending Slice Context)) :=
  inputs.foldlM (fun state item => addRow algebra state item.1 item.2) rows

def referenceRows (algebra : Algebra Slice Context) (rows : List (Nat × Slice))
    (inputs : List (Nat × Slice)) : Option (List (Nat × Slice)) :=
  inputs.foldlM (fun state item => referenceRow algebra state item.1 item.2) rows

theorem foldRows_exact (algebra : Algebra Slice Context) (rows : List (Nat × Pending Slice Context))
    (inputs : List (Nat × Slice)) :
    (foldRows algebra rows inputs).map (finishRows algebra) =
      referenceRows algebra (finishRows algebra rows) inputs := by
  induction inputs generalizing rows with
  | nil => rfl
  | cons item rest ih =>
    have one := addRow_exact algebra rows item.1 item.2
    cases advanced : addRow algebra rows item.1 item.2 with
    | none =>
      rw [advanced] at one
      simp only [Option.map_none] at one
      simp [foldRows,referenceRows,List.foldlM_cons,advanced,← one]
    | some updated =>
      rw [advanced] at one
      simp only [Option.map_some] at one
      simpa [foldRows,referenceRows,List.foldlM_cons,advanced,← one] using ih updated

def projectStep (project : State → Value) : ForInStep State → ForInStep Value
  | .done state => .done (project state)
  | .yield state => .yield (project state)

/-- Refinement of the actual imperative list loop, including early done and
Option failure. Unrelated state such as shared original rows may be carried
through the projection unchanged. -/
theorem forIn_project (project : State → Value)
    (advance : Input → State → Option (ForInStep State))
    (reference : Input → Value → Option (ForInStep Value))
    (preserves : ∀ input state, (advance input state).map (projectStep project) = reference input (project state))
    (inputs : List Input) (initial : State) :
    (forIn inputs initial advance).map project = forIn inputs (project initial) reference := by
  induction inputs generalizing initial with
  | nil => rfl
  | cons input rest ih =>
    have one := preserves input initial
    cases advanced : advance input initial with
    | none =>
      rw [advanced] at one
      simp only [Option.map_none] at one
      simp [List.forIn_cons,advanced,← one]
    | some action =>
      cases action with
      | done state =>
        rw [advanced] at one
        simp only [Option.map_some,projectStep] at one
        simp [List.forIn_cons,advanced,← one]
      | yield state =>
        rw [advanced] at one
        simp only [Option.map_some,projectStep] at one
        simpa [List.forIn_cons,advanced,← one] using ih state

end Eggshell.Research.DeferredAssembly

#print axioms Eggshell.Research.DeferredAssembly.step_exact
#print axioms Eggshell.Research.DeferredAssembly.fold_exact
#print axioms Eggshell.Research.DeferredAssembly.foldRows_exact
#print axioms Eggshell.Research.DeferredAssembly.forIn_project
