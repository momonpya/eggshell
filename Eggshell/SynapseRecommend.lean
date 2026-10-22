module

public import Eggshell.SynapseIndex
public import Eggshell.SynapseUsage

@[expose] public section

namespace Eggshell.Synapses.Recommend
open Lean DB

/-- A recommendation names data actually carried by its advisory witness.
Ordinary rereads and changed sources do not reward a candidate. -/
def carries (fact : Fact) (source : Range) : Bool :=
  match fact with
  | .supports support => support.source == source
  | .consumed edge => edge.rows.contains source
  | .coquoted _ quoted => quoted == source
  | .used usage => usage.source == source &&
      (usage.kind == .omittedThenRead || usage.kind == .deliveredThenCited)
  | .read _ => false

structure Offer where
  source : Range
  priority : Nat
  fact : Fact
  identity : String
  identity_exact : identity = Index.contentKey fact
  valid : fact.valid = true
  witness : carries fact source = true

def Offer.check? (source : Range) (priority : Nat) (fact : Fact)
    (identity : {value : String // value = Index.contentKey fact}) : Option Offer :=
  if valid : fact.valid = true then
    if witness : carries fact source = true then
      some ⟨source, priority, fact, identity.val, identity.property, valid, witness⟩ else none
  else none

theorem Offer.consumption_row (offer : Offer) (edge : Consumption) (kind : offer.fact = .consumed edge) :
    offer.source ∈ edge.rows := by
  have witness := offer.witness
  rw [kind] at witness
  exact Array.mem_of_contains_eq_true witness

theorem Offer.usage_is_evidence (offer : Offer) (usage : Usage) (kind : offer.fact = .used usage) :
    usage.kind = .omittedThenRead ∨ usage.kind = .deliveredThenCited := by
  have witness := offer.witness
  simp only [kind, carries, Bool.and_eq_true, Bool.or_eq_true, beq_iff_eq] at witness
  exact witness.2

def Offer.kind (offer : Offer) : String := match offer.fact with
  | .supports _ => "support"
  | .consumed _ => "consumption"
  | .coquoted _ _ => "coquotation"
  | .used usage => usage.kind.label
  | .read _ => "unavailable"

def Offer.json (offer : Offer) : Json := Json.mkObj [
  ("source", toJson offer.source), ("priority", toJson offer.priority),
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

/-- A partial walk never changes the original packet. Its receipt still
reports incompleteness rather than presenting an empty successful search. -/
def Result.admitted (result : Result) : Array Offer :=
  if result.complete && result.available then result.offers else #[]

theorem Result.incomplete_not_admitted (result : Result) (incomplete : result.complete = false) :
    result.admitted = #[] := by simp [admitted, incomplete]

def Result.receipt (result : Result) : Json := Json.mkObj [
  ("available", toJson result.available), ("complete", toJson result.complete),
  ("requests", toJson result.requests), ("facts", toJson result.facts),
  ("bytes", toJson result.bytes),
  ("index", toJson result.index), ("usage", toJson result.usage),
  ("offers", toJson (result.admitted.map Offer.json))]

def Result.stamp (result : Result) : String := Index.contentKey result.receipt

def addOffer (result : Result) (source : Range) (priority : Nat) (fact : Fact)
    (identity : {value : String // value = Index.contentKey fact}) : Result :=
  match Offer.check? source priority fact identity with
  | none => result
  | some offer => {result with offers := result.offers.push offer}

/-- Priority is inherited from the original nomination. Coquotation expands
one incidence hop; only reverse consumption is recursive. No score fitting,
whole-producer fallback, graph mutation or certification occurs here. -/
def collect (shared : Index.Reader) (usage : Option Index.Reader)
    (answers : Array (String × Nat)) (initial : Array Range) (query : String)
    (deadline : Nat) (limits : Limits := {}) : IO Result := do
  let database := shared.manifest.source.identity
  let mut roots := answers.map fun (answer, priority) => ({key := .answer database answer, priority} : Task)
  roots := roots ++ initial.map (fun source => ⟨.quoted source, 0⟩)
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
        result := addOffer result support.source task.priority fact identity
        queue := queue.push ⟨.consumer support.read.occurrence, task.priority⟩
        queue := queue.push ⟨.quoted support.source, task.priority⟩
      | .consumer _, .consumed edge =>
        for source in edge.rows do
          result := addOffer result source task.priority fact identity
          queue := queue.push ⟨.quoted source, task.priority⟩
        queue := queue.push ⟨.consumer edge.producer, task.priority⟩
      | .quoted _, .coquoted group _ =>
        if let .answer .. := group then queue := queue.push ⟨.group group, task.priority⟩
      | .group _, .coquoted _ source =>
        result := addOffer result source task.priority fact identity
      | .query _, .used value =>
        if value.kind == .omittedThenRead || value.kind == .deliveredThenCited then
          result := addOffer result value.source task.priority fact identity
          queue := queue.push ⟨.quoted value.source, task.priority⟩
      | _, _ => pure ()
  -- A checked omission is the more direct observation. Positive citation
  -- remains useful only where no omission of that same range was observed.
  let missing := result.offers.foldl (fun ranges offer => match offer.fact with
    | .used value => if value.kind == .omittedThenRead then ranges.insert offer.source else ranges
    | _ => ranges) ({} : Std.HashSet Range)
  return {result with offers := result.offers.filter fun offer => match offer.fact with
    | .used value => value.kind != .deliveredThenCited || !missing.contains offer.source
    | _ => true}

def read (source : PageMap.Snapshot) (writable : Bool) (answers : Array (String × Nat))
    (initial : Array Range) (query : String) (deadline : Nat) (limits : Limits := {}) : IO Result := do
  let (storage, _) ← Sidecar.destination (Sidecar.Owner.ofSnapshot source) writable
  let some shared ← Index.open? source storage .shared | return {available := false}
  collect shared (← Index.open? source .user .usage) answers initial query deadline limits

/-- Pin optional index publications once for both memo identity and planning.
An advancing background worker cannot silently change the input mid-request. -/
structure Prepared where
  source : PageMap.Head
  shared : Option Index.Reader
  usage : Option Index.Reader

def prepare (source : PageMap.Snapshot) (writable : Bool) : IO Prepared := do
  let (storage, _) ← Sidecar.destination (Sidecar.Owner.ofSnapshot source) writable
  return ⟨source.head, ← Index.open? source storage .shared, ← Index.open? source .user .usage⟩

def Prepared.identity (prepared : Prepared) : Json :=
  toJson (prepared.source.identity, prepared.source.authority,
    prepared.shared.map (·.index.head), prepared.usage.map (·.index.head))

def Prepared.collect (prepared : Prepared) (answers : Array (String × Nat)) (query : String)
    (deadline : Nat) (limits : Limits := {}) : IO Result := do
  let some shared := prepared.shared | return {available := false}
  _root_.Eggshell.Synapses.Recommend.collect shared prepared.usage answers #[] query deadline limits

/-- Locate a recommendation only inside an already hydrated original owner.
Fingerprint/range matching never creates a new owner or a control Match. -/
structure Located where
  offer : Offer
  row : Read
  within : offer.source.contains row.source = true

def locate (offers : Array Offer) (rows : Array Read) : Array Located := Id.run do
  let mut found := #[]
  for offer in offers do
    let matching := rows.filter (offer.source.contains ·.source)
    unless covered offer.source (matching.map (·.source)) do continue
    for row in matching do
      if within : offer.source.contains row.source = true then found := found.push ⟨offer, row, within⟩
  return found

theorem Located.same_fingerprint (located : Located) :
    located.offer.source.file = located.row.source.file := by
  have within := located.within
  simp only [Range.contains, Bool.and_eq_true, beq_iff_eq, decide_eq_true_eq] at within
  exact within.1.1

end Eggshell.Synapses.Recommend
