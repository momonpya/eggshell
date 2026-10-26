module

public import Eggshell.SynapseRecommend

@[expose] public section
namespace Eggshell.Synapses.Routing
open Lean Recommend

/-- One step in the existing advisory relation. No original output, command
grammar, similarity score, or human reference list enters this projection. -/
structure Step where
  targets : Array Target := #[]
  next : Array Index.Key := #[]
  deriving BEq

def project (key : Index.Key) (fact : Fact) : Step :=
  match key, fact with
  | .answer .., .supports support =>
    ⟨#[.range support.source], #[.group (.claim support.claim),
      .consumer support.read.occurrence, .quoted support.source]⟩
  | .consumer _, .consumed edge =>
    ⟨if edge.rows.isEmpty then #[.output edge.producer] else edge.rows.map Target.range,
      edge.rows.map Index.Key.quoted |>.push (.consumer edge.producer)⟩
  | .quoted _, .coquoted group _ => ⟨#[], #[.group group]⟩
  | .group _, .coquoted _ source => ⟨#[.range source], #[]⟩
  | .query _, .used value =>
    if value.kind == .omittedThenRead || value.kind == .omittedThenConsumed ||
        value.kind == .deliveredThenCited then
      ⟨#[.range value.source], #[.quoted value.source]⟩ else {}
  | _, _ => {}

/-- Projection cannot invent a recommended target. Control authority remains
outside this module: a supported target is still only an advisory witness. -/
theorem project_carries (key : Index.Key) (fact : Fact) (target : Target)
    (present : target ∈ (project key fact).targets) : carries fact target = true := by
  cases key <;> cases fact <;> simp only [project] at present <;>
    try simp_all [carries]
  all_goals
    split at present <;> simp_all [Array.mem_map, Bool.or_eq_true, beq_iff_eq]
  obtain ⟨source,member,rfl⟩ := present
  simpa using member

/-- The serialized digest is computed once when preparing the arena. Multiple
adjacency entries share this checked original fact rather than reparsing it. -/
structure Evidence where
  fact : Fact
  identity : String
  exact : identity = Index.contentKey fact
  valid : fact.valid = true

structure Arc where
  evidence : Nat
  targets : Array Nat
  next : Array Nat

structure Arena where
  keys : Array Index.Key := #[]
  keyIds : Std.HashMap String Nat := {}
  targets : Array Target := #[]
  targetIds : Std.HashMap String Nat := {}
  evidence : Array Evidence := #[]
  adjacency : Array (Array Arc) := #[]

def internKey (arena : Arena) (key : Index.Key) : Arena × Nat :=
  let spelling := (toJson key).compress
  match arena.keyIds[spelling]? with
  | some id => (arena,id)
  | none => ({arena with
      keys := arena.keys.push key
      keyIds := arena.keyIds.insert spelling arena.keys.size
      adjacency := arena.adjacency.push #[]},arena.keys.size)

def internTarget (arena : Arena) (target : Target) : Arena × Nat :=
  let spelling := (toJson target).compress
  match arena.targetIds[spelling]? with
  | some id => (arena,id)
  | none => ({arena with
      targets := arena.targets.push target
      targetIds := arena.targetIds.insert spelling arena.targets.size},arena.targets.size)

/-- Facts must arrive in canonical digest order, as in the source fact tree.
An absent or corrupt fact is rejected before any route becomes available. -/
def Arena.add (arena : Arena) (fact : Fact) : Except String Arena := do
  if valid : fact.valid = true then
    let identity := Index.contentKey fact
    let evidence := arena.evidence.size
    let mut arena := {arena with evidence := arena.evidence.push ⟨fact,identity,rfl,valid⟩}
    for key in Index.addresses fact do
      let step := project key fact
      if step.targets.isEmpty && step.next.isEmpty then continue
      let (updated,id) := internKey arena key
      arena := updated
      let mut targets := #[]
      for target in step.targets do
        let (updated,targetId) := internTarget arena target
        arena := updated
        targets := targets.push targetId
      let mut next := #[]
      for successor in step.next do
        let (updated,successorId) := internKey arena successor
        arena := updated
        next := next.push successorId
      arena := {arena with
        adjacency := arena.adjacency.modify id (·.push ⟨evidence,targets,next⟩)}
    return arena
  else throw "invalid routing evidence"

def Arena.prepare (facts : Array Fact) : Except String Arena :=
  facts.foldlM Arena.add {}

structure Walk where
  offers : Array Offer := #[]
  nodes : Nat := 0
  arcs : Nat := 0
  complete : Bool := true

/-- The query loop uses integer nodes and shared checked facts. The arena is
immutable and disposable; this prototype is not a whole-DB resident service. -/
def Arena.walk (arena : Arena) (roots : Array (Index.Key × Nat))
    (deadline : Nat) (arcLimit : Nat) : IO Walk := do
  let roots := roots.qsort fun a b =>
    if a.2 == b.2 then (toJson a.1).compress < (toJson b.1).compress else a.2 < b.2
  let mut visited : Std.HashSet Nat := {}
  let mut result : Walk := {}
  for (root,priority) in roots do
    let some rootId := arena.keyIds[(toJson root).compress]? | continue
    let mut queue := #[rootId]
    let mut position := 0
    while position < queue.size do
      let id := queue[position]!
      position := position+1
      if visited.contains id then continue
      if (← IO.monoMsNow) ≥ deadline then return {result with complete := false}
      visited := visited.insert id
      result := {result with nodes := result.nodes+1}
      let some arcs := arena.adjacency[id]? | throw (IO.userError "missing routing node")
      for arc in arcs do
        if result.arcs ≥ arcLimit || (← IO.monoMsNow) ≥ deadline then
          return {result with complete := false}
        result := {result with arcs := result.arcs+1}
        let some evidence := arena.evidence[arc.evidence]? |
          throw (IO.userError "missing routing evidence")
        for targetId in arc.targets do
          let some target := arena.targets[targetId]? |
            throw (IO.userError "missing routing target")
          -- Recheck the small projected predicate. A malformed arena cannot
          -- emit an Offer for data not carried by its immutable fact.
          if witness : carries evidence.fact target = true then
            result := {result with offers := result.offers.push {
              target,priority,fact := evidence.fact,identity := evidence.identity
              identity_exact := evidence.exact,valid := evidence.valid,witness}}
          else throw (IO.userError "routing projection changed its evidence")
        queue := queue ++ arc.next
  return result

end Eggshell.Synapses.Routing
