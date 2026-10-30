module
public import Eggshell.Synapses
public import Std.Data.HashMap.Lemmas
@[expose] public section

namespace Eggshell.Research.WorkEvidenceRequirements
open Eggshell.Synapses

/-- The DB namespace is part of the endpoint, including for tool occurrences.
An advisory dependency is never a Work equivalence or completion certificate. -/
inductive Root where
  | claim (value : Claim)
  | invocation (database : String) (value : Occurrence)
  deriving Inhabited, BEq, ReflBEq, LawfulBEq, Hashable

structure Requirement where
  root : Root
  ranges : Array Range
  upstream : Array Root
  original : Fact
  deriving BEq

/-- A declared citation or literal/path-line consumption can carry an advisory
dependency. Spelling, path-only, identifier, co-occurrence and usage remain
recommendation signals; none is silently promoted to an obligation. -/
def requirement? (database : String) (fact : Fact) : Option Requirement :=
  if !fact.valid then none else
  match fact with
  | .supports support =>
      if support.basis == .citation && support.claim.database == database &&
          support.read.binding.database == database then
        some ⟨.claim support.claim,#[support.source],
          #[.invocation database support.read.occurrence],fact⟩
      else none
  | .consumed edge =>
      if (edge.kind == .value || edge.kind == .pathLine) && !edge.rows.isEmpty then
        some ⟨.invocation database edge.consumer,edge.rows,
          #[.invocation database edge.producer],fact⟩
      else none
  | _ => none

def forRoot (database : String) (facts : List Fact) (root : Root) : List Requirement :=
  facts.filterMap fun fact => (requirement? database fact).filter (·.root == root)

/-- The original ledger is a type parameter, not a resident field. Runtime
lookup retains only postings; the refinement proof and its ledger erase. -/
structure Prepared (database : String) (facts : List Fact) where
  postings : Std.HashMap Root (List Requirement)
  exact : ∀ root, postings[root]?.getD [] = forRoot database facts root

def empty (database : String) : Prepared database [] :=
  ⟨{},by intro root; simp [forRoot]⟩

def add (prepared : Prepared database facts) (fact : Fact) : Prepared database (fact :: facts) :=
  let postings := match requirement? database fact with
    | none => prepared.postings
    | some required => prepared.postings.insert required.root
        (required :: prepared.postings[required.root]?.getD [])
  ⟨postings,by
    intro root
    simp only [forRoot,List.filterMap_cons]
    cases accepted : requirement? database fact with
    | none => simpa only [postings,accepted,Option.filter_none,Option.map_none,forRoot] using prepared.exact root
    | some required =>
      by_cases same : required.root = root
      · subst root
        simp only [postings,accepted,Std.HashMap.getElem?_insert,beq_self_eq_true,
          ↓reduceIte,Option.getD_some,Option.filter_some,beq_self_eq_true]
        rw [prepared.exact]
        rfl
      · simpa [postings,accepted,same,forRoot,Std.HashMap.getElem?_insert,
          Option.filter_some] using prepared.exact root⟩

def extendList (prepared : Prepared database facts) :
    (delta : List Fact) → Prepared database (delta.reverse ++ facts)
  | [] => by simpa only [List.reverse_nil,List.nil_append] using prepared
  | fact :: rest => by
    simpa only [List.reverse_cons,List.append_assoc,List.singleton_append] using
      extendList (add prepared fact) rest

def extend (prepared : Prepared database facts) (delta : Array Fact) :
    Prepared database (delta.toList.reverse ++ facts) := extendList prepared delta.toList

def prepare (database : String) (original : Array Fact) : Prepared database original.toList.reverse := by
  simpa only [List.append_nil] using extend (empty database) original

def lookup (prepared : Prepared database facts) (root : Root) : List Requirement :=
  prepared.postings[root]?.getD []

theorem lookup_complete (prepared : Prepared database facts) (root : Root) :
    lookup prepared root = forRoot database facts root := prepared.exact root

