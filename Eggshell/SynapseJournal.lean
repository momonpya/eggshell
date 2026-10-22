module

public import Eggshell.SynapseBuild
public import Eggshell.SynapseUsage
public import Eggshell.PluginModel

@[expose] public section

namespace Eggshell.Synapses.Journal
open Lean DB Persistence.Store _root_.Eggshell.Synapses.Extraction

structure Clock where
  domain : String
  nanos : Nat
  deriving BEq, ToJson, FromJson

structure IndexAt where
  head : PageMap.Head
  storage : Sidecar.Storage
  producer : String
  deriving BEq, ToJson, FromJson

/-- Captured before the current PreToolUse can deliver anything. Unconfirmed
offers make missing-delivery labels unknown, never positive evidence. -/
structure Knowledge where
  source : PageMap.Head
  indexed : Option IndexAt
  acknowledged : List String
  uncertain : Bool
  archive : Option String := none
  deriving BEq, ToJson, FromJson

inductive Payload where
  | start (occurrence : Occurrence) (work query : String) (knowledge : Knowledge)
  | finish (occurrence : Occurrence) (name input response : String) (archive : Option String)
  | answer (occurrence : Occurrence) (query text : String) (knowledge : Knowledge)
  deriving BEq, ToJson, FromJson

def Payload.occurrence : Payload → Occurrence
  | .start value .. | .finish value .. | .answer value .. => value

def Payload.kind : Payload → String
  | .start .. => "start"
  | .finish .. => "finish"
  | .answer .. => "answer"

def Payload.sameObservation (left right : Payload) : Bool :=
  match left, right with
  | .start a work query _, .start b other q _ => a == b && work == other && query == q
  | .finish a name input response archive, .finish b n i r other =>
    a == b && name == n && input == i && response == r && archive == other
  | .answer a query text _, .answer b q t _ => a == b && query == q && text == t
  | _, _ => false

def Payload.valid (database : String) (payload : Payload) : Bool :=
  payload.occurrence.valid && match payload with
  | .start _ _ query known | .answer _ query _ known =>
    digest query && known.source.identity == database
  | .finish .. => true

structure Entry where
  clock : Clock
  payload : Payload
  deriving BEq, ToJson, FromJson

def Entry.name (entry : Entry) : String :=
  Index.contentKey (entry.payload.kind, entry.payload.occurrence)

structure Turn where
  session : String
  turn : String
  deriving BEq, ToJson, FromJson

def Entry.turn (entry : Entry) : Turn :=
  ⟨entry.payload.occurrence.session, entry.payload.occurrence.turn⟩

def retainFirst (previous next : Entry) : Except String Entry :=
  if previous.payload.sameObservation next.payload then .ok previous
  else .error "conflicting native synaptic event"

theorem retry_keeps_first_observation (previous next accepted : Entry)
    (result : retainFirst previous next = .ok accepted) : accepted = previous := by
  unfold retainFirst at result
  split at result <;> simp_all

def completeKnowledge (known : Knowledge) (indexed : Bool) : Bool := !known.uncertain && indexed

theorem complete_knowledge_is_confirmed (known : Knowledge) (indexed : Bool)
    (complete : completeKnowledge known indexed = true) : known.uncertain = false ∧ indexed = true := by
  simpa [completeKnowledge, Bool.and_eq_true] using complete

def Turn.name (turn : Turn) : String := Index.contentKey turn

def implementation : String := Blake3.hex (Blake3.digest "eggshell.synaptic-journal".toUTF8 [
  Index.implementation.toUTF8, (include_str "SynapseJournal.lean").toUTF8,
  (include_str "PluginModel.lean").toUTF8, (include_str "SynapseLive.lean").toUTF8])

def directory (source : PageMap.Snapshot) : IO System.FilePath := do
  return (← Sidecar.locate source .user).directory / "synapses" / "events"

