module
public import Eggshell.CanonicalSource
public import Eggshell.HashDistinct
public import Std.Data.DHashMap.Basic
@[expose] public section

namespace Eggshell.Research.SourceProjectionWire
open Lean Eggshell.Synapses Eggshell.Synapses.CanonicalSource

/-- Full structural identity, not a display hash. Every cached ordinal retains
its meaning; a missing cache entry computes the same reference function. -/
structure Directory (α : Type) [BEq α] [LawfulBEq α] [Hashable α] where
  values : List α
  positions : Std.DHashMap α (fun value => {i : Nat // i = values.idxOf value}) := {}

variable {α : Type} [BEq α] [LawfulBEq α] [Hashable α]

def Directory.index (directory : Directory α) (value : α) : Nat :=
  match directory.positions.get? value with
  | some cached => cached.val
  | none => directory.values.idxOf value

theorem Directory.index_exact (directory : Directory α) (value : α) :
    directory.index value = directory.values.idxOf value := by
  unfold Directory.index
  cases directory.positions.get? value with
  | none => rfl
  | some cached => exact cached.property

theorem Directory.resolves (directory : Directory α) (value : α) (present : value ∈ directory.values) :
    directory.values.toArray[directory.index value]? = some value := by
  rw [directory.index_exact]
  have bound := List.idxOf_lt_length_of_mem present
  simp only [List.getElem?_toArray,List.getElem?_eq_getElem bound,List.getElem_idxOf bound]

def directory (input : List α) : Directory α :=
  let values := hashDistinct input
  let unique := HashDistinct.nodup input
  let data := values.toArray
  let add (found : Std.DHashMap α (fun value => {i : Nat // i = values.idxOf value}))
      (i : Fin data.size) := Id.run do
    have inside : i.val < values.length := by
      have bound := i.isLt
      change i.val < values.toArray.size at bound
      simpa only [List.size_toArray] using bound
    have same : data[i.val] = values[i.val] := by simp [data]
    have exactIndex : values.idxOf data[i.val] = i.val := by
      rw [same]
      have bound := List.idxOf_lt_length_of_mem (List.getElem_mem inside)
      exact (List.getElem_inj unique).mp (List.getElem_idxOf bound)
    return found.insert data[i.val] ⟨i.val,exactIndex.symm⟩
  ⟨values,(List.finRange data.size).foldl add {}⟩

theorem directory_member (input : List α) (value : α) : value ∈ (directory input).values ↔ value ∈ input := by
  change value ∈ hashDistinct input ↔ value ∈ input
  rw [HashDistinct.reference]
  exact List.mem_eraseDups

structure Scope where
  database : String
  owner : String
  work : String
  deriving BEq, ReflBEq, LawfulBEq, Hashable, ToJson, FromJson

def scope (binding : Binding) : Scope := ⟨binding.database,binding.owner,binding.work⟩

structure EncodedOrigin where
  occurrence : Nat
  scope : Nat
  first : Nat
  limit : Nat
  deriving BEq, ReflBEq, LawfulBEq, Hashable, ToJson, FromJson

structure Tables where
  files : Directory File
  occurrences : Directory Occurrence
  scopes : Directory Scope

def encodeOrigin (tables : Tables) (origin : Origin) : EncodedOrigin :=
  ⟨tables.occurrences.index origin.occurrence,tables.scopes.index (scope origin.binding),
    origin.binding.first,origin.binding.limit⟩

def Tables.fromRows (rows : Array StoredRow) : Tables :=
  let origins := rows.toList.flatMap (fun row => row.origins.toList)
  ⟨directory (rows.toList.map (·.key.file)),directory (origins.map (·.occurrence)),
    directory (origins.map (fun origin => scope origin.binding))⟩

def readOriginUsing (occurrences : Array Occurrence) (scopes : Array Scope) (encoded : EncodedOrigin) : Option Origin := do
  let occurrence ← occurrences[encoded.occurrence]?
  let fields ← scopes[encoded.scope]?
  return ⟨occurrence,⟨fields.database,fields.owner,fields.work,encoded.first,encoded.limit⟩⟩

theorem origin_tables_roundtrip (tables : Tables) (origin : Origin)
    (occurrence : origin.occurrence ∈ tables.occurrences.values)
    (fields : scope origin.binding ∈ tables.scopes.values) :
    readOriginUsing tables.occurrences.values.toArray tables.scopes.values.toArray (encodeOrigin tables origin) = some origin := by
  simp only [readOriginUsing,encodeOrigin]
  rw [tables.occurrences.resolves _ occurrence,tables.scopes.resolves _ fields]
  rfl

end Eggshell.Research.SourceProjectionWire
