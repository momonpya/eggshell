module

public import Eggshell.Handoff
public import tests.SearchMemo

@[expose] public section

/- Full-source reference engine and its diagnostic caches. This module is
compiled only into test targets; normal hooks cannot access this oracle. -/
namespace Eggshell.TestOracle

/-- Frozen result-line projection before streaming. Kept independent of the
new splitter so complete handoff comparisons exercise the original bytes. -/
def sourcePartsBeforeStreaming (spans : List LogicalText.ByteSpan) (separator source : String) :
    List String :=
  let (_, selected) := source.splitOn separator |>.foldl
    (init := (0, [])) fun (offset, selected) line =>
      let stop := offset + line.toUTF8.size
      let intersects := spans.any fun span => span.start < stop && offset < span.stop
      (stop + separator.toUTF8.size, if intersects then selected ++ [line] else selected)
  selected

theorem sourcePartsBeforeStreaming_exact (spans : List LogicalText.ByteSpan)
    (separator source : String) :
    sourcePartsBeforeStreaming spans separator source =
      Matcher.intersectingSourceParts spans separator source :=
  (Matcher.intersectingSourceParts_exact spans separator source).symm

def materializeContextBeforeStreaming (source : LogicalText.T)
    (spans : List LogicalText.ByteSpan) (native : Bool) : Option Value := do
  if !native then none
  let sourceSpans ← LogicalText.sourceSpans? source spans
  let separator := if source.original.contains "\\n" then "\\n" else "\n"
  let selected := sourcePartsBeforeStreaming sourceSpans separator source.original
  let fragment := "\n".intercalate selected
  if fragment.trimAscii.isEmpty then none else pure (.text fragment)

theorem materializeContextBeforeStreaming_exact (source : LogicalText.T)
    (spans : List LogicalText.ByteSpan) (native : Bool) :
    materializeContextBeforeStreaming source spans native =
      Matcher.materializeContext source spans native := by
  simp only [materializeContextBeforeStreaming, Matcher.materializeContext,
    sourcePartsBeforeStreaming_exact]

/-- Frozen save-time reverse-index compiler before direct Value traversal. -/
def rootReachBeforeFold (root : Value) : List (Value × Bool) :=
  let semantic := Std.HashSet.ofList root.semanticNodes
  (hashDistinct root.nodes).map fun node => (node, semantic.contains node)

theorem rootReachBeforeFold_exact (root : Value) :
    Persistence.Store.RootReach.compile root = rootReachBeforeFold root :=
  Persistence.Store.RootReach.compile_reference root
open Plugin Lean

/-- Frozen character-list normalizer, before direct UTF-8 iteration. Kept in
the independent test executable, never reachable from normal save/search. -/
def logicalNormalizerBeforeStreaming : LogicalText.Normalizer := fun text => Id.run do
  let mut pieces : Array LogicalText.Piece := #[]
  let mut word := ""
  let mut wordStart := 0
  let mut wordBytes := 0
  let mut offset := 0
  for character in text.toList do
    let original := String.singleton character
    let bytes := original.toUTF8.size
    if LogicalText.asciiCompoundCharacter character then
      if word.isEmpty then wordStart := offset
      word := word ++ original.toLower
      wordBytes := wordBytes + bytes
    else
      if !word.isEmpty then
        pieces := pieces.push {
          text := LogicalText.canonicalAsciiCompound word
          source := { start := wordStart, stop := wordStart + wordBytes }
        }
        word := ""
        wordBytes := 0
      pieces := pieces.push {
        text := if character.val < 128 || character.isWhitespace then " "
          else original.toLower
        source := { start := offset, stop := offset + bytes }
      }
    offset := offset + bytes
  if !word.isEmpty then
    pieces := pieces.push {
      text := LogicalText.canonicalAsciiCompound word
      source := { start := wordStart, stop := wordStart + wordBytes }
    }
  return pieces.toList

theorem logicalNormalizerBeforeStreaming_exact (text : String) :
    LogicalText.logicalNormalizer text = logicalNormalizerBeforeStreaming text := by
  rw [LogicalText.logicalNormalizer_list_exact]
  rfl

structure FileStamp where
  path : String
  head : Option DB.PageMap.Head
  deriving BEq