def open? (source : PageMap.Snapshot) : IO (Option PageMap.Snapshot) := do
  let some journal ← PageMap.open? (← directory source) | return none
  unless journal.head.authority == "private-synaptic-events:" ++ source.head.identity do
    throw (IO.userError "foreign synaptic event journal")
  return some journal

def prepare (source : PageMap.Snapshot) : IO PageMap.Snapshot := do
  let sidecar ← Sidecar.prepare (Sidecar.Owner.ofSnapshot source) .user
  let parent ← Sidecar.childDirectory sidecar.directory "synapses"
  let path := parent / "events"
  if let some journal ← PageMap.open? path then
    unless journal.head.authority == "private-synaptic-events:" ++ source.head.identity do
      throw (IO.userError "foreign synaptic event journal")
    return journal
  PageMap.create path ("private-synaptic-events:" ++ source.head.identity)

def maxBytes : Nat := 8 * 1024 * 1024

def entry (journal : PageMap.Snapshot) (ordinal : Nat) : IO Entry := do
  let count ← getNat journal.get (key "entry" ordinal)
  unless count ≤ maxBytes do throw (IO.userError "synaptic event exceeds its byte bound")
  let bytes ← readChunks journal journal.get "entry" ordinal
  let some text := String.fromUTF8? bytes | throw (IO.userError "invalid event UTF-8")
  let result ← IO.ofExcept (Json.parse text >>= fromJson? (α := Entry))
  unless (toJson result).compress.toUTF8 == bytes && result.payload.occurrence.valid &&
      digest result.clock.domain do throw (IO.userError "invalid or noncanonical synaptic event")
  return result

/-- First observed knowledge and time are immutable on identical retries.
Only one private B-tree publication adds the event and its turn posting. -/
def append (source : PageMap.Snapshot) (value : Entry) : IO Bool := do
  unless value.payload.valid source.head.identity && digest value.clock.domain do
    throw (IO.userError "invalid synaptic event identity")
  let bytes := (toJson value).compress.toUTF8
  unless bytes.size ≤ maxBytes do throw (IO.userError "synaptic event exceeds its byte bound")
  let journal ← prepare source
  let name := "event:" ++ value.name
  if let some previous ← journal.get name then
    let ordinal ← IO.ofExcept (payloadSize (some previous))
    let saved ← entry journal ordinal
    unless saved.name == value.name do throw (IO.userError "ambiguous event digest")
    let _ ← IO.ofExcept (retainFirst saved value)
    return false
  let (_, _, _) ← PageMap.withWriter journal fun writer => do
    let ordinal ← getNat writer.get "count"
    putChunks writer "entry" ordinal bytes
    putNat writer name ordinal
    putNat writer "count" (ordinal+1)
    let turn := value.turn
    writer.put ("turn:" ++ turn.name) (some ((toJson turn).compress.toUTF8))
    putNat writer (key ("posting:" ++ turn.name) ordinal) ordinal
    putNat writer ("latest:" ++ turn.name) (ordinal+1)
  return true

def turnEntries (journal : PageMap.Snapshot) (turn : Turn) : IO (Array Entry) := do
  let mut values := #[]
  for (ordinal, indexed) in ← Persistence.Store.directory journal ("posting:" ++ turn.name) do
    unless ordinal == indexed do throw (IO.userError "invalid event turn posting")
    let value ← entry journal ordinal
    unless value.turn == turn do throw (IO.userError "ambiguous event turn digest")
    values := values.push value
  return values.qsort fun a b => if a.clock.domain == b.clock.domain then a.clock.nanos < b.clock.nanos
    else a.clock.domain < b.clock.domain

def knowledge (source : PageMap.Snapshot) (known : List String) (uncertain : Bool)
    (archive : Option String := none) : IO Knowledge := do
  let indexed ← if let some reader ← Index.open? source .database .shared then
      pure (some ({head := reader.index.head, storage := .database, producer := reader.manifest.implementation} : IndexAt))
    else if let some reader ← Index.open? source .user .shared then
      pure (some ({head := reader.index.head, storage := .user, producer := reader.manifest.implementation} : IndexAt))
    else pure none
  return ⟨source.head, indexed, known, uncertain, archive⟩

