module

public import Std.Data.HashSet.Lemmas
public import Lean.Data.Json.FromToJson

@[expose] public section

namespace Eggshell.Synapses
open Lean

/-- Recommendation evidence has no import of Value, Match or Union authority. -/
structure File where
  relative : String
  fingerprint : String
  bytes : Nat
  deriving Inhabited, Repr, DecidableEq, BEq, ReflBEq, LawfulBEq, Hashable, ToJson, FromJson

def safeRelative (path : String) : Bool :=
  !path.isEmpty && !path.startsWith "/" && !path.contains '\x00' &&
    (path.splitOn "/").all (fun part => !part.isEmpty && part != "." && part != "..")

def digest (text : String) : Bool :=
  text.length == 64 && text.toList.all (fun c => c.isDigit || ('a' ≤ c && c ≤ 'f'))

def File.valid (file : File) : Bool := safeRelative file.relative && digest file.fingerprint

/-- Exact immutable output identity. A Work hash and its entire saved payload
identify data across sessions without equating operations or their authority. -/
structure Original where
  work : String
  content : String
  chars : Nat
  deriving Inhabited, Repr, DecidableEq, BEq, ReflBEq, LawfulBEq, Hashable, ToJson, FromJson

def Original.valid (original : Original) : Bool :=
  !original.work.isEmpty && digest original.content

inductive Subject where
  | file (file : File)
  | original (original : Original)
  deriving Inhabited, Repr, DecidableEq, BEq, ReflBEq, LawfulBEq, Hashable, ToJson, FromJson

instance : Coe File Subject := ⟨Subject.file⟩

def Subject.valid : Subject → Bool
  | .file data => data.valid
  | .original data => data.valid

def Subject.file? : Subject → Option File
  | .file data => some data
  | .original _ => none

def Subject.sameLocation (left right : Subject) : Bool := match left,right with
  | .file a,.file b => a.relative == b.relative
  | .original a,.original b => a.work == b.work
  | _,_ => false

/-- Closed intervals over immutable subjects. File coordinates are line
numbers; original-output coordinates are one-based character positions. -/
structure Range where
  subject : Subject
  first : Nat
  last : Nat
  deriving Inhabited, Repr, DecidableEq, BEq, ReflBEq, LawfulBEq, Hashable, ToJson, FromJson

def Range.valid (range : Range) : Bool :=
  range.subject.valid && 0 < range.first && range.first ≤ range.last &&
    match range.subject with | .file _ => true | .original original => range.last ≤ original.chars

def Range.file? (range : Range) : Option File := range.subject.file?

def Range.original (original : Original) (first limit : Nat) : Range :=
  ⟨.original original,first+1,limit⟩

def Range.contains (outer inner : Range) : Bool :=
  outer.subject == inner.subject && outer.first ≤ inner.first && inner.last ≤ outer.last

theorem Range.contains_self (range : Range) : range.contains range = true := by
  simp [Range.contains]

/-- A saved part of a citation must lie in both original intervals. The
fingerprint is part of equality; a path match alone cannot make an overlap. -/
def Range.intersection? (left right : Range) : Option Range :=
  let source := {left with first := max left.first right.first, last := min left.last right.last}
  if source.valid && left.contains source && right.contains source then some source else none

theorem Range.intersection_within {left right source : Range}
    (found : left.intersection? right = some source) :
    source.valid = true ∧ left.contains source = true ∧ right.contains source = true := by
  unfold intersection? at found
  dsimp only at found
  split at found
  · rename_i valid
    simp only [Option.some.injEq] at found
    subst source
    simpa only [Bool.and_eq_true, and_assoc] using valid
  · contradiction

structure Occurrence where
  session : String
  turn : String
  useId : String
  deriving Inhabited, Repr, DecidableEq, BEq, ReflBEq, LawfulBEq, Hashable, ToJson, FromJson

def Occurrence.valid (occurrence : Occurrence) : Bool :=
  !occurrence.session.isEmpty && !occurrence.turn.isEmpty && !occurrence.useId.isEmpty

structure Binding where
  database : String
  owner : String
  work : String
  first : Nat
  limit : Nat
  deriving Inhabited, Repr, DecidableEq, BEq, ReflBEq, LawfulBEq, Hashable, ToJson, FromJson

