module

public import Eggshell.SelectionDependency
public import Eggshell.GraphCodec
public import Eggshell.Receipt
public import Eggshell.Matcher
public import Eggshell.GraphStore
public import Eggshell.DiscoveryAudit

@[expose] public section

namespace Eggshell.SelectionAudit
open Lean

/-- A locator survives demand-memo reuse. Owner lists describe the surviving
delivery, while the immutable snapshot describes the entire chosen extraction. -/
structure Reference where
  receipt : String
  stage : String
  sha256 : String
  visible : List String
  controls : List String
  deriving ToJson, FromJson

def Reference.restrict (reference : Reference) (visible controls : List String) : Reference :=
  {reference with
    visible := reference.visible.filter visible.contains
    controls := reference.controls.filter controls.contains}

structure Generator where
  left : Json
  right : Json
  scope : String
  authority : Json
  deriving ToJson, FromJson

def Generator.encode (edge : UnionEdge) : Generator := {
  left := Persistence.valueToJson edge.left
  right := Persistence.valueToJson edge.right
  scope := match edge.scope with | .run _ => "run" | .workspace _ => "workspace"
  authority := Persistence.valueToJson (match edge.scope with | .run value | .workspace value => value) }

def Generator.decode (row : Generator) : Except String UnionEdge := do
  let left ← Persistence.valueFromJson 4096 row.left
  let right ← Persistence.valueFromJson 4096 row.right
  let authority ← Persistence.valueFromJson 4096 row.authority
  let scope ← match row.scope with
    | "run" => pure (UnionScope.run authority)
    | "workspace" => pure (UnionScope.workspace authority)
    | _ => throw "unknown equality generator scope"
  if safe : Value.sameExactFootprint left right then
    pure ⟨left, right, scope, Value.sameExactFootprint_sound safe⟩
  else throw "equality generator crosses Exact authority"

structure CompletedBranch where
  owner : String
  demand : Json
  projectedOutcome : Json
  /-- Positions in the shared checked comparison pool; Value payloads are
  serialized once, including comparisons shared by many completed branches. -/
  premises : List Nat
  deriving ToJson, FromJson

/-- Observed beside the actual matcher call, before saturation adds more
generators. Values and source frames remain shared until completed owners
are known; only those owners are serialized. -/
structure Admission where
  matched : Matcher.Match
  runLocal : List UnionEdge
  child : Json
  inquiry : Value
  nomination : Option UnionEdge
  schedule : Option Nat := none

def Admission.observe (view : RunView) (inquiry : Value) (corpus : Matcher.Corpus)
    (children : Std.HashMap Value Persistence.Store.ChildObservation)
    (matched : Matcher.Match) : Admission := Id.run do
  let mut child := Json.null
  if let some original := corpus.subworks.find? (view.quotient.toEquality.same matched.edge.work) then
    if let some parent := corpus.parents.find? (fun edge => edge.children.contains original) then
      child := Json.mkObj [("kind", toJson "topology"),
        ("requested", Persistence.valueToJson original), ("original", Persistence.valueToJson original),
        ("relation", Persistence.valueToJson parent.relation)]
    else if let some observed := children[original]? then
      child := observed.encode
  return {
    matched, runLocal := view.localUnions, child, inquiry
    nomination := Matcher.localUnion? view.quotient inquiry matched }

/-- The Match which proposed one actual local generator. Unlike completed
admission, nomination needs no completed subwork or Outcome context. -/
structure UnionOrigin where
  generator : Nat
  localCount : Nat
  inquiry : Json
  demand : Json
  work : Json
  currentFragment : Json
  pastFragment : Json
  wholeIdentity : Bool
  fragmentIdentity : Bool
  priorComplete : Bool
  demandComplete : Bool
  priorWeight : Nat
  demandWeight : Nat
  retrieved : Bool
  schedule : Option Nat := none
  deriving ToJson, FromJson

/-- Full structural keys disambiguate collision buckets; no display digest
or serialized Value is used as generator identity. -/
structure GeneratorKey where
  left : Value
  right : Value
  run : Bool
  authority : Value
  deriving BEq, Hashable

