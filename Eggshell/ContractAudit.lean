module

import Eggshell.SearchRank
import Eggshell.SearchProvider
import Eggshell.SemanticMatcher
import Eggshell.PluginModel
import Eggshell.Setup
import all Eggshell.GraphStore
public meta import Lean
import tests.FullSearchOracle

open Lean

/- The normal pinned DAG reader captures whole payload programs. Writer
reads use the same decoding/assembly implementation with their own read
capability; no alternate body representation or compatibility lane exists. -/
run_meta do
  for theoremName in #[``Eggshell.Extract.solve_demand_exact,
      ``Eggshell.Extract.solve_provenance,
      ``Eggshell.Selection.validFor_provenance_congr,
      ``Eggshell.Extract.runWithPolicyFuel_demand_exact,
      ``Eggshell.QuotientBuilder.AtomQuotient.Index.subwork_exact] do
    let axioms ← Lean.collectAxioms theoremName
    for axiomName in axioms do
      unless #[``propext, ``Classical.choice, ``Quot.sound].contains axiomName do
        throwError "Demand proof uses an unapproved axiom: {theoremName}: {axiomName}"
    logInfo m!"Audited {theoremName}: {axioms}"

run_meta do
  let environment ← getEnv
  for (caller, required) in #[
      (``Eggshell.Persistence.Store.NodeReader.read, ``Eggshell.DB.PageMap.Snapshot.readPayload),
      (``Eggshell.DB.PageMap.Snapshot.readPayload, ``Eggshell.DB.PageMap.Snapshot.readPayloadUsing),
      (``Eggshell.Persistence.Store.readChunks, ``Eggshell.DB.PageMap.Snapshot.readPayloadUsing),
      (``Eggshell.DB.PageMap.Snapshot.checkPayload?, ``Eggshell.DB.PageMap.HistoryReader.make?),
      (``Eggshell.DB.PageMap.Snapshot.checkPayload?, ``Eggshell.DB.PageMap.HistoryReader.retainBlob),
      (``Eggshell.DB.PageMap.Snapshot.checkPayload?, ``Eggshell.DB.PageMap.Snapshot.readPinnedBlob),
      (``Eggshell.DB.PageMap.Snapshot.checkPayload?, ``Eggshell.DB.PageMap.checkPayloadChunks),
      (``Eggshell.DB.PageMap.Snapshot.checkPayload?, ``Eggshell.DB.PageMap.PayloadPrefix.check?),
      (``Eggshell.Persistence.Store.bodiesEqual, ``Eggshell.DB.PageMap.QuietReader.make),
      (``Eggshell.Persistence.Store.bodiesEqual, ``Eggshell.DB.PageMap.checkPrefix),
      (``Eggshell.Persistence.Store.bodiesEqual, ``Eggshell.DB.PageMap.Snapshot.observe),
      (``Eggshell.Persistence.Store.bodiesEqual, ``Eggshell.Persistence.Store.bodyChunk)] do
    let some definition := environment.find? caller | throwError "Missing payload caller: {caller}"
    let some value := definition.value? | throwError "Missing payload implementation: {caller}"
    unless value.getUsedConstants.contains required do
      throwError "Payload caller bypasses canonical capture/validation: {caller}, {required}"
  logInfo "Audited complete payload program capture in production DAG reads"

