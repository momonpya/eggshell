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
  let corpus := Matcher.Corpus.build LogicalText.logicalNormalizer graph
  let observed := discovery.hits.reverse.map (SelectionAudit.Admission.observe discovery.view work corpus {})
  let some audited ← Plugin.auditRenderedSelection (some id) [] discovery ⟨extraction, rfl⟩ rendered observed |
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
  let admissions ← IO.ofExcept (replay.getObjValAs? (List Lean.Json) "matchAdmissions")
  require (!admissions.isEmpty &&
      replay.getObjValD "untrackedAdmissionBranches" == Lean.toJson ([] : List Nat) &&
      replay.getObjValD "untrackedSourceChildBranches" == Lean.toJson ([] : List Nat))
    "native completed Match lost its admission comparisons or original All child"
  let snapshot ← SelectionAudit.read reference
  let some admission := snapshot.admissions.head? | throw (IO.userError "missing admission fixture")
  let extended := Value.text (text ++ "\nthen perform additional work")
  let future ← union extended work
  let future := {future with scope := .run (.text "admission-fixture")}
  let earlyAdmission := {admission with
    demand := Persistence.valueToJson extended
    wholeIdentity := false
    localCount := 0}
  let early := {snapshot with runLocal := [SelectionAudit.Generator.encode future], admissions := [earlyAdmission]}
  let earlyReplay ← IO.ofExcept (SelectionAudit.analyze early)
  let earlyRows ← IO.ofExcept (earlyReplay.getObjValAs? (List Lean.Json) "matchAdmissions")
  let some first := earlyRows.head? | throw (IO.userError "early admission disappeared")
  let comparisons ← IO.ofExcept (first.getObjValAs? (List Lean.Json) "comparisons")
  require (comparisons.any (fun comparison =>
      comparison.getObjValD "role" == Lean.toJson "wholeWorkIdentity" &&
      comparison.getObjValD "accepted" == Lean.toJson false &&
      comparison.getObjValD "kind" == Lean.toJson "notEquivalent"))
    "a future local Union rewrote an earlier negative Match comparison"
  let retroactive := {early with admissions := [{earlyAdmission with localCount := 1}]}
  require ((SelectionAudit.analyze retroactive).toOption.isNone)
    "an admission was replayed against a later equality state"
  let unknownChild := {early with admissions := [{earlyAdmission with child := Lean.Json.null}]}
  let unknownReplay ← IO.ofExcept (SelectionAudit.analyze unknownChild)
  let unknownRows ← IO.ofExcept (unknownReplay.getObjValAs? (List Lean.Json) "matchAdmissions")
  require (unknownRows.all (fun row => row.getObjValD "sourceChild" == Lean.toJson "untracked"))
    "a missing source-child witness was classified as a complete admission"
  let missingPrefix := {early with admissions := [{earlyAdmission with localCount := 2}]}
  require ((SelectionAudit.analyze missingPrefix).toOption.isNone)
    "an admission used a nonexistent generator prefix"
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
  let strippedReplay ← SelectionAudit.inspect stripped
  require (strippedReplay.getObjValD "matchAdmissions" == Lean.toJson ([] : List Lean.Json))
    "an acknowledged completed owner retained a Match admission"

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
  let untrackedAdmissions ← IO.ofExcept (retained.getObjValAs? (List Nat) "untrackedAdmissionBranches")
  require (untrackedAdmissions.length == 1)
    "a branch without a recorded Match was counted as a complete admission"
  let empty ← SelectionAudit.inspect (reference.restrict [] [])
  require (empty.getObjValD "completedBranches" == Lean.toJson ([] : List Lean.Json) &&
      empty.getObjValD "matchAdmissions" == Lean.toJson ([] : List Lean.Json))
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