def GeneratorKey.ofEdge (edge : UnionEdge) : GeneratorKey := {
  left := edge.left, right := edge.right
  run := match edge.scope with | .run _ => true | .workspace _ => false
  authority := match edge.scope with | .run value | .workspace value => value }

def Admission.atPrefix (runLocal : List UnionEdge) (admission : Admission) : Bool :=
  DiscoveryAudit.atPrefix admission.runLocal runLocal

def unionOrigins (runLocal : List UnionEdge) (history : List Admission) : List UnionOrigin := Id.run do
  if runLocal.isEmpty then return []
  let mut nominated : Std.HashMap GeneratorKey Admission := {}
  for admission in history.reverse do
    if let some edge := admission.nomination then
      let key := GeneratorKey.ofEdge edge
      unless nominated.contains key do
        if admission.atPrefix runLocal then nominated := nominated.insert key admission
  return runLocal.zipIdx.filterMap fun (edge, index) => do
    let admission ← nominated[GeneratorKey.ofEdge edge]?
    unless admission.runLocal.length ≤ index do none
    let matched := admission.matched
    pure {
      generator := index, localCount := admission.runLocal.length
      inquiry := Persistence.valueToJson admission.inquiry
      demand := Persistence.valueToJson matched.demand
      work := Persistence.valueToJson matched.edge.work
      currentFragment := Persistence.valueToJson matched.work.currentFragment
      pastFragment := Persistence.valueToJson matched.work.pastFragment
      wholeIdentity := matched.work.wholeWorkIdentity
      fragmentIdentity := matched.work.fragmentIdentity
      priorComplete := matched.work.priorInDemand.complete
      demandComplete := matched.work.demandInPrior.complete
      priorWeight := matched.work.priorInDemand.coveredWeight
      demandWeight := matched.work.demandInPrior.coveredWeight
      retrieved := matched.retrieved, schedule := admission.schedule }

structure AdmissionSnapshot where
  owner : String
  branches : List Nat
  localCount : Nat
  demand : Json
  work : Json
  currentFragment : Json
  pastFragment : Json
  wholeIdentity : Bool
  fragmentIdentity : Bool
  subwork : Bool
  priorComplete : Bool
  demandComplete : Bool
  pastWhole : Bool
  groundedFragment : Bool
  retrieved : Bool
  child : Json
  schedule : Option Nat := none
  deriving ToJson, FromJson

def Admission.snapshot? (runLocal : List UnionEdge) (branches : List CompletedBranch)
    (admission : Admission) (owner : String) : Option AdmissionSnapshot := do
  unless admission.atPrefix runLocal do none
  let matched := admission.matched
  unless matched.automatic && matched.judgment.delivery == .completed do none
  let projected := Persistence.valueToJson matched.projectedEdge.relation
  let positions := branches.zipIdx.filterMap fun (branch, index) =>
    if branch.owner == owner && branch.projectedOutcome == projected &&
        branch.demand == Persistence.valueToJson matched.projectionWork then some index else none
  if positions.isEmpty then none else some {
    owner, branches := positions, localCount := admission.runLocal.length
    demand := Persistence.valueToJson matched.demand
    work := Persistence.valueToJson matched.edge.work
    currentFragment := Persistence.valueToJson matched.work.currentFragment
    pastFragment := Persistence.valueToJson matched.work.pastFragment
    wholeIdentity := matched.work.wholeWorkIdentity
    fragmentIdentity := matched.work.fragmentIdentity
    subwork := matched.work.subwork
    priorComplete := matched.work.priorInDemand.complete
    demandComplete := matched.work.demandInPrior.complete
    pastWhole := matched.work.pastWholeWork
    groundedFragment := matched.groundedOutcomeFragment
    retrieved := matched.retrieved
    child := admission.child, schedule := admission.schedule }

structure Snapshot where
  current : Json
  persistent : List Generator
  runLocal : List Generator
  premises : List DiscoveryAudit.ComparisonRow
  owners : List String
  completedBranches : List CompletedBranch := []
  admissions : List AdmissionSnapshot := []
  localOrigins : List UnionOrigin := []
  schedules : List DiscoveryAudit.ScheduleSnapshot := []
  continuations : List DiscoveryAudit.ContinuationSnapshot := []
  deriving ToJson, FromJson

