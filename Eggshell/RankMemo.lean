module

public import Eggshell.SurfaceJoin

@[expose] public section
namespace Eggshell.Matcher.RankMemo
open Lean LogicalText Persistence

/-- Positions are hints, never serialized evidence or an erased certificate.
The current complete source domain verifies every retained calculation. -/
abbrev Saved := List (String × List Nat)
def allowance : Nat := 262144
def frontierAllowance : Nat := 16384
def slots : Nat := 16
abbrev Slot := Fin slots
inductive Lane where
  | rank
  | selection
  | context
  deriving DecidableEq

def Lane.prefix : Lane → String
  | .rank => "memo:rank:"
  | .selection => "memo:selection:"
  | .context => "memo:context:"
def slotOf (key : String) : Slot :=
  ⟨(hash key).toNat % slots, Nat.mod_lt _ (by decide)⟩
def slotRow (slot : Slot) (lane : Lane := .rank) : String := lane.prefix ++ toString slot.val
def row (key : String) (lane : Lane := .rank) : String := slotRow (slotOf key) lane
def codec : DB.Wire.Codec Saved := DB.Wire.list (DB.Wire.text.product (DB.Wire.list DB.Wire.natural))

theorem codec_roundtrip (saved : Saved) (tail : List UInt8) :
    codec.decode (codec.encode saved ++ tail) = .ok (saved, tail) := codec.roundtrip saved tail

def binding (query target : Pattern) : String :=
  toString query.locator ++ ":" ++ toString target.locator

structure Input where
  query : LogicalText.T
  target : LogicalText.T
  weights : List Nat
  queryLocator : UInt64
  targetLocator : UInt64
  deriving DecidableEq

def Input.locator (input : Input) : UInt64 × UInt64 × UInt64 :=
  (input.queryLocator, input.targetLocator, hash input.weights)

def reference (input : Input) : List Evidence :=
  referenceRank input.weights (makePattern input.query) (makePattern input.target)

structure Entry where
  input : Input
  ranked : List Evidence
  exact : ranked = reference input

abbrev Cache := Std.HashMap (UInt64 × UInt64 × UInt64) Entry

def provider (cache : Cache) : RankProvider := fun weights query target =>
  let input : Input := ⟨query.logical, target.logical, weights, query.locator, target.locator⟩
  match cache[input.locator]? with
  | some entry =>
      if entry.input = input then entry.ranked else reference input
  | none => reference input

theorem provider_exact (cache : Cache) : provider cache = referenceRank := by
  funext weights query target
  simp only [provider]
  split
  · split
    · rename_i same
      rw [Entry.exact, same]
      simp only [reference, ← Pattern.canonical query, ← Pattern.canonical target]
    · simp only [reference, ← Pattern.canonical query, ← Pattern.canonical target]
  · simp only [reference, ← Pattern.canonical query, ← Pattern.canonical target]

