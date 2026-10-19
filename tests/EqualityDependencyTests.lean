module

public import Eggshell.Handoff

@[expose] public section

namespace Eggshell.EqualityDependencyTests

open EqualityDependency

def require (accepted : Bool) (message : String) : IO Unit :=
  unless accepted do throw (IO.userError message)

def union (left right : Value) : IO UnionEdge := do
  if safe : Value.sameExactFootprint left right then
    pure {
      left
      right
      scope := .workspace (.text "dependency-fixture")
      exactAuthority := Value.sameExactFootprint_sound safe
    }
  else throw (IO.userError "fixture tried to replace Exact authority")

def full (roots : List Value) (persistent : List UnionEdge) (runLocal : List UnionEdge := []) : IO Quotient := do
  let some quotient := QuotientBuilder.build? roots persistent runLocal |
    throw (IO.userError "fixture quotient did not certify")
  pure quotient

def application (value : Value) : Value :=
  .applyList .inquiry [Ref.semantic value]

def explicitAndCongruence : IO Unit := do
  let a := Value.text "a"
  let b := Value.text "b"
  let c := Value.text "c"
  let ab ← union a b
  let bc ← union b c
  let edges := [ab, bc]
  let stored := DirectIndex.make edges
  let current := DirectIndex.make (edges ++ [])
  let fa := application a
  let fc := application c
  let quotient ← full [fa, fc] edges
  require (classify quotient.toEquality stored current a c == .persistentUnion)
    "transitive stored Union was not direct"
  require (classify quotient.toEquality stored current fa fc == .congruence)
    "Semantic Apply congruence was not attributed"
  require (classify quotient.toEquality stored current fa fa == .literal)
    "literal identity depended on the root catalogue"
  let exactA := Value.applyList .inquiry [Ref.exact a]
  let exactC := Value.applyList .inquiry [Ref.exact c]
  let exactQuotient ← full [exactA, exactC] edges
  require (classify exactQuotient.toEquality stored current exactA exactC == .notEquivalent)
    "the dependency classifier crossed Exact authority"
  let without ← full [fa, fc] [ab]
  require (classify without.toEquality (DirectIndex.make [ab]) (DirectIndex.make ([ab] ++ [])) fa fc == .notEquivalent)
    "a removed generator survived in dependency attribution"
  let planned := QuotientBuilder.plannedBuild? [fa, fc] edges [] none
  let corrected := QuotientBuilder.plannedBuild? [fa, fc] [ab] [] planned.plan
  let some corrected := corrected.quotient | throw (IO.userError "planned correction failed")
  require (classify corrected.toEquality (DirectIndex.make [ab]) (DirectIndex.make ([ab] ++ [])) fa fc == .notEquivalent)
    "a saved congruence plan imported a removed dependency"

def mixedAtomsAndLocalOrigins : IO Unit := do
  let a := Value.text "a"
  let b := Value.text "b"
  let x := Value.text "x"
  let y := Value.text "y"
  let ab ← union a b
  let xf ← union x (application a)
  let yf ← union y (application b)
  let edges := [ab, xf, yf]
  let quotient ← full [x, y] edges
  require (classify quotient.toEquality (DirectIndex.make edges) (DirectIndex.make (edges ++ [])) x y == .congruence)
    "atomic Work was falsely classified as direct despite mixed generators"
  let xy ← union x y
  let runLocal := [xy]
  let localQuotient ← full [x, y] [ab] runLocal
  require (classify localQuotient.toEquality (DirectIndex.make [ab]) (DirectIndex.make ([ab] ++ runLocal)) x y == .localUnion)
    "unresolved local-Union ancestry was counted as a persistent direct explanation"

