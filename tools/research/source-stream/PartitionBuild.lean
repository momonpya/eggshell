module
public import VectorPartition
public import ProjectionCursor
public import ProjectionRetention
public import SourceCatalogue
public import BoundedSample
public import Eggshell.SourceDelta

@[expose] public section
namespace Eggshell.PartitionBuild
open Lean DB

def check (value : Bool) (message : String) : IO Unit :=
  unless value do throw (IO.userError message)

def implementation := Sha256.hex ((include_str "PartitionBuild.lean").toUTF8 ++
  (include_str "SourceCatalogue.lean").toUTF8 ++ (include_str "BoundedSample.lean").toUTF8)

def contract (model encoder : String) := Sha256.hex (toJson
  [model,encoder,VectorPartition.implementation,ProjectionCursor.implementation,ProjectionRetention.implementation,implementation]).compress.toUTF8

def folder (root : System.FilePath) (model encoder : String) := root / "partition" / contract model encoder

def sourceCompatible (source : PageMap.Snapshot) (before : PageMap.Head) : IO Bool := do
  if before == source.head then return true
  let some delta ← SourceDelta.read? source before | return false
  return delta.owners.isEmpty

def eligibility (source : PageMap.Snapshot) : IO String := do
  return Sha256.hex (toJson (← SourceCatalogue.stamp source)).compress.toUTF8

def open? (root : System.FilePath) (model encoder : String) (source : PageMap.Snapshot)
    (matrix : VectorMatrix.Ready) : IO (Option VectorPartition.Ready) := do
  let some ready ← VectorPartition.load? (folder root model encoder) | return none
  unless ready.header.basis.matrix == matrix.snapshot.head &&
      ready.header.basis.width*8 == (← ProjectionCursor.width matrix) &&
      ready.header.basis.eligibility == (← eligibility source) &&
      (← sourceCompatible source ready.header.basis.source) do return none
  return some ready

structure Preparation where
  mode : String
  points : Nat
  cells : Nat
  readMs : Nat := 0
  trainingMs : Nat := 0
  assignmentMs : Nat := 0
  writtenBytes : Nat := 0
  elapsedMs : Nat := 0
  changedOwners : Nat := 0
  projectionRows : Nat := 0
  addedKeys : Nat := 0
  removedKeys : Nat := 0
  touchedCells : Nat := 0
  retainedMetadataProbes : Nat := 0
  peakSampleRows : Nat := 0
  deriving ToJson

def selectSample (matrix : VectorMatrix.Ready) (references : Std.HashMap String Nat) :
    IO (BoundedSample.State ProjectionCursor.Row VectorPartition.sampleCapacity × Nat) :=
  ProjectionCursor.fold matrix (fun (sample,count) row => do
    if !references.contains row.key then return (sample,count)
    let rank := Sha256.hex ("training\n"++row.key).toUTF8 ++ "/" ++ row.key
    return (sample.insert rank row,count+1)) (BoundedSample.empty,0)

