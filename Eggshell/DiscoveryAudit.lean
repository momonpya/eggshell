module

public import Eggshell.Matcher
public import Eggshell.SelectionDependency
public import Eggshell.GraphCodec

@[expose] public section

namespace Eggshell.DiscoveryAudit
open Lean

def roleName : SelectionDependency.Role → String
  | .decomposition => "decomposition"
  | .deduplicatedChild => "deduplicatedChild"
  | .completedOutcome => "completedOutcome"
  | .advisoryOutcome => "advisoryOutcome"

structure ComparisonRow where
  role : String
  left : Json
  right : Json
  deriving BEq, ToJson, FromJson

def ComparisonRow.encode (comparison : SelectionDependency.Comparison) : ComparisonRow := {
  role := roleName comparison.role
  left := Persistence.valueToJson comparison.left
  right := Persistence.valueToJson comparison.right }

def atPrefix (before after : List UnionEdge) : Bool :=
  decide (before = after.take before.length)

structure AllUse where
  relation : Json
  generated : Bool
  deriving ToJson, FromJson

structure ScheduleSnapshot where
  pass : Nat
  kind : String
  localCount : Nat
  current : Json
  discovery : List Json
  tasks : List Json
  runAll : List Json
  premises : List ComparisonRow
  uses : List AllUse
  deriving ToJson, FromJson

structure Schedule where
  pass : Nat
  kind : String := "discovery"
  localUnions : List UnionEdge
  current : Value
  discovery : List Value
  tasks : List Value
  runAll : List AllEdge
  premises : List SelectionDependency.Comparison
  uses : List (AllEdge × Bool)

def Schedule.observe (event : Matcher.ScheduleObservation) : Schedule := {
  pass := event.pass, localUnions := event.view.localUnions, current := event.current
  discovery := event.extraction.discovery, tasks := event.tasks, runAll := event.runAll
  premises := (SelectionDependency.Report.ofValid event.valid).premises
  uses := event.extraction.selection.decompositionEdges.map fun edge =>
    (edge, event.runAll.any (fun prior => prior.relation == edge.relation)) }

/-- The certified terminal path has the same unadmitted root demand as the
first reference pass. It does not run another extraction for telemetry. -/
def Schedule.terminal {view : RunView} {current : Value} {text : String}
    (_terminal : Matcher.TerminalRoot view current text) : Schedule := {
  pass := 0, kind := "terminal", localUnions := view.localUnions, current
  discovery := [current], tasks := [current], runAll := [], premises := [], uses := [] }

def Schedule.snapshot? (after : List UnionEdge) (schedule : Schedule) : Option ScheduleSnapshot := do
  unless atPrefix schedule.localUnions after do none
  pure {
    pass := schedule.pass, kind := schedule.kind, localCount := schedule.localUnions.length
    current := Persistence.valueToJson schedule.current
    discovery := schedule.discovery.map Persistence.valueToJson
    tasks := schedule.tasks.map Persistence.valueToJson
    runAll := schedule.runAll.map (fun edge => Persistence.valueToJson edge.relation)
    premises := schedule.premises.map ComparisonRow.encode
    uses := schedule.uses.map fun (edge, generated) =>
      {relation := Persistence.valueToJson edge.relation, generated} }

structure SupportSnapshot where
  child : Nat
  localCount : Option Nat
  schedule : Option Nat
  demand : Json
  work : Json
  currentFragment : Json
  pastFragment : Json
  wholeIdentity : Bool
  fragmentIdentity : Bool
  retrieved : Bool
  automatic : Bool
  subwork : Bool
  deriving ToJson, FromJson

structure Support where
  child : Nat
  matched : Matcher.Match
  observed : Option (Nat × Option Nat)

structure ContinuationSnapshot where
  pass : Nat
  localCount : Nat
  current : Json
  text : String
  relation : Json
  support : List SupportSnapshot
  deriving ToJson, FromJson

structure Continuation where
  pass : Nat
  localUnions : List UnionEdge
  current : Value
  text : String
  edge : AllEdge
  support : List Support

def Continuation.observe (event : Matcher.ContinuationObservation)
    (locate : Matcher.Match → Option (Nat × Option Nat)) : Continuation := {
  pass := event.pass, localUnions := event.localUnions, current := event.current
  text := event.text, edge := event.edge
  support := event.edge.children.zipIdx.filterMap fun (child, index) => do
    if child == HandoffRemainder.value event.text then none else do
      let matched ← event.hits.find? fun matched => matched.demand == event.current &&
        matched.automatic && matched.work.subwork && matched.continuationWork == child
      pure ⟨index, matched, locate matched⟩ }

def Continuation.snapshot? (after : List UnionEdge) (event : Continuation) : Option ContinuationSnapshot := do
  unless atPrefix event.localUnions after do none
  pure {
    pass := event.pass, localCount := event.localUnions.length
    current := Persistence.valueToJson event.current, text := event.text
    relation := Persistence.valueToJson event.edge.relation
    support := event.support.map fun support => {
      child := support.child, localCount := support.observed.map (·.1)
      schedule := support.observed.bind (·.2)
      demand := Persistence.valueToJson support.matched.demand
      work := Persistence.valueToJson support.matched.edge.work
      currentFragment := Persistence.valueToJson support.matched.work.currentFragment
      pastFragment := Persistence.valueToJson support.matched.work.pastFragment
      wholeIdentity := support.matched.work.wholeWorkIdentity
      fragmentIdentity := support.matched.work.fragmentIdentity
      retrieved := support.matched.retrieved, automatic := support.matched.automatic
      subwork := support.matched.work.subwork } }

/-- The callback retains Value references, not quotients or reader caches.
Only a completed handoff serializes this trail. -/
structure Trail where
  current : Option Nat := none
  schedules : List Schedule := []
  continuations : List Continuation := []

def Trail.observe (trail : Trail) (event : Matcher.DiscoveryTrace)
    (locate : Matcher.Match → Option (Nat × Option Nat)) : Trail :=
  match event with
  | .scheduled event => {trail with
      current := some event.pass, schedules := Schedule.observe event :: trail.schedules}
  | .continued event => {trail with
      continuations := Continuation.observe event locate :: trail.continuations}

end Eggshell.DiscoveryAudit