def originalAt? (source : PageMap.Snapshot) (head : PageMap.Head) : IO (Option PageMap.Snapshot) := do
  if (← Build.changes source head).isNone then return none
  return some {source with head}

def indexAt? (source : PageMap.Snapshot) (known : Knowledge) : IO (Option Index.Reader) := do
  let some saved := known.indexed | return none
  let some current ← PageMap.open? (← Index.directory source saved.storage .shared) | return none
  unless current.head.identity == saved.head.identity && current.head.authority == saved.head.authority &&
      saved.head.bytes ≤ current.head.bytes do return none
  let index := {current with head := saved.head}
  let some manifest ← Index.manifest? index | return none
  unless manifest.implementation == saved.producer && saved.producer == Index.implementation &&
      manifest.scope == .shared && manifest.source.identity == source.head.identity do return none
  let some original ← originalAt? source known.source | return none
  unless ← Index.sameSources original manifest.source do return none
  return some ⟨index, manifest⟩

def ownerKeys (known : List String) : Array String :=
  (known.filterMap fun value => match value.splitOn ":" with
    | ["h", owner] | ["g", owner, _] | ["e", owner, _, _, _] => some owner
    | _ => none).eraseDups.toArray

def acknowledged (keys : List String) (doc : Document) (row : Read) : Bool :=
  keys.any fun value => match value.splitOn ":" with
    | ["h", owner] => owner == doc.owner
    | ["g", owner, result] => owner == doc.owner &&
        doc.source.any (fun text => Persistence.selectionKey (.text text) == result)
    | ["e", owner, result, first, limit] => owner == doc.owner &&
        doc.source.any (fun text => Persistence.selectionKey (.text text) == result) &&
        (first.toNat?).any (fun a => (limit.toNat?).any (fun b =>
          a ≤ row.binding.first && row.binding.limit ≤ b && a < b))
    | _ => false

def presentation (source : PageMap.Snapshot) (known : Knowledge) : IO Presentation := do
  let some original ← originalAt? source known.source | return {}
  let archive ← known.archive.bindM fun path => PageMap.open? (.mk path)
  let sources := #[original] ++ archive.toArray
  let mut ranges := #[]
  for snapshot in sources do
    let reader ← NodeReader.new snapshot
    for owner in ownerKeys known.acknowledged do
      let some id ← Build.ownerId? snapshot owner | continue
      let doc ← Build.document reader id
      let .ok rows := recordedRows snapshot.head.identity doc | continue
      ranges := ranges ++ (rows.filter (acknowledged known.acknowledged doc)).map (·.source)
  return {ranges := compactRanges ranges}

structure Replay where
  consumed : Array Fact := #[]
  usage : Array Fact := #[]
  consumers : Array Occurrence := #[]
  pending : Nat := 0
  unknown : Nat := 0
  origins : Array Provenance.Origin := #[]

def acceptPublishedOutput (ownerId : Option Nat) (previous observed : Trace) : Trace :=
  if ownerId.isSome then observed else previous

theorem unowned_output_keeps_public_trace (previous observed : Trace) :
    acceptPublishedOutput none previous observed = previous := rfl

