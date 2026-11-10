module
public import tools.research.CursorBinding
public import tools.research.CursorPage
@[expose] public section
open Lean Eggshell Eggshell.DB Eggshell.Synapses

def check (valid : Bool) (message : String) : IO Unit := unless valid do throw (IO.userError message)

def attempt (candidate : Bool) (bytes : ByteArray) : IO (Except String Index.StoredBinding) := do
  try return .ok (← if candidate then CursorBinding.decode bytes else Index.CanonicalDecoder.decodeWithoutEncode bytes)
  catch error => return .error error.toString

def same : Except String Index.StoredBinding → Except String Index.StoredBinding → Bool
  | .error left,.error right => left == right
  | .ok left,.ok right => left.fact == right.fact && left.read == right.read
  | _,_ => false

def pageSame : Except String PageMap.Page → Except String PageMap.Page → Bool
  | .error left,.error right => left == right
  | .ok left,.ok right => decide (left = right)
  | _,_ => false

def pageInputs (snapshot : PageMap.Snapshot) (ref : PageMap.Ref) (limit : Nat)
    (values : Array ByteArray) : IO (Array ByteArray) := do
  if values.size ≥ limit then return values
  let loaded ← snapshot.load ref
  let mut bytes := ByteArray.empty
  while bytes.size < ref.bytes do
    let count := min 4096 (ref.bytes-bytes.size)
    let part ← FileSystem.readPage snapshot.handle (ref.offset+bytes.size).toUInt64 ⟨count,Nat.min_le_left _ _⟩
    check (part.size == count) "raw page capture was truncated"
    bytes := bytes++part
  check (PageMap.digest bytes == ref.checksum) "raw page capture changed digest"
  let mut values := values.push bytes
  if let .branch children := loaded.page then
    for child in children do
      if _smaller : child.height < ref.height then values ← pageInputs snapshot child limit values
      else throw (IO.userError "raw page directory height did not decrease")
      if values.size ≥ limit then break
  return values
termination_by ref.height

@[noinline,nospecialize] def timedPages (candidate : Bool) (input : IO.Ref (Array ByteArray)) :
    IO (Array PageMap.Page × Nat × Nat) := do
  let began ← IO.monoNanosNow
  let allocations ← IO.getNumHeartbeats
  let mut values := #[]
  for _ in [:4] do
    values ← (← input.get).mapM fun bytes => IO.ofExcept
      (if candidate then PageMap.CursorReader.decode bytes else PageMap.CanonicalDecoder.decodeWithoutEncode bytes)
    values ← (← IO.mkRef values).get
  return (values,((← IO.monoNanosNow)-began)/1000,(← IO.getNumHeartbeats)-allocations)

@[noinline,nospecialize] def timed (candidate : Bool) (input : IO.Ref (Array ByteArray)) :
    IO (Array Index.StoredBinding × Nat × Nat) := do
  let began ← IO.monoNanosNow
  let allocations ← IO.getNumHeartbeats
  let bytes ← input.get
  let values ← bytes.mapM fun bytes =>
    if candidate then CursorBinding.decode bytes else Index.CanonicalDecoder.decodeWithoutEncode bytes
  let values ← (← IO.mkRef values).get
  let allocated := (← IO.getNumHeartbeats)-allocations
  return (values,((← IO.monoNanosNow)-began)/1000,allocated)

