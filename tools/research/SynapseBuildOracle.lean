module

public import Eggshell.SynapseIndex
public import Eggshell.SynapseTraceCache

@[expose] public section

namespace Eggshell.Synapses.BuildOracle
open Lean DB Persistence.Store _root_.Eggshell.Synapses.Extraction

/-- This adapter reads a pinned native publication. No export, tool execution,
or model is involved; unsupported observations remain unlocated. -/
def identities (edge : OutcomeEdge) : Array Occurrence := Provenance.identities edge

def document (reader : NodeReader snapshot) (id : Nat) : IO Document := Provenance.document reader id

structure Entry where
  id : Nat
  work : Nat

/-- The candidate directory supplies headers only, not window lists or bodies. -/
def entries (snapshot : PageMap.Snapshot) : IO (Array Entry) := do
  let mut result := #[]
  for (ordinal, id) in ← directory snapshot "searchCandidate" do
    let located ← locateOutcome snapshot id
    unless (← getNat snapshot.get (key "member" id)) == ordinal &&
        (← getNat snapshot.get (key "candidate" id)) == 1 do
      throw (IO.userError "synaptic candidate is not a live original owner")
    result := result.push ⟨id, located.header.work⟩
  return result

def topology (snapshot : PageMap.Snapshot) : IO (Std.HashMap Nat (Array Nat)) := do
  let mut result := {}
  for header in ← allHeaders snapshot do
    result := result.insert header.2.header.parent
      (result[header.2.header.parent]?.getD #[] ++ header.2.header.children.toArray)
  return result

def closure (edges : Std.HashMap Nat (Array Nat)) (roots : Array Nat) : Std.HashSet Nat := Id.run do
  let mut seen := {}
  let mut queue := roots
  let mut position := 0
  while position < queue.size do
    let current := queue[position]!
    position := position + 1
    if seen.contains current then continue
    seen := seen.insert current
    queue := queue ++ edges[current]?.getD #[]
  return seen

def reverse (edges : Std.HashMap Nat (Array Nat)) : Std.HashMap Nat (Array Nat) :=
  edges.fold (fun result parent children => children.foldl
    (fun result child => result.insert child (result[child]?.getD #[] |>.push parent)) result) {}

structure Changes where
  owners : Std.HashSet Nat := {}
  works : Std.HashSet Nat := {}
  removed : Bool := false

/-- Follow exact parent heads, not revision counters. A non-ancestor cache
requires an explicit rebuild rather than a fabricated incremental update. -/
def changes (snapshot : PageMap.Snapshot) (saved : PageMap.Head) : IO (Option Changes) := do
  if saved.identity != snapshot.head.identity || saved.authority != snapshot.head.authority then return none
  let mut current := snapshot.head
  let mut result : Changes := {}
  while current != saved do
    if current.revision ≤ saved.revision then return none
    let publication ← readPublication snapshot current.revision
    result := {result with removed := result.removed || !publication.change.removed.isEmpty}
    for id in publication.change.added ++ publication.change.removed ++ publication.change.affected do
      let frame ← readFrame snapshot snapshot.get id
      if let some header := OutcomeHeader.fromFrame? frame then
        result := {result with owners := result.owners.insert id, works := result.works.insert header.work}
      if let some header := AllHeader.fromFrame? frame then
        result := {result with works := result.works.insert header.parent}
      if let .apply .receipt references := frame.frame then
        if let some fields := SourceEvidence.receiptFields? references then
          if (← readNode snapshot snapshot.get fields.marker) == .text SourceEvidence.receiptMarker &&
              (← readNode snapshot snapshot.get fields.purpose) == .text SourceEvidence.receiptPurpose then
            let some owner := OutcomeHeader.fromFrame? (← readFrame snapshot snapshot.get fields.owner) |
              throw (IO.userError "source receipt does not refer to an original Outcome frame")
            result := {result with
              owners := result.owners.insert fields.owner
              works := result.works.insert owner.work}
    current := publication.parent
  return some result

def retain (readOwners answers : Std.HashSet String) (keepConsumption : Bool) : Fact → Bool
  | .read read => !readOwners.contains read.binding.owner
  | .supports support => !readOwners.contains support.read.binding.owner && !answers.contains support.claim.answer
  | .coquoted (.answer _ answer) _ => !answers.contains answer
  | .coquoted (.claim claim) _ => !answers.contains claim.answer
  | .consumed _ => keepConsumption
  | .used _ => false

theorem retained_support_independent (reads answers : Std.HashSet String) (keep : Bool) (support : Support)
    (retained : retain reads answers keep (.supports support) = true) :
    reads.contains support.read.binding.owner = false ∧ answers.contains support.claim.answer = false := by
  simpa [retain, Bool.and_eq_true] using retained

theorem usage_never_enters_shared_rebuild (reads answers : Std.HashSet String) (keep : Bool) (usage : Usage) :
    retain reads answers keep (.used usage) = false := rfl

structure Result where
  mode : String
  source : PageMap.Head
  index : PageMap.Head
  candidates : Nat := 0
  hydrated : Nat := 0
  consumptionRebuilt : Bool := false
  provenanceOriginals : Nat := 0
  provenanceIgnored : Nat := 0
  provenanceGroups : Nat := 0
  provenanceRecordsRead : Nat := 0
  answers : Nat := 0
  unsupported : Nat := 0
  facts : Nat := 0
  elapsedMs : Nat := 0
  deriving ToJson

structure Documents (snapshot : PageMap.Snapshot) where
  reader : NodeReader snapshot
  cache : IO.Ref (Std.HashMap Nat Document)
  catalogs : IO.Ref (Std.HashMap Nat ObservationContext.Catalog)
  prepared : Option PageMap.Snapshot := none
  additions : Std.HashMap Nat ContentCapture.Supplement := {}

def Documents.get (documents : Documents snapshot) (id : Nat) : IO Document := do
  if let some doc := (← documents.cache.get)[id]? then return doc
  let doc ← document documents.reader id
  documents.cache.modify (·.insert id doc)
  return doc

def Documents.catalog (documents : Documents snapshot) (id : Nat) : IO ObservationContext.Catalog := do
  if let some catalog := (← documents.catalogs.get)[id]? then return catalog
  let doc ← documents.get id
  let original ← match ← ObservedRecords.load? snapshot id doc with
    | some catalog => pure catalog
    | none => do
        let some raw := doc.source | throw (IO.userError "original record body is missing")
        let prepared ← IO.ofExcept (ObservedRecords.prepare raw)
        IO.ofExcept (ObservedRecords.catalog snapshot.head.identity doc prepared.records)
  -- File aliases are additional coordinates, never the original domain gate.
  let files := (recordedReads snapshot.head.identity doc).toOption.getD #[]
  let captured ← match ← ContentMetadata.load? snapshot id doc with
    | none => pure ({} : ObservationContext.Catalog)
    | some captured => do
      let extra ← match documents.additions[id]? with
        | some extra => pure (some extra)
        | none => documents.prepared.bindM fun prepared =>
          ContentMetadata.loadSupplement? prepared snapshot.head.identity id doc captured
      let original ← IO.ofExcept (ContentMetadata.catalog snapshot.head.identity doc captured)
      match extra with
      | none => pure original
      | some extra =>
        let added ← IO.ofExcept (ContentMetadata.catalogSupplement snapshot.head.identity doc captured extra)
        pure {located := original.located ++ added.located,quotations := original.quotations ++ added.quotations}
  let catalog := {original with
    located := files ++ captured.located ++ original.located
    quotations := captured.quotations ++ original.quotations}
  documents.catalogs.modify (·.insert id catalog)
  return catalog

def ownerId? (snapshot : PageMap.Snapshot) (owner : String) : IO (Option Nat) := do
  let some checked := Persistence.SelectionKey.check? owner |
    throw (IO.userError "noncanonical synaptic owner locator")
  let ids ← getIds snapshot.get ("owner:" ++ toString checked.digest)
  let live ← ids.filterM fun id => return (← snapshot.get (key "member" id)).isSome
  match live with
  | [] => return none
  | [id] => return some id
  | _ => throw (IO.userError "ambiguous synaptic owner locator")

/-- Scheduling probe only: bounded metadata reads and no directory creation. -/
def required (snapshot : PageMap.Snapshot) (storage : Sidecar.Storage) : IO Bool := do
  return (← Index.open? snapshot storage .shared).isNone

/-- The background extractor keeps only metadata between publications. A new
answer hydrates its cited original reads, never every unrelated source body. -/
def refresh (snapshot : PageMap.Snapshot) (storage : Sidecar.Storage)
    (additions : Array (Nat × ContentCapture.Supplement) := #[]) : IO Result := do
  let started ← IO.monoMsNow
  if additions.isEmpty then
    if let some ready ← Index.open? snapshot storage .shared then
      return {
        mode := "warm", source := snapshot.head, index := ready.index.head
        facts := ready.manifest.facts, elapsedMs := (← IO.monoMsNow) - started}
  let path ← Index.directory snapshot storage .shared
  let previous ← PageMap.open? path
  let metadata ← previous.bindM Index.manifest?
  let compatible := metadata.filter fun value => value.implementation == Index.implementation && value.scope == .shared
  let delta ← compatible.bindM fun value => changes snapshot value.source
  let incremental := delta.isSome
  let previousFacts ← if incremental then previous.mapM Index.allFacts else pure none
  let old := previousFacts.getD #[]
  Index.checkFacts snapshot.head.identity .shared old
  let catalog ← entries snapshot
  let all ← topology snapshot
  let mut changed := delta.getD {}
  let mut preparedAdditions := {}
  for (id,extra) in additions do
    unless !preparedAdditions.contains id && extra.sealed && catalog.any (·.id == id) do
      throw (IO.userError "supplement does not name one live original owner")
    let located ← locateOutcome snapshot id
    changed := {changed with owners := changed.owners.insert id,works := changed.works.insert located.header.work}
    preparedAdditions := preparedAdditions.insert id extra
  let affectedWorks := closure (reverse all) changed.works.toArray
  let documents : Documents snapshot := {
    reader := ← NodeReader.new snapshot
    cache := ← IO.mkRef {}
    catalogs := ← IO.mkRef {}
    prepared := previous
    additions := preparedAdditions}
  let mut readOwners := #[]
  let mut answerOwners := #[]
  let mut retiredReads : Std.HashSet String := {}
  let mut retiredAnswers : Std.HashSet String := {}
  let mut unsupported := 0
  for entry in catalog do
    if !incremental || changed.owners.contains entry.id || affectedWorks.contains entry.work then
      let doc ← documents.get entry.id
      if doc.native then
        if !incremental || changed.owners.contains entry.id then readOwners := readOwners.push entry
      else
        answerOwners := answerOwners.push entry
        retiredAnswers := retiredAnswers.insert doc.owner
  -- Retired original owners are absent from the current candidate directory.
  for id in changed.owners do
    let value ← readNode snapshot snapshot.get id
    retiredReads := retiredReads.insert (Persistence.selectionKey value)
    retiredAnswers := retiredAnswers.insert (Persistence.selectionKey value)
  -- A source retraction also invalidates its former answer/coquotation groups.
  for fact in old do
    if let .supports support := fact then
      if retiredReads.contains support.read.binding.owner then
        retiredAnswers := retiredAnswers.insert support.claim.answer
  for answer in retiredAnswers do
    if let some id ← ownerId? snapshot answer then
      if !answerOwners.any (·.id == id) && catalog.any (·.id == id) then
        let doc ← documents.get id
        if !doc.native then
          let entry := catalog.find? (·.id == id)
          if let some entry := entry then answerOwners := answerOwners.push entry
  let traces ← if incremental then
      match previous with
      | some previous => TraceCache.prepare snapshot previous changed.owners documents.get
      | none => throw (IO.userError "incremental trace preparation lost its prior pin")
    else TraceCache.rebuild snapshot
  for fact in old do
    if let .consumed edge := fact then
      unless TraceCache.group edge.producer == TraceCache.group edge.consumer do
        throw (IO.userError "cached consumption crosses original session/turn replay partitions")
  let mut graph ← IO.ofExcept (Graph.ofFacts (old.filter fun fact => match fact with
    | .consumed edge => incremental && !TraceCache.affected traces.changed edge
    | other => retain retiredReads retiredAnswers true other))
  for entry in readOwners do
    let catalog ← documents.catalog entry.id
    if catalog.located.isEmpty then unsupported := unsupported+1
    for read in catalog.reads do graph ← IO.ofExcept (graph.insert (.read read))
  let reads := graph.snapshot.filterMap fun fact => match fact with | .read read => some read | _ => none
  let mut workIds : Std.HashMap String Nat := {}
  for entry in catalog do
    if let some doc := (← documents.cache.get)[entry.id]? then workIds := workIds.insert doc.work entry.work
  -- Resolve only recorded read owners whose metadata was reused.
  let mut readIds : Std.HashMap String Nat := {}
  for read in reads do
    if readIds.contains read.binding.owner then continue
    if let some id ← ownerId? snapshot read.binding.owner then
      let located ← locateOutcome snapshot id
      workIds := workIds.insert read.binding.work located.header.work
      readIds := readIds.insert read.binding.owner id
  for entry in answerOwners do
    let doc ← documents.get entry.id
    let route := closure all #[entry.work]
    let available := reads.filter fun read => (workIds[read.binding.work]?).any route.contains
    let files := available.foldl (fun files read =>
      (read.source.file?.map files.insert).getD files) ({} : Std.HashSet File)
    let citations := ((layout (doc.source.getD "")).map fun decoded =>
      paragraphCitations decoded.text files.toArray).toOption.getD #[]
    let needed := available.filter fun read => citations.any (fun cited =>
      (cited.intersection? read.source).isSome)
    let quoteTexts := ((layout (doc.source.getD "")).map fun decoded =>
      decoded.text.splitOn "\n\n" |>.toArray.flatMap (fun paragraph =>
        (Quotes.extract paragraph).map (·.text))).toOption.getD #[]
    let quoteTexts := hashDistinct quoteTexts.toList |>.toArray
    let index := LiteralSearch.prepare quoteTexts
    let allowed := available.foldl (fun (set : Std.HashSet Read) read => set.insert read) {}
    let mut spellings := #[]
    let mut quoteOwners : Std.HashSet Nat := {}
    if !quoteTexts.isEmpty then
      for read in available do
        let some id := readIds[read.binding.owner]? | continue
        if quoteOwners.contains id then continue
        quoteOwners := quoteOwners.insert id
        let catalog ← documents.catalog id
        spellings := spellings ++ ObservationContext.quoteMatches index
          (catalog.quotations.filter (fun item => allowed.contains item.read))
    let mut located := #[]
    let mut seen : Std.HashSet Nat := {}
    for read in needed ++ spellings.map (·.read) do
      let some id := readIds[read.binding.owner]? | continue
      if seen.contains id then continue
      seen := seen.insert id
      let catalog ← documents.catalog id
      located := located ++ catalog.located
    match addAnswer snapshot.head.identity doc located graph with
    | .ok next => graph := next
    | .error _ => unsupported := unsupported + 1
    match ObservationContext.addQuotedAnswer snapshot.head.identity doc spellings graph with
    | .ok next => graph := next
    | .error _ => unsupported := unsupported + 1
  let portable ← Provenance.deriveRecords snapshot traces.replay
  graph ← IO.ofExcept (graph.merge portable.graph)
  let facts := graph.snapshot
  -- The same changed-owner feed and the same atomic index publication own
  -- the immutable original read view. Queries never normalize these bodies.
  let prepareRecords := fun writer : PageMap.Writer => do
    TraceCache.stage writer traces
    if !incremental then
      let pinned ← writer.snapshot
      let prior ← pinned.foldRange ⟨"observed-view:owner:","observed-view:owner;"⟩
        (fun keys row => pure (keys.push row.1)) (#[] : Array String)
      for key in prior do writer.put key none
    for owner in retiredReads do writer.put (ObservedRecordView.ownerKey owner) none
    for entry in readOwners ++ answerOwners do
      let document ← documents.get entry.id
      if let some extra := preparedAdditions[entry.id]? then
        let some captured ← ContentMetadata.load? snapshot entry.id document |
          throw (IO.userError "supplement lost its recorded parent")
        ContentMetadata.stageSupplement writer snapshot.head.identity entry.id document captured extra
      if document.source.isSome then
        ObservedRecordView.stage writer snapshot.head.identity document
  let head ← if incremental then
      let wanted := graph.facts
      let previous := old.foldl (fun set fact => set.insert fact) ({} : Std.HashSet Fact)
      Index.publishDelta snapshot storage .shared (metadata.map (·.source)) {
        removed := old.filter (!wanted.contains ·)
        added := facts.filter (!previous.contains ·) } prepareRecords
    else Index.replace snapshot storage .shared facts prepareRecords
  return {
    mode := if incremental then "incremental" else "rebuild", source := snapshot.head, index := head
    candidates := catalog.size, hydrated := (← documents.cache.get).size, answers := answerOwners.size,
    consumptionRebuilt := !traces.replay.isEmpty,provenanceOriginals := portable.originals,provenanceIgnored := portable.ignored
    provenanceGroups := traces.changed.size,provenanceRecordsRead := traces.replay.size
    unsupported, facts := facts.size, elapsedMs := (← IO.monoMsNow) - started}

end Eggshell.Synapses.BuildOracle
