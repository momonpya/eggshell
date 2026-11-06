module
public import tools.research.SourceViewBatch
public import Init.Data.Array.Find
public import Eggshell.PublicationStream
@[expose] public section

namespace Eggshell.Synapses.ReadBoundary
open Lean DB

/-- Registration is append-only for one service generation. Requests capture
this immutable directory once; registration grants no write authority. -/
structure Source where
  directory : System.FilePath
  database : String
  storage : Sidecar.Storage
  scope : String
  capability : String

def lookup (sources : Array Source) (database scope : String) : Option Source :=
  sources.find? fun source => source.database == database && source.scope == scope

def wellFormed (request : SourceViewBatch.Request) (source : Source) : Bool :=
  request.owners.size ≤ 4096 && request.owners.all (fun owner => owner.utf8ByteSize ≤ 256) &&
  request.access.source.identity == source.database &&
  request.access.metadata.source.identity == source.database &&
  request.access.metadata.implementation == CanonicalSource.Cache.implementation &&
  digest request.access.metadata.payload &&
  request.focus.all fun focus =>
    focus.question.utf8ByteSize ≤ _root_.Eggshell.Plugin.Publication.Stream.maxBytes && focus.rows.size ≤ request.owners.size &&
    focus.rows.all (fun row => request.owners.contains row.owner && row.work.utf8ByteSize ≤ 256 &&
      row.windows.all digest) &&
    focus.rows.foldl (fun n row => n+row.windows.length+row.semantic.length) 0 ≤ 65536

def accepts (request : SourceViewBatch.Request) (source : Source) : Bool :=
  source.capability == request.access.capability && wellFormed request source

structure Binding (sources : Array Source) (request : SourceViewBatch.Request) where
  source : Source
  registered : lookup sources request.access.database request.access.scope = some source
  admitted : accepts request source = true

theorem Binding.member (binding : Binding sources request) : binding.source ∈ sources :=
  Array.mem_of_find?_eq_some binding.registered

theorem Binding.scope_exact (binding : Binding sources request) :
    binding.source.database = request.access.database ∧ binding.source.scope = request.access.scope := by
  have accepted := Array.find?_some binding.registered
  simpa only [Bool.and_eq_true,beq_iff_eq] using accepted

theorem Binding.capability_exact (binding : Binding sources request) :
    binding.source.capability = request.access.capability := by
  have admitted : binding.source.capability = request.access.capability ∧
      wellFormed request binding.source = true := by
    simpa only [accepts,Bool.and_eq_true,beq_iff_eq] using binding.admitted
  exact admitted.1

/-- Appending registrations cannot change an already selected scope, even if
the new entries contain duplicate keys. No re-read of the registry is needed. -/
theorem lookup_append (sources extra : Array Source) (database scope : String) (source : Source)
    (found : lookup sources database scope = some source) :
    lookup (sources ++ extra) database scope = some source := by
  unfold lookup at found ⊢
  rw [Array.find?_append,found,Option.some_or]

def Binding.extend (binding : Binding sources request) (extra : Array Source) :
    Binding (sources ++ extra) request :=
  ⟨binding.source,lookup_append sources extra _ _ _ binding.registered,binding.admitted⟩

theorem Binding.extend_same_source (binding : Binding sources request) (extra : Array Source) :
    (binding.extend extra).source = binding.source := rfl

def resolve (sources : Array Source) (request : SourceViewBatch.Request) :
    Except String (Binding sources request) :=
  match found : lookup sources request.access.database request.access.scope with
  | none => .error "unknown prepared source scope"
  | some source =>
    if admitted : accepts request source = true then .ok ⟨source,found,admitted⟩
    else .error "original batch crossed its prepared read scope"

structure Entry (sources : Array Source) where
  request : SourceViewBatch.Request
  binding : Binding sources request

def prepareEntries (sources : Array Source) : (requests : List SourceViewBatch.Request) →
    Except String {entries : List (Entry sources) // entries.map (·.request) = requests}
  | [] => .ok ⟨[],rfl⟩
  | request :: rest => do
    let binding ← resolve sources request
    let tail ← prepareEntries sources rest
    return ⟨⟨request,binding⟩ :: tail.val,by simp only [List.map_cons,tail.property]⟩

def bounded (secret : String) (requests : Array SourceViewBatch.Request) : Bool :=
  match requests[0]? with
  | none => false
  | some first => requests.size ≤ 4096 && secret == first.access.capability &&
    requests.foldl (fun total part => total+part.owners.size) 0 ≤ 65536

structure Batch (secret : String) (requests : Array SourceViewBatch.Request) where
  sources : Array Source
  entries : Array (Entry sources)
  order : entries.map (·.request) = requests
  admitted : bounded secret requests = true

def prepare (sources : Array Source) (secret : String) (requests : Array SourceViewBatch.Request) :
    Except String (Batch secret requests) := do
  if admitted : bounded secret requests = true then
    let entries ← prepareEntries sources requests.toList
    return ⟨sources,entries.val.toArray,by simpa using congrArg List.toArray entries.property,admitted⟩
  else throw "invalid original batch bounds or capability"

theorem Batch.request_order (batch : Batch secret requests) : batch.entries.map (·.request) = requests := batch.order

/-- Public images are unrelated to authorization. Every entry carries its own
registry membership, exact capability and complete request binding. -/
theorem Batch.registered (batch : Batch secret requests) (i : Fin batch.entries.size) :
    batch.entries[i].binding.source ∈ batch.sources := batch.entries[i].binding.member

end Eggshell.Synapses.ReadBoundary
