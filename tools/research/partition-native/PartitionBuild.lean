module
public import VectorPartition
public import Eggshell.CandidateDomain
public import Eggshell.SourceDelta

@[expose] public section
namespace Eggshell.PartitionBuild
open Lean DB

def check (value : Bool) (message : String) : IO Unit :=
  unless value do throw (IO.userError message)

structure Row where
  key : String
  block : Nat
  position : Nat
  deriving Inhabited

structure Catalogue where
  blocks : VectorBlocks.Ready
  rows : Array Row
  descriptors : Std.HashMap Nat VectorBlocks.Block

def catalogue (blocks : VectorBlocks.Ready) : IO Catalogue := do
  let listed ← blocks.snapshot.foldRange ⟨"row:","row;"⟩ (fun xs row =>
    pure (if row.2.isSome then row::xs else xs)) []
  check (listed.length == blocks.manifest.rows) "incomplete original row directory"
  let mut rows := Array.replicate blocks.manifest.rows (default : Row)
  let mut positions : Std.HashSet Nat := {}
  let mut byKey : Std.HashMap String Nat := {}
  let mut descriptors : Std.HashMap Nat VectorBlocks.Block := {}
  for (encodedKey,raw) in listed do
    let some raw := raw | throw (IO.userError "withdrawn original row")
    let key := String.ofList (encodedKey.toList.drop 4)
    let (entry,tail) ← IO.ofExcept (VectorBlocks.entryCodec.decode raw.toList)
    check (tail.isEmpty && (VectorBlocks.entryCodec.encode entry).toByteArray == raw &&
      Receipt.validId key && entry.row < rows.size && !positions.contains entry.row && !byKey.contains key)
      "invalid or repeated original coordinate"
    let block ← match descriptors[entry.block]? with
      | some block => pure block
      | none => do
        let block ← VectorBlocks.descriptor blocks entry.block
        descriptors := descriptors.insert entry.block block
        pure block
    let absolute := blocks.manifest.offset+entry.row*blocks.manifest.rowBytes
    check (block.offset ≤ absolute && absolute+blocks.manifest.rowBytes ≤ block.offset+block.bytes)
      "original row exceeds its authenticated block"
    rows := rows.set! entry.row ⟨key,entry.block,entry.row⟩
    positions := positions.insert entry.row
    byKey := byKey.insert key entry.row
  check (positions.size == rows.size && descriptors.size == blocks.manifest.blocks)
    "original numerical catalogue does not cover its publication"
  return ⟨blocks,rows,descriptors⟩

/-- Stream only the requested original positions. The full vectors and all
query-by-source scores never become a JSON catalogue. -/
def walk (source : Catalogue) (positions : Array Nat) (visit : Nat → Row → ByteArray → IO Unit) : IO Unit := do
  let cache ← VectorBlocks.Cache.make
  let current ← IO.mkRef (none : Option VectorBlocks.Cached)
  let scope := (toJson source.blocks.snapshot.head).compress
  for (position,index) in positions.toList.zipIdx do
    let some row := source.rows[position]? | throw (IO.userError "foreign streaming position")
    let some block := source.descriptors[row.block]? | throw (IO.userError "missing original block")
    let load := do
      let checked ← VectorBlocks.readBlock source.blocks cache row.block block
      current.set (some ⟨scope,row.block,block,checked⟩)
      return checked
    let checked ← match ← current.get with
      | some known =>
        if known.id == row.block then
          if same : known.block = block then pure (same ▸ known.payload)
          else throw (IO.userError "streamed block descriptor changed")
        else load
      | none => load
    let relative := source.blocks.manifest.offset+row.position*source.blocks.manifest.rowBytes-block.offset
    if inside : relative+source.blocks.manifest.rowBytes ≤ block.bytes then
      let slot : VectorBlocks.Slot block source.blocks.manifest.rowBytes := ⟨relative,inside⟩
      visit index row (checked.slice slot)
    else throw (IO.userError "streamed row exceeds original block")

def rankedHash (domain : String) (source : Catalogue) (positions : Array Nat) : List Nat :=
  ((positions.toList.map fun i => (Sha256.hex (domain++"\n"++source.rows[i]!.key).toUTF8,i)).mergeSort
    (fun a b => a.1 < b.1 || (a.1 == b.1 && a.2 ≤ b.2))).map Prod.snd

def implementation := Sha256.hex (include_str "PartitionBuild.lean").toUTF8
def contract (model encoder : String) := Sha256.hex (toJson
  [model,encoder,VectorPartition.implementation,implementation]).compress.toUTF8
def folder (root : System.FilePath) (model encoder : String) := root / "partition" / contract model encoder

/-- A different head is reusable only if the actual publication chain proves
that no original owner was added or removed. Missing history never means empty. -/
def sourceCompatible (source : PageMap.Snapshot) (before : PageMap.Head) : IO Bool := do
  if before == source.head then return true
  let some delta ← SourceDelta.read? source before | return false
  return delta.owners.isEmpty

