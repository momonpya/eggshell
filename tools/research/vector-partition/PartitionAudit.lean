import VectorPartition
import Eggshell.SearchProvider
import Eggshell.Numerical
import Eggshell.CandidateDomain
import Lean

open Lean Eggshell DB
namespace PartitionAudit

private def check (yes : Bool) (message : String) : IO Unit :=
  unless yes do throw (IO.userError message)

run_meta do
  for name in #[``VectorPartition.training_preserves_samples,``VectorPartition.node_roundtrip] do
    for dep in ← Lean.collectAxioms name do
      unless #[``propext,``Classical.choice,``Quot.sound].contains dep do
        throwError "unapproved partition proof dependency: {dep}"
  logInfo "Partition sample preservation and canonical node codec checked"

structure Row where
  key : String
  block : Nat
  position : Nat
  deriving Inhabited

structure Catalogue where
  blocks : VectorBlocks.Ready
  rows : Array Row
  descriptors : Std.HashMap Nat VectorBlocks.Block
  byKey : Std.HashMap String Nat

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
  return ⟨blocks,rows,descriptors,byKey⟩

/-- Stream only the requested original positions. The full vectors and all
query-by-source scores never become a JSON catalogue. -/
def walk (source : Catalogue) (positions : Array Nat) (visit : Nat → Row → ByteArray → IO Unit) : IO Unit := do
  let cache ← VectorBlocks.Cache.make
  for (position,index) in positions.toList.zipIdx do
    let some row := source.rows[position]? | throw (IO.userError "foreign streaming position")
    let some block := source.descriptors[row.block]? | throw (IO.userError "missing original block")
    let checked ← VectorBlocks.readBlock source.blocks cache row.block block
    let relative := source.blocks.manifest.offset+row.position*source.blocks.manifest.rowBytes-block.offset
    if inside : relative+source.blocks.manifest.rowBytes ≤ block.bytes then
      let slot : VectorBlocks.Slot block source.blocks.manifest.rowBytes := ⟨relative,inside⟩
      visit index row (checked.slice slot)
    else throw (IO.userError "streamed row exceeds original block")

def rankedHash (domain : String) (source : Catalogue) (positions : Array Nat) : List Nat :=
  ((positions.toList.map fun i => (Sha256.hex (domain++"\n"++source.rows[i]!.key).toUTF8,i)).mergeSort
    (fun a b => a.1 < b.1 || (a.1 == b.1 && a.2 ≤ b.2))).map Prod.snd

def axisNominate (tree : VectorRoute.Tree) (query : VectorRoute.Point) (quota : Nat) : List String := Id.run do
  let mut frontier := [tree]
  let mut keys := []
  let mut leaves := 0
  while let tree::rest := frontier do
    if leaves == 128 then break
    frontier := rest
    match tree with
    | .leaf points _ => keys := points.reverse.map (·.key) ++ keys; leaves := leaves+1
    | .branch depth pivot left right =>
      let first := VectorRoute.coordinate query depth < VectorRoute.coordinate pivot depth ||
        (VectorRoute.coordinate query depth == VectorRoute.coordinate pivot depth && query.key < pivot.key)
      frontier := (if first then [left,right] else [right,left]) ++ frontier
  return keys.reverse.take quota

structure Query where
  label : String
  packed : Array ByteArray
  values : Array FloatArray
  self : Option String := none

def rawFrame (query : Query) (body : ByteArray) (rows width : Nat) : IO BlockScore.Frame := do
  let prefixBytes := query.packed.foldl (·++·) ByteArray.empty
  let raw := prefixBytes++body
  if exact : raw.size = (query.packed.size+rows)*width*8 then
    if bounded : raw.size ≤ BlockScore.maxFrameBytes then
      return ⟨raw,query.packed.size,rows,width,exact,bounded,#[],0,0,0,0⟩
    else throw (IO.userError "reference frame too large")
  else throw (IO.userError "reference frame dimensions disagree")

