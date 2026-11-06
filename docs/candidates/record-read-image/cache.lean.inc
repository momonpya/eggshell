structure CachedGeometry where
  owner : String
  geometry : Option Geometry
  encodedBytes : Nat
  exactBytes : encodedBytes = (toJson (owner,geometry)).compress.utf8ByteSize
  stamp : Nat := 0

def CachedGeometry.make (owner : String) (geometry : Option Geometry) : CachedGeometry :=
  ⟨owner,geometry,(toJson (owner,geometry)).compress.utf8ByteSize,rfl,0⟩

def CachedGeometry.charge (value : CachedGeometry) : Nat := 4*value.encodedBytes+256

def geometryIdentity (source : PageMap.Head) (database owner : String) : String :=
  (toJson (source,database,owner)).compress

/-- An immutable reference to a captured cache generation. It contains no
mutable cache owner, mutex, promise, IO reference or CAS capability. The read
handler already holds its unchanged bounded source-reply reservation. -/
structure Image where
  source : PageMap.Head
  database : String
  entries : Std.HashMap String CachedGeometry := {}

def Image.lookup? (image : Image) (source : PageMap.Head) (database owner : String) :
    Option CachedGeometry := do
  unless source = image.source ∧ database = image.database do none
  let value ← image.entries[geometryIdentity source database owner]?
  if value.owner = owner then some value else none

theorem Image.foreign_source (image : Image) (source : PageMap.Head) (database owner : String)
    (different : source ≠ image.source) : image.lookup? source database owner = none := by
  simp [lookup?,different]

theorem Image.foreign_database (image : Image) (source : PageMap.Head) (database owner : String)
    (different : database ≠ image.database) : image.lookup? source database owner = none := by
  simp [lookup?,different]

theorem Image.lookup_is_immutable (image : Image) (owner : String) :
    image.lookup? image.source image.database owner = (do
      let value ← image.entries[geometryIdentity image.source image.database owner]?
      if value.owner = owner then some value else none) := by
  simp [lookup?]

theorem CachedGeometry.encoded_size_exact (value : CachedGeometry) :
    value.encodedBytes = (toJson (value.owner,value.geometry)).compress.utf8ByteSize := value.exactBytes

structure Batch where
  rows : Array (String × Option Geometry) := #[]
  additions : Array CachedGeometry := #[]
  bytes : Nat := 0

/-- No cache-owner capability is available while a hit is read or a miss is
loaded. Misses may run concurrently; immutable full-source keys make duplicate
fills harmless. Admission and the absolute deadline are unchanged. -/
def Image.collect (image : Image) (owners : Array String) (deadline budget : Nat)
    (load : String → IO (Option Geometry)) : IO Batch := do
  let mut batch : Batch := {}
  for owner in owners do
    unless (← IO.monoMsNow) < deadline do throw (IO.userError "original record projection expired")
    let value ← match image.lookup? image.source image.database owner with
      | some value => pure value
      | none => do
        let value := CachedGeometry.make owner (← load owner)
        batch := {batch with additions := batch.additions.push value}
        pure value
    let bytes := batch.bytes+value.encodedBytes
    unless bytes ≤ budget do throw (IO.userError "original record projection exceeds reserved reply budget")
    batch := {batch with rows := batch.rows.push (owner,value.geometry),bytes}
  return batch

structure CacheState where
  entries : Std.HashMap String CachedGeometry := {}
  bytes : Nat := 0
  clock : Nat := 0
  loads : Nat := 0

/-- FIFO insertion is a cache-management operation. Reading an existing value
does not update a shared clock, LRU stamp or counter. -/
def CacheState.publish (state : CacheState) (source : PageMap.Head) (database : String)
    (value : CachedGeometry) : CacheState := Id.run do
  let key := geometryIdentity source database value.owner
  if state.entries.contains key || value.charge > geometryCapacity then return state
  let mut state := state
  while state.bytes+value.charge > geometryCapacity || state.entries.size ≥ 512 do
    let some (key,previous) := (state.entries.toArray.qsort fun a b => a.2.stamp < b.2.stamp)[0]? |
      return state
    state := {state with entries := state.entries.erase key,bytes := state.bytes-previous.charge}
  let clock := state.clock+1
  let stored : CachedGeometry := {value with stamp := clock}
  return {state with
    entries := state.entries.insert key stored
    bytes := state.bytes+value.charge
    clock := clock
    loads := state.loads+1}

abbrev Cache := Std.Mutex CacheState
def Cache.new : IO Cache := Std.Mutex.new {}

/-- Synchronization hands off one immutable map reference only. -/
def Cache.capture (cache : Cache) (source : PageMap.Head) (database : String)
    (owners : Array String) : IO Image := do
  let entries ← cache.atomically do return (← get).entries
  let selected := owners.foldl (fun selected owner =>
    let key := geometryIdentity source database owner
    match entries[key]? with
    | none => selected
    | some value => selected.insert key value) ({} : Std.HashMap String CachedGeometry)
  return ⟨source,database,selected⟩

def Cache.publish (cache : Cache) (image : Image) (values : Array CachedGeometry) : IO Unit := do
  if values.isEmpty then return
  cache.atomically do
    modify fun state => values.foldl (fun state value => state.publish image.source image.database value) state

theorem Cache.publish_empty (cache : Cache) (image : Image) : cache.publish image #[] = pure () := rfl

/-- No DB access or caller-supplied work occurs while the cache mutex is held. -/
def Cache.project (cache : Cache) (index : PageMap.Snapshot) (database : String)
    (owners : Array String) (deadline budget : Nat) : IO Batch := do
  let image ← cache.capture index.head database owners
  let batch ← image.collect owners deadline budget (fun owner => geometry? index database owner deadline)
  cache.publish image batch.additions
  return batch

theorem Cache.project_snapshot_boundary (cache : Cache) (index : PageMap.Snapshot) (database : String)
    (owners : Array String) (deadline budget : Nat) :
    cache.project index database owners deadline budget = (do
      let image ← cache.capture index.head database owners
      let batch ← image.collect owners deadline budget (fun owner => geometry? index database owner deadline)
      cache.publish image batch.additions
      return batch) := rfl

def Cache.stats (cache : Cache) : IO Json := do
  let state ← cache.atomically get
  return Json.mkObj [("loads",toJson state.loads),("chargedBytes",toJson state.bytes),
    ("capacity",toJson geometryCapacity),("entries",toJson state.entries.size)]