def Binding.valid (binding : Binding) : Bool :=
  !binding.database.isEmpty && !binding.owner.isEmpty && !binding.work.isEmpty &&
    binding.first < binding.limit

structure Read where
  occurrence : Occurrence
  source : Range
  binding : Binding
  /-- Selector keys only. Rebuild rechecks the original quoted spelling. -/
  quotations : Array String := #[]
  deriving Inhabited, Repr, DecidableEq, BEq, ReflBEq, LawfulBEq, Hashable, ToJson, FromJson

def Read.valid (read : Read) : Bool :=
  read.occurrence.valid && read.source.valid && read.binding.valid && read.quotations.all digest &&
    match read.source.subject with
    | .file _ => true
    | .original original => original.work == read.binding.work &&
        read.source.first == read.binding.first+1 && read.source.last == read.binding.limit

theorem original_read_binding (read : Read) (original : Original)
    (kind : read.source.subject = .original original) (valid : read.valid = true) :
    original.work = read.binding.work ∧ read.source.first = read.binding.first+1 ∧
      read.source.last = read.binding.limit := by
  have checked := valid
  simp only [Read.valid,kind,Bool.and_eq_true,beq_iff_eq] at checked
  simpa only [and_assoc] using checked.2

structure Claim where
  database : String
  answer : String
  first : Nat
  limit : Nat
  deriving Inhabited, Repr, DecidableEq, BEq, ReflBEq, LawfulBEq, Hashable, ToJson, FromJson

def Claim.valid (claim : Claim) : Bool :=
  !claim.database.isEmpty && !claim.answer.isEmpty && claim.first < claim.limit

structure Support where
  read : Read
  source : Range
  claim : Claim
  binding : Binding
  /-- The original citation can be wider than the part present in this read. -/
  cited : Range := source
  deriving Inhabited, Repr, DecidableEq, BEq, ReflBEq, LawfulBEq, Hashable, ToJson, FromJson

def Support.valid (support : Support) : Bool :=
  support.read.valid && support.source.valid && support.claim.valid &&
    support.binding.valid && support.binding.database == support.read.binding.database &&
    support.binding.owner == support.read.binding.owner && support.binding.work == support.read.binding.work &&
    support.read.binding.first ≤ support.binding.first && support.binding.limit ≤ support.read.binding.limit &&
    support.cited.valid && support.cited.contains support.source &&
    support.read.source.contains support.source

/-- The constructor checks the exact saved read covers the cited source range. -/
def Support.checked (read : Read) (source : Range) (claim : Claim)
    (binding : Binding := read.binding) (cited : Range := source) : Except String Support :=
  let support := Support.mk read source claim binding cited
  if support.valid then .ok support else .error "citation is not covered by its recorded read"

theorem Support.checked_covers {read : Read} {source : Range} {claim : Claim}
    {binding : Binding} {cited : Range} {support : Support}
    (checked : Support.checked read source claim binding cited = .ok support) :
    read.source.contains source = true := by
  unfold Support.checked at checked
  dsimp only at checked
  split at checked
  next valid =>
    simp only [Support.valid, Bool.and_eq_true] at valid
    exact valid.2
  next => contradiction

theorem Support.checked_within_citation {read : Read} {source : Range} {claim : Claim}
    {binding : Binding} {cited : Range} {support : Support}
    (checked : Support.checked read source claim binding cited = .ok support) :
    cited.contains source = true := by
  unfold Support.checked at checked
  dsimp only at checked
  split at checked
  next valid =>
    simp only [Support.valid, Bool.and_eq_true] at valid
    exact valid.1.2
  next => contradiction

inductive WitnessKind where
  | value | pathLine | path | identifier
  deriving Inhabited, Repr, DecidableEq, BEq, ReflBEq, LawfulBEq, Hashable, ToJson, FromJson

inductive DataFormat where
  | text | json
  deriving Inhabited, Repr, DecidableEq, BEq, ReflBEq, LawfulBEq, Hashable, ToJson, FromJson

