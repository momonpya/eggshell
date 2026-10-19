module

public import Eggshell.SelectionDependency
public import Eggshell.GraphCodec
public import Eggshell.Receipt

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

def roleName : SelectionDependency.Role → String
  | .decomposition => "decomposition"
  | .deduplicatedChild => "deduplicatedChild"
  | .completedOutcome => "completedOutcome"
  | .advisoryOutcome => "advisoryOutcome"

structure Premise where
  role : String
  left : Json
  right : Json
  deriving BEq, ToJson, FromJson

def Premise.encode (comparison : SelectionDependency.Comparison) : Premise := {
  role := roleName comparison.role
  left := Persistence.valueToJson comparison.left
  right := Persistence.valueToJson comparison.right }

structure CompletedBranch where
  owner : String
  demand : Json
  projectedOutcome : Json
  /-- Positions in the shared checked comparison pool; Value payloads are
  serialized once, including comparisons shared by many completed branches. -/
  premises : List Nat
  deriving ToJson, FromJson

structure Snapshot where
  current : Json
  persistent : List Generator
  runLocal : List Generator
  premises : List Premise
  owners : List String
  completedBranches : List CompletedBranch := []
  deriving ToJson, FromJson

/-- No second quotient build occurs in the hook. Only premises from a checked
production selection and its current generators are serialized here. -/
def Snapshot.ofReport (persistent runLocal : List UnionEdge)
    {graph : WorkGraph} {equality : Equality} {policy : OutcomePolicy}
    {current : Value} {selection : Selection}
    (report : SelectionDependency.Report graph equality policy current selection)
    (owners : List String) (bindings : List (Value × String) := []) : Snapshot := Id.run do
  let positions : Std.HashMap SelectionDependency.Comparison Nat :=
    report.premises.zipIdx.foldl (fun positions (premise, index) => positions.insert premise index) {}
  return {
  current := Persistence.valueToJson current
  persistent := persistent.map Generator.encode
  runLocal := runLocal.map Generator.encode
  premises := report.premises.map Premise.encode
  owners := owners.eraseDups
  completedBranches := (SelectionDependency.completedBranches equality current selection).flatMap
    fun branch => (bindings.filterMap fun (projected, owner) =>
      if projected == branch.edge.relation then some owner else none).eraseDups.map fun owner => {
        owner, demand := Persistence.valueToJson branch.demand
        projectedOutcome := Persistence.valueToJson branch.edge.relation
        premises := branch.premises.map (fun premise => positions.getD premise report.premises.length) } }

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
  let branches ← snapshot.completedBranches.mapM fun branch => do
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
    unless premises.getLast? == some (Premise.encode
        ⟨.completedOutcome, edge.work, demand⟩) do
      throw "completed branch lost its terminal Outcome comparison"
    let comparisons ← branch.premises.mapM fun position =>
      match rows[position]? with
      | some row => pure row
      | none => throw "completed branch comparison was not replayed"
    pure (Json.mkObj [("owner", toJson branch.owner), ("demand", branch.demand),
      ("projectedOutcome", branch.projectedOutcome), ("comparisons", toJson comparisons)])
  pure (Json.mkObj [
    ("status", toJson "partial"), ("component", toJson "selected-extraction"),
    ("scope", toJson "whole-selected-extraction-before-source-and-transport-pruning"),
    ("deliveryAncestry", toJson "untracked"),
    ("localUnionAncestry", toJson "untracked"),
    ("completedBranchScope", toJson "selected-root-to-outcome-positive-comparisons"),
    ("finalLeafSlice", toJson "untracked"),
    ("matchAdmission", toJson "untracked"), ("sourceChildWitness", toJson "untracked"),
    ("continuationAncestry", toJson "untracked"),
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
  pure (((result.setObjVal! "retained" (toJson reference)).setObjVal!
    "completedBranches" (toJson retained)).setObjVal! "untrackedCompletedOwners" (toJson unknown))

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