structure CachedComposite where
  stamps : List FileStamp
  graphs : List (Option Graph)
  composite : Persistence.Composite

structure CachedWorkspace where
  stamps : List FileStamp
  composite : Persistence.Composite
  graph : WorkGraph
  graphExact : graph = WorkGraph.fromValues composite.values
  prepared : TestOracle.CorpusCache.Prepared LogicalText.logicalNormalizer graph

/-- Physical pages may change without changing any semantic dependency.
The complete composite comparison includes negative candidate membership,
root order, topology, Union authority and origins, rather than selected hits.
Retagging cannot carry a compiled corpus onto a different current graph. -/
def CachedWorkspace.reuse (cached : CachedWorkspace) (stamps : List FileStamp)
    (composite : Persistence.Composite) (same : cached.composite = composite) : CachedWorkspace := {
  stamps, composite, graph := cached.graph
  graphExact := by rw [← same]; exact cached.graphExact
  prepared := { cached.prepared with freshCompiles := 0, frequencyTouches := 0 }
}

theorem CachedWorkspace.reuse_exact (cached : CachedWorkspace) (stamps : List FileStamp)
    (composite : Persistence.Composite) (same : cached.composite = composite) :
    (cached.reuse stamps composite same).prepared.corpus =
      Matcher.Corpus.build LogicalText.logicalNormalizer (WorkGraph.fromValues composite.values) := by
  change cached.prepared.corpus = _
  rw [cached.prepared.exact, cached.graphExact, same]

structure RuntimeCache where
  composites : List CachedComposite := []
  workspaces : List CachedWorkspace := []
  query : SearchMemo.Cache := none
  deriving Inhabited

initialize runtimeCache : IO.Ref RuntimeCache ← IO.mkRef {}

def fileStamp (path : System.FilePath) : IO FileStamp := do
  let snapshot ← DB.PageMap.open? path
  pure { path := path.normalize.toString, head := snapshot.map (·.head) }

/-- Open all head capabilities once. Loading uses exactly those pinned
extents; a concurrent head publication cannot mix pages into this request. -/
def composeGraphs (graphs : List Graph) : Persistence.Composite :=
  {
    values := graphs.flatMap (·.values) |>.eraseDups
    unions := graphs.flatMap fun graph => graph.unions.map (·.edge)
    authorities := graphs.map (·.authority)
    origins := graphs.flatMap fun graph => graph.values.map (fun value => (value, graph.authority))
    unionOrigins := graphs.flatMap fun graph => graph.unions.map (fun persistent =>
      (persistent.edge, graph.authority)) }

def pinnedComposite (snapshots : List (Option Persistence.Store.Snapshot)) :
    IO Persistence.Composite := do
  pure (composeGraphs (← snapshots.filterMap id |>.mapM Persistence.Store.materialize))

def cachedCompositeAt (paths : List System.FilePath)
    (snapshots : List (Option Persistence.Store.Snapshot)) :
    IO (List FileStamp × Persistence.Composite) := do
  unless paths.length == snapshots.length do throw (IO.userError "source snapshot arity mismatch")
  let stamps := paths.zip snapshots |>.map fun (path, snapshot) =>
    { path := path.normalize.toString, head := snapshot.map (·.head) : FileStamp }
  let cache ← runtimeCache.get
  match cache.composites.find? (fun cached => cached.stamps == stamps) with
  | some cached => pure (stamps, cached.composite)
  | none =>
      let previous := cache.composites.find? fun cached =>
        cached.stamps.map (·.path) == stamps.map (·.path)
      let graphs ← snapshots.zipIdx |>.mapM fun (snapshot, index) =>
        match snapshot with
        | none => pure none
        | some snapshot =>
          match previous.bind (fun cached => cached.stamps[index]?.bind (·.head)),
              previous.bind (fun cached => cached.graphs[index]?.bind id) with
          | some head, some graph =>
              if head.identity == snapshot.head.identity && head.revision ≤ snapshot.head.revision then
                some <$> Persistence.Store.revise snapshot head graph
              else some <$> Persistence.Store.materialize snapshot
          | _, _ => some <$> Persistence.Store.materialize snapshot
      let composite := composeGraphs (graphs.filterMap id)
      let current ← runtimeCache.get
      runtimeCache.set { current with composites := [{ stamps, graphs, composite }] }
      pure (stamps, composite)