structure Consumption where
  producer : Occurrence
  consumer : Occurrence
  producerFinish : Nat
  consumerStart : Nat
  kind : WitnessKind
  term : String
  inputFirst : Nat
  inputLimit : Nat
  outputFirst : Nat
  outputLimit : Nat
  inputFormat : DataFormat := .text
  outputFormat : DataFormat := .text
  /-- Only rows located in the actual producer output, never its entire read. -/
  rows : Array Range := #[]
  deriving Inhabited, Repr, DecidableEq, BEq, ReflBEq, LawfulBEq, Hashable, ToJson, FromJson

def Consumption.valid (edge : Consumption) : Bool :=
  edge.producer.valid && edge.consumer.valid && edge.producer != edge.consumer &&
    edge.producerFinish < edge.consumerStart && !edge.term.isEmpty &&
    edge.inputFirst < edge.inputLimit && edge.outputFirst < edge.outputLimit &&
    edge.rows.all Range.valid

def Consumption.checked (edge : Consumption) : Except String Consumption :=
  if edge.valid then .ok edge else .error "unavailable or invalid producer output"

theorem Consumption.checked_before {edge accepted : Consumption}
    (checked : edge.checked = .ok accepted) : edge.producerFinish < edge.consumerStart := by
  unfold Consumption.checked at checked
  split at checked
  next valid =>
    simp only [Consumption.valid, Bool.and_eq_true, decide_eq_true_eq] at valid
    exact valid.1.1.1.1.2
  next => contradiction

inductive Group where
  | answer (database owner : String)
  | claim (claim : Claim)
  deriving Inhabited, Repr, DecidableEq, BEq, ReflBEq, LawfulBEq, Hashable, ToJson, FromJson

def Group.valid : Group → Bool
  | .answer database owner => !database.isEmpty && !owner.isEmpty
  | .claim value => value.valid

inductive UsageKind where
  | omittedThenRead | deliveredThenCited | reread | sourceChanged
  deriving Inhabited, Repr, DecidableEq, BEq, ReflBEq, LawfulBEq, Hashable, ToJson, FromJson

def UsageKind.label : UsageKind → String
  | .omittedThenRead => "omitted_then_read"
  | .deliveredThenCited => "delivered_then_cited"
  | .reread => "reread"
  | .sourceChanged => "source_changed"

structure Event where
  occurrence : Occurrence
  ordinal : Nat
  deriving Inhabited, Repr, DecidableEq, BEq, ReflBEq, LawfulBEq, Hashable, ToJson, FromJson

structure Usage where
  event : Event
  /-- Opaque digest, never a plaintext question in a shared DB. -/
  query : String
  source : Range
  kind : UsageKind
  deriving Inhabited, Repr, DecidableEq, BEq, ReflBEq, LawfulBEq, Hashable, ToJson, FromJson

def Usage.valid (usage : Usage) : Bool :=
  usage.event.occurrence.valid && digest usage.query && usage.source.valid

inductive Fact where
  | read (read : Read)
  | consumed (edge : Consumption)
  | supports (support : Support)
  | coquoted (group : Group) (source : Range)
  | used (usage : Usage)
  deriving Inhabited, Repr, DecidableEq, BEq, ReflBEq, LawfulBEq, Hashable, ToJson, FromJson

def Fact.valid : Fact → Bool
  | .read value => value.valid
  | .consumed edge => edge.valid
  | .supports support => support.valid
  | .coquoted group source => group.valid && source.valid
  | .used usage => usage.valid

/-- Evidence union is the lattice operation; counts are derived after union. -/
def evidenceJoin [BEq α] [Hashable α] (left right : Std.HashSet α) : Std.HashSet α :=
  left.union right

def SameEvidence [BEq α] [Hashable α] (left right : Std.HashSet α) : Prop :=
  ∀ fact, left.contains fact = right.contains fact

theorem evidenceJoin_idempotent [BEq α] [Hashable α] [EquivBEq α] [LawfulHashable α]
    (evidence : Std.HashSet α) : SameEvidence (evidenceJoin evidence evidence) evidence := by
  intro fact
  simp [evidenceJoin, Std.HashSet.contains_union]

theorem evidenceJoin_commutative [BEq α] [Hashable α] [EquivBEq α] [LawfulHashable α]
    (left right : Std.HashSet α) : SameEvidence (evidenceJoin left right) (evidenceJoin right left) := by
  intro fact
  simp [evidenceJoin, Std.HashSet.contains_union, Bool.or_comm]