/-- All original body/row work happens in the background. A finish without
an exact published native owner remains pending instead of inventing evidence. -/
def replay (source : PageMap.Snapshot) (values : Array Entry) (deadline : Nat) : IO Replay := do
  let mut result : Replay := {}
  let mut trace : Trace := {}
  let mut domain := ""
  let mut starts : Std.HashMap Occurrence (String × Knowledge) := {}
  let mut locations : Std.HashMap Occurrence (Array OutputRow) := {}
  let mut usage : Graph := .empty
  for value in values do
    if (← IO.monoMsNow) ≥ deadline then throw (IO.userError "synaptic replay deadline")
    if domain != value.clock.domain then
      let projected ← IO.ofExcept (trace.locate locations)
      result := {result with consumed := result.consumed ++ projected.graph.snapshot}
      trace := {}; starts := {}; locations := {}; domain := value.clock.domain
    if trace.lastOrdinal.any (value.clock.nanos < ·) then
      result := {result with unknown := result.unknown+1}
      continue
    match value.payload with
    | .start occurrence work query known =>
      let .ok command := workCommand work | result := {result with unknown := result.unknown+1}; continue
      trace ← IO.ofExcept (trace.start occurrence value.clock.nanos command)
      starts := starts.insert occurrence (query, known)
      result := {result with consumers := result.consumers.push occurrence}
    | .finish occurrence name input response archive =>
      if !trace.starts.contains occurrence then result := {result with unknown := result.unknown+1}; continue
      let tool : Plugin.ToolEvent := ⟨name, occurrence.useId, input, response, none⟩
      let some started := trace.starts[occurrence]? | throw (IO.userError "missing observed start")
      let .ok command := workCommand (Plugin.canonicalToolWork tool) |
        throw (IO.userError "native finish has no literal invocation")
      unless command == started.command do
        throw (IO.userError "native finish changed its observed invocation")
      let expected := (Plugin.compileOperationOutcomes (.text occurrence.session) (.text occurrence.turn) tool).2
      let localId ← findNode? source expected
      let localId ← localId.filterM fun id => return (← source.get (key "member" id)).isSome
      let located ← if let some id := localId then pure (some (source, id)) else do
        let some path := archive | pure none
        let some archived ← PageMap.open? (.mk path) | pure none
        let some id ← findNode? archived expected | pure none
        if (← archived.get (key "member" id)).isSome then pure (some (archived, id)) else pure none
      let some (recorded, id) := located | do
        if archive.isSome then result := {result with pending := result.pending+1}
        else result := {result with unknown := result.unknown+1}
        continue
      let currentOriginal := localId.isSome
      if currentOriginal then
        let origin : Provenance.Origin :=
          ⟨id, occurrence, value.clock.domain, started.ordinal, value.clock.nanos⟩
        result := {result with origins := result.origins.push origin}
      let originalReader ← NodeReader.new recorded
      let doc ← Build.document originalReader id
      unless doc.occurrences.contains occurrence && doc.workText == some (Plugin.canonicalToolWork tool) do
        throw (IO.userError "native synaptic observation changed its exact occurrence")
      let some raw := doc.source | result := {result with unknown := result.unknown+1}; continue
      let .ok output := layout raw | result := {result with unknown := result.unknown+1}; continue
      let completed ← IO.ofExcept (trace.finish occurrence value.clock.nanos output.text)
      -- Foreign private work can label usage of this DB's memory, but cannot
      -- publish its terms or consumption edges into the shared DB lane.
      trace := acceptPublishedOutput localId trace completed
      if let .ok reads := locateReads recorded.head.identity doc completed then
        if currentOriginal then locations := locations.insert occurrence (reads.flatMap (·.rows))
        if let some (query, known) := starts[occurrence]? then
          let storedIndex ← indexAt? source known
          let mut stored := #[]
          if let some index := storedIndex then
            let files := reads.foldl (fun files read => files.insert read.read.source.file) ({} : Std.HashSet File)
            for file in files do
              let found ← index.lookup (.file file) 100000 deadline
              unless found.complete do throw (IO.userError "incomplete stored-read evidence")
              stored := stored ++ found.facts.filterMap (fun fact => match fact with
                | .read read => if read.occurrence != occurrence then some read.source else none
                | _ => none)
          let shown ← presentation source known
          let uncertain := !(completeKnowledge known storedIndex.isSome)
          if uncertain then
            result := {result with unknown := result.unknown+1}
            continue
          let feedback : Feedback := ({graph := usage, delivered := shown} : Feedback).start occurrence
          let feedback ← IO.ofExcept (feedback.completedRead occurrence query (reads.map (·.read.source)) stored)
          usage := feedback.graph
    | .answer occurrence query text known =>
      if known.uncertain then result := {result with unknown := result.unknown+1}; continue
      let shown ← presentation source known
      let feedback ← IO.ofExcept (({graph := usage, delivered := shown} : Feedback).answer occurrence query text)
      usage := feedback.graph
  let projected ← IO.ofExcept (trace.locate locations)
  return {result with consumed := result.consumed ++ projected.graph.snapshot, usage := usage.snapshot}