/-- All selected extraction comparisons are literal here. Congruence is
needed solely to establish that the original owner occupies an All-child role. -/
def nativeCongruentChild : IO Unit := do
  let text := "Bash\ncat congruent.c"
  let work := Value.text text
  let child := Value.text "stored child alias"
  let a := Value.text "child a"
  let b := Value.text "child b"
  let ab ← union a b
  let xa ← union work (application a)
  let yb ← union child (application b)
  let persistent := [ab, xa, yb]
  let result := Value.text "congruent.c contains the implementation"
  let occurrence := Value.applyList .occurrence [Ref.semantic result, Ref.semantic work]
  let owner := OutcomeEdge.make work result [occurrence] (by simp) (by simp [maxOutcomeObservations])
  let frame := AllEdge.make (.applyList .inquiry []) [child] (by simp) (by
    simp [child, Value.text, Value.applyList])
  let graph : WorkGraph := {all := [frame], outcomes := [owner]}
  let corpus := Matcher.Corpus.build LogicalText.logicalNormalizer graph
  let some discovery := Matcher.discoverIn? LogicalText.logicalNormalizer work
      [frame.relation, owner.relation] persistent graph corpus text none {} true true |
    throw (IO.userError "congruent-child native discovery did not converge")
  let extraction := Matcher.extraction discovery
  let some report := Plugin.discoverySelectionReport discovery |
    throw (IO.userError "congruent-child extraction has no checked report")
  let selected := (Plugin.selectedMatches discovery extraction).filter (·.blocks)
  require (!selected.isEmpty) "congruence did not establish the native owner's original child role"
  let bindings := selected.map fun item => (item.matched.projectedEdge.relation, "congruent-owner")
  let observed := discovery.hits.reverse.map fun matched =>
    (SelectionAudit.Admission.observe discovery.view work corpus {} matched, "congruent-owner")
  let snapshot := SelectionAudit.Snapshot.ofReport persistent discovery.view.localUnions
    report ["congruent-owner"] bindings observed
  let replay ← IO.ofExcept (SelectionAudit.analyze snapshot)
  let extractionRows ← IO.ofExcept (replay.getObjValAs? (List Lean.Json) "comparisons")
  let admissions ← IO.ofExcept (replay.getObjValAs? (List Lean.Json) "matchAdmissions")
  require (extractionRows.all (fun row => row.getObjValD "kind" == Lean.toJson "literal") &&
      admissions.any (fun admission =>
        ((admission.getObjValAs? (List Lean.Json) "comparisons").toOption.getD []).any fun row =>
          row.getObjValD "role" == Lean.toJson "subworkAlias" &&
          row.getObjValD "kind" == Lean.toJson "congruence"))
    "congruence in the original child-role witness disappeared behind literal extraction comparisons"