/-- No second quotient build occurs in the hook. Only premises from a checked
production selection and its current generators are serialized here. -/
def Snapshot.ofReport (persistent runLocal : List UnionEdge)
    {graph : WorkGraph} {equality : Equality} {policy : OutcomePolicy}
    {current : Value} {selection : Selection}
    (report : SelectionDependency.Report graph equality policy current selection)
    (owners : List String) (bindings : List (Value × String) := [])
    (admissions : List (Admission × String) := []) (history : List Admission := [])
    (trail : DiscoveryAudit.Trail := {}) : Snapshot := Id.run do
  let positions : Std.HashMap SelectionDependency.Comparison Nat :=
    report.premises.zipIdx.foldl (fun positions (premise, index) => positions.insert premise index) {}
  let completedBranches : List CompletedBranch := (SelectionDependency.completedBranches equality current selection).flatMap
    fun branch => (bindings.filterMap fun (projected, owner) =>
      if projected == branch.edge.relation then some owner else none).eraseDups.map fun owner => {
        owner, demand := Persistence.valueToJson branch.demand
        projectedOutcome := Persistence.valueToJson branch.edge.relation
        premises := branch.premises.map (fun premise => positions.getD premise report.premises.length) }
  return {
  current := Persistence.valueToJson current
  persistent := persistent.map Generator.encode
  runLocal := runLocal.map Generator.encode
  premises := report.premises.map DiscoveryAudit.ComparisonRow.encode
  owners := owners.eraseDups
  completedBranches
  admissions := admissions.filterMap fun (admission, owner) =>
    admission.snapshot? runLocal completedBranches owner
  localOrigins := unionOrigins runLocal history
  schedules := trail.schedules.reverse.filterMap (·.snapshot? runLocal)
  continuations := trail.continuations.reverse.filterMap (·.snapshot? runLocal) }

def capture (receipt : Option String) (snapshot : Snapshot)
    (visible controls : List String) : IO (Option Reference) := do
  let some receipt := receipt | return none
  try
    let stage := "selection-" ++ (← Receipt.fresh)
    let data := toJson snapshot
    Receipt.write receipt stage data
    pure (some {receipt, stage, sha256 := Sha256.hex data.compress.toUTF8, visible, controls})
  catch error =>
    IO.eprintln s!"Eggshell could not record selected equality premises: {error}"
    pure none

def kindName : EqualityDependency.Kind → String
  | .notEquivalent => "notEquivalent"
  | .literal => "literal"
  | .persistentUnion => "persistentUnion"
  | .localUnion => "localUnion"
  | .congruence => "congruence"

def admissionChild (data : Json) : Except String (Option (Value × Value)) := do
  if data == Json.null then return none
  let requested ← Persistence.valueFromJson 4096 (data.getObjValD "requested")
  let original ← Persistence.valueFromJson 4096 (data.getObjValD "original")
  match ← data.getObjValAs? String "kind" with
  | "topology" =>
      let value ← Persistence.valueFromJson 4096 (data.getObjValD "relation")
      let some edge := AllEdge.fromValue? value | throw "source child does not name an All"
      unless original == requested && edge.children.contains original do
        throw "source child is absent from its original All"
  | "indexed" =>
      let directory ← data.getObjValAs? String "directory"
      unless (System.FilePath.mk directory).isAbsolute do throw "relative child source directory"
      let _ ← (fromJson? (data.getObjValD "head") : Except String DB.PageMap.Head)
      let owner ← data.getObjValAs? Nat "owner"
      let child ← data.getObjValAs? Nat "child"
      let frame ← Persistence.Store.NodeFrame.fromJson (data.getObjValD "frame")
      let some checked := frame.check owner | throw "source child frame has forward references"
      let some header := Persistence.Store.AllHeader.fromFrame? checked |
        throw "source child frame is not an original All"
      unless header.children.contains child do throw "source child posting lost its position"
  | _ => throw "unknown source child evidence"
  pure (some (requested, original))

