module
public import Eggshell.CanonicalSourcePrepared
public import tools.research.SourceProjectionDictionary
@[expose] public section

namespace Eggshell.Research.SourceProjectionWire
open Lean Eggshell.Synapses Eggshell.Synapses.CanonicalSource

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

def Tables.fromProjection (projection : Shared.Projection) : Tables :=
  let rows := projection.rows.toList.flatMap (fun pair => pair.2.toList)
  let origins := rows.flatMap (fun row => row.origins.toList)
  ⟨directory (rows.map (·.key.file)),directory (origins.map (·.occurrence)),
    directory (origins.map (fun origin => scope origin.binding))⟩

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