def open? (root : System.FilePath) (model encoder : String) (source : PageMap.Snapshot)
    (matrix : VectorMatrix.Ready) (blocks : VectorBlocks.Ready) : IO (Option VectorPartition.Ready) := do
  let path := folder root model encoder
  let some snapshot ← PageMap.open? path | return none
  let some raw ← snapshot.get "ready" | return none
  unless raw.size ≤ 65536 do throw (IO.userError "oversized partition readiness")
  let some text := String.fromUTF8? raw | throw (IO.userError "invalid partition readiness")
  let header : VectorPartition.Header ← IO.ofExcept (Json.parse text >>= fromJson?)
  unless header.basis.matrix == matrix.snapshot.head && header.basis.blocks == blocks.snapshot.head &&
      header.basis.width*8 == blocks.manifest.rowBytes &&
      (← sourceCompatible source header.basis.source) do return none
  VectorPartition.open? path header.basis

structure Preparation where
  mode : String
  points : Nat
  cells : Nat
  readMs : Nat := 0
  trainingMs : Nat := 0
  assignmentMs : Nat := 0
  writtenBytes : Nat := 0
  elapsedMs : Nat := 0
  deriving ToJson

/-- Explicit maintenance only. Discovery-role membership comes from the
current original domain; focus projections cannot consume its nomination budget. -/
def prepare (root : System.FilePath) (model encoder : String) (source : PageMap.Snapshot)
    (matrix : VectorMatrix.Ready) (blocks : VectorBlocks.Ready) : IO Preparation := do
  let started ← IO.monoMsNow
  if let some ready ← open? root model encoder source matrix blocks then
    return {
      mode := "warm"
      points := ready.header.basis.rows
      cells := ready.header.cells
      elapsedMs := (← IO.monoMsNow)-started }
  let some domain ← CandidateDomain.openShared? source |
    throw (IO.userError "partition requires the prepared original domain")
  let input ← catalogue blocks
  let eligibleKeys := Eggshell.hashDistinct (domain.documents.flatMap (·.windows))
  let wanted := Std.HashSet.ofList eligibleKeys
  let positions := (input.rows.toList.zipIdx).filterMap fun (row,index) =>
    if wanted.contains row.key then some index else none
  check (positions.length == eligibleKeys.length && !positions.isEmpty) "partition eligible rows are missing"
  let positions := positions.toArray
  let samplePositions := (rankedHash "training" input positions).take VectorPartition.sampleCapacity
  let sampled := Std.HashSet.ofList samplePositions
  let samples ← IO.mkRef ([] : List VectorPartition.Sample)
  walk input positions fun _ row raw => do
    if sampled.contains row.position then
      let values ← IO.ofExcept (VectorPartition.decode raw)
      samples.modify (VectorPartition.Sample.mk row.key values :: ·)
  let points := (← samples.get).reverse
  check (points.length == samplePositions.length) "partition lost its fixed training sample"
  let readMs := (← IO.monoMsNow)-started
  let beginTraining ← IO.monoMsNow
  let trained := VectorPartition.train points
  let geometry := VectorPartition.compile trained.tree
  let runtime ← IO.ofExcept (VectorPartition.restore geometry (blocks.manifest.rowBytes/8))
  let trainingMs := (← IO.monoMsNow)-beginTraining
  let beginAssign ← IO.monoMsNow
  let keys ← IO.mkRef (Array.replicate geometry.cells (#[] : Array String))
  let sums ← IO.mkRef (Array.replicate geometry.cells (VectorPartition.zero (blocks.manifest.rowBytes/8)))
  walk input positions fun _ row raw => do
    let values ← IO.ofExcept (VectorPartition.decode raw)
    let cell ← IO.ofExcept (VectorPartition.assign runtime row.key values)
    keys.modify fun table => table.set! cell ((table[cell]!).push row.key)
    sums.modify fun table => table.set! cell (VectorPartition.add table[cell]! values)
  let cellKeys ← keys.get
  let cellSums ← sums.get
  let cells := cellKeys.mapIdx fun i keys => VectorPartition.Cell.mk (VectorPartition.normalize cellSums[i]!) keys
  let assignmentMs := (← IO.monoMsNow)-beginAssign
  let eligibility := Sha256.hex (toJson (eligibleKeys.mergeSort (· ≤ ·))).compress.toUTF8
  let basis : VectorPartition.Basis := ⟨source.head,matrix.snapshot.head,blocks.snapshot.head,
    eligibility,positions.size,blocks.manifest.rowBytes/8⟩
  check ((← PageMap.pin source.directory).head == source.head &&
    (← PageMap.pin matrix.snapshot.directory).head == matrix.snapshot.head &&
    (← PageMap.pin blocks.snapshot.directory).head == blocks.snapshot.head)
    "original basis changed during partition preparation"
  let path := folder root model encoder
  FileSystem.privateDirectory (root / "partition")
  let before ← PageMap.open? path
  let prepared ← VectorPartition.publish path basis geometry cells
  let some _ ← open? root model encoder source matrix blocks |
    throw (IO.userError "partition unavailable after publication")
  return {
    mode := if before.isSome then "replaced" else "prepared"
    points := basis.rows
    cells := cells.size
    readMs
    trainingMs
    assignmentMs
    writtenBytes := prepared.head.bytes-(before.map (·.head.bytes)).getD 0
    elapsedMs := (← IO.monoMsNow)-started }

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