def cachedCompositePinned (paths : List System.FilePath) :
    IO (List FileStamp × Persistence.Composite) := do
  cachedCompositeAt paths (← paths.mapM DB.PageMap.open?)

def cachedComposite (paths : List System.FilePath) : IO Persistence.Composite :=
  Prod.snd <$> cachedCompositePinned paths

def cachedWorkspaceAt (selection : Config.Selection)
    (snapshots : List (Option Persistence.Store.Snapshot)) : IO CachedWorkspace := do
  let eggPaths := selection.read.map (·.path)
  let (stamps, composite) ← cachedCompositeAt eggPaths snapshots
  let cache ← runtimeCache.get
  let previous := cache.workspaces.find? fun cached =>
    cached.stamps.map (·.path) == stamps.map (·.path)
  if let some previous := previous then
    if same : previous.composite = composite then
      let cached := previous.reuse stamps composite same
      runtimeCache.set { cache with workspaces :=
        cached :: cache.workspaces.filter (fun other =>
          other.stamps.map (·.path) != stamps.map (·.path)) |>.take 4 }
      return cached
  let graph := WorkGraph.fromValues composite.values
  let index := previous.map (·.prepared.index) |>.getD {}
  let prepared := TestOracle.CorpusCache.prepare LogicalText.logicalNormalizer index graph
  let cached : CachedWorkspace := { stamps, composite, graph, graphExact := rfl, prepared }
  let current ← runtimeCache.get
  runtimeCache.set { current with workspaces :=
    cached :: current.workspaces.filter (fun previous =>
      previous.stamps.map (·.path) != stamps.map (·.path)) |>.take 4 }
  pure cached

def cachedWorkspace (selection : Config.Selection) : IO CachedWorkspace := do
  cachedWorkspaceAt selection (← (selection.read.map (·.path)).mapM DB.PageMap.open?)

/-- An independent whole-frontier closure is intentionally slower than the
production queue. Each discovered owner nevertheless carries a real path. -/
def referenceSourceClosure (roots : List Value) (all : List AllEdge) (unions : List UnionEdge) :
    List (ReachedSource roots all unions) :=
  let initial := roots.attach.map fun ⟨work, present⟩ =>
    (⟨work, SourceRoute.root work present⟩ : ReachedSource roots all unions)
  let rec close : Nat → List (ReachedSource roots all unions) → List (ReachedSource roots all unions)
    | 0, known => known
    | fuel + 1, known =>
        let next := known.foldl (fun reached first =>
          (sourceNeighbors all unions first.work).foldl (fun reached neighbor =>
            if reached.any (fun row => row.work == neighbor.work) then reached else
              reached ++ [⟨neighbor.work, SourceRoute.step first.work neighbor.work
                first.route neighbor.link⟩]) reached) known
        if next.length == known.length then known else close fuel next
  close (roots.length + (all.flatMap (fun edge => edge.parent :: edge.children)).length +
    unions.length * 2 + 1) initial

/-- The reference computes reachability by scanning the full original graph,
then projects the saved frames. It does not use the production queue, posting
indexes or demanded reader. Matching/discovery still use the full corpus. -/
def referenceSourceAll (all : List AllEdge) (unions : List UnionEdge)
    (requested : List Value) (single : Bool) : List AllEdge :=
  if !single then all else
  let reached := (referenceSourceClosure requested all unions).map (·.work)
  all.filter fun edge => reached.contains edge.parent || edge.children.any reached.contains

def referenceSourceRecords (values : List Value) (owner : Value) : List SourceEvidence.Record :=
  let records := values.filterMap (SourceEvidence.receiptRecord? owner) |>.eraseDups
  if records.isEmpty then [SourceEvidence.unverified] else records

