module
public import ProjectionCursor

@[expose] public section
namespace Eggshell.ProjectionCache
open DB

def maxRows : Nat := 16384

structure Cached where
  scope : String
  row : ProjectionCursor.Row
  payload : ProjectionCursor.Raw row

def used (entries : Array Cached) : Nat := (entries.toList.map (·.payload.bytes.size)).sum

/-- The hash table retains coordinates, not another copy of the payloads.
All retained vector bytes occur in this one bounded array. -/
structure State (capacity : Nat) where
  entries : Array Cached
  index : Std.HashMap String Nat
  bytes : Nat
  exact : bytes = used entries
  bounded : bytes ≤ capacity
  slotsBounded : entries.size ≤ maxRows

theorem State.actual_bytes_bounded (state : State capacity) : used state.entries ≤ capacity := by
  rw [← state.exact]
  exact state.bounded

def State.empty (capacity : Nat) : State capacity := ⟨#[],{},0,rfl,Nat.zero_le _,by decide⟩

def State.insert (state : State capacity) (entry : Cached) : State capacity :=
  let key := entry.scope++entry.row.key
  if fits : state.bytes+entry.payload.bytes.size ≤ capacity ∧ state.entries.size+1 ≤ maxRows then
    ⟨state.entries.push entry,state.index.insert key state.entries.size,
      state.bytes+entry.payload.bytes.size,by simp [used,state.exact],fits.1,by simpa using fits.2⟩
  else if fits : entry.payload.bytes.size ≤ capacity then
    ⟨#[entry],(∅ : Std.HashMap String Nat).insert key 0,
      entry.payload.bytes.size,by simp [used],fits,by simp [maxRows]⟩
  else state

structure Cache where
  capacity : Nat
  state : IO.Ref (State capacity)
  hits : IO.Ref Nat
  misses : IO.Ref Nat

/-- One allowance is shared by every database served by this numerical daemon. -/
def Cache.make (capacity : Nat := 64*1024*1024) : IO Cache :=
  return ⟨capacity,← IO.mkRef (State.empty capacity),← IO.mkRef 0,← IO.mkRef 0⟩

def scope (matrix : VectorMatrix.Ready) : String := Sha256.hex
  (Lean.toJson [matrix.snapshot.directory.toString,(Lean.toJson matrix.snapshot.head).compress]).compress.toUTF8

/-- Callers bracket a complete frame with committed-prefix checks. A miss reads
and authenticates each original chunk; hits retain those exact checked bytes.
Source admission and freshness remain outside this advisory cache. -/
def read (matrix : VectorMatrix.Ready) (cache : Cache) (scope key : String) : IO Cached := do
  unless Receipt.validId scope && Receipt.validId key do
    throw (IO.userError "invalid projection cache identity")
  let state ← cache.state.get
  if let some position := state.index[scope++key]? then
    let some entry := state.entries[position]? | throw (IO.userError "projection cache coordinate is absent")
    unless entry.scope == scope && entry.row.key == key do
      throw (IO.userError "projection cache coordinate differs")
    cache.hits.modify (·+1)
    return entry
  cache.misses.modify (·+1)
  let some encoded ← matrix.snapshot.get ("row:"++key) | throw (IO.userError "requested projection is absent")
  let row ← ProjectionCursor.checked key encoded
  let payload ← ProjectionCursor.readPayload matrix row
  let entry := ⟨scope,row,payload⟩
  cache.state.modify (·.insert entry)
  return entry

end Eggshell.ProjectionCache