def indexedAdmission (withLocal : Bool := false) (withContinuation : Bool := false) : IO Unit := do
  let id ← Receipt.fresh
  let path := (← Paths.dataRoot) / ("admission-" ++ id ++ ".egg")
  let text := "Bash\ncat indexed-admission.c"
  let query := if withContinuation then text ++ "; cat extra.c"
    else if withLocal then "Bash\ncat INDEXED-ADMISSION.c" else text
  let work := Value.text text
  let result := Value.text "indexed-admission.c contains the implementation"
  let occurrence := Value.applyList .occurrence [Ref.semantic result, Ref.semantic work]
  let owner := OutcomeEdge.make work result [occurrence] (by simp) (by simp [maxOutcomeObservations])
  let frame := AllEdge.make (.applyList .inquiry []) [work] (by simp) (by
    simp [work, Value.text, Value.applyList])
  let initial ← DB.PageMap.create path (Persistence.valueToJson (.text "admission-fixture")).compress
  let (_, _, _) ← DB.PageMap.withWriter initial fun writer => do
    let intern : Persistence.Store.Intern := ⟨writer, ← IO.mkRef {}⟩
    let ids ← [owner.relation, frame.relation].mapM intern.root
    Persistence.Store.writeChange writer ⟨ids, [], false⟩
  let snapshot ← DB.PageMap.pin path
  let selection : Config.Selection := {
    label := "admission", read := [⟨"source", path⟩], write := none,
    semanticMatcher := none, handoffChars := 24000 }
  let some (some audited) ← Plugin.indexedDiscovery selection [some snapshot] query [] true none true
      (receipt := some id) |
    throw (IO.userError "indexed production discovery lost the native admission fixture")
  let some reference := audited.equalitySelection |
    throw (IO.userError "indexed production discovery omitted its admission locator")
  let replay ← SelectionAudit.inspect reference
  let admissions ← IO.ofExcept (replay.getObjValAs? (List Lean.Json) "matchAdmissions")
  require (!admissions.isEmpty && admissions.any (fun admission =>
      (admission.getObjValD "childEvidence").getObjValD "kind" == Lean.toJson "indexed") &&
      replay.getObjValD "untrackedAdmissionBranches" == Lean.toJson ([] : List Nat) &&
      replay.getObjValD "untrackedSourceChildBranches" == Lean.toJson ([] : List Nat))
    "indexed discovery omitted admission-time equality or its sparse original child frame"
  require (admissions.all (fun admission =>
      admission.getObjValD "schedulingAncestry" == Lean.toJson "recorded-step"))
    "a production Match lost the actual scheduling observation preceding its construction"
  let saved ← SelectionAudit.read reference
  require (!saved.schedules.isEmpty) "production scheduling observations were not serialized"
  let some firstSchedule := saved.schedules.head? | throw (IO.userError "missing scheduling fixture")
  let foreignTask := Persistence.valueToJson (.text "foreign scheduled task")
  let alteredTasks := {firstSchedule with tasks := firstSchedule.tasks ++ [foreignTask]}
  require ((SelectionAudit.analyze {saved with schedules := [alteredTasks]}).toOption.isNone)
    "a task absent from actual discovery acquired a scheduling record"
  let disconnected := {firstSchedule with discovery := [foreignTask], tasks := [foreignTask]}
  require ((SelectionAudit.analyze {saved with schedules := [disconnected]}).toOption.isNone)
    "a Match changed its original scheduled Demand"
  require (snapshot.head == (← DB.PageMap.pin path).head)
    "admission diagnostics changed the read-only source graph"
  if withLocal then
    require (!saved.runLocal.isEmpty && saved.localOrigins.length == saved.runLocal.length &&
        replay.getObjValD "untrackedLocalOrigins" == Lean.toJson ([] : List Nat))
      "production local Unions lost their actual proposing Match"
    require (admissions.any (fun admission =>
      ((admission.getObjValAs? (List Lean.Json) "comparisons").toOption.getD []).any fun row =>
        row.getObjValD "role" == Lean.toJson "fragmentIdentity" &&
        row.getObjValD "kind" == Lean.toJson "localUnion"))
      "the completed fixture did not actually depend on its new local Union"
    let origins ← IO.ofExcept (replay.getObjValAs? (List Lean.Json) "localUnionOrigins")
    require (origins.all (fun origin =>
      origin.getObjValD "schedulingAncestry" == Lean.toJson "recorded-step"))
      "a local proposer lost the scheduling epoch which exposed its Demand"
    let missingSchedules ← IO.ofExcept (SelectionAudit.analyze {saved with schedules := []})
    let untrackedSchedules ← IO.ofExcept (missingSchedules.getObjValAs? (List Lean.Json) "localUnionOrigins")
    require (untrackedSchedules.all (fun origin =>
      origin.getObjValD "schedulingAncestry" == Lean.toJson "untracked"))
      "a missing scheduling observation became a traced local proposal"
    require (origins.any (fun origin =>
        ((origin.getObjValAs? (List Lean.Json) "comparisons").toOption.getD []).any fun row =>
          row.getObjValD "role" == Lean.toJson "fragmentIdentity" &&
          row.getObjValD "kind" == Lean.toJson "notEquivalent") &&
        replay.getObjValD "localUnionAncestry" == Lean.toJson "untracked")
      "the proposing comparison was retroactively justified or complete causal ancestry was claimed"
    let some first := saved.localOrigins.head? | throw (IO.userError "missing local origin fixture")
    let cyclic := {saved with localOrigins := [{first with localCount := first.generator + 1}]}
    require ((SelectionAudit.analyze cyclic).toOption.isNone)
      "a local generator used itself or its future as nomination authority"
    let retrieved := {saved with localOrigins := [{first with retrieved := true}]}
    require ((SelectionAudit.analyze retrieved).toOption.isNone)
      "retrieval relatedness acquired a local-Union origin"
    let empty := {first with
      priorComplete := false, demandComplete := false, priorWeight := 0, demandWeight := 0}
    require ((SelectionAudit.analyze {saved with localOrigins := [empty]}).toOption.isNone)
      "zero-weight unaligned fragments acquired a local-Union origin"
    let foreign := {saved with localOrigins := [{first with inquiry := Persistence.valueToJson (.text "foreign")}]}
    require ((SelectionAudit.analyze foreign).toOption.isNone)
      "local nomination crossed its recorded Inquiry scope"
    let duplicate := {saved with localOrigins := [first, first]}
    require ((SelectionAudit.analyze duplicate).toOption.isNone)
      "a generator acquired duplicate origin records"
    let missing ← IO.ofExcept (SelectionAudit.analyze {saved with localOrigins := []})
    let unknown ← IO.ofExcept (missing.getObjValAs? (List Nat) "untrackedLocalOrigins")
    require (unknown.length == saved.runLocal.length)
      "missing local generator origins were counted as congruence-free"
  if withContinuation then
    require (!saved.continuations.isEmpty) "partial native completion did not record its generated continuation"
    let continuations ← IO.ofExcept (replay.getObjValAs? (List Lean.Json) "continuationRecords")
    require (continuations.all (fun event =>
      event.getObjValD "untrackedChildren" == Lean.toJson ([] : List Nat)))
      "a generated continuation child lost its actual root Match"
    require (saved.schedules.any (fun schedule => schedule.uses.any (·.generated)))
      "a later scheduling selection lost its generated All provenance"
    let some continuation := saved.continuations.head? | throw (IO.userError "missing continuation fixture")
    let brokenRoot := {continuation with current := foreignTask}
    require ((SelectionAudit.analyze {saved with continuations := [brokenRoot]}).toOption.isNone)
      "a continuation changed the external root while keeping its child witnesses"
    let some support := continuation.support.head? | throw (IO.userError "missing continuation support")
    let future := {support with localCount := some (saved.runLocal.length + 1)}
    require ((SelectionAudit.analyze {saved with continuations := [{continuation with support := [future]}]}).toOption.isNone)
      "a generated continuation depended on a future Match observation"
    let inactive := {support with automatic := false}
    require ((SelectionAudit.analyze {saved with continuations := [{continuation with support := [inactive]}]}).toOption.isNone)
      "a nonautomatic Match acquired a generated continuation child"
    let missing ← IO.ofExcept (SelectionAudit.analyze {saved with continuations := [{continuation with support := []}]})
    let records ← IO.ofExcept (missing.getObjValAs? (List Lean.Json) "continuationRecords")
    require (records.any (fun event =>
      !((event.getObjValAs? (List Nat) "untrackedChildren").toOption.getD []).isEmpty))
      "missing continuation support was counted as a traced child"
  if !withLocal && !withContinuation then
    let terminalId ← Receipt.fresh
    let some (some fast) ← Plugin.indexedTerminalRoot selection [some snapshot] text [] true none true
        (receipt := some terminalId) | throw (IO.userError "terminal native fixture missed its certified path")
    let some fastReference := fast.equalitySelection | throw (IO.userError "terminal fixture omitted equality capture")
    let fastReplay ← SelectionAudit.inspect fastReference
    let schedules ← IO.ofExcept (fastReplay.getObjValAs? (List Lean.Json) "schedulingRecords")
    require (schedules.any (fun schedule => schedule.getObjValD "kind" == Lean.toJson "terminal"))
      "terminal native capture reran or omitted its certified root scheduling case"