/-- Compare only against the generator prefix available at an observation. -/
def replayComparisons (persistent runLocal : List UnionEdge) (localCount : Nat)
    (pairs : List (String × Value × Value × Bool)) : Except String (List Json) := do
  unless localCount ≤ runLocal.length do throw "comparison prefix is outside the recorded run"
  let active := runLocal.take localCount
  let roots := pairs.flatMap fun (_, left, right, _) => [left, right]
  let some quotient := QuotientBuilder.build? roots persistent active |
    throw "observation snapshot does not generate a valid quotient"
  let stored := EqualityDependency.DirectIndex.make persistent
  let all := EqualityDependency.DirectIndex.make (persistent ++ active)
  pairs.mapM fun (role, left, right, accepted) => do
    let kind := EqualityDependency.classify quotient.toEquality stored all left right
    unless (kind != .notEquivalent) == accepted do
      throw "comparison changed under its original generator prefix"
    pure (Json.mkObj [("role", toJson role), ("accepted", toJson accepted),
      ("kind", toJson (kindName kind)), ("left", Persistence.valueToJson left),
      ("right", Persistence.valueToJson right)])

def analyzeUnionOrigin (persistent runLocal : List UnionEdge) (origin : UnionOrigin) : Except String Json := do
  let some edge := runLocal[origin.generator]? | throw "local origin names a missing generator"
  unless origin.localCount ≤ origin.generator do
    throw "a local generator depends on itself or a future generator"
  let inquiry ← Persistence.valueFromJson 4096 origin.inquiry
  let demand ← Persistence.valueFromJson 4096 origin.demand
  let work ← Persistence.valueFromJson 4096 origin.work
  let current ← Persistence.valueFromJson 4096 origin.currentFragment
  let past ← Persistence.valueFromJson 4096 origin.pastFragment
  unless edge.scope == .run inquiry && edge.left == current && edge.right == past do
    throw "local generator changed its nomination endpoints or Inquiry scope"
  unless !origin.retrieved && !origin.fragmentIdentity &&
      (origin.priorComplete || origin.demandComplete ||
        origin.priorWeight != 0 || origin.demandWeight != 0) do
    throw "recorded Match did not pass the local-Union nomination gate"
  let comparisons ← replayComparisons persistent runLocal origin.localCount [
    ("wholeWorkIdentity", demand, work, origin.wholeIdentity),
    ("fragmentIdentity", current, past, origin.fragmentIdentity)]
  pure (Json.mkObj [("generator", toJson origin.generator), ("localCount", toJson origin.localCount),
    ("status", toJson "nomination-replayed"), ("inquiry", origin.inquiry),
    ("comparisons", toJson comparisons), ("schedulingAncestry", toJson "untracked"),
    ("patternSelectionAncestry", toJson "untracked"), ("schedule", toJson origin.schedule)])

/-- Replay the exact generator prefix observed at Match construction. Future
local Unions cannot retroactively justify an admission comparison. Source IO
bindings remain an explicit boundary; this checks their retained frame, not
the current filesystem or semantic truth of the observation. -/
def analyzeAdmission (persistent runLocal : List UnionEdge) (branches : List CompletedBranch)
    (admission : AdmissionSnapshot) : Except String Json := do
  unless admission.localCount ≤ runLocal.length && !admission.branches.isEmpty do
    throw "invalid admission generator prefix or empty branch binding"
  let demand ← Persistence.valueFromJson 4096 admission.demand
  let work ← Persistence.valueFromJson 4096 admission.work
  let current ← Persistence.valueFromJson 4096 admission.currentFragment
  let past ← Persistence.valueFromJson 4096 admission.pastFragment
  unless !admission.retrieved && admission.subwork && admission.fragmentIdentity &&
      ((admission.pastWhole && admission.priorComplete) ||
        (admission.groundedFragment && (admission.priorComplete || admission.demandComplete))) do
    throw "recorded Match did not pass the completed admission gate"
  for position in admission.branches do
    let some branch := branches[position]? | throw "admission branch is outside the selection"
    unless branch.owner == admission.owner do throw "admission crossed source owners"
    let value ← Persistence.valueFromJson 4096 branch.projectedOutcome
    let some edge := OutcomeEdge.fromValue? value | throw "admission branch is not an Outcome"
    unless edge.work == current && branch.demand == admission.currentFragment do
      throw "admission changed the projected Work fragment or admitted demand"
  let child ← admissionChild admission.child
  let pairs := [("wholeWorkIdentity", demand, work, admission.wholeIdentity),
    ("fragmentIdentity", current, past, admission.fragmentIdentity)] ++
    (child.toList.flatMap fun (requested, original) =>
      [("subworkAlias", work, requested, true), ("originalChildAlias", requested, original, true)])
  let comparisons ← replayComparisons persistent runLocal admission.localCount pairs
  pure (Json.mkObj [("owner", toJson admission.owner), ("branches", toJson admission.branches),
    ("localCount", toJson admission.localCount), ("status", toJson "replayed"),
    ("sourceChild", toJson (if child.isSome then "recorded-source-boundary" else "untracked")),
    ("childEvidence", admission.child), ("comparisons", toJson comparisons),
    ("schedule", toJson admission.schedule)])

