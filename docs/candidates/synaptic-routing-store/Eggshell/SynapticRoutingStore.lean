module

public import Eggshell.SynapticRouting

@[expose] public section
namespace Eggshell.Synapses.Routing.Store
open Lean DB Recommend

deriving instance FromJson for Target

def implementation : String := Blake3.hex (Blake3.digest "eggshell.routing-store".toUTF8 [
  (include_str "SynapticRoutingStore.lean").toUTF8,
  (include_str "SynapticRouting.lean").toUTF8, Index.implementation.toUTF8])

/-- This is an advisory projection, never an Outcome or a completion proof.
The original fact remains in the pinned source index and is not copied. -/
structure Arc where
  evidence : String
  kind : Nat
  group : Option Nat
  targets : Array Nat
  next : Array Nat
  deriving BEq

def arcCodec : Wire.Codec Arc :=
  (Wire.text.product (Wire.natural.product ((Wire.optional Wire.natural).product
    ((Wire.list Wire.natural).product (Wire.list Wire.natural))))).iso
    (fun arc => (arc.evidence,arc.kind,arc.group,arc.targets.toList,arc.next.toList))
    (fun (evidence,kind,group,targets,next) => ⟨evidence,kind,group,targets.toArray,next.toArray⟩)
    (by intro arc; cases arc; simp)

theorem arc_roundtrip (arc : Arc) (tail : List UInt8) :
    arcCodec.decode (arcCodec.encode arc ++ tail) = .ok (arc,tail) :=
  arcCodec.roundtrip arc tail

def encode (arc : Arc) : ByteArray := (arcCodec.encode arc).toByteArray

def decode (payload : ByteArray) : IO Arc := do
  unless payload.size ≤ Index.payloadLimit do throw (IO.userError "routing arc exceeds its bound")
  let (arc,rest) ← IO.ofExcept (arcCodec.decode payload.toList)
  unless rest.isEmpty && encode arc == payload && digest arc.evidence && arc.kind < 6 &&
      (arc.kind == 0 || arc.kind == 2) == arc.group.isSome do
    throw (IO.userError "invalid or noncanonical routing arc")
  return arc

def kind : Fact → Nat
  | .supports _ => 0
  | .consumed _ => 1
  | .coquoted .. => 2
  | .used usage => match usage.kind with
    | .omittedThenRead => 3
    | .omittedThenConsumed => 4
    | _ => 5
  | .read _ => 0

def kindName : Nat → String
  | 0 => "support" | 1 => "consumption" | 2 => "coquotation"
  | 3 => "omitted_then_read" | 4 => "omitted_then_consumed"
  | _ => "delivered_then_cited"

structure Node where
  key : Index.Key
  id : Nat
  deriving ToJson, FromJson

structure Destination where
  target : Target
  id : Nat
  deriving ToJson, FromJson

structure Counts where
  facts : Nat := 0
  nodes : Nat := 0
  targets : Nat := 0
  arcs : Nat := 0
  deriving ToJson, FromJson

structure Manifest where
  basis : PageMap.Head
  source : PageMap.Head
  scope : Index.Scope
  implementation : String
  counts : Counts
  deriving ToJson, FromJson

def arcPrefix (node : Nat) : String := s!"arc:{node}:"
def arcName (node : Nat) (identity : String) : String := arcPrefix node ++ identity

def put [ToJson α] (writer : PageMap.Writer) (key : String) (value : α) : IO Unit := do
  writer.put key (some (← Index.checkedBytes value))

def counts (writer : PageMap.Writer) : IO Counts := do
  match ← writer.get "counts" with
  | some bytes => Index.decode bytes
  | none => pure {}

def internNode (writer : PageMap.Writer) (key : Index.Key) : IO Nat := do
  let name := "key:" ++ Index.contentKey key
  if let some bytes ← writer.get name then
    let node ← Index.decode (α := Node) bytes
    unless node.key == key do throw (IO.userError "routing node digest ambiguity")
    return node.id
  let previous ← counts writer
  let node : Node := ⟨key,previous.nodes⟩
  put writer name node
  put writer s!"node:{node.id}" node
  put writer "counts" {previous with nodes := previous.nodes+1}
  return node.id

def internDestination (writer : PageMap.Writer) (target : Target) : IO Nat := do
  let name := "destination:" ++ Index.contentKey target
  if let some bytes ← writer.get name then
    let destination ← Index.decode (α := Destination) bytes
    unless destination.target == target do throw (IO.userError "routing target digest ambiguity")
    return destination.id
  let previous ← counts writer
  let destination : Destination := ⟨target,previous.targets⟩
  put writer name destination
  put writer s!"target:{destination.id}" destination
  put writer "counts" {previous with targets := previous.targets+1}
  return destination.id

