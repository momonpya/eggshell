module
public import Eggshell.HashDistinct
@[expose] public section
namespace Eggshell.Research.DeliveryKeys
open Eggshell

/-- Specification: preserve first occurrences, except that a new status
replaces every old status for exactly its own source scope. -/
def step (scopeOf : String → Option String) (prior : List String) (key : String) : List String :=
  match scopeOf key with
  | none => (prior++[key]).eraseDups
  | some scope => ((prior.filter (fun old => scopeOf old != some scope))++[key]).eraseDups

def one (scopeOf : String → Option String) (prior : List String) (key : String) : List String :=
  match scopeOf key with
  | none => hashDistinct (prior++[key])
  | some scope => hashDistinct ((prior.filter (fun old => scopeOf old != some scope))++[key])

theorem one_exact (scopeOf : String → Option String) (prior : List String) (key : String) :
    one scopeOf prior key = step scopeOf prior key := by
  simp only [one,step,HashDistinct.reference]

theorem normalized_prefix (prior tail : List String) :
    (prior.eraseDups++tail).eraseDups = (prior++tail).eraseDups := by
  have stable : prior.eraseDups.eraseDups = prior.eraseDups := by
    apply HashDistinct.erase_nodup
    rw [← HashDistinct.reference]
    exact HashDistinct.nodup prior
  have removed : tail.removeAll prior.eraseDups = tail.removeAll prior := by
    simp only [List.removeAll,List.contains_eq_mem,List.mem_eraseDups]
  rw [List.eraseDups_append,List.eraseDups_append,stable,removed]

/-- An empty pending run leaves even a malformed legacy list unchanged. -/
def flush (prior : List String) : List String → List String
  | [] => prior
  | head::tail => hashDistinct (prior++(head::tail).reverse)

theorem flush_cons (scopeOf : String → Option String) (prior pending : List String)
    (key : String) (ordinary : scopeOf key = none) :
    flush prior (key::pending) = step scopeOf (flush prior pending) key := by
  cases pending with
  | nil => simp [flush,step,ordinary,HashDistinct.reference]
  | cons head tail =>
      simp only [flush,step,ordinary,HashDistinct.reference,List.reverse_cons]
      rw [normalized_prefix]
      simp only [List.append_assoc]

/-- Accumulate ordinary keys in reverse, flushing once at a scope update or
at the end. Scope updates retain their original order and replacement rule. -/
def loop (scopeOf : String → Option String) (incoming prior pending : List String) : List String :=
  match incoming with
  | [] => flush prior pending
  | key::rest =>
      match scopeOf key with
      | none => loop scopeOf rest prior (key::pending)
      | some _ => loop scopeOf rest (one scopeOf (flush prior pending) key) []

theorem loop_exact (scopeOf : String → Option String) (incoming prior pending : List String) :
    loop scopeOf incoming prior pending = incoming.foldl (step scopeOf) (flush prior pending) := by
  induction incoming generalizing prior pending with
  | nil => rfl
  | cons key rest ih =>
      cases ordinary : scopeOf key with
      | none =>
          simp only [loop,ordinary,List.foldl_cons]
          rw [ih,flush_cons scopeOf prior pending key ordinary]
      | some scope =>
          simp only [loop,ordinary,List.foldl_cons]
          rw [ih]
          simp only [flush,one_exact]

def batch (scopeOf : String → Option String) (prior incoming : List String) : List String :=
  loop scopeOf incoming prior []

theorem batch_exact (scopeOf : String → Option String) (prior incoming : List String) :
    batch scopeOf prior incoming = incoming.foldl (step scopeOf) prior :=
  loop_exact scopeOf incoming prior []

/-- A prepared update is a value with its original input bound by the type.
It carries no mutable state, locking primitive, or authority to accept an ACK. -/
structure Plan (scopeOf : String → Option String) (incoming : List String) where
  base : List String
  result : List String
  exact : result = incoming.foldl (step scopeOf) base

def prepare (scopeOf : String → Option String) (prior incoming : List String) : Plan scopeOf incoming :=
  ⟨prior,batch scopeOf prior incoming,batch_exact scopeOf prior incoming⟩

/-- An unchanged basis uses the prepared value. A concurrently updated basis
receives the same delta through the exact batch operation; nothing is dropped. -/
def Plan.apply {scopeOf : String → Option String} {incoming : List String}
    (plan : Plan scopeOf incoming) (current : List String) : List String :=
  if current == plan.base then plan.result else batch scopeOf current incoming

theorem Plan.apply_exact {scopeOf : String → Option String} {incoming : List String}
    (plan : Plan scopeOf incoming) (current : List String) :
    plan.apply current = incoming.foldl (step scopeOf) current := by
  unfold apply
  split
  · next equal => rw [eq_of_beq equal]; exact plan.exact
  · exact batch_exact scopeOf current incoming

end Eggshell.Research.DeliveryKeys