def decodeAll (data : Json) : Except String AllEdge := do
  let value ← Persistence.valueFromJson 4096 data
  let some edge := AllEdge.fromValue? value | throw "discovery trace does not name an All relation"
  pure edge

def analyzeSchedule (persistent runLocal : List UnionEdge)
    (schedule : DiscoveryAudit.ScheduleSnapshot) : Except String Json := do
  unless ["discovery", "terminal"].contains schedule.kind do throw "unknown scheduling observation"
  let current ← Persistence.valueFromJson 4096 schedule.current
  let discovery ← schedule.discovery.mapM (Persistence.valueFromJson 4096)
  let tasks ← schedule.tasks.mapM (Persistence.valueFromJson 4096)
  let prior ← schedule.runAll.mapM decodeAll
  let expected := discovery.filter fun task =>
    !HandoffRemainder.isValue task && Matcher.freshDemand current prior task
  unless tasks == expected do throw "scheduled tasks differ from the actual discovery filter"
  if schedule.kind == "terminal" then
    unless discovery == [current] && tasks == [current] && prior.isEmpty &&
        schedule.premises.isEmpty && schedule.uses.isEmpty do
      throw "terminal scheduling changed its certified unadmitted root"
  let pairs ← schedule.premises.mapM fun premise => do
    unless ["decomposition", "deduplicatedChild", "completedOutcome", "advisoryOutcome"].contains premise.role do
      throw "unknown scheduling comparison role"
    pure (premise.role, ← Persistence.valueFromJson 4096 premise.left,
      ← Persistence.valueFromJson 4096 premise.right, true)
  let comparisons ← replayComparisons persistent runLocal schedule.localCount pairs
  for use in schedule.uses do
    let edge ← decodeAll use.relation
    unless use.generated == prior.any (fun before => before.relation == edge.relation) do
      throw "scheduling confused an original All with a generated continuation"
    unless schedule.premises.any (fun premise => premise.role == "decomposition" &&
        premise.left == Persistence.valueToJson edge.parent) do
      throw "scheduling lost a selected All-parent comparison"
  pure (Json.mkObj [("pass", toJson schedule.pass), ("kind", toJson schedule.kind),
    ("localCount", toJson schedule.localCount), ("discovery", toJson schedule.discovery),
    ("tasks", toJson schedule.tasks), ("comparisons", toJson comparisons),
    ("uses", toJson schedule.uses), ("scope", toJson "whole-scheduling-selection"),
    ("dependencySlice", toJson "untracked"), ("admissionAncestry", toJson "untracked")])

def scheduleBinding (schedules : List DiscoveryAudit.ScheduleSnapshot)
    (pass : Option Nat) (localCount : Nat) (demand : Json) : Except String Bool := do
  let some pass := pass | return false
  let some schedule := schedules.find? (·.pass == pass) | return false
  unless schedule.localCount == localCount && schedule.tasks.contains demand do
    throw "Match observation changed its scheduled Demand or equality epoch"
  pure true