def selectedDeduplication : IO Unit := do
  let a := Value.text "a"
  let b := Value.text "b"
  let root := Value.text "root"
  let fa := application a
  let fb := application b
  let edge := AllEdge.make root [fa, fb] (by simp) (by
    simp [root, fa, fb, application, Value.text, Value.applyList])
  let owner := OutcomeEdge.make fa (.text "observed") [] (by simp) (by simp [maxOutcomeObservations])
  let graph : WorkGraph := { all := [edge], outcomes := [owner] }
  let ab ← union a b
  let quotient ← full [edge.relation, owner.relation] [ab]
  let extraction := Extract.runWithPolicy graph quotient.toEquality .allCompleted root
  require (extraction.priorOutcomes.contains (.text "observed") &&
      extraction.selection.decompositionEdges.length == 1)
    "fixture did not execute a completed decomposition"
  let some report := SelectionDependency.report? graph quotient.toEquality .allCompleted root extraction.selection |
    throw (IO.userError "actual extraction did not validate for dependency recording")
  let stored := DirectIndex.make [ab]
  let current := DirectIndex.make ([ab] ++ [])
  require (report.premises.any fun premise =>
    premise.role == .deduplicatedChild &&
      classify quotient.toEquality stored current premise.left premise.right == .congruence)
    "congruence needed to omit a duplicate child disappeared behind literal root identity"
  let snapshot := SelectionAudit.Snapshot.ofReport [ab] [] report ["chosen-owner"]
  let replay ← IO.ofExcept (SelectionAudit.analyze snapshot)
  let rows ← IO.ofExcept (replay.getObjValAs? (List Lean.Json) "comparisons")
  require (rows.any (fun row => row.getObjValD "role" == Lean.toJson "deduplicatedChild" &&
      row.getObjValD "kind" == Lean.toJson "congruence") &&
      replay.getObjValD "deliveryAncestry" == Lean.toJson "untracked")
    "offline replay lost a nonliteral structural dependency or certified the entire delivery"
  let invalidSnapshot := {snapshot with premises := [{
    role := "completedOutcome", left := Persistence.valueToJson fa,
    right := Persistence.valueToJson (.text "unrelated")}]}
  require ((SelectionAudit.analyze invalidSnapshot).toOption.isNone)
    "a false positive comparison became a valid equality receipt"
  let invalid := Selection.outcomes root [owner] []
  require ((SelectionDependency.report? graph quotient.toEquality .allCompleted root invalid).isNone)
    "an unsupported completed owner obtained a dependency report"