theorem add_only_root (prepared : Prepared database facts) (fact : Fact) (root : Root)
    (irrelevant : (requirement? database fact).all (fun required => required.root != root) = true) :
    lookup (add prepared fact) root = lookup prepared root := by
  rw [lookup_complete,lookup_complete]
  change forRoot database (fact :: facts) root = forRoot database facts root
  simp only [forRoot,List.filterMap_cons]
  cases accepted : requirement? database fact with
  | none => rfl
  | some required =>
    have different : (required.root == root) = false := by
      simpa [accepted] using irrelevant
    simp_all [Option.filter_some]

/-- WorkGraph fitting must carry these ranges for every selected root. This
predicate names actual delivered original ranges, not a relevance score. -/
def Closed (prepared : Prepared database facts) (selected : List Root)
    (delivered : Array Range) : Prop :=
  ∀ root ∈ selected, ∀ required ∈ lookup prepared root,
    ∀ source ∈ required.ranges, covered source delivered = true

theorem closed_keeps_dependency (prepared : Prepared database facts) (selected : List Root)
    (delivered : Array Range) (closed : Closed prepared selected delivered)
    (root : Root) (chosen : root ∈ selected) (required : Requirement)
    (present : required ∈ lookup prepared root) (source : Range)
    (needed : source ∈ required.ranges) : covered source delivered = true :=
  closed root chosen required present source needed

theorem weak_consumption_not_required (database : String) (edge : Consumption)
    (weak : edge.kind = .identifier ∨ edge.kind = .path) :
    requirement? database (.consumed edge) = none := by
  rcases weak with h | h <;> simp [requirement?,h]

theorem cooccurrence_not_required (database : String) (group : Group) (source : Range) :
    requirement? database (.coquoted group source) = none := by simp [requirement?]

theorem usage_not_required (database : String) (usage : Usage) :
    requirement? database (.used usage) = none := by simp [requirement?]

def Root.database : Root → String
  | .claim value => value.database
  | .invocation database _ => database

structure Walk where
  roots : List Root := []
  ranges : Array Range := #[]
  visited : Nat := 0
  postings : Nat := 0
  complete : Bool := false

/-- Walk selected roots through their prepared postings. This never scans the
fact ledger and never changes relevance, source data or native authority. A
bounded traversal reports incomplete instead of certifying a partial closure. -/
def walk (prepared : Prepared database facts) (roots : Array Root) (maxRoots : Nat) : Except String Walk := do
  unless roots.all (fun root => root.database == database) do throw "dependency roots crossed DB scope"
  let mut queue := roots
  let mut position := 0
  let mut visited : Std.HashSet Root := {}
  let mut ranges : Std.HashSet Range := {}
  let mut result : Walk := {}
  while position < queue.size do
    let root := queue[position]!
    position := position+1
    if visited.contains root then continue
    if visited.size == maxRoots then return {result with ranges := ranges.toArray}
    visited := visited.insert root
    result := {result with roots := root :: result.roots,visited := visited.size}
    let required := lookup prepared root
    result := {result with postings := result.postings+required.length}
    for dependency in required do
      for source in dependency.ranges do ranges := ranges.insert source
      queue := queue ++ dependency.upstream
  return {result with roots := result.roots.reverse,ranges := ranges.toArray,complete := true}

def checkClosed (prepared : Prepared database facts) (selected : List Root) (delivered : Array Range) : Bool :=
  selected.all fun root => (lookup prepared root).all fun dependency =>
    dependency.ranges.all fun source => covered source delivered

theorem checkClosed_exact (prepared : Prepared database facts) (selected : List Root) (delivered : Array Range) :
    checkClosed prepared selected delivered = true ↔ Closed prepared selected delivered := by
  simp only [checkClosed,Closed,List.all_eq_true,Array.all_eq_true']

end Eggshell.Research.WorkEvidenceRequirements