def analyzeContinuation (persistent runLocal : List UnionEdge)
    (schedules : List DiscoveryAudit.ScheduleSnapshot)
    (event : DiscoveryAudit.ContinuationSnapshot) : Except String Json := do
  unless event.localCount ≤ runLocal.length do throw "continuation equality epoch is outside the run"
  let current ← Persistence.valueFromJson 4096 event.current
  let edge ← decodeAll event.relation
  let remainder := HandoffRemainder.value event.text
  unless current == Value.text event.text && edge.parent == current &&
      edge.children.getLast? == some remainder do
    throw "continuation changed its external root or mandatory open remainder"
  let positions := event.support.map (·.child)
  unless positions.eraseDups.length == positions.length do throw "duplicate continuation child support"
  let support ← event.support.mapM fun row => do
    let some child := edge.children[row.child]? | throw "continuation support names a missing child"
    let demand ← Persistence.valueFromJson 4096 row.demand
    let work ← Persistence.valueFromJson 4096 row.work
    let fragment ← Persistence.valueFromJson 4096 row.currentFragment
    let past ← Persistence.valueFromJson 4096 row.pastFragment
    unless child != remainder && demand == current && row.automatic && row.subwork && fragment == child do
      throw "continuation child lost its actual automatic root Match"
    let comparisons ← row.localCount.mapM fun before => do
      unless before ≤ event.localCount do throw "continuation used a future Match observation"
      replayComparisons persistent runLocal before [
        ("wholeWorkIdentity", demand, work, row.wholeIdentity),
        ("fragmentIdentity", fragment, past, row.fragmentIdentity)]
    let scheduled ← match row.localCount with
      | none => pure false
      | some before => scheduleBinding schedules row.schedule before row.demand
    if let some pass := row.schedule then
      unless pass ≤ event.pass do throw "continuation used a future scheduled Match"
    pure (Json.mkObj [("child", toJson row.child), ("schedule", toJson row.schedule),
      ("localCount", toJson row.localCount), ("comparisons", toJson comparisons),
      ("scheduling", toJson (if scheduled then "recorded-step" else "untracked")),
      ("automaticGate", toJson "captured-production-result"),
      ("childRoleAncestry", toJson "untracked"), ("retrieved", toJson row.retrieved)])
  let unknown := edge.children.zipIdx.filterMap fun (child, index) =>
    if child != remainder && !positions.contains index then some index else none
  pure (Json.mkObj [("pass", toJson event.pass), ("localCount", toJson event.localCount),
    ("relation", event.relation), ("status", toJson "captured-production-continuation"),
    ("support", toJson support), ("untrackedChildren", toJson unknown),
    ("dependencySlice", toJson "untracked")])