def nativeDiscovery : IO Unit := do
  let text := "Bash\ncat clock.c"
  let work := Value.text text
  let result := Value.text "clock.c contains the clock implementation"
  let occurrence := Value.applyList .occurrence [Ref.semantic result, Ref.semantic work]
  let owner := OutcomeEdge.make work result [occurrence] (by simp) (by simp [maxOutcomeObservations])
  let frame := AllEdge.make (.applyList .inquiry []) [work] (by simp) (by
    simp [work, Value.text, Value.applyList])
  let values := [frame.relation, owner.relation]
  let graph := WorkGraph.fromValues values
  let some discovery := Matcher.discoverIn? LogicalText.logicalNormalizer work values [] graph
      (Matcher.Corpus.build LogicalText.logicalNormalizer graph) text none {} true true |
    throw (IO.userError "native discovery did not converge")
  let extraction := Matcher.extraction discovery
  require ((Plugin.boundaryMatches discovery extraction).any (·.blocks))
    "native fixture did not reach the production control selector"
  let some report := Plugin.discoverySelectionReport discovery |
    throw (IO.userError "production extraction bypassed its diagnostic component")
  require (report.premises.any (fun premise => premise.role == .completedOutcome))
    "the production component omitted its completed Outcome equality"
  let rendered := Plugin.renderAutomatic [] 24000 text [] true true discovery
  require rendered.isSome "native selection did not render"
  let unchanged ← Plugin.auditRenderedSelection none [] discovery ⟨extraction, rfl⟩ rendered
  require (Lean.toJson unchanged == Lean.toJson rendered)
    "disabled receipt capture changed the rendered handoff"
  let id ← Receipt.fresh
  let some audited ← Plugin.auditRenderedSelection (some id) [] discovery ⟨extraction, rfl⟩ rendered |
    throw (IO.userError "native selection disappeared while recording its premises")
  let some reference := audited.equalitySelection |
    throw (IO.userError "native selected extraction has no immutable receipt locator")
  let replay ← SelectionAudit.inspect reference
  require (replay.getObjValD "status" == Lean.toJson "partial" &&
      !reference.controls.isEmpty && audited.text == (rendered.map (·.text)).getD "")
    "native audit changed the body or missed a completed control owner"
  let branches ← IO.ofExcept (replay.getObjValAs? (List Lean.Json) "completedBranches")
  require (!branches.isEmpty && branches.any (fun branch =>
      branch.getObjValD "ownerControls" == Lean.toJson true) &&
      replay.getObjValD "untrackedCompletedOwners" == Lean.toJson ([] : List String))
    "native completed control lost its selected root-to-Outcome path"
  let decoded ← IO.ofExcept (Lean.fromJson? (Lean.toJson audited) : Except String Plugin.Handoff)
  require (Lean.toJson decoded.equalitySelection == Lean.toJson audited.equalitySelection)
    "demand-memo serialization lost the selected equality locator"
  let controlKeys := audited.sourceCheckpoints.map (·.key)
  if let some reconciled := audited.reconcileDelivery controlKeys 24000 96000 then
    require (reconciled.handoff.equalitySelection.all (·.controls.isEmpty))
      "already acknowledged control survived final equality attribution"
  let invalidOwner := {reference with visible := ["not-selected"]}
  let rejected ← try let _ ← SelectionAudit.inspect invalidOwner; pure false catch _ => pure true
  require rejected "an unselected owner was attributed to a valid extraction"
  let path := (← Paths.dataRoot) / "receipts" / id / (reference.stage ++ ".json")
  let bytes ← IO.FS.readBinFile path
  try
    IO.FS.writeFile path "{}"
    let rejected ← try let _ ← SelectionAudit.inspect reference; pure false catch _ => pure true
    require rejected "a replaced equality snapshot retained its original attribution"
  finally IO.FS.writeBinFile path bytes
  let _ ← SelectionAudit.inspect reference
  let stripped := reference.restrict [] []
  require (stripped.visible.isEmpty && stripped.controls.isEmpty)
    "discarded completion owners survived diagnostic restriction"