theorem evidenceJoin_associative [BEq α] [Hashable α] [EquivBEq α] [LawfulHashable α]
    (a b c : Std.HashSet α) :
    SameEvidence (evidenceJoin (evidenceJoin a b) c) (evidenceJoin a (evidenceJoin b c)) := by
  intro fact
  simp [evidenceJoin, Std.HashSet.contains_union, Bool.or_assoc]

def add [BEq α] [Hashable α] [BEq β] [Hashable β]
    (map : Std.HashMap α (Std.HashSet β)) (key : α) (value : β) :=
  map.insert key ((map[key]?.getD {}).insert value)

structure Graph where
  facts : Std.HashSet Fact := {}
  bindings : Std.HashMap Range (Std.HashSet Binding) := {}
  incoming : Std.HashMap Occurrence (Std.HashSet Consumption) := {}
  supported : Std.HashMap Claim (Std.HashSet Support) := {}
  groups : Std.HashMap Group (Std.HashSet Range) := {}
  quotedBy : Std.HashMap Range (Std.HashSet Group) := {}
  events : Std.HashMap Event Usage := {}
  usages : Std.HashMap Range (Std.HashSet Usage) := {}

def Graph.empty : Graph := {}

def Graph.bind (graph : Graph) (source : Range) (binding : Binding) : Graph :=
  {graph with bindings := add graph.bindings source binding}

/-- Insertion is transactional. A repeated event cannot acquire a new label. -/
def Graph.insert (graph : Graph) (fact : Fact) : Except String Graph := do
  unless fact.valid do throw "invalid advisory evidence"
  if graph.facts.contains fact then return graph
  let graph := {graph with facts := graph.facts.insert fact}
  match fact with
  | .read value => return graph.bind value.source value.binding
  | .consumed edge =>
    return {graph with incoming := add graph.incoming edge.consumer edge}
  | .supports support =>
    let graph := (graph.bind support.source support.binding).bind support.read.source support.read.binding
    return {graph with supported := add graph.supported support.claim support}
  | .coquoted group source =>
    return {graph with
      groups := add graph.groups group source
      quotedBy := add graph.quotedBy source group}
  | .used usage =>
    if let some previous := graph.events[usage.event]? then
      unless previous == usage do throw "conflicting immutable usage event"
    return {graph with
      events := graph.events.insert usage.event usage
      usages := add graph.usages usage.source usage}

def Graph.ofFacts (facts : Array Fact) : Except String Graph :=
  facts.foldlM Graph.insert Graph.empty

/-- Canonical interchange is separate from hash-table iteration order. -/
def Graph.snapshot (graph : Graph) : Array Fact :=
  graph.facts.toArray.qsort (fun a b => (toJson a).compress < (toJson b).compress)

def Graph.merge (left right : Graph) : Except String Graph :=
  Graph.ofFacts (evidenceJoin left.facts right.facts).toArray

def Graph.evidenceCount (graph : Graph) : Nat := graph.facts.size

def Graph.rangeCount (graph : Graph) : Nat :=
  let ranges := graph.facts.fold (fun ranges fact =>
    match fact with
    | .read value => ranges.insert value.source
    | .supports support => (ranges.insert support.source).insert support.read.source
    | .consumed edge => edge.rows.foldl (·.insert ·) ranges
    | .coquoted _ source => ranges.insert source
    | .used usage => ranges.insert usage.source) ({} : Std.HashSet Range)
  ranges.size

def Graph.sourceBindings (graph : Graph) (source : Range) : Array Binding :=
  (graph.bindings[source]?.getD {}).toArray

/-- Closed interval union, bounded by observed intervals rather than line numbers. -/
def covered (wanted : Range) (observed : Array Range) : Bool := Id.run do
  let rows := (observed.filter (·.subject == wanted.subject)).toList.mergeSort (fun a b => a.first ≤ b.first)
  let mut position := wanted.first
  for row in rows do
    if position < row.first then return false
    if position ≤ row.last then position := row.last + 1
    if wanted.last < position then return true
  return false