def fullScores (child : Numerical.Kernel) (source : Catalogue) (positions : Array Nat)
    (query : Query) : IO (FloatArray × Nat) := do
  let started ← IO.monoMsNow
  let body ← IO.mkRef ByteArray.empty
  let count ← IO.mkRef 0
  let scores ← IO.mkRef (FloatArray.emptyWithCapacity positions.size)
  let flush := do
    let rows ← count.get
    if rows == 0 then return
    let frame ← rawFrame query (← body.get) rows (source.blocks.manifest.rowBytes/8)
    let result ← IO.ofExcept (Json.parse (← Numerical.exchangeRaw child frame ((← IO.monoMsNow)+30000) (pure false)))
    check (!(result.getObjVal? "error").isOk) "reference numerical primitive failed"
    let values ← IO.ofExcept (result.getObjValAs? (Array Json) "scores")
    check (values.size == rows) "reference primitive omitted a row"
    for value in values do
      let value ← IO.ofExcept (SearchProvider.number value)
      check value.isFinite "reference primitive returned a nonfinite score"
      scores.modify (·.push value)
    body.set ByteArray.empty
    count.set 0
  walk source positions fun _ _ raw => do
    body.modify (·++raw)
    count.modify (·+1)
    if (← count.get) == 256 then flush
  flush
  let scores ← scores.get
  check (scores.size == positions.size) "full reference did not score every eligible original"
  return (scores,(← IO.monoMsNow)-started)

def fixture : IO Json := do
  let values := [1.0,0.0,-0.0,0.125].toFloatArray
  let samples := (List.range 65).map fun i =>
    VectorPartition.Sample.mk (Sha256.hex s!"identical-fixture-{i}".toUTF8) values
  let geometry := VectorPartition.compile (VectorPartition.train samples).tree
  let runtime ← IO.ofExcept (VectorPartition.restore geometry 4)
  let mut counts : Std.HashMap Nat Nat := {}
  for sample in samples do
    let cell ← IO.ofExcept (VectorPartition.assign runtime sample.key values)
    counts := counts.insert cell ((counts[cell]?.getD 0)+1)
  check (counts.size == geometry.cells && counts.toList.all (·.2 ≤ 32))
    "identical sample tie split lost coverage or overflowed"
  for node in geometry.nodes do
    let encoded := VectorPartition.nodeCodec.encode node
    let (_,tail) ← IO.ofExcept (VectorPartition.nodeCodec.decode (encoded++[7,8]))
    check (tail == [7,8]) "partition codec consumed its tail"
  let corrupt := VectorPartition.Geometry.mk #[.branch (VectorPartition.pack values) 0 "x" 0 0] 0 1
  check (VectorPartition.restore corrupt 4).toOption.isNone "cyclic assignment node accepted"
  return Json.mkObj [("identicalSamples",toJson samples.length),("cells",toJson geometry.cells),
    ("boundedTies",toJson true),("nodeCodecTail",toJson true),("cyclicNodeRejected",toJson true)]