/- All actual candidate compilers use the canonical lazy factory. Merely
adding a lazy helper while leaving Outcome compilation eager is rejected. -/
run_meta do
  let environment ← getEnv
  for (caller, required, forbidden) in #[
      (``Eggshell.Matcher.compile, ``Eggshell.Matcher.makePatternLazy,
        #[``Eggshell.Matcher.makePattern, ``Thunk.pure]),
      (``Eggshell.Matcher.Corpus.finishCandidate, ``Eggshell.Matcher.compile,
        #[``Eggshell.LogicalText.build, ``Eggshell.Matcher.makePattern]),
      (``Eggshell.Matcher.Corpus.compileCandidate, ``Eggshell.Matcher.compile,
        #[``Eggshell.LogicalText.build, ``Eggshell.Matcher.makePattern]),
      (``Eggshell.Matcher.Corpus.OutcomeMemo.prepare, ``Eggshell.Matcher.compile,
        #[``Eggshell.LogicalText.build, ``Eggshell.Matcher.makePattern])] do
    let some declaration := environment.find? caller | throwError "Missing lazy compiler: {caller}"
    let some body := declaration.value? | throwError "Compiler has no body: {caller}"
    let dependencies := body.getUsedConstants
    unless dependencies.contains required do
      throwError "Candidate compiler bypasses lazy normalization: {caller}, {required}"
    for name in forbidden do
      if dependencies.contains name then
        throwError "Candidate compiler eagerly constructs normalized text: {caller}, {name}"
  logInfo m!"Audited canonical lazy normalization in production candidate and memo compilers"

/- The capture caller uses an indexed collision bucket, never the full-list
specification. This gate checks the actual production declaration separately
from the equality and budget proofs below. -/
run_meta do
  let environment ← getEnv
  let some declaration := environment.find? ``Eggshell.DB.PageMap.ReadTrace.add |
    throwError "Missing production dependency capture"
  let some body := declaration.value? | throwError "Dependency capture has no body"
  let dependencies := body.getUsedConstants
  for required in #[``Eggshell.DB.PageMap.ObservationIndex.contains,
      ``Eggshell.DB.PageMap.ObservationIndex.insert] do
    unless dependencies.contains required do
      throwError "Production dependency capture bypasses its index: {required}"
  for forbidden in #[``List.contains, ``Eggshell.DB.PageMap.ReadSummary.step] do
    if dependencies.contains forbidden then
      throwError "Production dependency capture scans the entire trace: {forbidden}"
  logInfo m!"Audited indexed dependency capture and full-list negative control"

/- Body capture must use a checked pinned reference, and memo reuse must
pass the saved file identity through the typed validation entry point. -/
run_meta do
  let environment ← getEnv
  for (caller, required) in #[
      (``Eggshell.DB.PageMap.Snapshot.readBlob, ``Eggshell.DB.PageMap.Blob.pin?),
      (``Eggshell.DB.PageMap.Snapshot.readBlob, ``Eggshell.DB.PageMap.Snapshot.readPinnedBlob),
      (``Eggshell.DB.PageMap.Snapshot.readPinnedBlob, ``Eggshell.DB.PageMap.Snapshot.observe),
      (``Eggshell.Plugin.DemandMemo.dependenciesAgree, ``Eggshell.DB.PageMap.Snapshot.verifyReads?)] do
    let some declaration := environment.find? caller | throwError "Missing caller: {caller}"
    let some body := declaration.value? | throwError "Caller has no body: {caller}"
    unless body.getUsedConstants.contains required do
      throwError "Immutable dependency caller bypasses checked references: {caller}, {required}"
  logInfo m!"Audited immutable body capture and scoped dependency validation"

/- Production source capture, binding and delivery must remain connected.
This checks declaration reachability, separately from the kernel contracts. -/
run_meta do
  let environment ← getEnv
  for (root, required, forbidden) in #[
      (``Eggshell.Plugin.recordTool,
        #[``Eggshell.FileSystem.immutableBytes, ``Eggshell.Plugin.readNativeTool?],
        #[]),
      (``Eggshell.Plugin.captureTerminal,
        #[``Eggshell.Plugin.recordTool, ``Eggshell.Plugin.sealRecordedRead,
          ``Eggshell.Plugin.queueCheckpoint],
        #[``Eggshell.SourceObservation.step, ``Eggshell.Plugin.observeRelatedFiles]),
      (``Eggshell.Plugin.sealRecordedRead, #[``Eggshell.SourceEvidence.sealCapture], #[]),
      (``Eggshell.Plugin.preToolUse,
        #[``Eggshell.Plugin.nativeSourceInput?, ``Eggshell.SourceEvidence.capture,
          ], #[``Eggshell.SourceObservation.step]),
      (``Eggshell.Plugin.observeRelatedFiles,
        #[``Eggshell.SourceObservation.step, ``Eggshell.Plugin.observationTool,
          ``Eggshell.Plugin.queueCheckpoint,
          ``Eggshell.SourceObservation.acknowledge], #[]),
      (``Eggshell.SourceObservation.step,
        #[``Eggshell.FileSystem.readPage, ``Eggshell.SourceEvidence.stepRoot,
          ``Eggshell.SourceObservation.finish], #[]),
      (``Eggshell.Plugin.Worker.run,
        #[``Eggshell.Plugin.observeRelatedFiles], #[]),
      (``Eggshell.Plugin.reconcileToolReceipts,
        #[``Eggshell.Plugin.attachCertificate], #[]),
      (``Eggshell.Persistence.Store.Intern.root,
        #[``Eggshell.SourceEvidence.receiptFields?], #[]),
      (``Eggshell.Plugin.automaticHandoff,
        #[``Eggshell.Plugin.Handoff.checkSources, ``Eggshell.Persistence.Store.NodeReader.sources], #[]),
      (``Eggshell.Plugin.Handoff.checkSources,
        #[``Eggshell.Plugin.Handoff.withCheckedSources, ``Eggshell.SourceEvidence.observeRecords,
          ``Eggshell.Plugin.checkSourceUse?, ``Eggshell.Plugin.sourceRefreshText], #[]),
      (``Eggshell.Plugin.Handoff.checkedCheckpoints,
        #[``Eggshell.Plugin.checkApplicableSourceUse?], #[]),
      (``Eggshell.Plugin.renderOwnerSourceStatus,
        #[``Eggshell.Plugin.checkedOwnerSources?], #[``Eggshell.Plugin.sourceApplicable]),
      (``Eggshell.Plugin.indexedDiscoveryUsing,
        #[``Eggshell.Plugin.focusNeighborhood, ``Eggshell.Plugin.sourceFocus?,
          ``Eggshell.Plugin.prioritizedEvidence,
          ``Eggshell.SemanticMatcher.nominateIndexed], #[]),
      (``Eggshell.Plugin.renderAutomatic,
        #[``Eggshell.Plugin.sourceTable, ``Eggshell.Plugin.Selected.sourceUse,
          ``Eggshell.Plugin.Selected.sourceCheckpoint?, ``Eggshell.Plugin.ownerContextAllowances,
          ``Eggshell.Plugin.contextSlicePlan, ``Eggshell.Plugin.boundedFlexiblePacketSlices,
          ``Eggshell.Plugin.deliveredEvidenceRanges, ``Eggshell.Plugin.EvidenceRange.subtractAll,
          ``Eggshell.Plugin.DecodedLayout.make, ``Eggshell.Plugin.decodedEvidenceUsing?,
          ``Eggshell.Plugin.prepareContextualOwnerData, ``Eggshell.Plugin.coalesceRankedContexts,
          ``Eggshell.Plugin.ownerContextDemand, ``Eggshell.Plugin.adaptivePacketBudget,
          ``Eggshell.Plugin.coherentPacketDemand,
          ``Eggshell.Plugin.contextAllowanceLevels, ``Eggshell.Plugin.preferredContextLevel,
          ``Eggshell.Plugin.requestedContextLevels,
          ``Eggshell.Plugin.contextStructureHeads, ``Eggshell.Plugin.structureContextRanges,
          ``Eggshell.Plugin.contextRangesWithStructure,
          ``Eggshell.Plugin.meaningPacketEntry,
          ``Eggshell.Plugin.evidenceAdmissionPriority,
          ``Eggshell.Plugin.remainingEvidence], #[]),
      (``Eggshell.Plugin.nativeOccurrence,
        #[], #[``Eggshell.SourceEvidence.encode]) ] do
    let mut seen : Std.HashSet Name := {}
    let mut pending := [root]
    while !pending.isEmpty do
      if let name :: rest := pending then
        pending := rest
        if seen.contains name then continue
        seen := seen.insert name
        if let some definition := environment.find? name then
          if let some value := definition.value? then
            for dependency in value.getUsedConstants do
              if dependency.toString.startsWith "Eggshell." then pending := dependency :: pending
    for name in required do
      unless seen.contains name do throwError "Source boundary {root} does not reach {name}"
    for name in forbidden do
      if seen.contains name then throwError "Source metadata changes stable owner through {root}: {name}"
    logInfo m!"Audited source boundary {root}"

/- Keep the normal read/write boundary independent of the test-only full
   oracle and known whole-graph loaders, including indirect helper calls.
   This is a declaration dependency regression gate, not an IO/time theorem. -/
run_meta do
  let environment ← getEnv
  let forbidden := #[``Eggshell.Persistence.Store.materialize,
    ``Eggshell.Persistence.Store.revise, ``Eggshell.Persistence.loadExisting?,
    ``Eggshell.Persistence.loadComposite]
  for (root, normal) in #[(``Eggshell.Plugin.automaticHandoff, true),
      (``Eggshell.Plugin.computeAutomaticHandoff, true),
      (``Eggshell.Persistence.appendPrepared, true),
      (``Eggshell.Persistence.load, false),
      (``Eggshell.TestOracle.computeGeneralAutomaticHandoff, false)] do
    let mut seen : Std.HashSet Name := {}
    let mut pending := [root]
    let mut blocked : Option Name := none
    while !pending.isEmpty do
      if let name :: rest := pending then
        pending := rest
        if seen.contains name then continue
        seen := seen.insert name
        if forbidden.contains name || name.toString.startsWith "Eggshell.TestOracle." then
          blocked := some name
          break
        if let some definition := environment.find? name then
          if let some value := definition.value? then
            for dependency in value.getUsedConstants do
              if dependency.toString.startsWith "Eggshell." then
                pending := dependency :: pending
    if root == ``Eggshell.Plugin.computeAutomaticHandoff then
      unless seen.contains ``Eggshell.Plugin.SingleSource.find? do
        throwError "Normal search does not reach the complete readable-source selector"
    match normal, blocked with
    | true, some name =>
        throwError "Normal persistence/search boundary {root} reaches forbidden full-source declaration {name}"
    | true, none =>
        logInfo m!"Audited no full-source restoration reachable from {root}: {seen.size} declarations"
    | false, some name =>
        logInfo m!"Audited full-source gate rejects {root} via {name}"
    | false, none =>
        throwError "Full-source restoration regression gate failed to reject {root}"

/- The production federation interpreter must actually use checked child
substitution and streamed Atom comparisons. Reject a return to recursive DAG
comparison, and keep the frozen earlier interpreter as a negative control. -/
run_meta do
  let environment ← getEnv
  for (root, canonical) in #[(``Eggshell.Persistence.Store.Federated.Identity.add, true),
      (``Eggshell.TestOracle.FederationBeforeCanonical.Identity.add, false)] do
    let mut seen : Std.HashSet Name := {}
    let mut pending := [root]
    let mut recursive := false
    let mut substitution := false
    let mut chunks := false
    while !pending.isEmpty do
      if let name :: rest := pending then
        pending := rest
        if seen.contains name then continue
        seen := seen.insert name
        if #[``Eggshell.Persistence.Store.nodesEqual,
            ``Eggshell.Persistence.Store.nodesEqualBound].contains name then recursive := true
        if name == ``Eggshell.Persistence.Store.Federated.ReboundApplication.make? then substitution := true
        if name == ``Eggshell.Persistence.Store.bodiesEqual then chunks := true
        if let some definition := environment.find? name then
          if let some value := definition.value? then
            for dependency in value.getUsedConstants do
              if dependency.toString.startsWith "Eggshell." then pending := dependency :: pending
    unless recursive == !canonical && substitution == canonical && chunks do
      throwError "Federation identity boundary {root}: recursive={recursive}, substitution={substitution}, chunks={chunks}"
    logInfo m!"Audited federation identity {root}: recursive={recursive}, substitution={substitution}, chunks={chunks}"

/- Root persistence must really use the direct traversal. The equality proofs
above are erased, so the production definition graph need not reach either
flattened list specification. Keep the frozen old compiler as a negative gate. -/
run_meta do
  let environment ← getEnv
  let flattened := #[``Eggshell.Value.nodes, ``Eggshell.Value.refsNodes,
    ``Eggshell.Value.semanticNodes, ``Eggshell.Value.refsSemanticNodes]
  for (root, direct) in #[(``Eggshell.Persistence.Store.RootReach.compile, true),
      (``Eggshell.TestOracle.rootReachBeforeFold, false)] do
    let mut seen : Std.HashSet Name := {}
    let mut pending := [root]
    let mut blocked : Option Name := none
    while !pending.isEmpty do
      if let name :: rest := pending then
        pending := rest
        if seen.contains name then continue
        seen := seen.insert name
        if flattened.contains name then
          blocked := some name
          break
        if let some definition := environment.find? name then
          if let some value := definition.value? then
            for dependency in value.getUsedConstants do
              if dependency.toString.startsWith "Eggshell." then
                pending := dependency :: pending
    match direct, blocked with
    | true, none => logInfo m!"Audited direct root traversal from {root}: no flattened node list"
    | false, some name => logInfo m!"Audited flattened-node gate rejects {root} via {name}"
    | true, some name => throwError "Direct root traversal {root} reaches flattened node list {name}"
    | false, none => throwError "Flattened-node gate failed to reject {root}"

/- Search projection must stay outside normal publication. Also check the
actual positive/negative call graphs: an equality theorem alone would allow
a later implementation to reintroduce the full copied-parts list. -/
run_meta do
  let environment ← getEnv
  for (root, expectedStream, expectedList) in #[
      (``Eggshell.Persistence.appendPrepared, false, false),
      (``Eggshell.Matcher.materializeContext, true, false),
      (``Eggshell.Matcher.intersectingSourceParts, true, false),
      (``Eggshell.TestOracle.sourcePartsBeforeStreaming, false, true)] do
    let mut seen : Std.HashSet Name := {}
    let mut pending := [root]
    let mut streamed := false
    let mut copiedList := false
    while !pending.isEmpty do
      if let name :: rest := pending then
        pending := rest
        if seen.contains name then continue
        seen := seen.insert name
        if name == ``Eggshell.TextParts.foldProjection then streamed := true
        if name == ``String.splitOn || name == ``String.splitOnAux then copiedList := true
        if let some definition := environment.find? name then
          if let some value := definition.value? then
            for dependency in value.getUsedConstants do
              if dependency.toString.startsWith "Eggshell." ||
                  dependency == ``String.splitOn || dependency == ``String.splitOnAux then
                pending := dependency :: pending
    unless streamed == expectedStream && copiedList == expectedList do
      throwError "Source projection boundary {root}: streamed={streamed}, copied-list={copiedList}"
    logInfo m!"Audited source projection {root}: streamed={streamed}, copied-list={copiedList}"

/- Keep the selective frequency path connected to actual discovery and
outside append. Reject a return to eager Outcome scoring in that controller. -/
run_meta do
  let environment ← getEnv
  let selective := #[``Eggshell.Matcher.prepareInUsing, ``Eggshell.Matcher.contextTerms,
    ``Eggshell.Plugin.readDemandFrequencies]
  for (root, normalSearch) in #[(``Eggshell.Plugin.indexedDiscoveryUsing, true),
      (``Eggshell.Persistence.appendPrepared, false)] do
    let mut seen : Std.HashSet Name := {}
    let mut pending := [root]
    while !pending.isEmpty do
      if let name :: rest := pending then
        pending := rest
        if seen.contains name then continue
        seen := seen.insert name
        if let some definition := environment.find? name then
          if let some value := definition.value? then
            for dependency in value.getUsedConstants do
              if dependency.toString.startsWith "Eggshell." then
                pending := dependency :: pending
    for target in selective do
      unless seen.contains target == normalSearch do
        throwError "Demand frequency path {root} has unexpected dependency {target}"
    if seen.contains ``Eggshell.Matcher.Corpus.scoringTerms then
      throwError "Demand frequency path {root} reaches eager Outcome scoring terms"
    logInfo m!"Audited selective frequency path {root}: search={normalSearch}"

/- The actual term collector must stream over existing units. Its complete
flat-list specification belongs only to the erased equality theorem. -/
run_meta do
  let environment ← getEnv
  let some definition := environment.find? ``Eggshell.Matcher.contextTerms |
    throwError "Missing production context term collector"
  let some value := definition.value? |
    throwError "Context term collector has no implementation"
  let dependencies := value.getUsedConstants
  unless dependencies.contains ``List.foldl do
    throwError "Context term collector no longer folds existing units"
  if dependencies.contains ``List.flatMap || dependencies.contains ``List.map then
    throwError "Context term collector materializes repeated unit lists"
  logInfo "Audited context term collector: streaming fold, no repeated map/flatMap lists"

/- All incidence is a save-time index consumed by the actual native caller.
The sparse reads cannot hydrate a descendant or full topology. -/
run_meta do
  let environment ← getEnv
  for (root, target) in #[( ``Eggshell.Persistence.Store.Intern.root,
      ``Eggshell.Persistence.Store.AllHeader.writeIndex),
      (``Eggshell.Persistence.Store.AllHeader.writeIndex,
        ``Eggshell.Persistence.Store.AllParentPosting.write),
      (``Eggshell.Plugin.indexedTerminalRoot, ``Eggshell.Persistence.Store.literalAllParents),
      (``Eggshell.Plugin.indexedTerminalRoot, ``Eggshell.Persistence.Store.literalAllChildren),
      (``Eggshell.Persistence.Store.removeRoot, ``Eggshell.Persistence.Store.AllParentPosting.name)] do
    let some definition := environment.find? root | throwError "Missing All parent caller {root}"
    let some value := definition.value? | throwError "Missing All parent body {root}"
    unless value.getUsedConstants.contains target do
      throwError "All parent caller {root} no longer uses {target}"
  let some definition := environment.find? ``Eggshell.Persistence.Store.literalAllParents |
    throwError "Missing literal All parent lookup"
  let some value := definition.value? | throwError "Missing literal All parent lookup body"
  for forbidden in #[``Eggshell.Persistence.Store.allHeaders,
      ``Eggshell.Persistence.Store.NodeReader.read, ``Eggshell.Persistence.Store.resolve,
      ``Eggshell.Persistence.Store.materialize, ``Eggshell.Persistence.Store.topology] do
    if value.getUsedConstants.contains forbidden then
      throwError "Sparse All parent lookup restores a graph or descendant: {forbidden}"
  let some definition := environment.find? ``Eggshell.Persistence.Store.literalAllChildren |
    throwError "Missing literal All child lookup"
  let some value := definition.value? | throwError "Missing literal All child lookup body"
  for forbidden in #[``Eggshell.Persistence.Store.allHeaders,
      ``Eggshell.Persistence.Store.NodeReader.read, ``Eggshell.Persistence.Store.resolve,
      ``Eggshell.Persistence.Store.materialize, ``Eggshell.Persistence.Store.topology] do
    if value.getUsedConstants.contains forbidden then
      throwError "Sparse All child lookup restores a graph or descendant: {forbidden}"
  logInfo "Audited save-time All incidence, actual native caller and descendant-free direct lookups"