def computeGeneralAutomaticHandoff (selection : Config.Selection)
    (snapshots : List (Option Persistence.Store.Snapshot)) (current : String)
    (deliveredGraphs : List String) (enforce : Bool)
    (evidenceText : Option String := none)
    (staged : List Value := []) (stagedVisible : Bool := true)
    (enableLocalUnion : Bool := true) : IO (Option Handoff) := do
  if selection.read.isEmpty then pure none
  else
    let operationWork := enforce || evidenceText.isSome
    let cached ← cachedWorkspaceAt selection snapshots
    let composite := cached.composite
    let stagedGraph := WorkGraph.fromValues (staged.filter (!composite.values.contains ·))
    let graph : WorkGraph := {
      all := cached.graph.all ++ stagedGraph.all
      outcomes := cached.graph.outcomes ++ stagedGraph.outcomes
    }
    if graph.outcomes.isEmpty then return none
    let values := (composite.values ++ staged).eraseDups
    let prepared : TestOracle.CorpusCache.Prepared LogicalText.logicalNormalizer graph :=
      if same : graph = cached.graph then same.symm ▸ cached.prepared
      else TestOracle.CorpusCache.prepare LogicalText.logicalNormalizer cached.prepared.index graph
    let inquiry := Value.text current
    let (semantic, evidenceRanking, semanticEvidence) ← if operationWork then pure ({}, [], []) else
      match selection.semanticMatcher with
      | some command => SemanticMatcher.nominateWithRanking command inquiry current prepared.corpus
      | none => pure ({}, [], [])
    if semantic.pending then
      -- Status is a fixed-size notice, not selected evidence. Omitting it for
      -- a small evidence budget would misreport an unfinished search as empty.
      return some pendingSearch
    let input : SearchMemo.Input := {
      sources := selection.read.map (·.path.normalize.toString)
      authorities := composite.authorities, origins := composite.origins
      unionOrigins := composite.unionOrigins
      values, unions := composite.unions, graph, current, evidence := evidenceText
      semantic, localUnion := enableLocalUnion, native := operationWork }
    let cache ← runtimeCache.get
    let saved ← match selection.write with
      | some writable => do
          if let some snapshot ← DB.PageMap.open? writable.path then
            try Matcher.RankMemo.read snapshot catch _ => pure []
          else pure []
      | none => pure []
    let savedSaturation ← if staged.isEmpty then match selection.write with
      | some writable => do
          if let some snapshot ← DB.PageMap.open? writable.path then
            try SaturationMemo.read snapshot catch _ => pure []
          else pure []
      | none => pure []
      else pure []
    let (found, query) := SearchMemo.getUsing cache.query saved input prepared savedSaturation
    runtimeCache.set { cache with query }
    if staged.isEmpty then
      if let some writable := selection.write then
        if let some entry := query then
          if !entry.savedRanks.isEmpty then
            try Matcher.RankMemo.publish writable.path entry.savedRanks
            catch _ => pure () -- Optional acceleration cannot queue behind the writer.
          -- The reference evaluator verifies current results. Only the
          -- production final-view observer publishes its executed join plan.
    match found.result with
    | none => pure none
    | some result =>
        let meaning := !operationWork && selection.semanticMatcher.isSome
        let nominated := semantic.related.filter composite.values.contains ++
          semantic.related.filter (!composite.values.contains ·)
        let nominatedOwners := nominated.filterMap fun relation =>
          graph.outcomes.find? (·.relation == relation)
        let selected := selectedMatches result.discovery result.extraction
        let entries := if nominatedOwners.isEmpty then selected.map (·.matched.edge) else nominatedOwners
        let entryWorks := entries.map (·.work)
        let evidenceRoots := (rankEvidenceChoices evidenceRanking
          (entries.map fun owner => (owner.relation, owner.work))).map Prod.snd
        let requested := entryWorks ++ selected.map (·.matched.edge.work) ++
          stagedGraph.all.flatMap (fun edge => edge.parent :: edge.children)
        let sourceAll := if meaning then referenceSourceAll cached.graph.all composite.unions
          requested ((snapshots.filterMap id).length == 1) ++ stagedGraph.all else []
        let reached := referenceSourceClosure entryWorks sourceAll composite.unions
        let records := composite.values ++ staged
        let mut remaining := 4 * min (selection.handoffChars * 4)
          (selection.handoffBytes.getD (selection.handoffChars * 4))
        let mut support : List (SourceSupport entryWorks sourceAll composite.unions) := []
        if meaning then
          let rendered := (sourceEntrySelection true false nominated selected).map (·.matched.edge.relation)
          let ordered := cached.graph.outcomes.mergeSort fun left right =>
            let l := sourceFamilyPriority evidenceRoots sourceAll left.work
            let r := sourceFamilyPriority evidenceRoots sourceAll right.work
            if l == r then evidenceRanking.findIdx (· == left.relation) ≤
              evidenceRanking.findIdx (· == right.relation) else l < r
          for owner in ordered do
            if rendered.contains owner.relation then continue
            let some work := Persistence.Store.text? owner.work | continue
            let some body := Persistence.Store.text? owner.outcome | continue
            let size := work.utf8ByteSize + body.utf8ByteSize
            if size > remaining then continue
            let some row := reached.find? (fun row => row.work == owner.work) | continue
            if same : row.work = owner.work then
              support := support ++ [⟨owner, same ▸ row.route,
                referenceSourceRecords records owner.relation⟩]
              remaining := remaining - size
            else throw (IO.userError "reference source closure changed its original owner")
        let provenance := graph.outcomes.map fun owner =>
          (owner.relation, referenceSourceRecords records owner.relation)
        pure (renderAutomatic staged selection.handoffChars current
          deliveredGraphs enforce stagedVisible result.discovery ⟨result.extraction, result.exact⟩
          (provenance := provenance) (nominated := nominated) (meaningSelected := meaning)
          (semanticEvidence := semanticEvidence)
          (sourceAll := sourceAll) (sourceUnions := composite.unions)
          (entryWorks := entryWorks) (support := support) (byteBudget := selection.handoffBytes)
          (evidenceRanking := evidenceRanking))