/-- Only checked facts feed the projection. Full original evidence is kept in
the original index; the new rows contain handles and graph incidence only. -/
def insert (writer : PageMap.Writer) (fact : Fact) : IO Unit := do
  unless fact.valid do throw (IO.userError "invalid routing source fact")
  let identity := Index.contentKey fact
  if (← writer.get ("fact:" ++ identity)).isSome then return
  let mut arcs := 0
  for key in Index.addresses fact do
    let step := Routing.project key fact
    if step.targets.isEmpty && step.next.isEmpty then continue
    let id ← internNode writer key
    let targets ← step.targets.mapM (internDestination writer)
    let next ← step.next.mapM (internNode writer)
    let group ← match fact with
      | .supports support => pure (some (← internNode writer (.group (.claim support.claim))))
      | .coquoted group _ => pure (some (← internNode writer (.group group)))
      | _ => pure none
    let arc : Arc := ⟨identity,kind fact,group,targets,next⟩
    let payload := encode arc
    unless payload.size ≤ Index.payloadLimit do throw (IO.userError "routing arc exceeds its bound")
    writer.put (arcName id identity) (some payload)
    arcs := arcs+1
  writer.put ("fact:" ++ identity) (some ByteArray.empty)
  let previous ← counts writer
  put writer "counts" {previous with facts := previous.facts+1,arcs := previous.arcs+arcs}

structure Reader where
  snapshot : PageMap.Snapshot
  manifest : Manifest

def open? (basis : Index.Reader) (directory : System.FilePath) : IO (Option Reader) := do
  let some snapshot ← PageMap.open? directory | return none
  let some bytes ← snapshot.get "manifest" | return none
  let manifest ← Index.decode (α := Manifest) bytes
  unless manifest.basis == basis.index.head && manifest.source == basis.manifest.source &&
      manifest.scope == basis.manifest.scope && manifest.implementation == implementation &&
      manifest.counts.facts == basis.manifest.facts do return none
  return some ⟨snapshot,manifest⟩