/- The actual context lane retains only the demanded unit directory. Full
unit/Work directories remain specifications, never executing dependencies. -/
run_meta do
  let environment ← getEnv
  for (root, current) in #[( ``Eggshell.Matcher.surfaceContextCover, true),
      (``Eggshell.Matcher.surfaceContextCoverWith, false)] do
    let mut seen : Std.HashSet Name := {}
    let mut pending := [root]
    while !pending.isEmpty do
      if let name :: rest := pending then
        pending := rest
        if seen.contains name then continue
        seen := seen.insert name
        if let some definition := environment.find? name then
          -- Refinement propositions mention the full interpreter. They are
          -- erased, rather than executing edges of the production program.
          if definition matches .thmInfo _ then continue
          if let some value := definition.value? then
            for dependency in value.getUsedConstants do
              if dependency.toString.startsWith "Eggshell." then
                pending := dependency :: pending
    unless seen.contains ``Eggshell.Matcher.consumeContext == !current &&
        seen.contains ``Eggshell.Matcher.consumeUnitContext == current do
      throwError "Context traversal gate failed for {root}"
    if !current then
      logInfo "Audited context traversal gate rejects the former filtered-queue interpreter"
      continue
    unless seen.contains ``Eggshell.LogicalText.contextDemandIndex &&
        seen.contains ``Eggshell.LogicalText.foldPositions &&
        seen.contains ``Eggshell.LogicalText.ByteSource.make &&
        seen.contains ``Eggshell.LogicalText.ByteSource.slice? &&
        seen.contains ``Eggshell.Matcher.ContextDirectory.insert do
      throwError "Production context no longer consumes the certified demanded unit directory"
    for forbidden in #[``Eggshell.Matcher.Pattern.surface, ``Eggshell.Matcher.Pattern.surfaces,
        ``Eggshell.LogicalText.surfaceIndex, ``Eggshell.LogicalText.surfaceKeys,
        ``Eggshell.Matcher.Pattern.contextSurface, ``Eggshell.LogicalText.contextSurfaceIndex,
        ``List.range, ``Eggshell.LogicalText.gramsAt,
        ``Eggshell.LogicalText.byteSlice?, ``Eggshell.LogicalText.logicalSlice?] do
      if seen.contains forbidden then
        throwError "Production context expands an unrequested directory: {forbidden}"
    logInfo "Audited context matching: certified occurrence queues, prepared byte source, no full unit/Work/position directory"
  let some queue := environment.find? ``Eggshell.Matcher.consumeUnitContext |
    throwError "Missing production context queue"
  let some body := queue.value? | throwError "Missing production context queue body"
  if body.getUsedConstants.contains ``List.filter then
    throwError "Production context queue scans its entire remaining occurrence list"

/- Work anchor enumeration also prepares its byte source outside the loop.
The complete slice interpreter belongs to the erased equality proof. -/
run_meta do
  let environment ← getEnv
  let some definition := environment.find? ``Eggshell.LogicalText.gramsAt |
    throwError "Missing production Work anchor enumeration"
  let some value := definition.value? |
    throwError "Work anchor enumeration has no implementation"
  let dependencies := value.getUsedConstants
  unless dependencies.contains ``Eggshell.LogicalText.ByteSource.make &&
      dependencies.contains ``Eggshell.LogicalText.ByteSource.slice? do
    throwError "Work anchor enumeration no longer uses a prepared byte source"
  if dependencies.contains ``Eggshell.LogicalText.logicalSlice? ||
      dependencies.contains ``Eggshell.LogicalText.byteSlice? then
    throwError "Work anchor enumeration reconverts the complete source per anchor"
  logInfo "Audited Work anchor enumeration: prepared byte source and exact slice refinement"

/- Actual selected-owner controllers retain one typed reader, rather than
calling the per-owner administrative constructor wrapper. Private mutable
tables stay opaque; this gate is not a filesystem/value refinement proof. -/
run_meta do
  let environment ← getEnv
  for root in #[``Eggshell.Plugin.indexedTerminalRoot, ``Eggshell.Plugin.indexedDiscovery,
      ``Eggshell.Plugin.federatedDiscovery] do
    let some definition := environment.find? root | throwError "Missing source controller {root}"
    let some value := definition.value? | throwError "Missing source controller body {root}"
    let dependencies := value.getUsedConstants
    unless dependencies.contains ``Eggshell.Persistence.Store.NodeReader.outcome do
      throwError "Selected owner controller no longer uses the bound DAG reader: {root}"
    for forbidden in #[``Eggshell.Persistence.Store.readLocatedOutcome,
        ``Eggshell.Persistence.Store.readLocatedWork,
        ``Eggshell.Persistence.Store.readLocatedWorkOrigin] do
      if dependencies.contains forbidden then
        throwError "Selected owner controller allocates independent reader tables: {root}, {forbidden}"
    logInfo m!"Audited pinned owner reader in actual {root}"

  for (root, topology, unions) in #[
      (``Eggshell.Plugin.indexedTerminalRoot, ``Eggshell.Persistence.Store.NodeReader.atomTopology?,
        ``Eggshell.Persistence.Store.NodeReader.atomUnions?),
      (``Eggshell.Plugin.indexedDiscovery, ``Eggshell.Persistence.Store.DemandTopology.read,
        ``Eggshell.Persistence.Store.NodeReader.unions),
      (``Eggshell.Persistence.Store.Federated.prepare, ``Eggshell.Persistence.Store.NodeReader.topology,
        ``Eggshell.Persistence.Store.NodeReader.unions)] do
    let some definition := environment.find? root | throwError "Missing topology controller {root}"
    let some value := definition.value? | throwError "Missing topology controller body {root}"
    let dependencies := value.getUsedConstants
    unless dependencies.contains topology && dependencies.contains unions do
      throwError "Topology and Union do not use the bound reader: {root}"
    for forbidden in #[``Eggshell.Persistence.Store.topology, ``Eggshell.Persistence.Store.readUnions,
        ``Eggshell.Persistence.Store.atomTopology?, ``Eggshell.Persistence.Store.atomUnions?] do
      if dependencies.contains forbidden then
        throwError "Topology controller creates independent administrative readers: {root}, {forbidden}"
    if root == ``Eggshell.Plugin.indexedDiscovery &&
        dependencies.contains ``Eggshell.Persistence.Store.NodeReader.topology then
      throwError "Single-source discovery eagerly hydrates All before its demand closure"
  let some federated := environment.find? ``Eggshell.Plugin.federatedDiscovery |
    throwError "Missing federated discovery"
  let some body := federated.value? | throwError "Missing federated discovery body"
  unless body.getUsedConstants.contains ``Eggshell.Persistence.Store.Federated.Catalogue.readers do
    throwError "Federated owners do not reuse the topology reader family"
  if body.getUsedConstants.contains ``Eggshell.Persistence.Store.NodeReaders.new then
    throwError "Federated discovery allocates a second source reader family"
  for root in #[``Eggshell.Persistence.Store.NodeReader.readTopology,
      ``Eggshell.Persistence.Store.NodeReader.unions] do
    let some definition := environment.find? root | throwError "Missing bound topology reader {root}"
    let some value := definition.value? | throwError "Missing bound topology body {root}"
    unless value.getUsedConstants.contains ``Eggshell.Persistence.Store.NodeReader.read do
      throwError "Topology resolution bypasses the pinned DAG table: {root}"
    if value.getUsedConstants.contains ``Eggshell.Persistence.Store.readNode then
      throwError "Topology resolution creates per-endpoint tables: {root}"
  logInfo "Audited one pinned source reader across All, Union and selected Outcome owners"

/- The exact memo is consumed by both real candidate compilation paths;
proving a disconnected alternate compiler does not pass this gate. -/
run_meta do
  let environment ← getEnv
  for (root, target) in #[(``Eggshell.Plugin.indexedTerminalRoot,
      ``Eggshell.Matcher.Corpus.compileCandidatesUsing),
      (``Eggshell.Plugin.IndexedOwners.retain, ``Eggshell.Matcher.Corpus.OutcomeMemo.prepare)] do
    let some definition := environment.find? root | throwError "Missing Outcome memo caller {root}"
    let some value := definition.value? | throwError "Missing Outcome memo body {root}"
    unless value.getUsedConstants.contains target do
      throwError "Production caller does not consume canonical Outcome reuse: {root}"
    logInfo m!"Audited canonical Outcome compilation reuse in {root}"