/- Frozen cold-federation controller, independent of the new canonical-child
interpreter. Kept only for complete output and physical-read comparisons. -/
namespace FederationBeforeCanonical
open Persistence.Store Federated

structure Identity (sources : Array Snapshot) where
  nodes : Array (Node sources) := #[]
  aliases : Std.HashMap (Nat × Nat) Nat := {}
  buckets : Std.HashMap Nat (List Nat) := {}

def Identity.add (index : Identity sources) (node : Node sources) : IO (Identity sources × Nat) := do
  let key := (node.source.val, node.id)
  if let some known := index.aliases[key]? then return (index, known)
  let digest ← nodeHash node.snapshot node.id
  for candidate in index.buckets.getD digest [] do
    let some original := index.nodes[candidate]? |
      throw (IO.userError "federated identity bucket exceeds its request table")
    if ← nodesEqual original.snapshot original.id node.snapshot node.id then
      return ({index with aliases := index.aliases.insert key candidate}, candidate)
  let id := index.nodes.size
  let next : Identity sources := {
    nodes := index.nodes.push node
    aliases := index.aliases.insert key id
    buckets := index.buckets.insert digest (index.buckets.getD digest [] ++ [id]) }
  pure (next, id)

def Identity.lookup (index : Identity sources) (source : Fin sources.size) (id : Nat) : IO Nat := do
  let some canonical := index.aliases[(source.val, id)]? |
    throw (IO.userError "live reference is absent from the federated semantic index")
  pure canonical

structure Catalogue (sources : Array Snapshot) where
  identity : Identity sources
  roots : List Nat
  orders : Std.HashMap Nat Nat
  owners : Std.HashMap Nat (Node sources)
  documents : List (Document sources)
  all : List AllEdge
  unions : List UnionEdge