/-- Initial construction streams immutable fact pages in bounded batches.
Interrupted construction has no ready manifest and cannot be opened. This
prototype deliberately does not substitute a full rebuild for delta updates. -/
def build (basis : Index.Reader) (directory : System.FilePath) (batchSize : Nat := 1024)
    (batchBytes : Nat := 8*1024*1024) : IO Reader := do
  unless 0 < batchSize && batchSize ≤ 1024 && Index.payloadLimit ≤ batchBytes &&
      batchBytes ≤ 8*1024*1024 && !(← directory.pathExists) do
    throw (IO.userError "fresh routing directory and bounded fact/byte batch required")
  let snapshot ← PageMap.create directory ("routing:" ++ basis.index.head.identity)
  let current ← IO.mkRef snapshot
  let flush := fun (facts : Array Fact) => do
    let (_,_,_) ← PageMap.withWriter (← current.get) fun writer =>
      facts.forM (insert writer)
    current.set (← PageMap.pin directory)
  let remaining ← basis.index.foldRange ⟨"fact:","fact;"⟩ (fun (pending,cost) row => do
    let some bytes := row.2 | return (pending,cost)
    let fact ← Index.decode (α := Fact) bytes
    unless row.1 == Index.factName fact && fact.valid && basis.manifest.scope.accepts fact &&
        Index.belongs basis.manifest.source.identity fact do
      throw (IO.userError "source routing fact is not bound to the pinned index")
    let (pending,cost) ← if cost+bytes.size > batchBytes && !pending.isEmpty then do
        flush pending
        pure (#[],0)
      else pure (pending,cost)
    let pending := pending.push fact
    if pending.size < batchSize then return (pending,cost+bytes.size)
    flush pending
    return (#[],0)) ((#[],0) : Array Fact × Nat)
  if !remaining.1.isEmpty then flush remaining.1
  let (_,_,_) ← PageMap.withWriter (← current.get) fun writer => do
    let total ← counts writer
    unless total.facts == basis.manifest.facts do throw (IO.userError "routing source coverage mismatch")
    put writer "manifest" ({
      basis := basis.index.head
      source := basis.manifest.source
      scope := basis.manifest.scope
      implementation
      counts := total} : Manifest)
  let some ready ← open? basis directory | throw (IO.userError "routing publication did not seal")
  return ready

structure Scan where
  arcs : Array Arc := #[]
  bytes : Nat := 0
  pages : Nat := 0
  complete : Bool := true

def scanAt (reader : Reader) (ref : PageMap.Ref) (node : Nat)
    (limit byteLimit deadline : Nat) (initial : Scan) : IO Scan := do
  if !initial.complete then return initial
  if initial.arcs.size ≥ limit || initial.bytes ≥ byteLimit || (← IO.monoMsNow) ≥ deadline then
    return {initial with complete := false}
  let loaded ← reader.snapshot.load ref
  let range : PageMap.KeyRange := ⟨arcPrefix node,s!"arc:{node};"⟩
  let mut result := {initial with pages := initial.pages+1}
  match loaded.page with
  | .leaf rows =>
    for (name,payload) in range.select rows do
      let some payload := payload | continue
      if result.arcs.size ≥ limit || result.bytes+payload.size > byteLimit ||
          (← IO.monoMsNow) ≥ deadline then return {result with complete := false}
      let arc ← decode payload
      unless name == arcName node arc.evidence && arc.targets.all (· < reader.manifest.counts.targets) &&
          arc.next.all (· < reader.manifest.counts.nodes) &&
          arc.group.all (· < reader.manifest.counts.nodes) do throw (IO.userError "foreign routing incidence")
      result := {result with arcs := result.arcs.push arc,bytes := result.bytes+payload.size}
    return result
  | .branch children =>
    for child in children do
      if range.overlaps child then
        if _smaller : child.height < ref.height then
          result ← scanAt reader child node limit byteLimit deadline result
        else throw (IO.userError "routing page height did not decrease")
        if !result.complete then return result
    return result
termination_by ref.height

structure RawHint where
  target : Nat
  priority : Nat
  evidence : String
  kind : Nat
  group : Option Nat
  lane : Nat

/-- A projection hint is intentionally a different type from checked Offer
and from every e-graph certification type. -/
structure Hint where
  target : Target
  priority : Nat
  evidence : String
  kind : Nat
  group : Option Group

inductive QuotedCause where
  | quoted (group : Group)
  deriving ToJson

def Hint.reasonKey (hint : Hint) : String := match hint.group with
  | some group => Index.contentKey (QuotedCause.quoted group)
  | none => hint.evidence

def Hint.json (hint : Hint) : Json := Json.mkObj [
  ("target",toJson hint.target),("source",toJson hint.target.source?),
  ("priority",toJson hint.priority),("kind",toJson (kindName hint.kind)),
  ("evidence",toJson hint.evidence)]

structure Walk where
  hints : Array Hint := #[]
  nodes : Nat := 0
  arcs : Nat := 0
  bytes : Nat := 0
  complete : Bool := true

structure Limits where
  nodes : Nat := 65536
  arcs : Nat := 262144
  hints : Nat := 262144
  queue : Nat := 524288
  bytes : Nat := 32*1024*1024

def Reader.destination (reader : Reader) (id : Nat) : IO (Target × Nat) := do
  let some bytes ← reader.snapshot.get s!"target:{id}" |
    throw (IO.userError "missing routing destination")
  let destination ← Index.decode (α := Destination) bytes
  unless destination.id == id do throw (IO.userError "routing destination moved")
  return (destination.target,bytes.size)

def Reader.group (reader : Reader) (id : Nat) : IO (Group × Nat) := do
  let some bytes ← reader.snapshot.get s!"node:{id}" |
    throw (IO.userError "missing routing group")
  let node ← Index.decode (α := Node) bytes
  unless node.id == id do throw (IO.userError "routing group moved")
  let .group group := node.key | throw (IO.userError "routing cause is not a group")
  return (group,bytes.size)

def Reader.locate (reader : Reader) (key : Index.Key) : IO (Option Nat × Nat) := do
  let some bytes ← reader.snapshot.get ("key:" ++ Index.contentKey key) | return (none,0)
  let root ← Index.decode (α := Node) bytes
  unless root.key == key && root.id < reader.manifest.counts.nodes do
    throw (IO.userError "routing root differs from its address")
  return (some root.id,bytes.size)

/-- Private usage supplies query roots. Its descendants return to the shared
relation, exactly as the original reader dispatch does for non-query keys. -/
def walk (shared : Reader) (usage : Option Reader) (roots : Array (Index.Key × Nat))
    (deadline : Nat) (limits : Limits := {}) : IO Walk := do
  if let some usage := usage then
    unless shared.manifest.scope == .shared && usage.manifest.scope == .usage &&
        shared.manifest.source.identity == usage.manifest.source.identity &&
        shared.manifest.source.authority == usage.manifest.source.authority do
      throw (IO.userError "routing overlay has a different source or privacy scope")
  let readerFor := fun (lane : Nat) => if lane == 0 then shared else usage.getD shared
  let locate := fun (key : Index.Key) => do
    let lane := match key with | .query _ => if usage.isSome then 1 else 0 | _ => 0
    let (id,bytes) ← (readerFor lane).locate key
    pure (id.map (lane,·),bytes)
  let roots := roots.qsort fun a b =>
    if a.2 == b.2 then (toJson a.1).compress < (toJson b.1).compress else a.2 < b.2
  let mut seen : Std.HashSet (Nat × Nat) := {}
  let mut result : Walk := {}
  let mut pending : Array RawHint := #[]
  for (key,priority) in roots do
    if (← IO.monoMsNow) ≥ deadline then return {result with complete := false}
    let (root,bytes) ← locate key
    if result.bytes+bytes > limits.bytes then return {result with complete := false}
    result := {result with bytes := result.bytes+bytes}
    let some root := root | continue
    let mut queue := #[root]
    let mut position := 0
    while position < queue.size do
      let (lane,node) := queue[position]!
      position := position+1
      if seen.contains (lane,node) then continue
      if result.nodes ≥ limits.nodes || result.arcs ≥ limits.arcs ||
          result.bytes ≥ limits.bytes || (← IO.monoMsNow) ≥ deadline then
        return {result with complete := false}
      seen := seen.insert (lane,node)
      let reader := readerFor lane
      let scanned ← match reader.snapshot.head.root with
        | none => pure ({} : Scan)
        | some ref => scanAt reader ref node (limits.arcs-result.arcs) (limits.bytes-result.bytes) deadline {}
      result := {result with
        nodes := result.nodes+1
        arcs := result.arcs+scanned.arcs.size
        bytes := result.bytes+scanned.bytes}
      unless scanned.complete do return {result with complete := false}
      for arc in scanned.arcs do
        if pending.size+arc.targets.size > limits.hints || queue.size+arc.next.size > limits.queue then
          return {result with complete := false}
        pending := pending ++ arc.targets.map (fun target => ⟨target,priority,arc.evidence,arc.kind,arc.group,lane⟩)
        if lane == 0 then queue := queue ++ arc.next.map (0,·)
        else
          for next in arc.next do
            let some bytes ← reader.snapshot.get s!"node:{next}" |
              throw (IO.userError "missing private routing descendant")
            let node ← Index.decode (α := Node) bytes
            unless node.id == next do throw (IO.userError "private routing descendant moved")
            let (destination,cost) ← locate node.key
            if result.bytes+bytes.size+cost > limits.bytes then return {result with complete := false}
            result := {result with bytes := result.bytes+bytes.size+cost}
            if let some destination := destination then queue := queue.push destination
  -- Group by target before materializing, so repeated evidence for one
  -- range does not trigger repeated metadata reads or unbounded caches.
  let ordered := (pending.mapIdx (fun ordinal hint => (ordinal,hint))).qsort fun a b =>
    if a.2.lane == b.2.lane then a.2.target < b.2.target else a.2.lane < b.2.lane
  let mut previous : Option ((Nat × Nat) × Target) := none
  let mut groups : Std.HashMap (Nat × Nat) Group := {}
  let mut displayed : Array (Nat × Hint) := #[]
  for (ordinal,hint) in ordered do
    if (← IO.monoMsNow) ≥ deadline then return {result with complete := false}
    let reader := readerFor hint.lane
    let (target,bytes) ← match previous with
      | some (id,target) => if id == (hint.lane,hint.target) then pure (target,0) else reader.destination hint.target
      | none => reader.destination hint.target
    if result.bytes+bytes > limits.bytes then return {result with complete := false}
    result := {result with bytes := result.bytes+bytes}
    let (group,groupBytes) ← match hint.group with
      | none => pure (none,0)
      | some id =>
        if let some group := groups[(hint.lane,id)]? then pure (some group,0)
        else do
          let (group,bytes) ← reader.group id
          pure (some group,bytes)
    if result.bytes+groupBytes > limits.bytes then return {result with complete := false}
    result := {result with bytes := result.bytes+groupBytes}
    if groupBytes > 0 then
      if let some id := hint.group then
        if let some group := group then groups := groups.insert (hint.lane,id) group
    previous := some ((hint.lane,hint.target),target)
    displayed := displayed.push (ordinal,⟨target,hint.priority,hint.evidence,hint.kind,group⟩)
  return {result with hints := (displayed.qsort (fun a b => a.1 < b.1)).map Prod.snd}

def Reader.walk (reader : Reader) (roots : Array (Index.Key × Nat))
    (deadline : Nat) (limits : Limits := {}) : IO Walk :=
  _root_.Eggshell.Synapses.Routing.Store.walk reader none roots deadline limits

end Eggshell.Synapses.Routing.Store