/-- Full maintenance is explicit, or selected after missing/discontinuous source
history. Rebuilding also compacts retired member slots within the new root. -/
def rebuild (root : System.FilePath) (model encoder : String) (source : PageMap.Snapshot)
    (matrix : VectorMatrix.Ready) : IO Preparation := do
  let started ← IO.monoMsNow
  let references ← SourceCatalogue.references source
  let (reservoir,eligible) ← selectSample matrix references
  check (eligible == references.size) "partition eligible rows are missing"
  let rowBytes ← ProjectionCursor.width matrix
  -- Decode the fixed hash sample in original matrix-key order, preserving
  -- the previous training and floating-point accumulation order exactly.
  let sampled := ((reservoir.entries.toList.map Prod.snd).mergeSort (fun a b => a.key ≤ b.key)).toArray
  let input : ProjectionCursor.Catalogue := ⟨matrix,sampled,rowBytes⟩
  let samples ← IO.mkRef ([] : List VectorPartition.Sample)
  ProjectionCursor.walk input (List.range sampled.size).toArray fun _ row raw => do
    let values ← IO.ofExcept (VectorPartition.decode raw)
    samples.modify (VectorPartition.Sample.mk row.key values :: ·)
  let points := (← samples.get).reverse
  check (points.length == min eligible VectorPartition.sampleCapacity) "partition lost its fixed training sample"
  let readMs := (← IO.monoMsNow)-started
  let beginTraining ← IO.monoMsNow
  let trained := VectorPartition.train points
  let geometry := VectorPartition.compile trained.tree
  let runtime ← IO.ofExcept (VectorPartition.restore geometry (input.rowBytes/8))
  let trainingMs := (← IO.monoMsNow)-beginTraining
  let beginAssign ← IO.monoMsNow
  let keys ← IO.mkRef (Array.replicate geometry.cells (#[] : Array String))
  let sums ← IO.mkRef (Array.replicate geometry.cells (VectorPartition.zero (input.rowBytes/8)))
  let assigned ← ProjectionCursor.fold matrix (fun count row => do
    if !references.contains row.key then return count
    let raw ← ProjectionCursor.readPayload matrix row
    let values ← IO.ofExcept (VectorPartition.decode raw.bytes)
    let id ← IO.ofExcept (VectorPartition.assign runtime row.key values)
    keys.modify fun table => table.set! id ((table[id]!).push row.key)
    sums.modify fun table => table.set! id (VectorPartition.add table[id]! values)
    return count+1) 0
  check (assigned == eligible) "partition assignment lost original keys"
  let cellKeys ← keys.get
  let cellSums ← sums.get
  let cells := cellKeys.mapIdx fun i members =>
    VectorPartition.Cell.mk (VectorPartition.normalize cellSums[i]!) members
  let assignmentMs := (← IO.monoMsNow)-beginAssign
  let basis : VectorPartition.Basis := ⟨source.head,matrix.snapshot.head,
    ← eligibility source,eligible,input.rowBytes/8⟩
  check ((← PageMap.pin source.directory).head == source.head &&
    (← PageMap.pin matrix.snapshot.directory).head == matrix.snapshot.head)
    "original basis changed during partition preparation"
  let path := folder root model encoder
  FileSystem.privateDirectory (root / "partition")
  let before ← PageMap.open? path
  let prepared ← VectorPartition.publish path basis geometry cells references
  let some _ ← open? root model encoder source matrix |
    throw (IO.userError "partition unavailable after publication")
  return {
    mode := if before.isSome then "rebuilt" else "prepared"
    points := basis.rows,cells := cells.size,readMs,trainingMs,assignmentMs
    writtenBytes := prepared.head.bytes-(before.map (·.head.bytes)).getD 0
    elapsedMs := (← IO.monoMsNow)-started
    projectionRows := sampled.size+eligible
    peakSampleRows := reservoir.entries.size }

structure MemberEdit where
  cell : Nat
  key : String
  count : Nat

/-- Only dirty owners and their changed original windows are read. The fixed
trained assignment computes member coordinates without a reverse directory.
Centroids remain the last trained representatives until an explicit rebuild. -/
def incremental (root : System.FilePath) (model encoder : String) (source : PageMap.Snapshot)
    (matrix : VectorMatrix.Ready) (before : VectorPartition.Ready) : IO (Option Preparation) := do
  let started ← IO.monoMsNow
  let some delta ← SourceDelta.read? source before.header.basis.source | return none
  let some history ← PageMap.HistoryReader.make? source before.header.basis.source | return none
  let some _ ← PageMap.HistoryReader.make? matrix.snapshot before.header.basis.matrix | return none
  unless before.header.basis.width*8 == (← ProjectionCursor.width matrix) &&
      before.header.basis.eligibility == (← eligibility history.snapshot) do return none
  let retention ← ProjectionRetention.check matrix before.header.basis.matrix
  unless retention.preserved do return none
  let removed ← SourceDelta.documents history.snapshot delta.owners
  let added ← SourceDelta.documents source delta.owners
  let edits := (PartitionDelta.changes (removed.flatMap (·.windows)) (added.flatMap (·.windows))).filter
    fun change => change.removed != change.added
  if edits.length > 16384 then return none
  let directory := edits.foldl (fun table edit => table.insert edit.key edit)
    ({} : Std.HashMap String PartitionDelta.Change)
  let selected ← ProjectionCursor.select matrix (edits.map (·.key))
  let runtime ← if edits.isEmpty then pure none else some <$> VectorPartition.geometry before
  let pending ← IO.mkRef (#[] : Array MemberEdit)
  let cells ← IO.mkRef ({} : Std.HashMap Nat (ByteArray × Nat))
  let rows ← IO.mkRef before.header.basis.rows
  let slots ← IO.mkRef before.header.slots
  let activated ← IO.mkRef 0
  let deactivated ← IO.mkRef 0
  let readMs := (← IO.monoMsNow)-started
  ProjectionCursor.walk selected (List.range selected.rows.size).toArray fun _ row raw => do
    let some runtime := runtime | throw (IO.userError "delta assignment geometry missing")
    let values ← IO.ofExcept (VectorPartition.decode raw)
    let id ← IO.ofExcept (VectorPartition.assign runtime row.key values)
    let some change := directory[row.key]? | throw (IO.userError "unrequested delta projection")
    let encoded ← before.snapshot.get (VectorPartition.postingKey id row.key)
    let previous ← match encoded with | none => pure 0 | some value => VectorPartition.decodeCount value
    let transition ← IO.ofExcept (PartitionDelta.checked previous change)
    if previous == transition.after then return
    let (center,count) ← match (← cells.get)[id]? with
      | some value => pure value
      | none => VectorPartition.cell before id
    let next ← if previous == 0 && transition.after > 0 then do
        rows.modify (·+1)
        activated.modify (·+1)
        pure (count+1)
      else if previous > 0 && transition.after == 0 then do
        check (count > 0 && (← rows.get) > 0) "delta unique coverage underflow"
        rows.modify (·-1)
        deactivated.modify (·+1)
        pure (count-1)
      else pure count
    if encoded.isNone then slots.modify (·+1)
    cells.modify (·.insert id (center,next))
    pending.modify (·.push ⟨id,row.key,transition.after⟩)
  let basis : VectorPartition.Basis := {before.header.basis with
    source := source.head
    matrix := matrix.snapshot.head
    eligibility := ← eligibility source
    rows := ← rows.get }
  let header : VectorPartition.Header := {before.header with basis,slots := ← slots.get}
  check ((← PageMap.pin source.directory).head == source.head &&
    (← PageMap.pin matrix.snapshot.directory).head == matrix.snapshot.head)
    "original basis changed during incremental assignment"
  let (_,_,written) ← PageMap.withWriter before.snapshot fun writer => do
    for edit in ← pending.get do
      writer.put (VectorPartition.postingKey edit.cell edit.key) (some (Wire.natural.encode edit.count).toByteArray)
    for (id,value) in (← cells.get).toList do
      writer.put (s!"cell:{id}") (some (VectorPartition.cellCodec.encode value).toByteArray)
    writer.put "ready" (some (toJson header).compress.toUTF8)
    writer.flush
    check ((← writer.root.get).any (·.rows == header.nodes+header.cells+header.slots+1))
      "incremental member coverage differs from its header"
    check ((← PageMap.pin source.directory).head == source.head &&
      (← PageMap.pin matrix.snapshot.directory).head == matrix.snapshot.head)
      "original basis changed before incremental publication"
  let some _ ← open? root model encoder source matrix |
    throw (IO.userError "incremental assignment unavailable after publication")
  return some {
    mode := "publication-delta",points := header.basis.rows,cells := header.cells,
    readMs,assignmentMs := (← IO.monoMsNow)-started-readMs,writtenBytes := written,
    elapsedMs := (← IO.monoMsNow)-started,changedOwners := delta.owners.length,
    projectionRows := selected.rows.size,addedKeys := ← activated.get,removedKeys := ← deactivated.get,
    touchedCells := (← cells.get).size,retainedMetadataProbes := retention.probes }

def prepare (root : System.FilePath) (model encoder : String) (source : PageMap.Snapshot)
    (matrix : VectorMatrix.Ready) : IO Preparation := do
  let started ← IO.monoMsNow
  if let some ready ← open? root model encoder source matrix then
    return {
      mode := "warm"
      points := ready.header.basis.rows
      cells := ready.header.cells
      elapsedMs := (← IO.monoMsNow)-started}
  if let some previous ← VectorPartition.load? (folder root model encoder) then
    if let some result ← incremental root model encoder source matrix previous then return result
  rebuild root model encoder source matrix

def share (total count index : Nat) : Nat := total/count + if index < total%count then 1 else 0

theorem share_le_total (total count index : Nat) (positive : 0 < count) : share total count index ≤ total := by
  unfold share
  split
  · rename_i extra
    have remainder : 0 < total%count := by omega
    have nonzero : 0 < total := Nat.lt_of_lt_of_le remainder (Nat.mod_le _ _)
    have many : 1 < count := by
      by_cases one : count = 1
      · rw [one,Nat.mod_one] at remainder
        omega
      · omega
    have := Nat.div_lt_self nonzero many
    omega
  · simpa using Nat.div_le_self total count

end Eggshell.PartitionBuild