def prepare (sources : Array Snapshot) : IO (Catalogue sources) := do
  let mut identity : Identity sources := {}
  let mut topology := []
  let mut unions := []
  for source in List.finRange sources.size do
    let snapshot := sources[source]
    let edges ← Persistence.Store.topology snapshot
    topology := topology ++ edges
    let edges ← readUnions snapshot (← authority snapshot)
    unions := unions ++ edges.map (·.edge)
    let nodes ← directory snapshot "semanticUses"
    unless nodes.length == (← getNat snapshot.get "semanticPopulation") &&
        nodes.all (fun row => row.2 > 0) do
      throw (IO.userError "federated semantic population is incomplete")
    for (id, _) in nodes do identity := (← identity.add ⟨source, id⟩).1
  let mut roots := []
  let mut owners : Std.HashMap Nat (Node sources) := {}
  let mut documents : List (Document sources) := []
  let mut known : Std.HashSet Nat := {}
  for source in List.finRange sources.size do
    let snapshot := sources[source]
    for (_, id) in (← rootDirectory snapshot) do
      roots := roots ++ [← identity.lookup source id]
    let rows ← directory snapshot "outcome"
    unless rows.length == (← getNat snapshot.get "liveOutcomes") do
      throw (IO.userError "federated Outcome population is incomplete")
    for (_, id) in rows do
      let _ ← locateOutcome snapshot id
      let canonical ← identity.lookup source id
      unless owners.contains canonical do owners := owners.insert canonical ⟨source, id⟩
    for document in (← searchDocuments snapshot) do
      let owner ← identity.lookup source document.owner
      unless owners.contains owner do throw (IO.userError "federated candidate is not an Outcome")
      unless known.contains owner do
        known := known.insert owner
        documents := documents ++ [⟨⟨source, document.owner⟩, document, owner,
          ← identity.lookup source document.work, 0⟩]
  roots := hashDistinct roots
  let orders := Std.HashMap.ofList (roots.zipIdx)
  documents ← documents.mapM fun document => do
    let some ordinal := orders[document.owner]? |
      throw (IO.userError "federated document has no live source root")
    pure {document with ordinal}
  let result : Catalogue sources := {
    identity, roots, orders, owners
    documents := documents.mergeSort (fun first second => first.ordinal ≤ second.ordinal)
    all := topology.eraseDups
    unions }
  pure result

end FederationBeforeCanonical
end Eggshell.TestOracle

namespace Eggshell.TestOracle

open Eggshell.Matcher
open Eggshell.LogicalText