def run (parent output : System.FilePath) : IO Unit := do
  check (!(← output.pathExists)) "keep the earlier partition trial"
  FileSystem.privateDirectory output
  let fixture ← fixture
  IO.FS.writeFile (output / "fixture.json") fixture.pretty
  let source ← PageMap.pin (parent / "fixtures/source-50000.egg")
  let some domain ← CandidateDomain.openShared? source | throw (IO.userError "original eligible domain unavailable")
  let semantic := parent / "scale-data-50000/read-cache" / source.head.identity / "semantic"
  let some matrix ← VectorMatrix.open? semantic MiniLM.model SearchProvider.encoderContract |
    throw (IO.userError "original numerical matrix unavailable")
  let some axis ← VectorRoute.open? semantic MiniLM.model SearchProvider.encoderContract matrix |
    throw (IO.userError "original axis router unavailable")
  let some blocked ← VectorBlocks.open? semantic MiniLM.model SearchProvider.encoderContract matrix axis |
    throw (IO.userError "original authenticated blocks unavailable")
  let start ← IO.monoMsNow
  let catalogue ← catalogue blocked
  let catalogueMs := (← IO.monoMsNow)-start
  let documents := domain.documents.toArray
  let ownerIds := documents.map (·.owner)
  let eligibleKeys := hashDistinct (documents.toList.flatMap (·.windows))
  let originalWindows := eligibleKeys.toArray
  let originalWindowOrdinal := eligibleKeys.zipIdx |>.foldl
    (fun m (key,i) => m.insert key i) ({} : Std.HashMap String Nat)
  let eligibleSet := Std.HashSet.ofList eligibleKeys
  let positions := (catalogue.rows.toList.zipIdx).filterMap fun (row,index) =>
    if eligibleSet.contains row.key then some index else none
  check (positions.length == eligibleKeys.length && positions.length == 50000) "eligible domain differs from fixed source"
  let positions := positions.toArray
  let eligibleIndex := ((positions.toList.zipIdx).map fun (position,index) => (catalogue.rows[position]!.key,index))
    |>.foldl (fun m (k,i) => m.insert k i) ({} : Std.HashMap String Nat)
  let samplePositions := (rankedHash "training" catalogue positions).take VectorPartition.sampleCapacity
  let sampleSet := Std.HashSet.ofList samplePositions
  let probePositions := ((rankedHash "probe" catalogue positions).filter (fun i => !sampleSet.contains i)).take 8
  let probeSet := Std.HashSet.ofList probePositions
  let samples ← IO.mkRef ([] : List VectorPartition.Sample)
  let axisPoints ← IO.mkRef ([] : List VectorRoute.Point)
  let probes ← IO.mkRef ({} : Std.HashMap Nat ByteArray)
  let start ← IO.monoMsNow
  walk catalogue positions fun _ row bytes => do
    axisPoints.modify ((← IO.ofExcept (VectorRoute.sketch row.key bytes)) :: ·)
    if sampleSet.contains row.position then
      samples.modify (VectorPartition.Sample.mk row.key (← IO.ofExcept (VectorPartition.decode bytes)) :: ·)
    if probeSet.contains row.position then probes.modify (·.insert row.position bytes)
  let materializeMs := (← IO.monoMsNow)-start
  let samples := (← samples.get).reverse
  check (samples.length == samplePositions.length) "training sample incomplete"
  let start ← IO.monoMsNow
  let trained := VectorPartition.train samples
  let geometry := VectorPartition.compile trained.tree
  let runtime ← IO.ofExcept (VectorPartition.restore geometry (blocked.manifest.rowBytes/8))
  let trainingMs := (← IO.monoMsNow)-start
  IO.eprintln s!"trained {samples.length} samples into {geometry.cells} cells in {trainingMs} ms"
  let start ← IO.monoMsNow
  let keys ← IO.mkRef (Array.replicate geometry.cells (#[] : Array String))
  let sums ← IO.mkRef (Array.replicate geometry.cells (VectorPartition.zero (blocked.manifest.rowBytes/8)))
  walk catalogue positions fun _ row bytes => do
    let values ← IO.ofExcept (VectorPartition.decode bytes)
    let cell ← IO.ofExcept (VectorPartition.assign runtime row.key values)
    keys.modify fun table => table.set! cell ((table[cell]!).push row.key)
    sums.modify fun table => table.set! cell (VectorPartition.add table[cell]! values)
  let cellKeys ← keys.get
  let cellSums ← sums.get
  let cells := cellKeys.mapIdx fun i keys => VectorPartition.Cell.mk (VectorPartition.normalize cellSums[i]!) keys
  let assignmentMs := (← IO.monoMsNow)-start
  let eligibility := Sha256.hex (toJson (eligibleKeys.mergeSort (· ≤ ·))).compress.toUTF8
  let basis : VectorPartition.Basis := ⟨source.head,matrix.snapshot.head,blocked.snapshot.head,
    eligibility,positions.size,blocked.manifest.rowBytes/8⟩
  let start ← IO.monoMsNow
  let _ ← VectorPartition.publish (output / "partition") basis geometry cells
  let some ready ← VectorPartition.open? (output / "partition") basis | throw (IO.userError "partition publication failed")
  let publishMs := (← IO.monoMsNow)-start
  check ((← VectorPartition.open? (output / "partition") {basis with rows := basis.rows+1}).isNone)
    "changed eligible basis accepted"
  let start ← IO.monoMsNow
  let eligibleAxis := (VectorRoute.prepare 0 (← axisPoints.get).reverse).tree
  let axisTrainingMs := (← IO.monoMsNow)-start
  let layout := MiniLM.layout (← Paths.installRoot)
  let options : SearchProvider.Options := {
    cache := output / "unused-query-root"
    models := layout.models }
  let privateOptions ← SearchProvider.queryOptions options
  let mut queries := #[]
  for i in [1:4] do
    let text := s!"Find kernel realtime clock observations for monotonic scheduling and elapsed timers, question {i}."
    let packed ← IO.ofExcept (← SearchProvider.vectors privateOptions text).getArr?
    let raw ← packed.mapM fun value => IO.ofExcept (value.getStr? >>= VectorMatrix.decodeHex)
    let values ← raw.mapM (IO.ofExcept ∘ VectorPartition.decode)
    queries := queries.push (Query.mk s!"natural-{i}" raw values none)
  for (position,i) in probePositions.zipIdx do
    let some raw := (← probes.get)[position]? | throw (IO.userError "held source probe unavailable")
    queries := queries.push ⟨s!"source-{i}",#[raw],#[← IO.ofExcept (VectorPartition.decode raw)],some catalogue.rows[position]!.key⟩
  let some config ← Numerical.defaultConfig? | throw (IO.userError "existing numerical runtime unavailable")
  let child : Numerical.Kernel ← IO.Process.spawn {
    cmd := config.python.toString
    args := #["-c",BlockScore.kernelSource]
    stdin := .piped
    stdout := .piped
    stderr := .inherit }
  let mut results := #[]
  try
    for query in queries do
      let (scores,referenceMs) ← fullScores child catalogue positions query
      IO.FS.writeBinFile (output / (query.label++".scores")) (VectorPartition.pack scores)
      let mut scalarBitsChecked := 0
      if query.label == "natural-1" then
        let input ← IO.ofExcept (Json.parse (← IO.FS.readFile (parent / "inputs/routed-request.json")))
        let oldDocs ← IO.ofExcept (input.getObjValAs? (Array Json) "documents")
        let oldKeys ← oldDocs.foldlM (fun keys doc => do
          return keys ++ (← IO.ofExcept (doc.getObjValAs? (Array String) "windows"))) (#[] : Array String)
        let oldBits : Array Nat ← IO.ofExcept
          (Json.parse (← IO.FS.readFile (parent / "compare-shared-0/scores.json")) >>= fromJson?)
        check (oldKeys.size == 3125 && oldBits.size == oldKeys.size) "frozen scalar score evidence changed"
        for (key,index) in oldKeys.toList.zipIdx do
          let some position := eligibleIndex[key]? | throw (IO.userError "scalar evidence outside eligible domain")
          check (scores[position]!.toBits.toNat == oldBits[index]!) "bulk reference changed an original scalar score bit"
        scalarBitsChecked := oldKeys.size
      let fullOrder := ((List.range positions.size).map fun i =>
        (scores[i]!,originalWindowOrdinal[catalogue.rows[positions[i]!]!.key]?.getD positions.size))
        |>.mergeSort SearchRank.scoreOrder
      let start ← IO.monoMsNow
      let selected ← VectorPartition.nominate ready query.values 3125
      let learnedMs := (← IO.monoMsNow)-start
      let queryPoint ← IO.ofExcept (VectorRoute.sketch
        (Persistence.Store.windowKey (Wire.hex query.packed[0]!.toList)) query.packed[0]!)
      let start ← IO.monoMsNow
      let old ← VectorRoute.nominate axis queryPoint 128
      let oldKeys := old.val.keys.filter eligibleSet.contains |>.take 3125
      let oldMs := (← IO.monoMsNow)-start
      let start ← IO.monoMsNow
      let eligibleKeys := axisNominate eligibleAxis queryPoint 3125
      let eligibleMs := (← IO.monoMsNow)-start
      let mut methods := #[]
      for (name,keys,ms) in [("axis-current",oldKeys,oldMs),("axis-eligible",eligibleKeys,eligibleMs),
          ("learned-eligible",selected.val.keys,learnedMs)] do
        let wanted := Std.HashSet.ofList keys
        check (keys.length ≤ 3125 && wanted.size == keys.length && keys.all eligibleSet.contains)
          "router returned duplicate, ineligible or excessive keys"
        let mut recalls := #[]
        for k in [8,32,128] do
          let expected := (fullOrder.take k).map fun (_,i) => originalWindows[i]!
          let found := expected.filter wanted.contains
          recalls := recalls.push (Json.mkObj [("k",toJson k),("found",toJson found.length),
            ("expected",toJson expected),("retained",toJson found)])
        let ownerScores := documents.toList.zipIdx |>.filterMap fun (document,index) => Id.run do
          let mut best : Option Float := none
          for key in document.windows do
            if wanted.contains key then
              if let some position := eligibleIndex[key]? then
                best := some (max (best.getD (-1.0e30)) scores[position]!)
          return best.map (·,index)
        let owners := (ownerScores.mergeSort SearchRank.scoreOrder).take 8 |>.map fun (_,i) => ownerIds[i]!
        methods := methods.push (Json.mkObj [("method",toJson name),("nominations",toJson keys.length),
          ("routingMs",toJson ms),("windowRecall",toJson recalls),("topOwners",toJson owners),
          ("selfPresent",toJson (query.self.map wanted.contains))])
      let fullOwners := (documents.toList.zipIdx |>.map fun (document,index) =>
        (document.windows.foldl (fun score key => match eligibleIndex[key]? with
          | some i => max score scores[i]! | none => score) (-1.0e30),index)).mergeSort SearchRank.scoreOrder
        |>.take 8 |>.map fun (_,i) => ownerIds[i]!
      if query.label == "natural-1" then
        let previous ← IO.ofExcept (Json.parse (← IO.FS.readFile (parent / "inputs/scalar-reference/result.json")))
        let original ← IO.ofExcept (previous.getObjValAs? (List Nat) "referenceRelatedRoots")
        check (original == fullOwners) "bulk owner ranking differs from the frozen complete provider"
      let result := Json.mkObj [("query",toJson query.label),("fullReferenceMs",toJson referenceMs),
        ("originalScalarBitsChecked",toJson scalarBitsChecked),
        ("storedFullProviderOwnerRankingChecked",toJson (query.label == "natural-1")),
        ("fullOwnerTop8",toJson fullOwners),("methods",toJson methods),("selection",toJson selected.val)]
      results := results.push result
      IO.FS.writeFile (output / "queries.json") (toJson results).pretty
      IO.eprintln s!"{query.label}: full={referenceMs} ms; learned={learnedMs} ms; cells={selected.val.visitedCells}"
  finally Numerical.stopRaw child
  check ((← PageMap.pin source.directory).head == source.head &&
    (← PageMap.pin matrix.snapshot.directory).head == matrix.snapshot.head &&
    (← PageMap.pin blocked.snapshot.directory).head == blocked.snapshot.head) "original publication changed"
  let record := Json.mkObj [("basis",toJson basis),("fixture",fixture),
    ("catalogueMs",toJson catalogueMs),("materializeMs",toJson materializeMs),
    ("trainingMs",toJson trainingMs),("assignmentMs",toJson assignmentMs),
    ("publishMs",toJson publishMs),("axisTrainingMs",toJson axisTrainingMs),
    ("trainingSamples",toJson samples.length),("cells",toJson cells.size),
    ("cellSizes",toJson (cells.map (·.keys.size))),("sourceQueriesOutsideTraining",toJson true),
    ("queries",toJson results),("safeFloatPruningClaimed",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("sourceEmbeddingCalls",toJson (0 : Nat)),("adopted",toJson false)]
  IO.FS.writeFile (output / "result.json") record.pretty

end PartitionAudit

def main (args : List String) : IO UInt32 := do
  let [parent,output] := args | throw (IO.userError "PartitionAudit CURRENT-BLOCK-CHECKOUT NEW-OUTPUT")
  PartitionAudit.run (.mk parent) (.mk output)
  return 0
