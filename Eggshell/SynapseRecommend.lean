module

public import Eggshell.SynapseIndex
public import Eggshell.SynapseUsage
public import Eggshell.ObservationContext

@[expose] public section

namespace Eggshell.Synapses.Recommend
open Lean DB

def implementation : String := Blake3.hex (Blake3.digest "eggshell.observation-recommendation".toUTF8 [
  (include_str "SynapseRecommend.lean").toUTF8,(include_str "ObservationContext.lean").toUTF8,
  (include_str "JsonScalars.lean").toUTF8,(include_str "SynapseTransport.lean").toUTF8,
  (include_str "SynapseUsage.lean").toUTF8])

/-- Output identity is native occurrence identity. File coordinates are an
additional addressing scheme, never a prerequisite for recommending data. -/
inductive Target where
  | range (source : Range)
  | output (producer : Occurrence)
  deriving DecidableEq, BEq, ToJson

def Target.source? : Target → Option Range
  | .range source => some source
  | .output _ => none

/-- A recommendation names data actually carried by its advisory witness.
Ordinary rereads and changed sources do not reward a candidate. -/
def carries (fact : Fact) : Target → Bool
  | .output producer => match fact with
    | .consumed edge => edge.producer == producer
    | _ => false
  | .range source => match fact with
    | .supports support => support.source == source
    | .consumed edge => edge.rows.contains source
    | .coquoted _ quoted => quoted == source
    | .used usage => usage.source == source &&
        (usage.kind == .omittedThenRead || usage.kind == .omittedThenConsumed || usage.kind == .deliveredThenCited)
    | .read _ => false

structure Offer where
  target : Target
  priority : Nat
  fact : Fact
  identity : String
  identity_exact : identity = Index.contentKey fact
  valid : fact.valid = true
  witness : carries fact target = true