/-- Frozen matcher before Work-first hydration; independent regression oracle. -/
def findInUsingBeforeWorkGate (normalize : Normalizer) (demandProvider : DemandProvider normalize)
    (cover : CoverageProvider) (quotient : Quotient)
    (corpus : Corpus) (current : Value) (currentText : String)
    (evidenceText : Option String := none)
    (semantic : SemanticNominations := {})
    (currentNative : Bool := false) : List Match :=
  let demand := demandProvider currentText currentNative
  let currentPattern := demand.pattern
  let currentPatterns := demand.workPatterns
  /-
  Native results can reveal a symbol that reconnects historical context, but
  they are not the current Work. The context lane is surface-only and cannot
  create Local Union.
  -/
  let noveltyCeiling := corpus.population + 1
  /-
  Candidate admission is Work-to-Work only. Outcome text supplies the payload
  and its smallest relevant projection after a Work match; it is not a second
  retrieval engine that can inject unrelated history into Demand.
  -/
  admittedCandidates currentPattern corpus semantic |>.flatMap
      fun candidate =>
    let edge := candidate.edge
    /-
    Retrieval is an independent advisory lane, not a fallback after surface
    failure. A weak shared token must not hide a stronger semantic retrieval.
    It is placed first so an identical intrinsic alignment is processed later
    and remains the authoritative identity/applicability judgment.
    -/
    let related := if externallyNominated semantic.related candidate then
      [candidate.retrievalPair current currentPattern] else []
    let pairs := related ++ candidate.intrinsicPairs quotient current
      currentPattern currentPatterns
    pairs.flatMap fun pair =>
      let pastWeights := corpus.informationWeights pair.past candidate.native
      let currentWeights := corpus.informationWeights pair.current currentNative
      let alignments := if pair.retrieved then
        [(completeCoverage pair.past pastWeights noveltyCeiling,
          completeCoverage pair.current currentWeights noveltyCeiling)]
        else cover pair.past pair.current
          pastWeights currentWeights noveltyCeiling
      alignments.filterMap fun (priorInDemand, demandInPrior) => do
        let pastComplete := priorInDemand.complete
        let currentComplete := demandInPrior.complete
        let (pastSpans, currentSpans) ←
          if pastComplete then
            some (priorInDemand.querySpans, priorInDemand.targetSpans)
          else if currentComplete then
            some (demandInPrior.targetSpans, demandInPrior.querySpans)
          else if priorInDemand.compareScore demandInPrior != .lt then
            some (priorInDemand.querySpans, priorInDemand.targetSpans)
          else
            some (demandInPrior.targetSpans, demandInPrior.querySpans)
        let pastSpan ← LogicalText.envelope? pastSpans
        let currentSpan ← LogicalText.envelope? currentSpans
        let pastFragment := if priorInDemand.coveredUnits.length =
            pair.past.logical.units.length then pair.pastValue else
          (materializeFragment pair.past.logical pastSpans).map (·.1) |>.getD pair.pastValue
        let currentFragment := if demandInPrior.coveredUnits.length =
            pair.current.logical.units.length then pair.currentValue else
          (materializeFragment pair.current.logical currentSpans).map (·.1) |>.getD pair.currentValue
        let subwork := corpus.subworks.any (quotient.toEquality.same edge.work)
        let wholeWorkIdentity := quotient.toEquality.same current edge.work
        let preliminaryWork : WorkAlignment := {
          priorInDemand
          demandInPrior
          subwork
          pastWholeWork := pair.pastWhole
          wholeWorkIdentity
          fragmentIdentity := quotient.toEquality.same currentFragment pastFragment
          currentFragment
          pastFragment
          currentSpan
          pastSpan
        }
        let context : Option ContextAlignment := do
          let outcomePattern ← candidate.outcome
          let contextDemandText := atomText? (preliminaryWork.contextDemand current)
            |>.getD currentText
          let contextDemandPattern := makePattern
            (LogicalText.build normalize contextDemandText)
          let contextDemandWeights := corpus.informationWeights contextDemandPattern
            currentNative
          /-
          Result coverage grounds an already-Unioned Work fragment in observed
          bytes. It never creates equality: external retrieval stays advisory,
          and the original Outcome relation remains Exact provenance.
          -/
          match surfaceContextCover contextDemandPattern outcomePattern contextDemandWeights
              noveltyCeiling with
          | some demandInOutcome =>
              pure {
                demandInOutcome
                outcomeFragment := materializeContextBeforeStreaming outcomePattern.logical
                  demandInOutcome.targetSpans candidate.native
                alreadyVisible := false
              }
          | none =>
              let evidence ← evidenceText
              let evidencePattern := makePattern (LogicalText.build normalize evidence)
              let outcomeWeights := corpus.informationWeights outcomePattern
              let outcomeInContext ← surfaceContextCover outcomePattern evidencePattern
                outcomeWeights noveltyCeiling
              pure {
                demandInOutcome := outcomeInContext
                alreadyVisible := true
              }
        pure {
          demand := current
          edge := edge
          work := preliminaryWork
          context := context
          retrieved := pair.retrieved
        }


set_option maxRecDepth 4096 in
/-- The ordered map/flatMap factorization preserves the complete pre-change
matcher for every corpus, quotient, normalizer and coverage provider. -/
theorem findInUsingBeforeWorkGate_exact (normalize : LogicalText.Normalizer)
    (demands : Matcher.DemandProvider normalize) (cover : Matcher.CoverageProvider)
    (quotient : Quotient) (corpus : Matcher.Corpus) (current : Value) (text : String)
    (evidence : Option String) (semantic : Matcher.SemanticNominations) (native : Bool) :
    findInUsingBeforeWorkGate normalize demands cover quotient corpus current text evidence semantic native =
      Matcher.findInUsing normalize demands cover quotient corpus current text evidence semantic native := by
  unfold findInUsingBeforeWorkGate Matcher.findInUsing Matcher.Candidate.findMatches
    Matcher.Candidate.preparedWorks Matcher.Candidate.prepareWork Matcher.Candidate.groundContext
    Matcher.groundContextPatterns Matcher.contextPattern Matcher.compile
    Matcher.Candidate.workAlignments Matcher.WorkView.alignments
  simp only [List.filterMap_flatMap, List.filterMap_map, List.map_flatMap,
    List.map_filterMap, Option.map_map, Function.comp_def]
  simp only [materializeContextBeforeStreaming_exact]
  congr 1
  funext candidate
  congr 1
  funext pair
  congr 1
  funext alignment
  split <;> (try split) <;> (try split) <;>
    simp only [← Option.map_eq_map, map_bind, map_pure] <;> rfl

end Eggshell.TestOracle