def readKind (requested : Range) (stored delivered : Array Range) (fingerprintChecked : Bool) : UsageKind :=
  if !fingerprintChecked then .reread
  else if covered requested stored then
    if covered requested delivered then .reread else .omittedThenRead
  else if stored.any (fun range => range.subject.sameLocation requested.subject && range.subject != requested.subject)
    then .sourceChanged
  else .reread

theorem omitted_requires_checked (requested : Range) (stored delivered : Array Range)
    (checked : Bool) (omitted : readKind requested stored delivered checked = .omittedThenRead) :
    checked = true := by
  cases checked <;> simp_all [readKind]

theorem omitted_requires_stored (requested : Range) (stored delivered : Array Range)
    (checked : Bool) (omitted : readKind requested stored delivered checked = .omittedThenRead) :
    covered requested stored = true ∧ covered requested delivered = false := by
  unfold readKind at omitted
  split at omitted
  next => contradiction
  next =>
    split at omitted
    next stored =>
      split at omitted
      next => contradiction
      next delivered => exact ⟨by simpa using stored, by simpa using delivered⟩
    next => split at omitted <;> contradiction

def Graph.recordRead (graph : Graph) (event : Event) (query : String) (requested : Range)
    (stored delivered : Array Range) (checked : Bool) : Except String Graph :=
  graph.insert (.used {
    event := event
    query := query
    source := requested
    kind := readKind requested stored delivered checked})

def Graph.recordCitation (graph : Graph) (event : Event) (query : String) (source : Range)
    (delivered : Array Range) : Except String Graph :=
  if covered source delivered then
    graph.insert (.used {event, query, source, kind := .deliveredThenCited})
  else .ok graph

structure UsageCounts where
  omittedThenRead : Nat := 0
  deliveredThenCited : Nat := 0
  reread : Nat := 0
  sourceChanged : Nat := 0
  deriving Repr, BEq, ToJson

def Graph.usageCounts (graph : Graph) (source : Range) (query : Option String := none) : UsageCounts :=
  (graph.usages[source]?.getD {}).fold (fun counts usage =>
    if query.any (· != usage.query) then counts else
    match usage.kind with
    | .omittedThenRead => {counts with omittedThenRead := counts.omittedThenRead + 1}
    | .deliveredThenCited => {counts with deliveredThenCited := counts.deliveredThenCited + 1}
    | .reread => {counts with reread := counts.reread + 1}
    | .sourceChanged => {counts with sourceChanged := counts.sourceChanged + 1}) {}

/-- Incidence traversal visits each shared answer once, without building cliques. -/
def Graph.companions (graph : Graph) (sources : Array Range) : Std.HashMap Range Nat := Id.run do
  let mut groups : Std.HashSet Group := {}
  for source in sources do
    for group in graph.quotedBy[source]?.getD {} do
      if let .answer .. := group then groups := groups.insert group
  let mut counts : Std.HashMap Range Nat := {}
  for group in groups do
    for source in graph.groups[group]?.getD {} do
      counts := counts.insert source (counts[source]?.getD 0 + 1)
  return counts

structure Relevant where
  ranges : Std.HashSet Range := {}
  occurrences : Std.HashSet Occurrence := {}
  unlocated : Array Consumption := #[]

/-- Supports seed reverse consumption. Only located witness rows add body ranges. -/
def Graph.relevant (graph : Graph) (claims : Array Claim) : Relevant := Id.run do
  let mut result : Relevant := {}
  let mut queue : Array Occurrence := #[]
  for claim in claims do
    for support in graph.supported[claim]?.getD {} do
      result := {result with ranges := result.ranges.insert support.source}
      queue := queue.push support.read.occurrence
  let mut position := 0
  while position < queue.size do
    let some occurrence := queue[position]? | break
    position := position + 1
    if result.occurrences.contains occurrence then continue
    result := {result with occurrences := result.occurrences.insert occurrence}
    for edge in graph.incoming[occurrence]?.getD {} do
      result := {result with ranges := edge.rows.foldl (·.insert ·) result.ranges}
      if edge.rows.isEmpty then result := {result with unlocated := result.unlocated.push edge}
      queue := queue.push edge.producer
  return result

end Eggshell.Synapses