structure Checkpoint where
  source : PageMap.Head
  index : String
  count : Nat
  implementation : String
  deriving BEq, ToJson, FromJson

def lane (storage : Sidecar.Storage) : String := if storage == .database then "database" else "user"

def checkpoint? (journal : PageMap.Snapshot) (name : String) : IO (Option Checkpoint) := do
  (← journal.get name).mapM (Index.decode (α := Checkpoint))

def Checkpoint.sameInput (previous : Checkpoint) (source : PageMap.Snapshot)
    (index : String) (count : Nat) (limit : Nat := 16) : IO Bool := do
  unless previous.index == index && previous.count == count &&
      previous.implementation == Eggshell.Synapses.Journal.implementation do return false
  Index.sameSources source previous.source limit

def mark (source : PageMap.Snapshot) (name : String) (checkpoint : Checkpoint) : IO Unit := do
  let journal ← prepare source
  let bytes ← Index.checkedBytes checkpoint
  let _ ← PageMap.withWriter journal fun writer => do
    if (← writer.get name) != some bytes then writer.put name (some bytes)

/-- Constant metadata probe; no journal entries or original bodies are read. -/
def required (source : PageMap.Snapshot) (storage : Sidecar.Storage := .database) : IO Bool := do
  let some journal ← open? source | return false
  let some reader ← Index.open? source storage .shared | return true
  let some previous ← checkpoint? journal ("checkpoint:" ++ lane storage) | return true
  return !(← previous.sameInput source reader.index.head.identity (← getNat journal.get "count"))

structure Result where
  turns : Nat := 0
  consumed : Nat := 0
  usage : Nat := 0
  pending : Nat := 0
  unknown : Nat := 0
  complete : Bool := true
  deriving ToJson, FromJson

def publish (source : PageMap.Snapshot) (storage : Sidecar.Storage) (result : Replay) (deadline : Nat) : IO Unit := do
  let some shared ← Index.open? source storage .shared | throw (IO.userError "synaptic source index is not warm")
  let mut old := #[]
  for consumer in result.consumers.toList.eraseDups do
    let found ← shared.lookup (.consumer consumer) 100000 deadline
    unless found.complete do throw (IO.userError "incomplete consumer retirement evidence")
    old := old ++ found.facts
  let previous := old.foldl (fun set fact => set.insert fact) ({} : Std.HashSet Fact)
  let wanted := result.consumed.foldl (fun set fact => set.insert fact) ({} : Std.HashSet Fact)
  let _ ← Index.publishDelta source storage .shared (some shared.manifest.source) {
    removed := old.filter (!wanted.contains ·), added := result.consumed.filter (!previous.contains ·) }
  if result.usage.isEmpty then return
  if let some usageReader ← Index.open? source .user .usage then
    let _ ← Index.publishDelta source .user .usage (some usageReader.manifest.source) {added := result.usage}
  else
    let cache ← Index.prepare source .user .usage
    let _ ← Index.replace source .user .usage ((← Index.allFacts cache) ++ result.usage)