/- Durable rank advice must be consumed by the actual sparse discovery path.
Administrative enumeration may not enter the automatic hook call graph. -/
run_meta do
  let environment ← getEnv
  let some automatic := environment.find? ``Eggshell.Plugin.automaticHandoff |
    throwError "Missing automatic handoff"
  let some automaticBody := automatic.value? | throwError "Missing automatic handoff body"
  unless automaticBody.getUsedConstants.contains ``Eggshell.Matcher.RankMemo.Reader.new do
    throwError "Automatic handoff does not bind a durable rank reader"
  if automaticBody.getUsedConstants.contains ``Eggshell.Matcher.RankMemo.read then
    throwError "Automatic handoff enumerates every unused rank record"
  let some indexed := environment.find? ``Eggshell.Plugin.indexedDiscoveryUsing |
    throwError "Missing indexed discovery"
  let some indexedBody := indexed.value? | throwError "Missing indexed discovery body"
  unless indexedBody.getUsedConstants.contains ``Eggshell.Matcher.GeometryMemo.prepareRanksFromM do
    throwError "Indexed discovery does not consume demanded durable rank advice"
  logInfo "Audited actual demanded rank lookup: pinned reader, no administrative enumeration"
  unless indexedBody.getUsedConstants.contains ``Eggshell.Matcher.GeometryMemo.prepareUsingM do
    throwError "Indexed discovery does not consume durable selection replay"
  unless indexedBody.getUsedConstants.contains ``Eggshell.Matcher.GeometryMemo.Context.groundM do
    throwError "Indexed discovery does not consume demanded durable context plans"
  unless indexedBody.getUsedConstants.contains ``Eggshell.Plugin.DiscoveryMemo.Publisher.checkpoint do
    throwError "Indexed discovery does not preserve completed calculations before terminal delivery"
  for forbidden in #[``Eggshell.Matcher.RankMemo.publish, ``Eggshell.Plugin.SaturationMemo.publish] do
    if indexedBody.getUsedConstants.contains forbidden then
      throwError "Discovery bypasses the single checkpoint publication: {forbidden}"
  for name in #[``Eggshell.Matcher.GeometryMemo.Context.groundPatternsM,
      ``Eggshell.Matcher.GeometryMemo.Context.Prepared.addM] do
    let some definition := environment.find? name | throwError "Missing context plan caller: {name}"
    let some value := definition.value? | throwError "Missing context plan implementation: {name}"
    if value.getUsedConstants.contains ``Eggshell.Matcher.RankMemo.read then
      throwError "Context plan enumerates unused durable demands: {name}"
  logInfo "Audited durable context plans in the actual discovery controller"
  let some contextObtain := environment.find? ``Eggshell.Matcher.GeometryMemo.Context.obtain |
    throwError "Missing durable context certifier"
  let some contextBody := contextObtain.value? | throwError "Missing context certifier body"
  unless contextBody.getUsedConstants.contains ``Eggshell.Matcher.ContextPlan.repair do
    throwError "Context certifier bypasses single-pass current-domain repair"
  if contextBody.getUsedConstants.contains ``Eggshell.Matcher.ContextPlan.check then
    throwError "Context certifier validates and then regenerates a changed plan"
  let some contextGround := environment.find? ``Eggshell.Matcher.GeometryMemo.Context.groundRowM |
    throwError "Missing production context grounding"
  let some contextGroundBody := contextGround.value? | throwError "Missing context grounding body"
  unless contextGroundBody.getUsedConstants.contains ``Eggshell.Matcher.GeometryMemo.Context.groundPatternsM do
    throwError "Production context grounding bypasses operation-bound repair"
  unless automaticBody.getUsedConstants.contains ``Eggshell.Plugin.demandResponse? do
    throwError "Automatic demand reuse bypasses its current nomination certificate"
  let some reuse := environment.find? ``Eggshell.Plugin.demandResponse? |
    throwError "Missing demand response validation"
  let some reuseBody := reuse.value? | throwError "Missing demand response validation body"
  unless reuseBody.getUsedConstants.contains ``Eggshell.Plugin.DemandMemo.readObserved &&
      reuseBody.getUsedConstants.contains ``Eggshell.Plugin.DemandMemo.dependenciesAgree do
    throwError "Demand response validation omits current nominations or graph dependencies"
  unless indexedBody.getUsedConstants.contains ``Eggshell.Plugin.IndexedContext.semantic do
    throwError "Observed demand reuse bypasses the current external semantic reader"
  logInfo "Audited production nomination certificate and current external observation caller"
  let some controller := environment.find? ``Eggshell.Plugin.indexedDiscovery |
    throwError "Missing single-source controller"
  let some controllerBody := controller.value? | throwError "Missing single-source controller body"
  unless controllerBody.getUsedConstants.contains ``Eggshell.Plugin.headerSemanticNominations do
    throwError "Single-source semantic reuse hydrates topology before its current observation"
  unless controllerBody.getUsedConstants.contains ``Eggshell.Persistence.Store.DemandTopology.new &&
      controllerBody.getUsedConstants.contains ``Eggshell.Persistence.Store.DemandTopology.read &&
      controllerBody.getUsedConstants.contains ``Eggshell.Persistence.Store.DemandTopology.childLookup do
    throwError "Single-source controller omits demand topology or global child authority"
  unless indexedBody.getUsedConstants.contains ``Eggshell.Plugin.IndexedContext.prepareTopology &&
      indexedBody.getUsedConstants.contains ``Eggshell.Plugin.IndexedContext.childMembership do
    throwError "Shared controller does not consume its pinned demand topology adapter"
  logInfo "Audited actual per-pass demand topology and separate global child authority"
  let some childLookup := environment.find? ``Eggshell.Persistence.Store.DemandTopology.childLookup |
    throwError "Missing pinned child-posting lookup"
  let some childBody := childLookup.value? | throwError "Missing child-posting implementation"
  for required in #[``Eggshell.Quotient.AliasIndex.prepare,
      ``Eggshell.Quotient.AliasIndex.aliases,
      ``Eggshell.Persistence.Store.literalAllChildren] do
    unless childBody.getUsedConstants.contains required do
      throwError "Completion bypasses the certified current alias index: {required}"
  for forbidden in #[``Eggshell.Persistence.Store.NodeReader.topology,
      ``Eggshell.Persistence.Store.NodeReader.readTopology,
      ``Eggshell.Persistence.Store.allHeaders] do
    if childBody.getUsedConstants.contains forbidden then
      throwError "Completion restores the whole All graph: {forbidden}"
  logInfo "Audited general structured child-role lookup without All hydration"
  let mut queue := [``Eggshell.Plugin.headerSemanticNominations]
  let mut seen : Std.HashSet Name := {}
  while let name :: remaining := queue do
    queue := remaining
    if seen.contains name then continue
    seen := seen.insert name
    for forbidden in #[``Eggshell.Persistence.Store.resolve, ``Eggshell.Persistence.Store.readNode,
        ``Eggshell.Persistence.Store.NodeReader.read, ``Eggshell.Persistence.Store.NodeReader.topology,
        ``Eggshell.Persistence.Store.NodeReader.unions, ``Eggshell.Persistence.Store.materialize] do
      if name == forbidden then throwError "Semantic preflight restores a whole Value: {name}"
    if name.toString.startsWith "Eggshell." then
      if let some declaration := environment.find? name then
        if let some body := declaration.value? then queue := body.getUsedConstants.toList ++ queue
  logInfo "Audited header-only semantic preflight before selected Value restoration"
  for root in #[``Eggshell.Matcher.SelectionReplay.check, ``Eggshell.Matcher.SelectionReplay.positions,
      ``Eggshell.Matcher.SelectionReplay.Index.extend] do
    let some definition := environment.find? root | throwError "Missing selection runtime {root}"
    let some value := definition.value? | throwError "Missing selection runtime body {root}"
    for forbidden in #[``List.append, ``List.flatMap] do
      if value.getUsedConstants.contains forbidden then
        throwError "Selection runtime rebuilds its old chosen history: {root}"
  logInfo "Audited actual selection replay: demanded IO, indexed unit membership, no copied selection history"

/- The reuse predicate must inspect the current dependency sequence before
building a replacement. Reject a return to building a signature just to
decide whether the already certified old key can be reused. -/
run_meta do
  let environment ← getEnv
  for root in #[``Eggshell.QuotientBuilder.CongruenceMemo.refsAgree,
      ``Eggshell.QuotientBuilder.CongruenceMemo.signatureAgrees] do
    let some definition := environment.find? root | throwError "Missing signature dependency checker {root}"
    let some body := definition.value? | throwError "Missing dependency checker body {root}"
    for forbidden in #[``Eggshell.QuotientBuilder.normalizeRefs,
        ``Eggshell.QuotientBuilder.signature, ``Eggshell.QuotientBuilder.CongruenceMemo.Key.make] do
      if body.getUsedConstants.contains forbidden then
        throwError "Signature hit probe reconstructs or rehashes its replacement: {root}, {forbidden}"
  for (root, required) in #[
      (``Eggshell.QuotientBuilder.CongruenceMemo.prepareRows,
        ``Eggshell.QuotientBuilder.CongruenceMemo.prepareSignature),
      (``Eggshell.QuotientBuilder.CongruenceMemo.prepareScript,
        ``Eggshell.QuotientBuilder.CongruenceMemo.Script.repairFrom),
      (``Eggshell.QuotientBuilder.CongruenceMemo.Script.repairFrom,
        ``Eggshell.QuotientBuilder.CongruenceMemo.ReplayState.next)] do
    let mut seen : Std.HashSet Name := {}
    let mut pending := [root]
    while !pending.isEmpty do
      if let name :: rest := pending then
        pending := rest
        if seen.contains name then continue
        seen := seen.insert name
        if let some definition := environment.find? name then
          if let some body := definition.value? then
            for dependency in body.getUsedConstants do
              if dependency.toString.contains "CongruenceMemo" then
                pending := dependency :: pending
    unless seen.contains required do
      throwError "Production saturation bypasses its dependency interpreter: {root}, {required}"
  logInfo "Audited current signature dependencies before replacement construction in actual saturation"

/- This module is imported by the test executable, not the product executable.
   Reject admissions and any new axiom outside Lean's standard logical basis. -/
