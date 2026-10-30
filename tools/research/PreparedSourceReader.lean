module
public import Eggshell.CanonicalSourcePrepared
public import Eggshell.SynapticBindings
public import tools.research.PrivateRoutingView
@[expose] public section

namespace Eggshell.Synapses.PreparedSource
open Lean DB

/-- A query-local read handle, with no publication callback. The concrete
adapters validate the same scoped replies; no executable callback crosses JSON. -/
structure Reader where
  access : CanonicalSource.Shared.Access
  rows : Array String → Nat → IO CanonicalSource.Shared.Projection
  bindings : Array Range → Std.HashSet String → Nat → IO IndexedBindings.Resolved
  records : Array String → Nat → IO ObservedRecordView.Projection
  routing : Option (Routing.PrivateView.Request → Nat → IO Routing.PrivateView.Reply) := none

def Reader.identity (reader : Reader) : Json := reader.access.identity

def Reader.metadata (reader : Reader) := reader.access.metadata

theorem Reader.capability_not_identity (reader : Reader) (capability : String) :
    ({reader with access := {reader.access with capability}}).identity = reader.identity := rfl

/-- Same checks as the original client after parsing. Reuse them for typed
in-process replies rather than silently trusting a local transport. -/
def checkedRows (access : CanonicalSource.Shared.Access) (owners : Array String)
    (result : CanonicalSource.Shared.Projection) : IO CanonicalSource.Shared.Projection := do
  unless result.identity == access.identity && result.rows.map Prod.fst == owners &&
      result.layouts.map Prod.fst == owners do
    throw (IO.userError "prepared source projection changed its owner domain")
  for (owner,rows) in result.rows do
    unless rows.all (fun row => row.origins.all (fun origin =>
        origin.binding.database == access.database && origin.binding.owner == owner)) do
      throw (IO.userError "prepared source projection crossed its owner scope")
    let _ ← IO.ofExcept (CanonicalSource.load access.database rows)
    pure ()
  for ((_,rows),(_,entries)) in result.rows.zip result.layouts do
    let _ ← IO.ofExcept (CanonicalSource.Recipe.check rows entries)
    pure ()
  return result

def checkedBindings (access : CanonicalSource.Shared.Access) (wanted : Array Range)
    (allowed : Std.HashSet String) (found : IndexedBindings.Projection) : IO IndexedBindings.Resolved := do
  unless found.identity == access.identity && some found.index == access.metadata.bindings do
    throw (IO.userError "original bindings changed their prepared publication")
  let wanted := Std.HashSet.ofArray wanted
  unless found.rows.size == wanted.size &&
      (Std.HashSet.ofArray (found.rows.map Prod.fst)).size == wanted.size do
    throw (IO.userError "original binding reply changed its requested range domain")
  let mut rows := {}
  for (source,values) in found.rows do
    unless wanted.contains source && values.all (fun read => read.valid && read.source == source &&
        read.binding.database == access.database && allowed.contains read.binding.owner) do
      throw (IO.userError "original binding reply crossed its requested domain")
    rows := rows.insert source values
  return {
    rows
    complete := found.complete
    requests := found.requests
    bytes := found.bytes
    unresolved := found.unresolved
    unusable := found.unusable}

def checkedRecords (access : CanonicalSource.Shared.Access) (owners : Array String)
    (result : ObservedRecordView.Projection) : IO ObservedRecordView.Projection := do
  unless result.source == access.source && result.rows.map Prod.fst == owners do
    throw (IO.userError "original record projection changed its requested source or owner domain")
  for (owner,found) in result.rows do
    if let some view := found then
      unless view.header.database == access.database && view.header.owner == owner do
        throw (IO.userError "original record view crossed its read scope")
  return result

/-- These typed operations require an authenticated, pinned, borrowed view.
The service authenticates before calling them; the network wrappers serialize
their result, while the local adapter consumes the result directly. -/
def rowsAt (access : CanonicalSource.Shared.Access) (loaded : CanonicalSource.Shared.Loaded)
    (owners : Array String) (deadline : Nat) : IO CanonicalSource.Shared.Projection := do
  unless owners.size ≤ 4096 && owners.all (fun owner => owner.utf8ByteSize ≤ 256) do
    throw (IO.userError "invalid prepared source projection request")
  let prepared ← loaded.rows owners deadline
  return ⟨access.identity,prepared.map (fun (owner,recipe) => (owner,recipe.rows)),access.reuse,
    prepared.map (fun (owner,recipe) => (owner,recipe.records))⟩

