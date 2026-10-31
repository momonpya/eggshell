module
public import tools.research.OwnerPalette
public import tools.research.PublishedPlanMetadata
public import tools.research.PreparedRangeCoverage
public import tools.research.ScopeAlternatives
@[expose] public section

namespace Eggshell.Synapses.PreparedSourceView
open Lean DB CanonicalSource

def requireSome (value : Option α) (message : String) : Except String α :=
  match value with | some value => .ok value | none => .error message

/-- Metadata is never a StoredRow or a Delivery.Part. There is no body to
accidentally render or parse before selection. -/
structure RowRef where
  key : Key
  origins : Array Origin
  cost : Nat × Nat
  references : Array String
  deriving BEq

structure UnitRef where
  keys : Array Key
  ranges : List (Nat × Nat)
  coverage : Eggshell.Research.PreparedRangeCoverage.CoverageIndex ranges := Eggshell.Research.PreparedRangeCoverage.CoverageIndex.prepare ranges

structure Extent where
  first : Nat
  last : Nat
  deriving BEq,Hashable,ToJson,FromJson

def compileExtents (rows : Array StoredRow) : Array Extent :=
  (Eggshell.Research.ScopeAlternatives.shapes rows).map fun shape =>
    ⟨rows[shape.first].key.line,rows[shape.last].key.line⟩

structure OwnerStored where
  plan : PublishedPlanMetadata.Stored
  descriptor : OwnerPalette.Descriptor
  records : List (List Nat)
  scopes : Array (File × Array Extent)
  deriving ToJson,FromJson

structure OwnerReady where
  stored : OwnerStored
  rows : Array RowRef
  units : Array UnitRef
  json : Json
  bytes : Nat

def references (origins : Array Origin) : Array String :=
  (hashDistinct (origins.toList.map fun origin =>
    (toJson (origin.binding.database,origin.binding.owner,origin.binding.work,origin.occurrence)).compress)).toArray

