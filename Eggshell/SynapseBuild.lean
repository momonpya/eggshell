module

public import Eggshell.SynapseIndex

@[expose] public section

namespace Eggshell.Synapses.Build
open Lean DB Persistence.Store _root_.Eggshell.Synapses.Extraction

/-- This adapter reads a pinned native publication. No export, tool execution,
or model is involved; unsupported observations remain unlocated. -/
def identities (edge : OutcomeEdge) : Array Occurrence :=
  edge.observations.toArray.filterMap fun observation => do
    let .apply .occurrence references := observation | none
    let [(.semantic, result), (.semantic, work), (.exact, session),
        (.exact, turn), (.exact, useId)] := references.toList | none
    if result != edge.outcome || work != edge.work then none else
      some ⟨← text? session, ← text? turn, ← text? useId⟩

def document (reader : NodeReader snapshot) (id : Nat) : IO Document := do
  let edge ← reader.outcome (← reader.locateOutcome id)
  let owner := Persistence.selectionKey edge.relation
  -- A display hash nominates a bucket, never a unique source by itself.
  let candidates ← getIds snapshot.get ("owner:" ++ toString (hash edge.relation).toNat)
  let live ← candidates.filterM fun id => return (← snapshot.get (key "member" id)).isSome
  unless live == [id] do throw (IO.userError "ambiguous synaptic source owner")
  return {
    owner, work := Persistence.selectionKey edge.work
    workText := text? edge.work, source := text? edge.outcome
    native := edge.observations.any (Relation.observesOutcomeWork edge.outcome edge.work)
    occurrences := identities edge
    files := ← IO.ofExcept (fileMap ((← reader.sources id).toArray.map toJson)) }

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
    for id in publication.change.added ++ publication.change.removed do
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
  answers : Nat := 0
  unsupported : Nat := 0
  facts : Nat := 0
  elapsedMs : Nat := 0
  deriving ToJson

structure Documents (snapshot : PageMap.Snapshot) where
  reader : NodeReader snapshot
  cache : IO.Ref (Std.HashMap Nat Document)

def Documents.get (documents : Documents snapshot) (id : Nat) : IO Document := do
  if let some doc := (← documents.cache.get)[id]? then return doc
  let doc ← document documents.reader id
  documents.cache.modify (·.insert id doc)
  return doc

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
def refresh (snapshot : PageMap.Snapshot) (storage : Sidecar.Storage) : IO Result := do
  let started ← IO.monoMsNow
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
  let changed := delta.getD {}
  let affectedWorks := closure (reverse all) changed.works.toArray
  let documents : Documents snapshot := ⟨← NodeReader.new snapshot, ← IO.mkRef {}⟩
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
  let mut graph ← IO.ofExcept (Graph.ofFacts (old.filter (retain retiredReads retiredAnswers (!changed.removed))))
  for entry in readOwners do
    match recordedReads snapshot.head.identity (← documents.get entry.id) with
    | .ok reads =>
      for located in reads do graph ← IO.ofExcept (graph.insert (.read located.read))
    | .error _ => unsupported := unsupported + 1
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
    let files := available.foldl (fun files read => files.insert read.source.file) ({} : Std.HashSet File)
    let citations := ((layout (doc.source.getD "")).map fun decoded =>
      paragraphCitations decoded.text files.toArray).toOption.getD #[]
    let needed := available.filter fun read => citations.any (fun cited => read.source.contains cited)
    let mut located := #[]
    let mut seen : Std.HashSet Nat := {}
    for read in needed do
      let some id := readIds[read.binding.owner]? | continue
      if seen.contains id then continue
      seen := seen.insert id
      match recordedReads snapshot.head.identity (← documents.get id) with
      | .ok rows => located := located ++ rows
      | .error _ => unsupported := unsupported + 1
    match addAnswer snapshot.head.identity doc located graph with
    | .ok next => graph := next
    | .error _ => unsupported := unsupported + 1
  let facts := graph.snapshot
  let head ← if incremental then
      let wanted := graph.facts
      let previous := old.foldl (fun set fact => set.insert fact) ({} : Std.HashSet Fact)
      Index.publishDelta snapshot storage .shared (metadata.map (·.source)) {
        removed := old.filter (!wanted.contains ·)
        added := facts.filter (!previous.contains ·) }
    else Index.replace snapshot storage .shared facts
  return {
    mode := if incremental then "incremental" else "rebuild", source := snapshot.head, index := head
    candidates := catalog.size, hydrated := (← documents.cache.get).size, answers := answerOwners.size,
    unsupported, facts := facts.size, elapsedMs := (← IO.monoMsNow) - started}

end Eggshell.Synapses.Build