/-- Background replay is bounded by turns and a deadline. Publication is
idempotent; checkpoint failure leaves the same immutable events replayable. -/
def refresh (source : PageMap.Snapshot) (storage : Sidecar.Storage) (deadline : Nat)
    (limit : Nat := 8) : IO Result := do
  let _ ← Build.refresh source storage
  let some journal ← open? source | return {}
  let some reader ← Index.open? source storage .shared | throw (IO.userError "synaptic source index is not warm")
  let count ← getNat journal.get "count"
  let expected : Checkpoint := ⟨source.head, reader.index.head.identity, count, implementation⟩
  let checkpointKey := "checkpoint:" ++ lane storage
  if let some previous ← checkpoint? journal checkpointKey then
    if ← previous.sameInput source expected.index count (source.head.revision-previous.source.revision+1) then
      if previous != expected then mark source checkpointKey expected
      return {}
  let turns ← journal.foldRange ⟨"turn:", "turn;"⟩ (fun turns row => do
    let some bytes := row.2 | return turns
    let turn ← Index.decode (α := Turn) bytes
    unless row.1 == "turn:" ++ turn.name do throw (IO.userError "foreign event turn directory")
    return turns.push turn) #[]
  let mut result : Result := {}
  let mut current := source
  for turn in turns do
    let checkpoint : Checkpoint := ⟨source.head, reader.index.head.identity, ← getNat journal.get ("latest:" ++ turn.name), implementation⟩
    let turnKey := "processed:" ++ lane storage ++ ":" ++ turn.name
    if let some previous ← checkpoint? journal turnKey then
      if ← previous.sameInput source checkpoint.index checkpoint.count (source.head.revision-previous.source.revision+1) then continue
    if result.turns ≥ limit || (← IO.monoMsNow) ≥ deadline then
      result := {result with complete := false}
      break
    let replayed ← replay current (← turnEntries journal turn) deadline
    if storage == .database && !replayed.origins.isEmpty then
      let updated ← Provenance.publish current replayed.origins
      if updated.head != current.head then
        current := updated
        let _ ← Build.refresh current storage
        pure ()
    publish current storage replayed deadline
    if replayed.pending == 0 then mark current turnKey checkpoint
    else result := {result with complete := false}
    result := {result with
      turns := result.turns+1, consumed := result.consumed+replayed.consumed.size
      usage := result.usage+replayed.usage.size, pending := result.pending+replayed.pending, unknown := result.unknown+replayed.unknown}
  if result.complete then mark current checkpointKey expected
  return result

/-- Native maintenance has no executable or numerical-provider configuration. -/
structure Target where
  owner : Sidecar.Owner
  storage : Sidecar.Storage
  deriving BEq, ToJson, FromJson

def registry : IO System.FilePath := do return (← Paths.dataRoot) / "synaptic-targets"

def register (source : PageMap.Snapshot) (writable : Bool) : IO Unit := do
  let owner := Sidecar.Owner.ofSnapshot source
  let (storage, _) ← Sidecar.destination owner writable
  let target : Target := ⟨owner, storage⟩
  let root ← registry
  FileSystem.rejectSymlinkAncestors root
  FileSystem.privateDirectory root
  FileSystem.immutableBytes (root / (Index.contentKey target ++ ".json")) (← Index.checkedBytes target)

def targets : IO (Array (System.FilePath × Target)) := do
  let root ← registry
  if !(← root.pathExists) then return #[]
  let mut result := #[]
  for entry in ← root.readDir do
    if !entry.fileName.endsWith ".json" then continue
    try
      let bytes ← FileSystem.boundedBytes entry.path 65536
      let target ← Index.decode (α := Target) bytes
      unless entry.fileName == Index.contentKey target ++ ".json" do
        throw (IO.userError "foreign native maintenance target")
      result := result.push (entry.path, target)
    catch error => IO.eprintln s!"Eggshell retained an unreadable native maintenance target: {error}"
  return result

end Eggshell.Synapses.Journal