def ownerStored (owner : String) (stored : Recipe.Stored) (layout : Recipe.Checked stored.rows) : OwnerStored :=
  let files := stored.rows.foldl (fun (files : Std.HashMap File (Array StoredRow)) row =>
    files.insert row.key.file ((files[row.key.file]?.getD #[]).push row)) {}
  ⟨(PublishedPlanMetadata.prepare owner stored layout).metadata,
    OwnerPalette.describe stored layout,stored.records.map (·.indices),
    files.toArray.map (fun (file,rows) => (file,compileExtents rows))⟩

theorem owner_stored_costs (owner : String) (stored : Recipe.Stored) (layout : Recipe.Checked stored.rows) :
    (ownerStored owner stored layout).plan.costs = stored.rows.map (fun row =>
      ((Packet.rowText row).length,(Packet.rowText row).utf8ByteSize)) :=
  by simpa only [ownerStored] using (PublishedPlanMetadata.prepare owner stored layout).costs_exact

def decodeOwner (database owner : String) (stored : OwnerStored) : Except String OwnerReady := do
  unless stored.plan.owner == owner && stored.descriptor.inScope database owner &&
      stored.plan.costs.size == stored.descriptor.rows.size &&
      stored.records.all (fun record => !record.isEmpty && record.all (· < stored.descriptor.rows.size)) &&
      stored.scopes.all (fun (file,extents) => stored.descriptor.files.contains file &&
        extents.all (fun extent => 0 < extent.first && extent.first ≤ extent.last)) do
    throw "published owner view crosses its original scope or row domain"
  let rows ← stored.descriptor.rows.mapIdxM fun index row => do
    let some file := stored.descriptor.files[row.file]? | throw "published file coordinate is missing"
    let some origins := row.origins.mapM stored.descriptor.origin? | throw "published origin is missing"
    unless stored.plan.costs[index]? == some row.cost do throw "published original costs disagree"
    return ({key := ⟨file,row.line⟩,origins,cost := row.cost,references := references origins} : RowRef)
  let units ← stored.plan.units.mapM fun unit => do
    unless !unit.indices.isEmpty && unit.indices.all (· < rows.size) do throw "published original unit is outside its rows"
    let keys ← unit.indices.toArray.mapM fun index =>
      requireSome ((rows[index]?).map (·.key)) "published unit row is missing"
    return ({keys,ranges := unit.ranges} : UnitRef)
  let json := toJson stored.descriptor
  return ⟨stored,rows,units,json,json.compress.utf8ByteSize⟩

def ownerName (owner : String) : String := "view-owner:" ++ owner

def publishOwner (writer : PageMap.Writer) (owner : String) (stored : Recipe.Stored) : IO Unit := do
  unless stored.rows.all (fun row => row.origins.all (·.binding.owner == owner)) do
    throw (IO.userError "published view crosses its original owner")
  let layout ← IO.ofExcept (Recipe.check stored.rows stored.records)
  let bytes := (toJson (ownerStored owner stored layout)).compress.toUTF8
  unless bytes.size ≤ 32*1024*1024 do throw (IO.userError "published owner view exceeds its bound")
  Persistence.Store.putPayload writer (ownerName owner) bytes

def readValue [FromJson α] (snapshot : PageMap.Snapshot) (key : String) : IO α := do
  let descriptor ← snapshot.get key
  unless descriptor.isSome do throw (IO.userError "source view is not prepared")
  let size ← IO.ofExcept (PageMap.payloadSize descriptor)
  unless size ≤ 32*1024*1024 do throw (IO.userError "source view exceeds its bound")
  let bytes ← snapshot.readPayload key
  unless bytes.size ≤ 32*1024*1024 do throw (IO.userError "source view exceeds its bound")
  let some text := String.fromUTF8? bytes | throw (IO.userError "source view is not UTF-8")
  IO.ofExcept (Json.parse text >>= fromJson?)

def readOwner (snapshot : PageMap.Snapshot) (database owner : String) : IO OwnerReady := do
  let stored ← readValue snapshot (ownerName owner)
  IO.ofExcept (decodeOwner database owner stored)

def bindings (owner : String) (rows : Array RowRef) : List (Nat × Nat) :=
  hashDistinct (rows.toList.flatMap fun row => row.origins.toList.filterMap fun origin =>
    if origin.binding.owner == owner then some (origin.binding.first,origin.binding.limit) else none)

/-- Only query groups are assembled here. The complete base catalogue and
its range unions are resident publication metadata. -/
def groupedUnits (owner : String) (ready : OwnerReady)
    (groups : List (List (Nat × Nat))) : Except String (Array UnitRef) := do
  let mut units := ready.units
  let mut seen := Std.HashSet.ofArray (ready.units.map (·.ranges))
  for spans in groups do
    let requested := (Array.range ready.rows.size).toList.filter fun index =>
      (ready.rows[index]?).any fun row => row.origins.any fun origin =>
        origin.binding.owner == owner && spans.any fun (first,limit) =>
          first < origin.binding.limit && origin.binding.first < limit
    let selected := hashDistinct (requested ++ (ready.stored.records.filter fun record =>
      record.any requested.contains).flatten)
    if selected.isEmpty then continue
    let rows ← selected.toArray.mapM fun index => requireSome (ready.rows[index]?) "source group escaped its row domain"
    let ranges := bindings owner rows
    if seen.contains ranges then continue
    seen := seen.insert ranges
    units := units.push {keys := rows.map (·.key),ranges}
  return units

/-- A genuinely federated view remaps already-published record identities.
It never reconstructs boundaries from code. Singleton coverage is retained
for rows without a bounded record in the joined view. -/
def federatedUnits (owner : String) (parts : Array OwnerReady) (rows : Array RowRef)
    (groups : List (List (Nat × Nat))) : Except String (Array UnitRef) := do
  if parts.size == 1 then
    let some ready := parts[0]? | throw "federated owner disappeared"
    return ← groupedUnits owner ready groups
  let positions := Std.HashMap.ofArray (rows.mapIdx fun index row => (row.key,index))
  let mut records := []
  for part in parts do
    for record in part.stored.records do
      let remapped ← record.mapM fun index => do
        let row ← requireSome (part.rows[index]?) "federated record escaped its owner"
        requireSome positions[row.key]? "federation lost an original record row"
      records := records ++ [remapped]
  records := hashDistinct records
  let covered := Std.HashSet.ofList records.flatten
  let catalogue := records ++ (Array.range rows.size).toList.filterMap fun index =>
    if covered.contains index then none else some [index]
  let requested := groups.map fun spans =>
    (Array.range rows.size).toList.filter fun index => (rows[index]?).any fun row =>
      row.origins.any fun origin => origin.binding.owner == owner && spans.any fun (first,limit) =>
        first < origin.binding.limit && origin.binding.first < limit
  let candidates := catalogue ++ requested.map (fun indices =>
    hashDistinct (indices ++ (records.filter (fun record => record.any indices.contains)).flatten))
  let mut seen : Std.HashSet (List (Nat × Nat)) := {}
  let mut units := #[]
  for indices in candidates do
    if indices.isEmpty then continue
    let selected ← indices.toArray.mapM fun index => requireSome (rows[index]?) "federated unit escaped its rows"
    let ranges := bindings owner selected
    if seen.contains ranges then continue
    seen := seen.insert ranges
    units := units.push {keys := selected.map (·.key),ranges}
  return units

structure FileStored where
  file : File
  order : String
  stem : String
  extents : Array Extent
  deriving ToJson,FromJson

def fileStored (file : File) : FileStored :=
  ⟨file,(toJson file).compress,Index.contentKey file,#[]⟩

def fileName (file : File) : String := "view-file:" ++ Index.contentKey file

def publishFile (writer : PageMap.Writer) (file : File) : IO Unit := do
  let bytes := (toJson (fileStored file)).compress.toUTF8
  unless bytes.size ≤ 32*1024*1024 do throw (IO.userError "published file view exceeds its bound")
  Persistence.Store.putPayload writer (fileName file) bytes

structure FileReady where
  stored : FileStored
  ordered : stored.order = (toJson stored.file).compress
  identity : stored.stem = Index.contentKey stored.file

def FileReady.addExtents (ready : FileReady) (extents : Array Extent) : FileReady :=
  ⟨{ready.stored with extents := (hashDistinct (ready.stored.extents.toList ++ extents.toList)).toArray},
    ready.ordered,ready.identity⟩

def readFile (snapshot : PageMap.Snapshot) (file : File) : IO FileReady := do
  let stored : FileStored ← readValue snapshot (fileName file)
  unless stored.file == file && stored.file.valid && stored.extents.all
      (fun range => 0 < range.first && range.first ≤ range.last) do
    throw (IO.userError "published source scopes changed their file identity")
  if ordered : stored.order = (toJson stored.file).compress then
    if identity : stored.stem = Index.contentKey stored.file then return ⟨stored,ordered,identity⟩
    else throw (IO.userError "published file identity differs from its source")
  else throw (IO.userError "published file order differs from its source")

/-- Existing canonical code remains behind a fetch API. This join combines
only keys, original bindings and costs; it cannot validate or reparse code. -/
def join (parts : Array RowRef) (files : Std.HashMap File FileReady) : Except String (Array RowRef) := do
  let mut rows : Std.HashMap Key RowRef := {}
  for row in parts do
    unless files.contains row.key.file do throw "source view has no prepared file identity"
    if let some previous := rows[row.key]? then
      unless previous.cost == row.cost do throw "conflicting published original costs"
      rows := rows.insert row.key {previous with
        origins := (hashDistinct (previous.origins.toList ++ row.origins.toList)).toArray,
        references := (hashDistinct (previous.references.toList ++ row.references.toList)).toArray}
    else rows := rows.insert row.key row
  return rows.toArray.map Prod.snd |>.qsort fun a b =>
    if a.key.file == b.key.file then a.key.line < b.key.line
    else
      let first := (files[a.key.file]?).map (·.stored.order) |>.getD ""
      let second := (files[b.key.file]?).map (·.stored.order) |>.getD ""
      first < second

structure Domain where
  rows : Array RowRef
  costs : Array (Nat × Nat)
  fileIds : Std.HashMap File Nat
  rowIds : Std.HashMap Key Nat
  payloads : Array Nat
  files : Std.HashMap File FileReady

def domain (rows : Array RowRef) (files : Std.HashMap File FileReady)
    (frames : Array (Nat × Nat)) : Except String Domain := do
  let mut references : Std.HashMap File (Std.HashSet String) := {}
  for row in rows do
    references := references.insert row.key.file (row.references.foldl
      (fun found reference => found.insert reference) (references[row.key.file]?.getD {}))
  let mut costs := frames
  let mut fileIds := {}
  let mut rowIds := {}
  let mut payloads := #[]
  for row in rows do
    unless fileIds.contains row.key.file do
      let some file := files[row.key.file]? | throw "source cost view has no prepared file"
      let refs := (references[row.key.file]?.getD {}).toArray.qsort (· < ·)
      let caption := "SOURCE " ++ file.stored.order ++ "\nORIGINAL READS " ++ (toJson refs).compress ++ "\nCODE\nEND SOURCE\n"
      fileIds := fileIds.insert row.key.file costs.size
      costs := costs.push (caption.length,caption.utf8ByteSize)
    rowIds := rowIds.insert row.key costs.size
    payloads := payloads.push costs.size
    costs := costs.push row.cost
  return ⟨rows,costs,fileIds,rowIds,payloads,files⟩

structure Bound (p : SharedCoverage.Problem) where
  sourceRows : Array (RowRef × Fin p.costs.size)
  frames : Std.HashMap File (Fin p.costs.size)

def bind (data : Domain) (p : SharedCoverage.Problem) : Option (Bound p) := do
  unless data.rows.size == data.payloads.size do none
  let checked := fun index => do
    let expected ← data.costs[index]?
    unless p.costs[index]? == some expected do none
    if bound : index < p.costs.size then some (⟨index,bound⟩ : Fin p.costs.size) else none
  let sourceRows ← (data.rows.zip data.payloads).mapM fun (row,index) => do
    return (row,← checked index)
  let mut frames := {}
  for (file,index) in data.fileIds.toArray do frames := frames.insert file (← checked index)
  return ⟨sourceRows,frames⟩

def Bound.selectedRows (bound : Bound p) (nodes : List Nat) : Array RowRef :=
  let selected := Std.HashSet.ofList nodes
  bound.sourceRows.filterMap fun (row,atom) => if selected.contains atom.val then some row else none

theorem Bound.selected_original (bound : Bound p) (nodes : List Nat) (row : RowRef)
    (present : row ∈ bound.selectedRows nodes) : ∃ atom, (row,atom) ∈ bound.sourceRows := by
  simp only [Bound.selectedRows,Array.mem_filterMap] at present
  obtain ⟨⟨original,atom⟩,member,accepted⟩ := present
  split at accepted
  · cases Option.some.inj accepted
    exact ⟨atom,member⟩
  · contradiction

/-- Advisory alternatives consume publication-prepared extents. There is no
code string, lexer, block parser or dependency inference on this path. -/
def prepareScopes (data : Domain) (p : SharedCoverage.Problem) (familyCount : Nat)
    (bound : Bound p) : Option (Eggshell.Research.ScopeAlternatives.Prepared p) := do
  let sourceAtoms := Std.HashSet.ofArray (bound.sourceRows.map Prod.snd)
  let freeFrames := (List.finRange p.costs.size).filter fun atom =>
    atom.val < familyCount && p.costs[atom] == (0,0)
  let mut byAnchor : Std.HashMap (Fin p.costs.size) (List (Fin p.offers.size)) := {}
  for index in List.finRange p.offers.size do
    if let some anchor := p.offers[index].closure.find? sourceAtoms.contains then
      byAnchor := byAnchor.insert anchor (index :: byAnchor[anchor]?.getD [])
  let rows := Std.HashMap.ofArray (bound.sourceRows.map fun (row,atom) => (row.key,atom))
  let mut scopes := #[]
  let mut recognized := 0
  let mut inspected := 0
  for (file,ready) in data.files.toArray do
    for extent in ready.stored.extents do
      recognized := recognized+1
      let count := extent.last+1-extent.first
      if count > rows.size then continue
      let body := (Array.range count).mapM fun offset => rows[(⟨file,extent.first+offset⟩ : Key)]?
      let some body := body | continue
      let frame ← bound.frames[file]?
      let closure := hashDistinct (freeFrames ++ frame :: body.toList)
      let paid := Std.HashSet.ofList closure
      let possible := hashDistinct (closure.flatMap (fun atom => byAnchor[atom]?.getD []))
      inspected := inspected+possible.length
      let contained := possible.filter fun index => p.offers[index].closure.all paid.contains
      let covers := hashDistinct (contained.flatMap fun index => p.offers[index].covers)
      if covers.isEmpty then continue
      let charge := closure.foldl (fun total atom =>
        (total.1+p.costs[atom].1,total.2+p.costs[atom].2)) p.fixed
      if p.limit.1 < charge.1 || p.limit.2 < charge.2 then continue
      scopes := scopes.push {
        first := ⟨file,extent.first⟩,last := ⟨file,extent.last⟩,
        rows := count,offer := {closure,covers},contained}
  return ⟨scopes,recognized,inspected⟩

end Eggshell.Synapses.PreparedSourceView