def bindingsAt (access : CanonicalSource.Shared.Access) (loaded : CanonicalSource.Shared.Loaded)
    (wanted : Array Range) (allowed : Std.HashSet String) (deadline : Nat) : IO IndexedBindings.Projection := do
  unless wanted.size ≤ 32768 && allowed.size ≤ 4096 do
    throw (IO.userError "invalid prepared binding request")
  let some original := loaded.originals | throw (IO.userError "original bindings are not prepared")
  let result ← IndexedBindings.resolve original wanted allowed deadline
  return {
    identity := access.identity
    index := original.index.head
    rows := result.rows.toArray
    complete := result.complete
    requests := result.requests
    bytes := result.bytes
    unresolved := result.unresolved
    unusable := result.unusable}

def recordsAt (cache : ObservedRecordView.Cache) (access : CanonicalSource.Shared.Access)
    (loaded : CanonicalSource.Shared.Loaded) (owners : Array String) (deadline maxBytes : Nat) :
    IO ObservedRecordView.Projection := do
  unless owners.size ≤ 4096 && owners.all (fun owner => owner.utf8ByteSize ≤ 256) do
    throw (IO.userError "invalid original record projection request")
  let some original := loaded.originals | throw (IO.userError "original record view is not prepared")
  let mut rows : Array (String × Option ObservedRecordView.Geometry) := #[]
  let mut size := 0
  for owner in owners do
    unless (← IO.monoMsNow) < deadline do throw (IO.userError "original record projection expired")
    let found ← cache.acquire original.index access.database owner deadline
    size := size+(toJson (owner,found)).compress.utf8ByteSize
    unless size ≤ maxBytes-4096 do throw (IO.userError "original record projection exceeds reserved reply budget")
    rows := rows.push (owner,found)
  return ⟨access.source,rows,← cache.stats⟩

def routingAt (source : PageMap.Snapshot) (pages : PageMap.PagePool) (scope : String)
    (loaded : CanonicalSource.Shared.Loaded) (request : Routing.PrivateView.Request)
    (deadline : Nat) : IO Routing.PrivateView.Reply := do
  let some original := loaded.originals | throw (IO.userError "routing source is not prepared")
  let original ← if original.index.head == request.basis then pure original else do
    let current ← PageMap.pin original.index.directory
    let some pinned ← PageMap.HistoryReader.make? current request.basis |
      throw (IO.userError "requested routing index is retired")
    let some manifest ← Index.manifest? pinned.snapshot | throw (IO.userError "routing index has no manifest")
    unless manifest.scope == .shared && manifest.implementation == Index.implementation &&
        (← Index.sameSources source manifest.source) do
      throw (IO.userError "routing index has a different source scope")
    pure (⟨← pinned.snapshot.sharePages pages scope,manifest⟩ : Index.Reader)
  let some routing ← Routing.Store.open? original | throw (IO.userError "routing source is cold")
  Routing.PrivateView.execute routing request deadline

/-- The service clears this slot before releasing its pool borrow. An escaped
callback cannot read or retain the Loaded value after that continuation. -/
def borrowed (access : CanonicalSource.Shared.Access) (slot : IO.Ref (Option CanonicalSource.Shared.Loaded))
    (source : PageMap.Snapshot) (pages : PageMap.PagePool) (scope : String)
    (cache : ObservedRecordView.Cache) (stopping : IO.Ref Bool) (outerDeadline maxBytes : Nat) : Reader :=
  let budget := fun requested => do
    let cutoff := min outerDeadline requested
    unless !(← stopping.get) && (← IO.monoMsNow) < cutoff do
      throw (IO.userError "prepared local reader expired or stopped")
    let some loaded ← slot.get | throw (IO.userError "prepared local borrow is closed")
    pure (cutoff,loaded)
  {access
   rows := fun owners requested => do
     let (cutoff,loaded) ← budget requested
     let owners := (hashDistinct owners.toList).toArray
     checkedRows access owners (← rowsAt access loaded owners cutoff)
   bindings := fun wanted allowed requested => do
     let (cutoff,loaded) ← budget requested
     checkedBindings access wanted allowed (← bindingsAt access loaded wanted allowed cutoff)
   records := fun owners requested => do
     let (cutoff,loaded) ← budget requested
     let owners := (hashDistinct owners.toList).toArray
     checkedRecords access owners (← recordsAt cache access loaded owners cutoff maxBytes)
   routing := some fun request requested => do
     let (cutoff,loaded) ← budget requested
     routingAt source pages scope loaded request cutoff}

theorem borrowed_identity (access : CanonicalSource.Shared.Access) (slot : IO.Ref (Option CanonicalSource.Shared.Loaded))
    (source : PageMap.Snapshot) (pages : PageMap.PagePool) (scope : String)
    (cache : ObservedRecordView.Cache) (stopping : IO.Ref Bool) (deadline maxBytes : Nat) :
    (borrowed access slot source pages scope cache stopping deadline maxBytes).identity = access.identity := rfl

end Eggshell.Synapses.PreparedSource