def Offer.check? (target : Target) (priority : Nat) (fact : Fact)
    (identity : {value : String // value = Index.contentKey fact}) : Option Offer :=
  if valid : fact.valid = true then
    if witness : carries fact target = true then
      some ⟨target, priority, fact, identity.val, identity.property, valid, witness⟩ else none
  else none

theorem Offer.consumption_row (offer : Offer) (edge : Consumption) (kind : offer.fact = .consumed edge)
    (source : Range) (target : offer.target = .range source) : source ∈ edge.rows := by
  have witness := offer.witness
  rw [kind,target] at witness
  exact Array.mem_of_contains_eq_true witness

theorem Offer.usage_is_evidence (offer : Offer) (usage : Usage) (kind : offer.fact = .used usage) :
    (usage.kind = .omittedThenRead ∨ usage.kind = .omittedThenConsumed) ∨ usage.kind = .deliveredThenCited := by
  have witness := offer.witness
  cases target : offer.target <;> simp_all [carries, Bool.and_eq_true, Bool.or_eq_true, beq_iff_eq]

theorem Offer.output_has_producer (offer : Offer) (producer : Occurrence)
    (target : offer.target = .output producer) :
    ∃ edge, offer.fact = .consumed edge ∧ edge.producer = producer := by
  have witness := offer.witness
  cases kind : offer.fact <;> simp_all [carries,beq_iff_eq]

def Offer.kind (offer : Offer) : String := match offer.fact with
  | .supports _ => "support"
  | .consumed _ => "consumption"
  | .coquoted _ _ => "coquotation"
  | .used usage => usage.kind.label
  | .read _ => "unavailable"

def Offer.json (offer : Offer) : Json := Json.mkObj [
  ("target", toJson offer.target), ("source", toJson offer.target.source?), ("priority", toJson offer.priority),
  ("kind", toJson offer.kind), ("evidence", toJson offer.identity)]

structure Limits where
  requests : Nat := 256
  facts : Nat := 8192
  bytes : Nat := 8*1024*1024

structure Task where
  key : Index.Key
  priority : Nat

structure Result where
  offers : Array Offer := #[]
  requests : Nat := 0
  facts : Nat := 0
  bytes : Nat := 0
  complete : Bool := true
  available : Bool := true
  index : Option PageMap.Head := none
  usage : Option PageMap.Head := none
  failure : Option String := none

/-- A partial walk never changes the original packet. Its receipt still
reports incompleteness rather than presenting an empty successful search. -/
def Result.admitted (result : Result) : Array Offer :=
  if result.complete && result.available && result.failure.isNone then result.offers else #[]

theorem Result.incomplete_not_admitted (result : Result) (incomplete : result.complete = false) :
    result.admitted = #[] := by simp [admitted, incomplete]

theorem Result.failed_not_admitted (result : Result) (failed : result.failure.isSome = true) :
    result.admitted = #[] := by
  cases found : result.failure <;> simp_all [admitted]

def Result.receipt (result : Result) : Json := Json.mkObj [
  ("available", toJson result.available), ("complete", toJson result.complete),
  -- An exception can occur after successful reads. Do not report those
  -- interrupted counters as zero observed operations.
  ("requests", if result.failure.isSome then Json.null else toJson result.requests),
  ("facts", if result.failure.isSome then Json.null else toJson result.facts),
  ("bytes", if result.failure.isSome then Json.null else toJson result.bytes),
  ("failure", toJson result.failure),
  ("index", toJson result.index), ("usage", toJson result.usage),
  ("offers", toJson (result.admitted.map Offer.json))]

def Result.stamp (result : Result) : String := Index.contentKey result.receipt

def addOffer (result : Result) (target : Target) (priority : Nat) (fact : Fact)
    (identity : {value : String // value = Index.contentKey fact}) : Result :=
  match Offer.check? target priority fact identity with
  | none => result
  | some offer => {result with offers := result.offers.push offer}

/-- Priority is inherited from the original nomination. Coquotation expands
one incidence hop; only reverse consumption is recursive. No score fitting,
whole-producer fallback, graph mutation or certification occurs here. -/
def collect (shared : Index.Reader) (usage : Option Index.Reader)
    (answers : Array (String × Nat)) (initial : Array Range) (query : String)
    (deadline : Nat) (limits : Limits := {}) (consumers : Array (Occurrence × Nat) := #[]) : IO Result := do
  let database := shared.manifest.source.identity
  let mut roots := answers.map fun (answer, priority) => ({key := .answer database answer, priority} : Task)
  roots := roots ++ initial.map (fun source => ⟨.quoted source, 0⟩)
  roots := roots ++ consumers.map (fun (consumer,priority) => ⟨.consumer consumer,priority⟩)
  if usage.isSome && digest query then roots := roots.push ⟨.query query, 0⟩
  roots := roots.qsort fun a b =>
    if a.priority == b.priority then (toJson a.key).compress < (toJson b.key).compress
    else a.priority < b.priority
  let mut nextRoot := 0
  let mut queue : Array Task := #[]
  let mut position := 0
  let mut seen : Array Index.Key := #[]
  let mut result : Result := {index := some shared.index.head, usage := usage.map (·.index.head)}
  -- Descendants inherit their root's priority. Exhaust each root's FIFO
  -- closure before the next root, rather than repeatedly sorting a growing
  -- fanout. First visitation therefore retains the best nominated priority.
  repeat
    if position == queue.size then
      let some root := roots[nextRoot]? | break
      nextRoot := nextRoot+1
      queue := #[root]
      position := 0
    let some task := queue[position]? | break
    position := position+1
    if (← IO.monoMsNow) ≥ deadline then
      result := {result with complete := false}
      break
    if seen.contains task.key then continue
    if result.requests ≥ limits.requests || result.facts ≥ limits.facts || result.bytes ≥ limits.bytes ||
        (← IO.monoMsNow) ≥ deadline then
      result := {result with complete := false}
      break
    seen := seen.push task.key
    let reader := match task.key with | .query _ => usage.getD shared | _ => shared
    let found ← reader.lookup task.key (limits.facts-result.facts) deadline (some (limits.bytes-result.bytes))
    result := {result with
      requests := result.requests+1
      facts := result.facts+found.checked.size
      bytes := result.bytes+found.payloadBytes}
    if !found.complete then result := {result with complete := false}; break
    for checked in found.checked do
      let fact := checked.fact
      let identity : {value : String // value = Index.contentKey fact} := ⟨Index.contentKey fact, rfl⟩
      match task.key, fact with
      | .answer .., .supports support =>
        result := addOffer result (.range support.source) task.priority fact identity
        queue := queue.push ⟨.group (.claim support.claim), task.priority⟩
        queue := queue.push ⟨.consumer support.read.occurrence, task.priority⟩
        queue := queue.push ⟨.quoted support.source, task.priority⟩
      | .consumer _, .consumed edge =>
        if edge.rows.isEmpty then
          result := addOffer result (.output edge.producer) task.priority fact identity
        for source in edge.rows do
          result := addOffer result (.range source) task.priority fact identity
          queue := queue.push ⟨.quoted source, task.priority⟩
        queue := queue.push ⟨.consumer edge.producer, task.priority⟩
      | .quoted _, .coquoted group _ =>
        queue := queue.push ⟨.group group, task.priority⟩
      | .group _, .coquoted _ source =>
        result := addOffer result (.range source) task.priority fact identity
      | .query _, .used value =>
        if value.kind == .omittedThenRead || value.kind == .omittedThenConsumed || value.kind == .deliveredThenCited then
          result := addOffer result (.range value.source) task.priority fact identity
          queue := queue.push ⟨.quoted value.source, task.priority⟩
      | _, _ => pure ()
  -- A checked omission is the more direct observation. Positive citation
  -- remains useful only where no omission of that same range was observed.
  let missing := result.offers.foldl (fun ranges offer => match offer.fact with
    | .used value => if value.kind == .omittedThenRead || value.kind == .omittedThenConsumed then ranges.insert value.source else ranges
    | _ => ranges) ({} : Std.HashSet Range)
  return {result with offers := result.offers.filter fun offer => match offer.fact with
    | .used value => value.kind != .deliveredThenCited || !missing.contains value.source
    | _ => true}

/-- Pin optional index publications once for both memo identity and planning.
An advancing background worker cannot silently change the input mid-request. -/
structure Prepared where
  source : PageMap.Snapshot
  shared : Option Index.Reader
  usage : Option Index.Reader
  failure : Option String := none

def prepare (source : PageMap.Snapshot) (writable : Bool) : IO Prepared := do
  try
    let (storage, _) ← Sidecar.destination (Sidecar.Owner.ofSnapshot source) writable
    return ⟨source, ← Index.open? source storage .shared, ← Index.open? source .user .usage, none⟩
  catch error => return ⟨source, none, none, some s!"index-open: {error}"⟩

def Prepared.identity (prepared : Prepared) : Json :=
  toJson (implementation,prepared.source.head.identity, prepared.source.head.authority,
    prepared.shared.map (·.index.head), prepared.usage.map (·.index.head), prepared.failure)

def Prepared.collect (prepared : Prepared) (answers : Array (String × Nat)) (query : String)
    (deadline : Nat) (limits : Limits := {}) (consumers : Array (Occurrence × Nat) := #[]) : IO Result := do
  if prepared.failure.isSome then return {complete := false, available := false, failure := prepared.failure}
  let some shared := prepared.shared | return {available := false}
  try _root_.Eggshell.Synapses.Recommend.collect shared prepared.usage answers #[] query deadline limits consumers
  catch error => return {
    complete := false, index := some shared.index.head, usage := prepared.usage.map (·.index.head)
    failure := some s!"index-read: {error}"}

/-- Locate a recommendation only inside an already hydrated original owner.
Fingerprint/range matching never creates a new owner or a control Match. -/
structure Located where
  offer : Offer
  source : Range
  target : offer.target = .range source
  row : Read
  within : source.contains row.source = true

def locate (offers : Array Offer) (rows : Array Read) : Array Located := Id.run do
  let mut found := #[]
  for offer in offers do
    let .range source := offer.target | continue
    if target : offer.target = .range source then
      let matching := rows.filter (source.contains ·.source)
      unless covered source (matching.map (·.source)) do continue
      for row in matching do
        if within : source.contains row.source = true then found := found.push ⟨offer,source,target,row,within⟩
  return found

theorem Located.same_subject (located : Located) :
    located.source.subject = located.row.source.subject := by
  have within := located.within
  simp only [Range.contains, Bool.and_eq_true, beq_iff_eq, decide_eq_true_eq] at within
  exact within.1.1

structure LocatedOutput (doc : Extraction.Document) where
  offer : Offer
  fragment : ObservationContext.Fragment doc
  target : offer.target = .output fragment.occurrence

def locateOutputsUsing (offers : Array Offer) (database : String)
    (prepared : ObservationContext.Prepared doc) : Array (LocatedOutput doc) :=
  offers.filterMap fun offer => do
    let .output _ := offer.target | none
    let .consumed edge := offer.fact | none
    let fragment ← prepared.locate? database edge
    if target : offer.target = .output fragment.occurrence then some ⟨offer,fragment,target⟩ else none

def locateOutputs (offers : Array Offer) (database : String) (doc : Extraction.Document) : Array (LocatedOutput doc) :=
  (ObservationContext.prepare? doc).map (locateOutputsUsing offers database) |>.getD #[]

end Eggshell.Synapses.Recommend