/-- Explicit-only folds and congruence replay run outside the hook deadline.
The result concerns selected comparisons, never whole-delivery ancestry. -/
def analyze (snapshot : Snapshot) : Except String Json := do
  let persistent ← snapshot.persistent.mapM Generator.decode
  let runLocal ← snapshot.runLocal.mapM Generator.decode
  let current ← Persistence.valueFromJson 4096 snapshot.current
  let pairs ← snapshot.premises.mapM fun premise => do
    unless ["decomposition", "deduplicatedChild", "completedOutcome", "advisoryOutcome"].contains premise.role do
      throw "unknown selected comparison role"
    pure (premise.role, ← Persistence.valueFromJson 4096 premise.left,
      ← Persistence.valueFromJson 4096 premise.right)
  let roots := current :: pairs.flatMap (fun (_, left, right) => [left, right])
  let some quotient := QuotientBuilder.build? roots persistent runLocal |
    throw "selected equality snapshot does not generate a valid quotient"
  let stored := EqualityDependency.DirectIndex.make persistent
  let all := EqualityDependency.DirectIndex.make (persistent ++ runLocal)
  let rows ← pairs.mapM fun (role, left, right) => do
    let kind := EqualityDependency.classify quotient.toEquality stored all left right
    if kind == .notEquivalent then throw "selected positive comparison failed equality replay"
    pure (Json.mkObj [("role", toJson role), ("kind", toJson (kindName kind)),
      ("left", Persistence.valueToJson left), ("right", Persistence.valueToJson right)])
  let branches ← snapshot.completedBranches.zipIdx.mapM fun (branch, index) => do
    unless snapshot.owners.contains branch.owner do
      throw "completed branch is not part of the checked selection"
    let premises ← branch.premises.mapM fun position =>
      match snapshot.premises[position]? with
      | some premise => pure premise
      | none => throw "completed branch comparison is outside the checked selection"
    let demand ← Persistence.valueFromJson 4096 branch.demand
    let projected ← Persistence.valueFromJson 4096 branch.projectedOutcome
    let [edge] := (WorkGraph.fromValues [projected]).outcomes |
      throw "completed branch does not name an Outcome"
    unless premises.getLast? == some (DiscoveryAudit.ComparisonRow.encode
        ⟨.completedOutcome, edge.work, demand⟩) do
      throw "completed branch lost its terminal Outcome comparison"
    let comparisons ← branch.premises.mapM fun position =>
      match rows[position]? with
      | some row => pure row
      | none => throw "completed branch comparison was not replayed"
    pure (Json.mkObj [("selectionBranch", toJson index), ("owner", toJson branch.owner), ("demand", branch.demand),
      ("projectedOutcome", branch.projectedOutcome), ("comparisons", toJson comparisons)])
  let admissions ← snapshot.admissions.mapM (analyzeAdmission persistent runLocal snapshot.completedBranches)
  let originIndices := snapshot.localOrigins.map (·.generator)
  unless originIndices.eraseDups.length == originIndices.length do
    throw "local generator has duplicate origin records"
  let origins ← snapshot.localOrigins.mapM (analyzeUnionOrigin persistent runLocal)
  let passes := snapshot.schedules.map (·.pass)
  unless passes.eraseDups.length == passes.length do throw "duplicate scheduling observation"
  let schedules ← snapshot.schedules.mapM (analyzeSchedule persistent runLocal)
  let admissions ← (snapshot.admissions.zip admissions).mapM fun (record, row) => do
    let known ← scheduleBinding snapshot.schedules record.schedule record.localCount record.demand
    pure (row.setObjVal! "schedulingAncestry" (toJson (if known then "recorded-step" else "untracked")))
  let origins ← (snapshot.localOrigins.zip origins).mapM fun (record, row) => do
    let known ← scheduleBinding snapshot.schedules record.schedule record.localCount record.demand
    pure (row.setObjVal! "schedulingAncestry" (toJson (if known then "recorded-step" else "untracked")))
  let continuations ← snapshot.continuations.mapM (analyzeContinuation persistent runLocal snapshot.schedules)
  pure (Json.mkObj [
    ("status", toJson "partial"), ("component", toJson "selected-extraction"),
    ("scope", toJson "whole-selected-extraction-before-source-and-transport-pruning"),
    ("deliveryAncestry", toJson "untracked"),
    ("localUnionAncestry", toJson "untracked"),
    ("localUnionOrigins", toJson origins),
    ("localOriginScope", toJson "recorded-run-before-source-and-transport-pruning"),
    ("untrackedLocalOrigins", toJson ((List.range runLocal.length).filter (!originIndices.contains ·))),
    ("completedBranchScope", toJson "selected-root-to-outcome-positive-comparisons"),
    ("finalLeafSlice", toJson "untracked"),
    ("matchAdmission", toJson (if admissions.isEmpty then "untracked" else "partial")),
    ("sourceChildWitness", toJson "per-admission-source-boundary"),
    ("matchAdmissions", toJson admissions),
    ("continuationAncestry", toJson "untracked"),
    ("schedulingAncestry", toJson (if schedules.isEmpty then "untracked" else "partial")),
    ("schedulingRecords", toJson schedules), ("continuationRecords", toJson continuations),
    ("completedBranches", toJson branches),
    ("comparisons", toJson rows)])

def read (reference : Reference) : IO Snapshot := do
  unless Receipt.validId reference.receipt && reference.stage.startsWith "selection-" &&
      Receipt.validId ((reference.stage.drop 10).copy) do
    throw (IO.userError "invalid selected equality receipt locator")
  let path := (← Paths.dataRoot) / "receipts" / reference.receipt / (reference.stage ++ ".json")
  FileSystem.rejectSymlinkAncestors path
  let bytes ← FileSystem.boundedBytes path (8 * 1024 * 1024)
  let some text := String.fromUTF8? bytes | throw (IO.userError "invalid equality receipt encoding")
  let envelope ← IO.ofExcept (Json.parse text)
  unless envelope.getObjValD "receipt" == toJson reference.receipt &&
      envelope.getObjValD "stage" == toJson reference.stage do
    throw (IO.userError "selected equality receipt identity mismatch")
  let data ← IO.ofExcept (envelope.getObjVal? "data")
  unless Sha256.hex data.compress.toUTF8 == reference.sha256 do
    throw (IO.userError "selected equality snapshot digest mismatch")
  let snapshot ← IO.ofExcept (fromJson? data : Except String Snapshot)
  unless (reference.visible ++ reference.controls).all snapshot.owners.contains do
    throw (IO.userError "delivered completed owner is absent from the selected extraction")
  pure snapshot