def syntheticDemandFilter : IO Unit := do
  let root := Value.applyList .inquiry []
  let child := Value.text "synthetic child"
  let text := "synthetic remainder"
  let remainder := HandoffRemainder.value text
  let edge := AllEdge.make root [child, remainder] (by simp) (by
    simp [root, child, remainder, HandoffRemainder.value, Value.text, Value.applyList])
  let schedule : DiscoveryAudit.ScheduleSnapshot := {
    pass := 0, kind := "discovery", localCount := 0, current := Persistence.valueToJson root
    discovery := [Persistence.valueToJson child, Persistence.valueToJson remainder]
    tasks := [], runAll := [Persistence.valueToJson edge.relation], premises := [], uses := [] }
  let _ ← IO.ofExcept (SelectionAudit.analyzeSchedule [] [] schedule)
  let rematched := {schedule with tasks := [Persistence.valueToJson child]}
  require ((SelectionAudit.analyzeSchedule [] [] rematched).toOption.isNone)
    "a generated continuation child was rematched as a fresh source Demand"
  let remainderTask := {schedule with tasks := [Persistence.valueToJson remainder]}
  require ((SelectionAudit.analyzeSchedule [] [] remainderTask).toOption.isNone)
    "a synthetic remainder was treated as an independently matchable Demand"