run_meta do
  let contracts := #[
    ``Eggshell.Matcher.Match.retrieved_projection_keeps_owner,
    ``Eggshell.Matcher.retrieved_is_advisory,
    ``Eggshell.Matcher.retrieved_never_unions,
    ``Eggshell.Plugin.mem_supportFirst,
    ``Eggshell.Plugin.mem_transportOrder,
    ``Eggshell.Plugin.native_transport_keeps_support_order,
    ``Eggshell.Plugin.neighborhood_transport_has_source_path,
    ``Eggshell.Plugin.source_support_has_original_path,
    ``Eggshell.Plugin.source_support_has_no_control,
    ``Eggshell.Plugin.contextual_owner_preserves_control,
    ``Eggshell.Plugin.hook_deadline_preserves_upstream,
    ``Eggshell.Plugin.hook_deadline_never_extends_upstream,
    ``Eggshell.Plugin.coherent_entry_packet_budget_bounded,
    ``Eggshell.Plugin.coherent_entry_packet_budget_tail_independent,
    ``Eggshell.Plugin.RankedContext.join_covers,
    ``Eggshell.Plugin.coalesce_context_covers,
    ``Eggshell.Plugin.coalesce_ranked_contexts_covers,
    ``Eggshell.Plugin.expanded_context_ranges_cover_expansions,
    ``Eggshell.Plugin.core_context_ranges_covers,
    ``Eggshell.Plugin.context_ranges_keep_core_prefix,
    ``Eggshell.Plugin.adaptive_packet_budget_bounded,
    ``Eggshell.Plugin.adaptive_packet_budget_follows_demand,
    ``Eggshell.Plugin.coherent_packet_demand_covers_entries,
    ``Eggshell.Plugin.context_allowance_levels_within_demand,
    ``Eggshell.Plugin.preferred_context_level_is_existing,
    ``Eggshell.Plugin.requested_context_level_bounded,
    ``Eggshell.Plugin.nominated_support_remains_packet_entry,
    ``Eggshell.Plugin.same_family_entry_precedes_support,
    ``Eggshell.Plugin.earlier_family_support_precedes_later_entry,
    ``Eggshell.Plugin.packet_level_never_decreases,
    ``Eggshell.Plugin.packet_enrichment_never_decreases,
    ``Eggshell.Plugin.structure_context_keeps_planned_positions,
    ``Eggshell.Plugin.structured_context_keeps_core_ranges,
    ``Eggshell.Plugin.structured_context_core_prefix,
    ``Eggshell.Plugin.record_context_retains_original,
    ``Eggshell.Plugin.context_ranges_cover_expansions,
    ``Eggshell.Plugin.context_ranges_keep_nominated_position,
    ``Eggshell.Plugin.ContextSpan.ranges_cover,
    ``Eggshell.Plugin.ContextSpan.widen_covers,
    ``Eggshell.Plugin.ContextSelection.total_bounded,
    ``Eggshell.Plugin.remaining_evidence_was_planned,
    ``Eggshell.Plugin.contextual_support_has_no_control,
    ``Eggshell.Plugin.admitted_source_support_preserves_no_control,
    ``Eggshell.Plugin.native_transport_preserves_control,
    ``Eggshell.Plugin.native_transport_is_original,
    ``Eggshell.Plugin.native_discovery_nominations_empty,
    ``Eggshell.Plugin.control_delta_only_uses_checkpoints,
    ``Eggshell.Plugin.control_delta_omits_staged_native_history,
    ``Eggshell.Plugin.intrinsic_transport_unchanged,
    ``Eggshell.Plugin.source_entry_native_unchanged,
    ``Eggshell.Plugin.source_entry_was_selected,
    ``Eggshell.Plugin.source_entry_exclusion_requires_selected,
    ``Eggshell.Plugin.source_family_priority_bounded,
    ``Eggshell.Plugin.source_family_child_priority,
    ``Eggshell.Plugin.FocusedNeighborhood.original_owner,
    ``Eggshell.Plugin.source_focus_requires_original_positions,
    ``Eggshell.Plugin.primary_evidence_positions_preserved,
    ``Eggshell.Plugin.IndexedSemanticNominations.focused_identity_injective,
    ``Eggshell.Plugin.owner_source_status_within_byte_budget,
    ``Eggshell.Plugin.source_frame_fits_both,
    ``Eggshell.Plugin.source_frame_preserves_text,
    ``Eggshell.Plugin.source_entry_is_nominated,
    ``Eggshell.Plugin.empty_nomination_keeps_intrinsic,
    ``Eggshell.Plugin.nonempty_source_entries_preserved,
    ``Eggshell.Plugin.source_entry_owner_has_evidence,
    ``Eggshell.Plugin.fit_whole_slices_within_allowance,
    ``Eggshell.Plugin.bounded_whole_slices_same_selection,
    ``Eggshell.Plugin.fit_preferred_slices_within_allowance,
    ``Eggshell.Plugin.fit_dual_slices_within_allowances,
    ``Eggshell.Plugin.packet_level_keeps_owners,
    ``Eggshell.Plugin.packet_enrichment_preserves_coverage,
    ``Eggshell.Plugin.Worker.oversized_utf8_reply_is_incomplete,
    ``Eggshell.Plugin.fitting_owner_is_complete_when_it_fits,
    ``Eggshell.Plugin.identical_alternatives_preserve_whole_fitting,
    ``Eggshell.Plugin.complete_transport_evidence,
    ``Eggshell.Plugin.transport_evidence_binding_present,
    ``Eggshell.Plugin.surrounding_tool_evidence_is_original,
    ``Eggshell.Plugin.surrounding_tool_binding_is_original,
    ``Eggshell.Persistence.Store.IncidentAll.neighbor_is_original,
    ``Eggshell.Persistence.Store.IncidentAll.disconnected_rejected,
    ``Eggshell.Plugin.SourceRoute.work_has_original_path,
    ``Eggshell.SemanticMatcher.IndexedOrder.existing,
    ``Eggshell.SemanticMatcher.IndexedOrder.covers,
    ``Eggshell.Persistence.Store.ranked_support_is_original,
    ``Eggshell.Persistence.Store.WorkOwnerPosting.matches_original,
    ``Eggshell.Persistence.Store.checked_work_owner_original,
    ``Eggshell.Persistence.Store.foreign_work_owner_rejected,
    ``Eggshell.Persistence.Store.work_owner_bucket_complete,
    ``Eggshell.Persistence.Store.work_owner_retraction_exact,
    ``Eggshell.Plugin.EvidenceRange.source_exact,
    ``Eggshell.Plugin.EvidenceRange.text_bounded,
    ``Eggshell.Plugin.EvidenceRange.subtract_covers,
    ``Eggshell.Plugin.EvidenceRange.subtractAll_covers,
    ``Eggshell.Plugin.DecodedLayout.is_canonical,
    ``Eggshell.Plugin.decoded_layout_preserves_evidence,
    ``Eggshell.Plugin.decoded_tool_text_recreates_source,
    ``Eggshell.Plugin.decoded_evidence_source_exact,
    ``Eggshell.Plugin.decoded_evidence_reencodes_original,
    ``Eggshell.Plugin.decoded_evidence_occurrence_bound,
    ``Eggshell.Plugin.contextualSlice_without_positions,
    ``Eggshell.Plugin.evidenceRangeKey_ne_graphKey,
    ``Eggshell.SemanticMatcher.IndexedNomination.window_owned,
    ``Eggshell.SourceEvidence.relative_cannot_escape,
    ``Eggshell.SourceEvidence.checked_dependencies_exact,
    ``Eggshell.SourceEvidence.changed_dependency_rejected,
    ``Eggshell.SourceEvidence.incomplete_record_rejected,
    ``Eggshell.SourceEvidence.relocated_record_agreement,
    ``Eggshell.SourceEvidence.receipt_owner_bound,
    ``Eggshell.SourceEvidence.receipt_other_owner_rejected,
    ``Eggshell.SourceEvidence.authorization_has_current_dependencies,
    ``Eggshell.SourceEvidence.authorization_uses_observed_ledger,
    ``Eggshell.SourceEvidence.checked_iff_valid_dependencies,
    ``Eggshell.SourceObservation.add_bounded,
    ``Eggshell.SourceObservation.observation_bytes_bounded,
    ``Eggshell.SourceObservation.observation_certificate_bound,
    ``Eggshell.SourceObservation.pending_is_not_complete,
    ``Eggshell.SourceObservation.resumed_digest_exact,
    ``Eggshell.SourceObservation.bank_storage_bounded,
    ``Eggshell.Plugin.existing_read_certificate_retained,
    ``Eggshell.SourceObservation.changed_dependencies_are_historical,
    ``Eggshell.SourceObservation.dependent_result_requires_old_content,
    ``Eggshell.Plugin.observation_binds_new_record,
    ``Eggshell.Plugin.source_references_restore,
    ``Eggshell.Plugin.selected_source_table_restores,
    ``Eggshell.Plugin.checked_source_use_has_current_dependencies,
    ``Eggshell.Plugin.applicable_source_use_has_current_dependencies,
    ``Eggshell.Plugin.checked_owner_requires_every_dependency,
    ``Eggshell.Plugin.owner_source_status_within_budget,
    ``Eggshell.Plugin.checked_source_blocks_require_a_checkpoint,
    ``Eggshell.Plugin.selected_source_checkpoint_requires_local_completion,
    ``Eggshell.Plugin.unknown_native_source_input_rejected,
    ``Eggshell.SourceEvidence.accepted_read_plan_dependencies,
    ``Eggshell.SourceEvidence.read_plan_dependencies_nonempty,
    ``Eggshell.SourceEvidence.stream_filters_preserve_dependencies,
    ``Eggshell.SourceEvidence.combined_files_exact,
    ``Eggshell.SourceEvidence.joined_read_plan_dependencies,
    ``Eggshell.SourceEvidence.joined_read_plan_preserves_every_source,
    ``Eggshell.Persistence.Store.source_header_bound,
    ``Eggshell.Plugin.native_receipt_ignores_source,
    ``Eggshell.Plugin.operation_owner_ignores_source,
    ``Eggshell.Plugin.unverified_source_never_blocks,
    ``Eggshell.Plugin.source_block_requires_checked_dependencies,
    ``Eggshell.Plugin.source_notice_fits,
    ``Eggshell.Plugin.source_refresh_has_no_control,
    ``Eggshell.SourceObservation.unverified_emits_no_evidence,
    ``Eggshell.Plugin.unknown_source_refresh_is_silent,
    ``Eggshell.Plugin.repeated_source_refresh_is_silent,
    ``Eggshell.Plugin.unnamed_source_refresh_is_silent,
    ``Eggshell.Plugin.source_refresh_overhead_bounded,
    ``Eggshell.Plugin.replace_source_status_preserves_other_keys,
    ``Eggshell.Plugin.add_delivered_preserves_other_keys,
    ``Eggshell.QuotientBuilder.CongruenceMemo.refsAgree_exact,
    ``Eggshell.QuotientBuilder.CongruenceMemo.signatureAgrees_exact,
    ``Eggshell.QuotientBuilder.CongruenceMemo.advanceSeen_outside,
    ``Eggshell.QuotientBuilder.CongruenceMemo.ChangedKeys.advance,
    ``Eggshell.QuotientBuilder.CongruenceMemo.ChangedKeys.advance_keys,
    ``Eggshell.QuotientBuilder.CongruenceMemo.ReplayState.next,
    ``Eggshell.QuotientBuilder.CongruenceMemo.Script.repairFrom,
    ``Eggshell.Matcher.SelectionReplay.Index.empty_exact,
    ``Eggshell.Matcher.SelectionReplay.Index.extend_exact,
    ``Eggshell.Matcher.SelectionReplay.Index.conflicts_exact,
    ``Eggshell.Matcher.SelectionReplay.check_exact,
    ``Eggshell.Matcher.SelectionReplay.positions_lower,
    ``Eggshell.Matcher.SelectionReplay.positions_check,
    ``Eggshell.Matcher.SelectionReplay.obtain_exact,
    ``Eggshell.Matcher.RankMemo.select_binding,
    ``Eggshell.Matcher.GeometryMemo.prepared_provider_exact,
    ``Eggshell.Matcher.Corpus.OutcomeMemo.prepare_exact,
    ``Eggshell.Matcher.Corpus.OutcomeMemo.different_body_not_reused,
    ``Eggshell.Matcher.Corpus.OutcomeMemo.nontext_preserves_cache,
    ``Eggshell.Matcher.Corpus.OutcomeMemo.finish_exact,
    ``Eggshell.Matcher.Corpus.compileCandidatesUsing_exact,
    ``Eggshell.Persistence.Store.NodeReader.scope_exact,
    ``Eggshell.Persistence.Store.NodeReaders.at_scope,
    ``Eggshell.Persistence.Store.NodeReader.different_scope,
    ``Eggshell.TextParts.foldSplitOnAux_exact,
    ``Eggshell.TextParts.foldSplitOn_exact,
    ``Eggshell.TextParts.foldProjectionAux_exact,
    ``Eggshell.TextParts.foldProjection_exact,
    ``Eggshell.Matcher.sourcePartEnd_bounds,
    ``Eggshell.Matcher.sourcePartStep_afterEnd,
    ``Eggshell.Matcher.sourcePartSuffix_stable,
    ``Eggshell.Matcher.intersectingSourceParts_exact,
    ``Eggshell.TestOracle.sourcePartsBeforeStreaming_exact,
    ``Eggshell.TestOracle.materializeContextBeforeStreaming_exact,
    ``Eggshell.Value.foldNodes_exact,
    ``Eggshell.Value.foldRefsNodes_exact,
    ``Eggshell.Value.foldSemanticNodes_exact,
    ``Eggshell.Value.foldRefsSemanticNodes_exact,
    ``Eggshell.HashDistinct.fold_contains,
    ``Eggshell.Persistence.Store.RootReach.compile_reference,
    ``Eggshell.TestOracle.rootReachBeforeFold_exact,
    ``Eggshell.LogicalText.logicalNormalizer_list_exact,
    ``Eggshell.LogicalText.ByteSource.slice_exact,
    ``Eggshell.LogicalText.contextGramUsing_exact,
    ``Eggshell.LogicalText.grams_exact,
    ``Eggshell.LogicalText.gramsAt_width,
    ``Eggshell.LogicalText.indexGrams_lookup,
    ``Eggshell.LogicalText.gramsAt_lookup_single,
    ``Eggshell.LogicalText.contextSurfaceIndex_exact,
    ``Eggshell.LogicalText.foldPositions_exact,
    ``Eggshell.LogicalText.contextDemandIndex_exact,
    ``Eggshell.LogicalText.contextDemandIndex_unrequested,
    ``Eggshell.LogicalText.contextDemandIndex_single,
    ``Eggshell.Matcher.Pattern.canonical,
    ``Eggshell.Matcher.compile_eager_exact,
    ``Eggshell.Matcher.Corpus.finishCandidate_eager_exact,
    ``Eggshell.Matcher.Pattern.contextSurface_exact,
    ``Eggshell.Matcher.ContextEquivalent.insert,
    ``Eggshell.Matcher.ContextDirectory.filtered,
    ``Eggshell.Matcher.consumeUnitContext_exact,
    ``Eggshell.Matcher.surfaceContextCoverUnits_exact,
    ``Eggshell.Matcher.ContextPlan.check_exact,
    ``Eggshell.Matcher.ContextPlan.check_generate,
    ``Eggshell.Matcher.ContextPlan.repair_exact,
    ``Eggshell.Matcher.ContextPlan.score_generate_exact,
    ``Eggshell.Matcher.ContextPlan.decode_encode,
    ``Eggshell.Matcher.surfaceContextCoverPlan_exact,
    ``Eggshell.Matcher.GeometryMemo.Context.provider_exact,
    ``Eggshell.Matcher.GeometryMemo.Context.changed_input_rejected,
    ``Eggshell.Matcher.PreparedMatch.groundUsing_exact,
    ``Eggshell.Matcher.distinctiveAnchorCount_exact,
    ``Eggshell.Matcher.consumeContext_congr,
    ``Eggshell.Matcher.consumeContext_requested_congr,
    ``Eggshell.Matcher.Pattern.contextDemand_exact,
    ``Eggshell.Matcher.surfaceContextCover_demand_exact,
    ``Eggshell.Matcher.surfaceContextCover_exact,
    ``Eggshell.TestOracle.logicalNormalizerBeforeStreaming_exact,
    ``Eggshell.IncrementalQuotient.ViewProvider.result_exact,
    ``Eggshell.IncrementalQuotient.ViewProvider.withPlan_generation,
    ``Eggshell.IncrementalQuotient.ViewProvider.advance_generation,
    ``Eggshell.Plugin.SaturationMemo.capturePlan_bounded,
    ``Eggshell.Plugin.SaturationMemo.capturePlan_producer,
    ``Eggshell.Plugin.DiscoveryMemo.captured_producer,
    ``Eggshell.Plugin.DiscoveryMemo.captured_bounded,
    ``Eggshell.Plugin.DiscoveryMemo.captured_restore_exact,
    ``Eggshell.Plugin.SaturationMemo.viewProvider_generation,
    ``Eggshell.Relation.semanticValues_map,
    ``Eggshell.Relation.exactValues_map,
    ``Eggshell.Relation.splitOccurrence_map,
    ``Eggshell.Persistence.Store.NodeFrame.nativeResolved_exact,
    ``Eggshell.Matcher.Corpus.compiled_work_view,
    ``Eggshell.Matcher.Corpus.compiled_work_view_candidate,
    ``Eggshell.Matcher.Corpus.workScoringTerms_exact,
    ``Eggshell.Matcher.Corpus.workTerms_has_unit,
    ``Eggshell.Matcher.Corpus.weightedUnits_congr,
    ``Eggshell.Matcher.Corpus.informationWeights_congr,
    ``Eggshell.Matcher.WorkView.pair_patterns,
    ``Eggshell.Matcher.WorkView.alignments_weights_congr,
    ``Eggshell.Matcher.PreparedMatch.ground_exact,
    ``Eggshell.Matcher.reusedContextPattern_same,
    ``Eggshell.Matcher.reusedContextPattern_exact,
    ``Eggshell.Matcher.prepareInUsing_exact,
    ``Eggshell.Matcher.prepareInUsing_frequency_congr,
    ``Eggshell.Matcher.contextTerms_has_unit,
    ``Eggshell.Matcher.contextTerms_exact,
    ``Eggshell.Matcher.groundContextPatterns_weights_congr,
    ``Eggshell.Matcher.groundPrepared_frequency_congr,
    ``Eggshell.Matcher.prepareAndGround_exact,
    ``Eggshell.Plugin.extendDemandFrequencies_preserves,
    ``Eggshell.Matcher.GeometryMemo.inputsWork_exact,
    ``Eggshell.Matcher.Corpus.compileCandidate_phases,
    ``Eggshell.Matcher.Corpus.compileWorkCandidate_owner,
    ``Eggshell.Matcher.Corpus.finishCandidate_compiled,
    ``Eggshell.Matcher.Candidate.workAlignments_outcome_independent,
    ``Eggshell.Matcher.Candidate.findMatches_no_work,
    ``Eggshell.Matcher.Candidate.finish_no_work,
    ``Eggshell.Matcher.findInUsing_work_projection_exact,
    ``Eggshell.TestOracle.findInUsingBeforeWorkGate_exact,
    ``Eggshell.SearchRank.rankRows_map,
    ``Eggshell.SearchRank.document_frequency_append,
    ``Eggshell.SearchRank.windows_exact,
    ``Eggshell.SearchRank.locatedWindows_exact,
    ``Eggshell.Persistence.Store.window_codec_roundtrip,
    ``Eggshell.Persistence.Store.span_codec_roundtrip,
    ``Eggshell.Persistence.Store.SourceWindow.source_exact,
    ``Eggshell.Persistence.Store.WindowRange.extraction_bounded,
    ``Eggshell.Persistence.Store.WindowRange.chunks_bounded,
    ``Eggshell.SearchProvider.CheckedVector.source_shape,
    ``Eggshell.FileSystem.ReadSize.native_bound,
    ``Eggshell.SemanticMatcher.candidate_text_source,
    ``Eggshell.SemanticMatcher.WindowPull.handles_exact,
    ``Eggshell.SemanticMatcher.WindowPull.handles_bounded,
    ``Eggshell.SemanticMatcher.documentOwners_owned,
    ``Eggshell.Persistence.Store.BodyChunk.bounded,
    ``Eggshell.Persistence.Store.ReferencePairs.positions,
    ``Eggshell.Persistence.Store.ReferencePairs.unequal_arity,
    ``Eggshell.Persistence.Store.ReferencePairs.resolved,
    ``Eggshell.Persistence.Store.ReferencePairs.application_exact,
    ``Eggshell.Value.semanticNodes_subset_nodes,
    ``Eggshell.Persistence.SelectionKey.spelling_exact,
    ``Eggshell.Persistence.Store.RootReach.compile_nodes,
    ``Eggshell.Persistence.Store.RootReach.compile_unique,
    ``Eggshell.Persistence.Store.RootReach.compile_member,
    ``Eggshell.Persistence.Store.RootReach.compile_role,
    ``Eggshell.Persistence.Store.RootReach.compile_semantic_complete,
    ``Eggshell.Persistence.Store.RootReach.codec_roundtrip,
    ``Eggshell.Persistence.Store.RootReach.check_exact,
    ``Eggshell.Persistence.Store.NodeMembership.retract_add,
    ``Eggshell.Plugin.manualHandoffForRoots_advisory,
    ``Eggshell.Persistence.Store.Federated.PostingSet.raw_add,
    ``Eggshell.Persistence.Store.Federated.PostingSet.complete_stream,
    ``Eggshell.Persistence.Store.Federated.PostingSet.membership,
    ``Eggshell.Persistence.Store.Federated.ApplicationKey.denote_injective,
    ``Eggshell.Persistence.Store.Federated.ApplicationKey.rebind_exact,
    ``Eggshell.Persistence.Store.Federated.ApplicationKey.equality_exact,
    ``Eggshell.Persistence.Store.Federated.ReboundApplication.resolved,
    ``Eggshell.Persistence.Store.Federated.ReboundApplication.parent_bound,
    ``Eggshell.SearchProvider.WindowBatch.make,
    ``Eggshell.SearchProvider.WindowBatch.existing,
    ``Eggshell.QuotientBuilder.AtomQuotient.Index.append_partition,
    ``Eggshell.QuotientBuilder.AtomQuotient.independent,
    ``Eggshell.QuotientBuilder.AtomQuotient.Index.aliases_are_atoms,
    ``Eggshell.Quotient.AliasBuckets.collect_membership,
    ``Eggshell.Quotient.AliasIndex.aliases_exact,
    ``Eggshell.Quotient.AliasIndex.child_role_exact,
    ``Eggshell.QuotientBuilder.AtomQuotient.prepare_mixed_rejected,
    ``Eggshell.QuotientBuilder.AtomQuotient.Index.append_no_replay,
    ``Eggshell.QuotientBuilder.AtomQuotient.Index.beginRun_partition,
    ``Eggshell.IncrementalQuotient.make_agrees,
    ``Eggshell.Equivalent.without_edges,
    ``Eggshell.QuotientBuilder.CongruenceSound.merge_sound,
    ``Eggshell.QuotientBuilder.CongruenceSound.explicit_sound,
    ``Eggshell.QuotientBuilder.CongruenceSound.signature_sound,
    ``Eggshell.QuotientBuilder.CongruenceSound.saturation_sound,
    ``Eggshell.QuotientBuilder.CongruenceSound.certified_sound,
    ``Eggshell.QuotientBuilder.CongruenceSound.build_sound,
    ``Eggshell.QuotientBuilder.CongruenceFixed.take_perm,
    ``Eggshell.QuotientBuilder.CongruenceFixed.merge_progress,
    ``Eggshell.QuotientBuilder.CongruenceFixed.pass_progress,
    ``Eggshell.QuotientBuilder.CongruenceFixed.saturation_fixed,
    ``Eggshell.QuotientBuilder.CongruenceFixed.kernel_fixed,
    ``Eggshell.QuotientBuilder.CongruenceComplete.pass_closed,
    ``Eggshell.QuotientBuilder.CongruenceComplete.kernel_domain,
    ``Eggshell.QuotientBuilder.CongruenceComplete.kernel_connected,
    ``Eggshell.QuotientBuilder.CongruenceComplete.kernel_semantic_closed,
    ``Eggshell.QuotientBuilder.CongruenceComplete.evaluate_equivalent,
    ``Eggshell.QuotientBuilder.CongruenceComplete.kernel_complete,
    ``Eggshell.QuotientBuilder.CongruenceComplete.outside_atom_literal,
    ``Eggshell.QuotientBuilder.CongruenceComplete.build_complete,
    ``Eggshell.QuotientBuilder.CongruenceComplete.build_complete_atoms,
    ``Eggshell.QuotientBuilder.CongruenceComplete.kernel_root,
    ``Eggshell.QuotientBuilder.CongruenceSound.attach_exact,
    ``Eggshell.QuotientBuilder.CongruenceSound.Checked.ungenerated_rejected,
    ``Eggshell.QuotientBuilder.CongruenceSound.Checked.without_edges,
    ``Eggshell.QuotientBuilder.CongruenceSound.Checked.domain_independent,
    ``Eggshell.QuotientBuilder.CongruenceSound.Checked.atoms_independent,
    ``Eggshell.IncrementalQuotient.generatedView_exact,
    ``Eggshell.IncrementalQuotient.generatedView_complete,
    ``Eggshell.IncrementalQuotient.make_generated,
    ``Eggshell.IncrementalQuotient.ViewProvider.generated,
    ``Eggshell.IncrementalQuotient.ViewProvider.complete,
    ``Eggshell.IncrementalQuotient.ViewProvider.domain_independent,
    ``Eggshell.Plugin.SaturationMemo.viewProvider_generated,
    ``Eggshell.Plugin.SaturationMemo.viewProvider_domain_independent,
    ``Eggshell.Plugin.quotientWorkRoots_contains_work,
    ``Eggshell.IncrementalQuotient.make_extraction,
    ``Eggshell.QuotientBuilder.CongruenceMemo.Key.ext,
    ``Eggshell.QuotientBuilder.CongruenceMemo.Prepared.canonical,
    ``Eggshell.QuotientBuilder.CongruenceMemo.pass_exact,
    ``Eggshell.QuotientBuilder.CongruenceMemo.Script.repair,
    ``Eggshell.QuotientBuilder.CongruenceMemo.Script.wrong_instructions_rejected,
    ``Eggshell.QuotientBuilder.CongruenceMemo.apply_compiled,
    ``Eggshell.QuotientBuilder.plannedSaturateCongruence_exact,
    ``Eggshell.QuotientBuilder.plannedBuild_exact,
    ``Eggshell.IncrementalQuotient.ViewProvider.observed_exact,
    ``Eggshell.Matcher.discoverUsingM_views_exact,
    ``Eggshell.Matcher.discoverInUsing_views_exact,
    ``Eggshell.Plugin.SaturationMemo.codec_roundtrip,
    ``Eggshell.Plugin.SaturationMemo.restored_build_exact,
    ``Eggshell.QuotientBuilder.memoSaturateCongruence_exact,
    ``Eggshell.QuotientBuilder.saturateCongruence_reference,
    ``Eggshell.DB.PageMap.page_codec_roundtrip,
    ``Eggshell.DB.PageMap.PageCache.touch_bounded,
    ``Eggshell.DB.PageMap.PageCache.touch_recent,
    ``Eggshell.DB.PageMap.head_codec_roundtrip,
    ``Eggshell.DB.PageMap.blob_codec_roundtrip,
    ``Eggshell.DB.PageMap.blob_bytes_preserved_by_append,
    ``Eggshell.DB.PageMap.blob_bytes_preserved_by_recovery,
    ``Eggshell.DB.PageMap.foreign_read_identity_rejected,
    ``Eggshell.DB.PageMap.checkPayloadChunks_full_domain,
    ``Eggshell.DB.PageMap.checkPrefixLoop_exact,
    ``Eggshell.DB.PageMap.checkPrefix_exact,
    ``Eggshell.DB.PageMap.PayloadPrefix.outside_rejected,
    ``Eggshell.DB.PageMap.HistoryReader.retains_exact_reference,
    ``Eggshell.DB.PageMap.read_observation_roundtrip,
    ``Eggshell.DB.PageMap.changed_observation_rejected,
    ``Eggshell.DB.PageMap.ReadTrace.add_bounded,
    ``Eggshell.DB.PageMap.ObservationIndex.contains_exact,
    ``Eggshell.DB.PageMap.ReadTrace.add_exact,
    ``Eggshell.DB.PageMap.ReadTrace.fold_exact,
    ``Eggshell.DB.PageMap.ReadTrace.incomplete_stays_incomplete,
    ``Eggshell.DB.PageMap.RangeProgress.unexpected_rejected,
    ``Eggshell.Persistence.Store.change_codec_roundtrip,
    ``Eggshell.Persistence.Store.publication_codec_roundtrip,
    ``Eggshell.Persistence.Store.NodeFrame.check_exact,
    ``Eggshell.Persistence.Store.NodeFrame.forward_rejected,
    ``Eggshell.Persistence.Store.payloadSize_missing_rejected,
    ``Eggshell.Persistence.Store.payloadSize_encoded,
    ``Eggshell.Persistence.Store.exactIds_sound,
    ``Eggshell.Persistence.Store.semanticIds_sound,
    ``Eggshell.Persistence.Store.AllHeader.parent_before,
    ``Eggshell.Persistence.Store.AllHeader.child_before,
    ``Eggshell.Persistence.Store.AllHeader.interpret_parent,
    ``Eggshell.Persistence.Store.AllHeader.interpret_children,
    ``Eggshell.Persistence.Store.AllHeader.interpret_frame,
    ``Eggshell.Persistence.Store.LocatedAll.foreign_head_rejected,
    ``Eggshell.Plugin.semantic_child_membership,
    ``Eggshell.Plugin.topology_demand_keeps_references,
    ``Eggshell.Plugin.membership_demand_covers_staged,
    ``Eggshell.Persistence.Store.OutcomeHeader.work_before,
    ``Eggshell.Persistence.Store.OutcomeHeader.outcome_before,
    ``Eggshell.Persistence.Store.OutcomeHeader.observation_before,
    ``Eggshell.Persistence.Store.LocatedOutcome.foreign_head_rejected,
    ``Eggshell.Persistence.Store.Change.neutral_exact,
    ``Eggshell.DB.PageMap.derivedStep_false,
    ``Eggshell.DB.PageMap.derived_trace_exact,
    ``Eggshell.DB.PageMap.derived_rows_preserve,
    ``Eggshell.DB.PageMap.derived_trace_preserve,
    ``Eggshell.Persistence.Store.Change.authoritative_neutral_rejected,
    ``Eggshell.Persistence.Store.CheckedChange.neutral_derived,
    ``Eggshell.Plugin.DemandMemo.codec_roundtrip,
    ``Eggshell.Plugin.DemandMemo.neutral_replay,
    ``Eggshell.Plugin.DemandMemo.NeutralChain.preserves,
    ``Eggshell.Plugin.DemandMemo.changed_request_rejected,
    ``Eggshell.Plugin.DemandMemo.changed_nominations_rejected,
    ``Eggshell.Plugin.DemandMemo.observed_record_has_current_nominations,
    ``Eggshell.Plugin.DemandMemo.metadata_reader_uses_pinned_file,
    ``Eggshell.Plugin.DemandMemo.metadata_reader_counts_actual_io,
    ``Eggshell.Plugin.demand_cache_requires_persisted_evidence,
    ``Eggshell.Persistence.Store.term_payload_roundtrip,
    ``Eggshell.Persistence.Store.different_term_rejected,
    ``Eggshell.Persistence.Store.reviseValues_retired,
    ``Eggshell.Persistence.Store.reviseValues_new,
    ``Eggshell.Persistence.Store.union_pair_key_symmetric,
    ``Eggshell.Persistence.Store.LocatedUnion.foreign_head_rejected,
    ``Eggshell.Graph.removeUnionPair_membership,
    ``Eggshell.Graph.removeUnionPair_retired,
    ``Eggshell.DB.PageMap.merge_lookup,
    ``Eggshell.DB.PageMap.Lookup.pages_bounded,
    ``Eggshell.DB.PageMap.KeyRange.select_exact,
    ``Eggshell.DB.PageMap.leaf_bounds,
    ``Eggshell.DB.PageMap.KeyRange.prune_exact,
    ``Eggshell.DB.PageMap.KeyRange.prunedRows_exact,
    ``Eggshell.Persistence.Store.Chunk.payload_bounded,
    ``Eggshell.Persistence.Store.Chunk.adjacent_exact,
    ``Eggshell.Persistence.Store.different_chunk_rejected,
    ``Eggshell.DB.PageMap.pairwise_of_ordered,
    ``Eggshell.FileSystem.publication_agreement_exact,
    ``Eggshell.Matcher.Corpus.stored_owner_terms_exact,
    ``Eggshell.Matcher.Corpus.compileCandidate_nontext,
    ``Eggshell.Matcher.Corpus.compileCandidate_owner,
    ``Eggshell.Matcher.Corpus.compileCandidate_atom_work,
    ``Eggshell.Matcher.Corpus.compileCandidates_textual,
    ``Eggshell.Matcher.Corpus.build_textual_projection,
    ``Eggshell.Matcher.findIn_textual_projection,
    ``Eggshell.Plugin.IndexedOwners.candidates_exact,
    ``Eggshell.Plugin.IndexedOwners.atom_outcomes,
    ``Eggshell.Plugin.SaturationMemo.viewProvider_exact,
    ``Eggshell.Plugin.SingleSource.table_exact,
    ``Eggshell.Plugin.SingleSource.only_present,
    ``Eggshell.Plugin.SingleSource.two_rejected,
    ``Eggshell.Plugin.indexed_saturation_memo_exact,
    ``Eggshell.Matcher.Corpus.stored_work_surfaces_exact,
    ``Eggshell.Matcher.sharesSurface_keys,
    ``Eggshell.Matcher.stored_work_surface_admission,
    ``Eggshell.Matcher.findIn_no_surface_admissions,
    ``Eggshell.Plugin.renderAutomatic_empty_terminal,
    ``Eggshell.Persistence.Store.AllParentPosting.matches_exact,
    ``Eggshell.Persistence.Store.AllHeader.child_membership_exact,
    ``Eggshell.Matcher.Candidate.prepareWork_subworks_exact,
    ``Eggshell.Matcher.selected_admissions_exact,
    ``Eggshell.Matcher.findInUsing_selected_exact,
    ``Eggshell.Matcher.findInUsing_no_admissions,
    ``Eggshell.Extract.runWithPolicy_unadmitted_root,
    ``Eggshell.Selection.validFor_selected,
    ``Eggshell.Extract.runWithPolicy_terminal_exact,
    ``Eggshell.Extract.runWithPolicy_terminal_all_irrelevant,
    ``Eggshell.Extract.runWithPolicy_terminal_selected,
    ``Eggshell.Extract.classified_selected,
    ``Eggshell.Extract.solve_selected,
    ``Eggshell.Extract.runWithPolicyFuel_selected,
    ``Eggshell.Extract.runWithPolicyFuel_sound,
    ``Eggshell.Matcher.extraction_sound,
    ``Eggshell.Matcher.TerminalRoot.changed_union_rejected,
    ``Eggshell.Matcher.TerminalRoot.changed_projection_rejected,
    ``Eggshell.Matcher.TerminalRoot.changed_demand_rejected,
    ``Eggshell.Matcher.TerminalRoot.discovery_exact,
    ``Eggshell.Plugin.renderAutomatic_no_hits,
    ``Eggshell.TestOracle.CorpusCache.prepare_exact,
    ``Eggshell.Matcher.Corpus.full_frequencies_exact,
    ``Eggshell.Matcher.Corpus.appendCandidates_exact,
    ``Eggshell.Matcher.Corpus.ownerRows_count,
    ``Eggshell.Frequency.Index.replace,
    ``Eggshell.Frequency.affectedRegion,
    ``Eggshell.Frequency.change_no_zeros,
    ``Eggshell.TestOracle.SearchMemo.get_exact,
    ``Eggshell.TestOracle.SearchMemo.getUsing_exact,
    ``Eggshell.TestOracle.CachedWorkspace.reuse_exact,
    ``Eggshell.Matcher.GeometryMemo.provider_exact,
    ``Eggshell.Matcher.GeometryMemo.prepareRanksFrom_bounded,
    ``Eggshell.Matcher.pairedCoveragesUsing_exact,
    ``Eggshell.Matcher.RankMemo.provider_exact,
    ``Eggshell.Matcher.RankMemo.codec_roundtrip,
    ``Eggshell.Matcher.EvidenceReplay.certify_exact,
    ``Eggshell.Matcher.EvidenceReplay.runs_flatten,
    ``Eggshell.Matcher.EvidenceReplay.mergePairs_perm,
    ``Eggshell.Matcher.EvidenceReplay.mergeRuns_perm,
    ``Eggshell.Matcher.EvidenceReplay.replay_nodup,
    ``Eggshell.Matcher.EvidenceReplay.Keyed.order_exact,
    ``Eggshell.Matcher.SurfaceJoin.Group.lookup_exact,
    ``Eggshell.Matcher.SurfaceJoin.Directory.lookup_exact,
    ``Eggshell.Matcher.demandProvider_exact,
    ``Eggshell.Matcher.GeometryMemo.changed_input_rejected,
    ``Eggshell.TestOracle.SearchMemo.evaluateUsing_exact,
    ``Eggshell.TestOracle.SearchMemo.changed_input_rejected,
    ``Eggshell.LogicalText.indexedUnitSpan_exact,
    ``Eggshell.LogicalText.grams_exact,
    ``Eggshell.SemanticMatcher.eligible_iff_readable_owner,
    ``Eggshell.SemanticMatcher.readable_owner_remains_eligible,
    ``Eggshell.SemanticMatcher.nomination_has_corpus_owner,
    ``Eggshell.SemanticMatcher.index_receipt_matches_batch,
    ``Eggshell.SemanticMatcher.mismatched_index_acknowledgement_rejected,
    ``Eggshell.Plugin.committed_index_owner_present,
    ``Eggshell.Plugin.committedPromotion?_identity,
    ``Eggshell.Plugin.index_ticket_root_is_published,
    ``Eggshell.Plugin.pending_search_has_no_authority,
    ``Eggshell.Plugin.terminal_order_preserves_answer,
    ``Eggshell.Plugin.terminal_seal_preserves_observations,
    ``Eggshell.Plugin.terminal_close_never_reopens,
    ``Eggshell.Plugin.Worker.expired_window_cannot_start,
    ``Eggshell.Plugin.Worker.busy_open_gate_retries,
    ``Eggshell.Plugin.Worker.completed_empty_gate_is_finished,
    ``Eggshell.Plugin.Worker.read_admission_is_live,
    ``Eggshell.Plugin.Worker.read_admission_is_bounded,
    ``Eggshell.Plugin.Worker.stale_waiter_cannot_start,
    ``Eggshell.Plugin.Worker.changed_waiter_context_cannot_start,
    ``Eggshell.Plugin.Worker.incomplete_delivery_has_no_authority,
    ``Eggshell.Plugin.Worker.stale_search_reply_is_discarded,
    ``Eggshell.Plugin.Worker.old_context_reply_is_discarded,
    ``Eggshell.Plugin.Worker.expired_search_reply_is_incomplete,
    ``Eggshell.Plugin.Worker.missing_search_reply_is_incomplete,
    ``Eggshell.Plugin.Daemon.valid_hook_reply_is_preserved,
    ``Eggshell.Plugin.Daemon.absent_hook_reply_is_incomplete,
    ``Eggshell.Plugin.Daemon.invalid_hook_reply_is_incomplete,
    ``Eggshell.SearchRank.deduplicated_nodup,
    ``Eggshell.SearchRank.terms_nodup,
    ``Eggshell.SearchRank.document_count_exact,
    ``Eggshell.SearchRank.Corpus.rank_exact,
    ``Eggshell.SearchRank.lexical_exact,
    ``Eggshell.SearchProvider.oversized_corpus_not_retained,
    ``Eggshell.SearchRank.selected_no_duplicates,
    ``Eggshell.SearchRank.selected_within_budget,
    ``Eggshell.SearchRank.selected_is_existing,
    ``Eggshell.SearchRank.selected_was_ranked,
    ``Eggshell.SearchRank.zero_budget_is_empty,
    ``Eggshell.Plugin.ranked_evidence_choice_is_original,
    ``Eggshell.Setup.configured_is_preserved,
    ``Eggshell.Setup.check_never_initializes,
    ``Eggshell.Setup.initialize_only_when_missing,
    ``Eggshell.SearchProvider.accepted_cache_identity,
    ``Eggshell.SearchProvider.changed_cache_text_rejected,
    ``Eggshell.SearchProvider.changed_cache_model_rejected]
  for contract in contracts do
    let axioms ← Lean.collectAxioms contract
    for dependency in axioms do
      unless #[``propext, ``Quot.sound, ``Classical.choice].contains dependency do
        throwError "{contract} depends on unapproved axiom {dependency}"
    logInfo m!"Audited {contract}: {axioms}"