def main (args : List String) : IO Unit := do
  let [database,output] := args | throw (IO.userError "cursor-binding-checks DATABASE OUTPUT")
  check (!(← (System.FilePath.mk output).pathExists)) "preserve direct-binding component result"
  let source ← PageMap.pin (.mk database)
  let some reader ← Index.open? source .user .shared | throw (IO.userError "existing shared synaptic index required")
  let index ← reader.index.forkReader
  let bytes ← index.foldRange ⟨"binding:","binding;"⟩ (fun values (_,value) =>
    pure (value.map values.push |>.getD values)) (#[] : Array ByteArray)
  check (!bytes.isEmpty) "real original bindings required"
  let mut controls := 0
  for index in [: min bytes.size 128] do
    let original := bytes[index]!
    let variants := #[original,ByteArray.empty,original.push 0,original.extract 0 (original.size/2),
      original.extract 0 (original.size-1)] ++ #[2,127,128,255].map (fun n => ByteArray.mk #[UInt8.ofNat n]++original)
    for bytes in variants do
      let a ← attempt false bytes
      let b ← attempt true bytes
      check (same a b) "direct binding changed a value or error"
      controls := controls+1
  for bytes in #[ByteArray.mk (Array.replicate 32768 (128 : UInt8)),ByteArray.mk (Array.replicate 32769 (0 : UInt8))] do
    check (same (← attempt false bytes) (← attempt true bytes)) "direct binding malformed/size bound differs"
    controls := controls+1
  let input ← IO.mkRef bytes
  let mut trials := #[]
  for repetition in [:3] do
    let order := if repetition%2 == 0 then #[false,true] else #[true,false]
    let first ← timed order[0]! input
    let second ← timed order[1]! input
    check (first.1.size == second.1.size && (first.1.zip second.1).all
      (fun (left,right) => left.fact == right.fact && left.read == right.read)) "full binding inventory differs"
    trials := trials.push (Json.mkObj [("candidateFirst",toJson order[0]!),
      ("referenceUs",toJson (if order[0]! then second.2.1 else first.2.1)),
      ("candidateUs",toJson (if order[0]! then first.2.1 else second.2.1)),
      ("referenceSmallAllocationEvents",toJson (if order[0]! then second.2.2 else first.2.2)),
      ("candidateSmallAllocationEvents",toJson (if order[0]! then first.2.2 else second.2.2)),("allEqual",toJson true)])
  let mut pages := #[]
  if let some root := source.head.root then pages ← pageInputs source root 64 pages
  if let some root := index.head.root then pages ← pageInputs index root 128 pages
  let mut pageControls := 0
  let synthetic := PageMap.encode (.leaf [("カーネル",none),("binary",some (ByteArray.mk #[255,0,128]))])
  check (pageSame (PageMap.CanonicalDecoder.decodeWithoutEncode synthetic) (PageMap.CursorReader.decode synthetic))
    "cursor optional/binary field differs"
  pageControls := pageControls+1
  for bytes in pages do
    for variant in #[bytes,ByteArray.empty,bytes.push 0,bytes.extract 0 (bytes.size/2),bytes.extract 0 (bytes.size-1)] ++
        #[2,127,128,255].map (fun n => ByteArray.mk #[UInt8.ofNat n]++bytes) do
      check (pageSame (PageMap.CanonicalDecoder.decodeWithoutEncode variant) (PageMap.CursorReader.decode variant))
        "cursor page changed a value or error"
      pageControls := pageControls+1
  let pageInput ← IO.mkRef pages
  let mut pageTrials := #[]
  for repetition in [:3] do
    let order := if repetition%2 == 0 then #[false,true] else #[true,false]
    let first ← timedPages order[0]! pageInput
    let second ← timedPages order[1]! pageInput
    check (decide (first.1 = second.1)) "actual cursor pages differ"
    pageTrials := pageTrials.push (Json.mkObj [("candidateFirst",toJson order[0]!),
      ("referenceUs",toJson (if order[0]! then second.2.1 else first.2.1)),
      ("candidateUs",toJson (if order[0]! then first.2.1 else second.2.1)),
      ("referenceSmallAllocationEvents",toJson (if order[0]! then second.2.2 else first.2.2)),
      ("candidateSmallAllocationEvents",toJson (if order[0]! then first.2.2 else second.2.2)),("allEqual",toJson true)])
  check ((← PageMap.pin (.mk database)).head == source.head) "component changed original source"
  IO.FS.writeFile (.mk output) (Json.mkObj [("source",toJson source.head),("index",toJson index.head),
    ("bindings",toJson bytes.size),("encodedBytes",toJson (bytes.foldl (fun sum bytes => sum+bytes.size) 0)),
    ("controls",toJson controls),("trials",toJson trials),("allEqual",toJson true),
    ("pageSamples",toJson pages.size),("pageControls",toJson pageControls),("pageTrials",toJson pageTrials),
    ("pagePassesPerTrial",toJson (4 : Nat)),("rawPageBytes",toJson (pages.foldl (fun n bytes => n+bytes.size) 0)),
    ("allInventoryNotActualQuerySubset",toJson true),("notWholeHookTime",toJson true),
    ("notSeparateArmRss",toJson true),("sourceUnchanged",toJson true),
    ("allocationEventsAreNotBytesOrRss",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).compress