def advisoryContinuation : IO Unit := do
  let original := "Bash\ncat advisory.c"
  let text := original ++ "; cat other.c"
  let work := Value.text original
  let current := Value.text text
  let result := Value.text "advisory.c contains the original observed source"
  let occurrence := Value.applyList .occurrence [Ref.semantic result, Ref.semantic work]
  let owner := OutcomeEdge.make work result [occurrence] (by simp) (by simp [maxOutcomeObservations])
  let frame := AllEdge.make (.applyList .inquiry []) [work] (by simp) (by
    simp [work, Value.text, Value.applyList])
  let graph : WorkGraph := {all := [frame], outcomes := [owner]}
  let corpus := Matcher.Corpus.build LogicalText.logicalNormalizer graph
  let trail ← IO.mkRef ({} : DiscoveryAudit.Trail)
  let some discovery ← Matcher.discoverUsingM? () graph.all (fun _ => graph.outcomes)
      (fun _ => [frame.relation, owner.relation]) (fun _ _ => none)
      (fun state view tasks => pure (state, Matcher.demandedMatches LogicalText.logicalNormalizer
        corpus view current none {} true tasks)) current [] text 32 false
      (recordTrace := fun event => trail.modify (fun value => value.observe event (fun _ => none))) |
    throw (IO.userError "advisory continuation trace did not converge")
  require ((Matcher.extraction discovery).selection.completedUses.isEmpty && discovery.view.localUnions.isEmpty)
    "retrieval-only continuation acquired equality or completed Work"
  let trail ← trail.get
  let some continuation := trail.continuations.head? |
    throw (IO.userError "retrieval-only matching did not exercise generated continuation support")
  let some snapshot := continuation.snapshot? [] | throw (IO.userError "advisory continuation changed its epoch")
  let schedules := trail.schedules.reverse.filterMap (·.snapshot? [])
  let replay ← IO.ofExcept (SelectionAudit.analyzeContinuation [] [] schedules snapshot)
  let support ← IO.ofExcept (replay.getObjValAs? (List Lean.Json) "support")
  require (support.any (fun row => row.getObjValD "retrieved" == Lean.toJson true &&
      row.getObjValD "comparisons" == Lean.Json.null))
    "advisory continuation support was rejected or a missing Match observation was counted as literal"

def run : IO Unit := do
  explicitAndCongruence
  mixedAtomsAndLocalOrigins
  selectedDeduplication
  completedBranchIsolation
  nativeDiscovery
  nativeCongruentChild
  indexedAdmission
  indexedAdmission true
  indexedAdmission false true
  syntheticDemandFilter
  advisoryContinuation
  IO.println "PASS equality dependency: direct closure, congruence, Exact, retraction, local ancestry, child deduplication, isolated completed branches and native extraction"

end Eggshell.EqualityDependencyTests