/-- Unlike a positive-only trace, this certifier checks the entire current
join count, every source ordinal, permutation and stable frequency ordering.
Missing/new/duplicate/out-of-range positions cannot produce a stale answer. -/
def obtainUsing (saved : Saved) (weights : List Nat) (query target : Pattern)
    (source : EvidenceReplay.Indexed (surfaceEvidence query target)) :
    {ranked : List Evidence // ranked = referenceRank weights query target} ×
      Option (String × List Nat) × Bool := Id.run do
  if source.count < 32 || source.count > frontierAllowance then
    return (⟨referenceRank weights query target, rfl⟩, none, false)
  let key := binding query target
  if let some positions := (saved.find? (·.1 == key)).map Prod.snd then
    if let some (ranked, repaired) := EvidenceReplay.repairIndexed weights source positions then
      return (ranked, some (key, repaired), true)
  let generated := EvidenceReplay.generate weights (surfaceEvidence query target)
  return (generated.1, some (key, generated.2), false)

def obtain (saved : Saved) (weights : List Nat) (query target : Pattern) :=
  obtainUsing saved weights query target (SurfaceJoin.current query target)

structure Prepared where
  cache : Cache := {}
  saved : Saved := []
  charged : Nat := 0
  bounded : charged ≤ allowance := by decide
  reused : Nat := 0
  computed : Nat := 0

/-- Only demanded orders are retained. The additive encoded charge bounds
the optional durable row; it is not a claim about allocator RSS. -/
def Prepared.addUsing (prepared : Prepared) (previous : Saved) (weights : List Nat)
    (query target : Pattern) (source : EvidenceReplay.Indexed (surfaceEvidence query target)) : Prepared :=
  -- Tiny joins are faster to execute directly. Do not hash and retain an
  -- additional result merely because a memo interface is available.
  if source.count < 32 || source.count > frontierAllowance then prepared else
  let found := obtainUsing previous weights query target source
  let input : Input := ⟨query.logical, target.logical, weights, query.locator, target.locator⟩
  let entry : Entry := ⟨input, found.1.val, by
    rw [found.1.property]
    change referenceRank weights query target =
      referenceRank weights (makePattern query.logical) (makePattern target.logical)
    rw [← Pattern.canonical query, ← Pattern.canonical target]⟩
  let cache := prepared.cache.insert input.locator entry
  let reused := prepared.reused + (if found.2.2 then 1 else 0)
  let computed := prepared.computed + (if found.2.2 then 0 else 1)
  match found.2.1 with
  | none => { prepared with cache, reused, computed }
  | some retained =>
      if prepared.saved.any (·.1 == retained.1) then { prepared with cache, reused, computed }
      else
        let cost := codec.encodedSize [retained]
        if fits : prepared.charged + cost ≤ allowance then
          { cache, saved := retained :: prepared.saved, charged := prepared.charged + cost,
            bounded := fits, reused, computed }
        else { prepared with cache, reused, computed }

def Prepared.add (prepared : Prepared) (previous : Saved) (weights : List Nat)
    (query target : Pattern) : Prepared :=
  prepared.addUsing previous weights query target (SurfaceJoin.current query target)

def readSlot (snapshot : Store.Snapshot) (slot : Slot) (lane : Lane := .rank) : IO Saved := do
  let tag := slotRow slot lane
  let some _ ← snapshot.get tag | return []
  let size ← Store.getNat snapshot.get tag
  unless size ≤ allowance do throw (IO.userError "rank memo exceeds its encoded allowance")
  let payloadSize ← Store.getNat snapshot.get (Store.key tag 0)
  unless payloadSize == size do throw (IO.userError "rank memo payload differs from its bounded marker")
  let bytes ← Store.readChunks snapshot snapshot.get tag 0
  let (saved, tail) ← IO.ofExcept (codec.decode bytes.toList)
  unless saved.length == 1 && tail.isEmpty && (codec.encode saved).toByteArray == bytes do
    throw (IO.userError "noncanonical rank memo")
  pure saved

/-- A slot collision only loses an optional hint. The complete locator must
agree before positions reach the current-domain certifier. -/
def select (key : String) (saved : Saved) : Saved := saved.filter (·.1 == key)

theorem select_binding (key : String) (saved : Saved) (entry : String × List Nat)
    (member : entry ∈ select key saved) : entry.1 = key := by
  simpa only [beq_iff_eq] using (List.mem_filter.mp member).2

def readKey (snapshot : Store.Snapshot) (key : String) (lane : Lane := .rank) : IO Saved := do
  pure (select key (← readSlot snapshot (slotOf key) lane))

/-- Administrative enumeration only; production loads demanded keys directly. -/
def read (snapshot : Store.Snapshot) (lane : Lane := .rank) : IO Saved := do
  let mut saved := []
  for slot in List.finRange slots do
    saved := saved ++ (← readSlot snapshot slot lane)
  pure saved

/-- Advice is tied to one pinned publication. It is deliberately not a
semantic observation: arbitrary/stale positions still need full current join
count, permutation and ordering certification in `obtain`. -/
structure Reader (lane : Lane := .rank) where
  snapshot : Store.Snapshot
  fetched : IO.Ref (Std.HashMap Slot Saved)
  loads : IO.Ref Nat

def Reader.new (snapshot : Store.Snapshot) (lane : Lane := .rank) : IO (Reader lane) := do
  let untraced := { snapshot with trace := ← IO.mkRef none }
  pure ⟨untraced, ← IO.mkRef {}, ← IO.mkRef 0⟩

def Reader.get (reader : Reader lane) (key : String) : IO Saved := do
  let slot := slotOf key
  if let some saved := (← reader.fetched.get)[slot]? then return select key saved
  reader.loads.modify (· + 1)
  let saved ← try readSlot reader.snapshot slot lane catch _ => pure []
  reader.fetched.modify (·.insert slot saved)
  return select key saved

/-- Compile the current overlap directory once. Small joins bypass both the
durable lookup and memo allocation, as in the pure caller. -/
def Prepared.addM (prepared : Prepared) (reader : Reader) (weights : List Nat)
    (query target : Pattern) : IO Prepared := do
  let source := SurfaceJoin.current query target
  if source.count < 32 || source.count > frontierAllowance then return prepared
  let saved ← reader.get (binding query target)
  return prepared.addUsing saved weights query target source

/-- Append changed demanded slots to the caller's single publication batch.
The caller seals one derived-only change after every lane is ready. -/
def publishUsing (writer : Store.Writer) (saved : Saved) (lane : Lane := .rank) : IO Bool := do
    let mut changed := false
    let mut written : Std.HashSet Slot := {}
    for entry in saved do
      let slot := slotOf entry.1
      let tag := slotRow slot lane
      -- A single publication selects the first demanded key per slot.
      if written.contains slot then continue
      written := written.insert slot
      let bytes := (codec.encode [entry]).toByteArray
      if bytes.size > allowance then continue
      if let some _ ← writer.get tag then
        let size ← Store.getNat writer.get tag
        let payloadSize ← Store.getNat writer.get (Store.key tag 0)
        if size ≤ allowance && payloadSize == size then
          let previous ← Store.readChunks (← writer.snapshot) writer.get tag 0
          if previous == bytes then continue
      Store.putChunks writer tag 0 bytes
      Store.putNat writer tag bytes.size
      changed := true
    pure changed

/-- Only changed, demanded slots are written. Other requests stay untouched,
including their old orders after a frequency change; repair happens on demand.
Busy writers win immediately. No whole memo frontier is rewritten. -/
def publish (path : System.FilePath) (saved : Saved) (lane : Lane := .rank) : IO _root_.Unit := do
  if saved.isEmpty then return
  let snapshot ← DB.PageMap.pin path
  let _ ← DB.PageMap.withWriter snapshot fun writer => do
    if ← publishUsing writer saved lane then Store.writeChange writer ⟨[], [], false⟩
  pure ()

end Eggshell.Matcher.RankMemo
