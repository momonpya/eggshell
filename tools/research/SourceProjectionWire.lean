module
public import Eggshell.CanonicalSourcePrepared
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
  deriving ToJson, FromJson

structure EncodedRow where
  file : Nat
  line : Nat
  code : String
  origins : Array EncodedOrigin
  deriving ToJson, FromJson

structure Wire where
  identity : Json
  reuse : Shared.Reuse
  files : Array File
  occurrences : Array Occurrence
  scopes : Array Scope
  rows : Array (String × Array EncodedRow)
  layouts : Array (String × List Recipe.Entry)
  deriving ToJson, FromJson

structure Tables where
  files : Directory File
  occurrences : Directory Occurrence
  scopes : Directory Scope

def Tables.fromProjection (projection : Shared.Projection) : Tables :=
  let rows := projection.rows.toList.flatMap (fun pair => pair.2.toList)
  let origins := rows.flatMap (fun row => row.origins.toList)
  ⟨directory (rows.map (·.key.file)),directory (origins.map (·.occurrence)),
    directory (origins.map (fun origin => scope origin.binding))⟩

def encodeOrigin (tables : Tables) (origin : Origin) : EncodedOrigin :=
  ⟨tables.occurrences.index origin.occurrence,tables.scopes.index (scope origin.binding),
    origin.binding.first,origin.binding.limit⟩

def encodeRow (tables : Tables) (row : StoredRow) : EncodedRow :=
  ⟨tables.files.index row.key.file,row.key.line,row.code,row.origins.map (encodeOrigin tables)⟩

def packUsing (tables : Tables) (projection : Shared.Projection) : Wire :=
  ⟨projection.identity,projection.reuse,tables.files.values.toArray,tables.occurrences.values.toArray,
    tables.scopes.values.toArray,projection.rows.map (fun (owner,rows) =>
      (owner,rows.map (encodeRow tables))),projection.layouts⟩

def pack (projection : Shared.Projection) : Wire := packUsing (Tables.fromProjection projection) projection

def readOrigin (wire : Wire) (encoded : EncodedOrigin) : Option Origin := do
  let occurrence ← wire.occurrences[encoded.occurrence]?
  let fields ← wire.scopes[encoded.scope]?
  return ⟨occurrence,⟨fields.database,fields.owner,fields.work,encoded.first,encoded.limit⟩⟩

def readRow (wire : Wire) (encoded : EncodedRow) : Option StoredRow := do
  let file ← wire.files[encoded.file]?
  let origins ← encoded.origins.mapM (readOrigin wire)
  return ⟨⟨file,encoded.line⟩,encoded.code,origins⟩

def unpack (wire : Wire) : Option Shared.Projection := do
  let rows ← wire.rows.mapM fun (owner,rows) => do
    return (owner,← rows.mapM (readRow wire))
  return ⟨wire.identity,rows,wire.reuse,wire.layouts⟩

theorem list_mapM_roundtrip {α β : Type} (values : List α) (encode : α → β) (decode : β → Option α)
    (one : ∀ value ∈ values, decode (encode value) = some value) :
    (values.map encode).mapM decode = some values := by
  induction values with
  | nil => rfl
  | cons first rest ih =>
      simp only [List.map_cons,List.mapM_cons,one first (by simp)]
      rw [ih (fun value member => one value (by simp [member]))]
      rfl

theorem array_mapM_roundtrip {α β : Type} (values : Array α) (encode : α → β) (decode : β → Option α)
    (one : ∀ value ∈ values, decode (encode value) = some value) :
    (values.map encode).mapM decode = some values := by
  rw [Array.mapM_eq_mapM_toList]
  simp only [Array.toList_map]
  rw [list_mapM_roundtrip _ encode decode (fun value member => one value (by simpa using member))]
  simp

theorem origin_roundtrip (tables : Tables) (projection : Shared.Projection) (origin : Origin)
    (occurrence : origin.occurrence ∈ tables.occurrences.values)
    (fields : scope origin.binding ∈ tables.scopes.values) :
    readOrigin (packUsing tables projection) (encodeOrigin tables origin) = some origin := by
  simp only [readOrigin,packUsing,encodeOrigin]
  rw [tables.occurrences.resolves _ occurrence,tables.scopes.resolves _ fields]
  rfl

theorem row_roundtrip (tables : Tables) (projection : Shared.Projection) (row : StoredRow)
    (file : row.key.file ∈ tables.files.values)
    (origins : ∀ origin ∈ row.origins, origin.occurrence ∈ tables.occurrences.values ∧
      scope origin.binding ∈ tables.scopes.values) :
    readRow (packUsing tables projection) (encodeRow tables row) = some row := by
  simp only [readRow,encodeRow]
  change (do
    let file ← tables.files.values.toArray[tables.files.index row.key.file]?
    let origins ← (row.origins.map (encodeOrigin tables)).mapM (readOrigin (packUsing tables projection))
    pure ⟨⟨file,row.key.line⟩,row.code,origins⟩) = some row
  rw [tables.files.resolves _ file]
  rw [array_mapM_roundtrip row.origins (encodeOrigin tables) _ (fun origin member =>
    origin_roundtrip tables projection origin (origins origin member).1 (origins origin member).2)]
  rfl

theorem unpack_pack (projection : Shared.Projection) : unpack (pack projection) = some projection := by
  let tables := Tables.fromProjection projection
  have one (pair : String × Array StoredRow) (member : pair ∈ projection.rows) (row : StoredRow)
      (present : row ∈ pair.2) :
      readRow (packUsing tables projection) (encodeRow tables row) = some row := by
    apply row_roundtrip
    · apply directory_member _ _ |>.mpr
      exact List.mem_map.mpr ⟨row,List.mem_flatMap.mpr ⟨pair,by simpa using member,by simpa using present⟩,rfl⟩
    · intro origin belongs
      have rowMember : row ∈ projection.rows.toList.flatMap (fun pair => pair.2.toList) :=
        List.mem_flatMap.mpr ⟨pair,by simpa using member,by simpa using present⟩
      have originMember : origin ∈ (projection.rows.toList.flatMap (fun pair => pair.2.toList)).flatMap
          (fun row => row.origins.toList) := List.mem_flatMap.mpr ⟨row,rowMember,by simpa using belongs⟩
      constructor
      · apply directory_member _ _ |>.mpr
        exact List.mem_map.mpr ⟨origin,originMember,rfl⟩
      · apply directory_member _ _ |>.mpr
        exact List.mem_map.mpr ⟨origin,originMember,rfl⟩
  have rows : ((packUsing tables projection).rows).mapM (fun (owner,rows) => do
      return (owner,← rows.mapM (readRow (packUsing tables projection)))) = some projection.rows := by
    change (projection.rows.map (fun (owner,rows) => (owner,rows.map (encodeRow tables)))).mapM
      (fun (owner,rows) => do return (owner,← rows.mapM (readRow (packUsing tables projection)))) = _
    refine array_mapM_roundtrip (β := String × Array EncodedRow) projection.rows
      (fun (owner,rows) => (owner,rows.map (encodeRow tables)))
      (fun (owner,rows) => do return (owner,← rows.mapM (readRow (packUsing tables projection)))) ?_
    intro pair member
    simp only
    rw [array_mapM_roundtrip pair.2 (encodeRow tables) _ (one pair member)]
    rfl
  change unpack (packUsing tables projection) = some projection
  unfold unpack
  rw [rows]
  rfl

end Eggshell.Research.SourceProjectionWire