/-- The right completed Outcome must not inherit congruence from the left
subtree merely because both were selected in one extraction. -/
def completedBranchIsolation : IO Unit := do
  let root := Value.applyList .inquiry []
  let left := Value.text "left branch"
  let right := Value.text "right branch"
  let a := Value.text "branch a"
  let b := Value.text "branch b"
  let fa := application a
  let fb := application b
  let top := AllEdge.make root [left, right] (by simp) (by
    simp [root, left, right, Value.text, Value.applyList])
  let bottom := AllEdge.make left [fa, fb] (by simp) (by
    simp [left, fa, fb, application, Value.text, Value.applyList])
  let leftOwner := OutcomeEdge.make fa (.text "left observed") [] (by simp)
    (by simp [maxOutcomeObservations])
  let rightOwner := OutcomeEdge.make right (.text "right observed") [] (by simp)
    (by simp [maxOutcomeObservations])
  let graph : WorkGraph := {all := [top, bottom], outcomes := [leftOwner, rightOwner]}
  let ab ← union a b
  let quotient ← full [top.relation, bottom.relation, leftOwner.relation, rightOwner.relation] [ab]
  let extraction := Extract.runWithPolicy graph quotient.toEquality .allCompleted root
  let some report := SelectionDependency.report? graph quotient.toEquality .allCompleted root extraction.selection |
    throw (IO.userError "branch fixture did not select a checked extraction")
  let snapshot := SelectionAudit.Snapshot.ofReport [ab] [] report ["left", "right"]
    [(leftOwner.relation, "left"), (rightOwner.relation, "right")]
  let replay ← IO.ofExcept (SelectionAudit.analyze snapshot)
  let branches ← IO.ofExcept (replay.getObjValAs? (List Lean.Json) "completedBranches")
  require (branches.length == 2) "completed branch accounting lost or duplicated an Outcome"
  let some leftBranch := branches.find? (fun branch => branch.getObjValD "owner" == Lean.toJson "left") |
    throw (IO.userError "left completed branch is missing")
  let some rightBranch := branches.find? (fun branch => branch.getObjValD "owner" == Lean.toJson "right") |
    throw (IO.userError "right completed branch is missing")
  let leftRows ← IO.ofExcept (leftBranch.getObjValAs? (List Lean.Json) "comparisons")
  let rightRows ← IO.ofExcept (rightBranch.getObjValAs? (List Lean.Json) "comparisons")
  require (leftRows.any (fun row => row.getObjValD "kind" == Lean.toJson "congruence") &&
      rightRows.all (fun row => row.getObjValD "kind" == Lean.toJson "literal"))
    "a sibling subtree's congruence contaminated the literal completed branch"
  let id ← Receipt.fresh
  let some reference ← SelectionAudit.capture (some id) snapshot ["left", "right"] ["left"] |
    throw (IO.userError "branch fixture failed to record its immutable selection")
  let retained ← SelectionAudit.inspect (reference.restrict ["right"] [])
  let retainedBranches ← IO.ofExcept (retained.getObjValAs? (List Lean.Json) "completedBranches")
  require (retainedBranches.length == 1 && retainedBranches.all (fun branch =>
      branch.getObjValD "owner" == Lean.toJson "right" &&
      branch.getObjValD "ownerVisible" == Lean.toJson true &&
      branch.getObjValD "ownerControls" == Lean.toJson false) &&
      retained.getObjValD "deliveryAncestry" == Lean.toJson "untracked")
    "final source/transport pruning retained another branch or certified complete ancestry"
  let empty ← SelectionAudit.inspect (reference.restrict [] [])
  require (empty.getObjValD "completedBranches" == Lean.toJson ([] : List Lean.Json))
    "a fully acknowledged delivery retained completed branches"
  let unbound := {snapshot with completedBranches := []}
  let some unboundReference ← SelectionAudit.capture (some id) unbound ["left"] [] |
    throw (IO.userError "unbound branch fixture failed to record")
  let unknown ← SelectionAudit.inspect unboundReference
  require (unknown.getObjValD "untrackedCompletedOwners" == Lean.toJson ["left"])
    "a missing branch was counted as congruence-free"
  let some first := snapshot.completedBranches.head? | throw (IO.userError "no branch fixture")
  let malformed := {snapshot with completedBranches := [{first with premises := []}]}
  require ((SelectionAudit.analyze malformed).toOption.isNone)
    "a branch without its completed Outcome premise was accepted"
  let outOfBounds := {snapshot with completedBranches := [{first with premises := [snapshot.premises.length]}]}
  require ((SelectionAudit.analyze outOfBounds).toOption.isNone)
    "an out-of-bounds branch comparison was accepted"
  let foreign := {snapshot with completedBranches := [{first with owner := "foreign"}]}
  require ((SelectionAudit.analyze foreign).toOption.isNone)
    "a completed branch acquired an unselected source owner"

def run : IO Unit := do
  explicitAndCongruence
  mixedAtomsAndLocalOrigins
  selectedDeduplication
  completedBranchIsolation
  nativeDiscovery
  IO.println "PASS equality dependency: direct closure, congruence, Exact, retraction, local ancestry, child deduplication, isolated completed branches and native extraction"

end Eggshell.EqualityDependencyTests