def inspect (reference : Reference) : IO Json := do
  let snapshot ← read reference
  let result ← IO.ofExcept (analyze snapshot)
  let branches ← IO.ofExcept (result.getObjValAs? (List Json) "completedBranches")
  let retained := branches.filterMap fun branch =>
    let owner := (branch.getObjValAs? String "owner").toOption.getD ""
    let visible := reference.visible.contains owner
    let control := reference.controls.contains owner
    if visible || control then some
      ((branch.setObjVal! "ownerVisible" (toJson visible)).setObjVal! "ownerControls" (toJson control))
    else none
  let recorded := snapshot.completedBranches.map (·.owner)
  let unknown := (reference.visible ++ reference.controls).eraseDups.filter (!recorded.contains ·)
  let positions := retained.filterMap fun branch => (branch.getObjValAs? Nat "selectionBranch").toOption
  let admissions ← IO.ofExcept (result.getObjValAs? (List Json) "matchAdmissions")
  let admissions := admissions.filterMap fun admission =>
    let used := ((admission.getObjValAs? (List Nat) "branches").toOption.getD []).filter positions.contains
    if used.isEmpty then none else some (admission.setObjVal! "branches" (toJson used))
  let admitted := admissions.flatMap fun admission =>
    (admission.getObjValAs? (List Nat) "branches").toOption.getD []
  let sourced := (admissions.filter (fun admission =>
    admission.getObjValD "sourceChild" != toJson "untracked")).flatMap fun admission =>
      (admission.getObjValAs? (List Nat) "branches").toOption.getD []
  pure ((((((result.setObjVal! "retained" (toJson reference)).setObjVal!
    "completedBranches" (toJson retained)).setObjVal! "untrackedCompletedOwners" (toJson unknown)).setObjVal!
    "matchAdmissions" (toJson admissions)).setObjVal!
    "untrackedAdmissionBranches" (toJson (positions.filter (!admitted.contains ·)))).setObjVal!
    "untrackedSourceChildBranches" (toJson (positions.filter (!sourced.contains ·))))

def readStage (receipt stage : String) : IO Json := do
  unless Receipt.validId receipt && ["search", "published", "ack"].contains stage do
    throw (IO.userError "invalid hook receipt stage")
  let path := (← Paths.dataRoot) / "receipts" / receipt / (stage ++ ".json")
  FileSystem.rejectSymlinkAncestors path
  let bytes ← FileSystem.boundedBytes path (8 * 1024 * 1024)
  let some text := String.fromUTF8? bytes | throw (IO.userError "invalid hook receipt encoding")
  let envelope ← IO.ofExcept (Json.parse text)
  unless envelope.getObjValD "receipt" == toJson receipt && envelope.getObjValD "stage" == toJson stage do
    throw (IO.userError "hook receipt stage identity mismatch")
  IO.ofExcept (envelope.getObjVal? "data")

def inspectHook (receipt : String) : IO Json := do
  let search ← readStage receipt "search"
  let reference ← IO.ofExcept
    (fromJson? ((search.getObjValD "equalityOrigin").getObjValD "selection") : Except String Reference)
  let analysis ← inspect reference
  let published ← try pure (some (← readStage receipt "published")) catch _ => pure none
  let acknowledgement ← try pure (some (← readStage receipt "ack")) catch _ => pure none
  if let some record := published then
    let output ← IO.ofExcept (record.getObjValAs? String "output")
    unless record.getObjValD "sha256" == toJson (Sha256.hex output.toUTF8) &&
        record.getObjValD "bytes" == toJson output.utf8ByteSize do
      throw (IO.userError "published hook output digest mismatch")
  pure (Json.mkObj [("receipt", toJson receipt), ("search", search),
    ("published", toJson published), ("acknowledgement", toJson acknowledgement),
    ("hostIngestion", toJson "unconfirmed"), ("selection", analysis)])

end Eggshell.SelectionAudit
