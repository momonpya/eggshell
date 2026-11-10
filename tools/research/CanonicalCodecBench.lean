import tools.research.CanonicalPageCodec
import tools.research.CanonicalBindingDecode
import Eggshell.CanonicalSourceCache
open Lean Eggshell Eggshell.DB Eggshell.Synapses

namespace CanonicalCodecBench
def check (value : Bool) (message : String) : IO Unit := unless value do throw (IO.userError message)
def write (path : System.FilePath) (value : Json) : IO Unit := IO.FS.writeFile path value.compress

def gatherPages (snapshot : PageMap.Snapshot) (ref : PageMap.Ref) (values : Array ByteArray) : IO (Array ByteArray) := do
  if values.size ≥ 128 then return values
  let loaded ← snapshot.load ref
  let mut values := values.push (PageMap.encode loaded.page)
  if let .branch children := loaded.page then
    for child in children do
      if _smaller : child.height < ref.height then values ← gatherPages snapshot child values
      else throw (IO.userError "original page height did not decrease")
      if values.size ≥ 128 then break
  return values
termination_by ref.height

def prepared (source : PageMap.Snapshot) : IO (System.FilePath × CanonicalSource.Cache.Manifest) := do
  for storage in [Sidecar.Storage.database,.user] do
    if let some ready ← CanonicalSource.Cache.open? source storage then
      return (← CanonicalSource.Cache.directory source storage,ready.metadata)
  throw (IO.userError "existing prepared source is required; this probe never warms it")

def comparePage (bytes : ByteArray) : Bool :=
  match PageMap.decode bytes,PageMap.decodeWithoutEncode bytes with
  | .ok a,.ok b => decide (a = b)
  | .error a,.error b => a == b
  | _,_ => false

def compareBinding (bytes : ByteArray) : IO Bool := do
  let old ← try pure (.ok (← Index.decodeBinding bytes) : Except String Index.StoredBinding)
    catch error => pure (.error error.toString)
  let fresh ← try pure (.ok (← Index.decodeWithoutEncode bytes) : Except String Index.StoredBinding)
    catch error => pure (.error error.toString)
  return match old,fresh with
    | .ok a,.ok b => a.fact == b.fact && a.read == b.read
    | .error a,.error b => a == b
    | _,_ => false

def variants (bytes : ByteArray) : Array ByteArray :=
  #[ByteArray.empty,bytes,bytes.push 0,bytes.extract 0 (bytes.size/2),bytes.extract 0 (bytes.size-1)] ++
    (#[2,127,128,255].map fun n => ByteArray.mk #[UInt8.ofNat n]++bytes)

@[noinline] def pagePass (reference : Bool) (input : IO.Ref (Array ByteArray)) : IO (Nat × Nat) := do
  let started ← IO.monoNanosNow
  let mut count := 0
  for _ in [:24] do
    -- Reading the dynamic input after the clock prevents reusing a pure
    -- decoder result from controls or from the other measured arm.
    for bytes in ← input.get do
      let page ← IO.ofExcept (if reference then PageMap.decode bytes else PageMap.decodeWithoutEncode bytes)
      count := count + match page with | .leaf rows => rows.length | .branch children => children.length
  return ((← IO.monoNanosNow)-started,count)

@[noinline] def bindingPass (reference : Bool) (input : IO.Ref (Array ByteArray)) : IO (Nat × Nat) := do
  let started ← IO.monoNanosNow
  let mut count := 0
  for _ in [:24] do
    for bytes in ← input.get do
      let value ← if reference then Index.decodeBinding bytes else Index.decodeWithoutEncode bytes
      count := count+value.fact.utf8ByteSize+value.read.binding.limit
  return ((← IO.monoNanosNow)-started,count)

def run (directory report : System.FilePath) : IO Unit := do
  check (!(← report.pathExists)) "preserve prior native measurement"
  let source ← PageMap.pin directory
  let (path,metadata) ← prepared source
  let some bound ← CanonicalSource.Cache.boundIndex? source path metadata |
    throw (IO.userError "existing original binding index required")
  let index := bound.reader.index
  let some root := index.head.root | throw (IO.userError "existing original index is empty")
  let pages ← gatherPages index root #[]
  let bindings ← index.foldRange ⟨"binding:","binding;"⟩ (fun values (_,bytes) => do
    if values.size ≥ 1024 then return values
    return bytes.map values.push |>.getD values) (#[] : Array ByteArray)
  check (!pages.isEmpty && !bindings.isEmpty) "nonempty real page and binding inputs required"
  let mut controls := 0
  for bytes in pages do
    check (comparePage bytes) "actual page decoder differs"
    controls := controls+1
  for bytes in bindings do
    check (← compareBinding bytes) "actual original binding decoder differs"
    controls := controls+1
  for bytes in pages.take 4 do
    for altered in variants bytes do
      check (comparePage altered) "page corruption/truncation error differs"
      controls := controls+1
  for bytes in bindings.take 4 do
    for altered in variants bytes do
      check (← compareBinding altered) "binding corruption/truncation error differs"
      controls := controls+1
  for bytes in #[#[128,0],#[255,0],#[2],#[0,0,0],#[1,1,255]] do
    let bytes := ByteArray.mk (bytes.map UInt8.ofNat)
    check (comparePage bytes && (← compareBinding bytes)) "noncanonical tag/integer control differs"
    controls := controls+2
  let pageInput ← IO.mkRef pages
  let bindingInput ← IO.mkRef bindings
  let mut rounds := #[]
  for pass in [:3] do
    let order := if pass%2 == 0 then #[true,false] else #[false,true]
    let mut results := #[]
    for reference in order do
      let (pageNs,pageCount) ← pagePass reference pageInput
      let (bindingNs,bindingCount) ← bindingPass reference bindingInput
      results := results.push (Json.mkObj [("reference",toJson reference),("pageNs",toJson pageNs),
        ("bindingNs",toJson bindingNs),("pageCount",toJson pageCount),("bindingCount",toJson bindingCount)])
    rounds := rounds.push results
  check ((← PageMap.pin directory).head == source.head) "probe changed the original source head"
  write report (Json.mkObj [("sourceHead",toJson source.head),("bindingHead",toJson index.head),
    ("pages",toJson pages.size),("pageBytes",toJson (pages.foldl (fun n bytes => n+bytes.size) 0)),
    ("bindings",toJson bindings.size),("bindingBytes",toJson (bindings.foldl (fun n bytes => n+bytes.size) 0)),
    ("controls",toJson controls),("rounds",toJson rounds),("dynamicInputAfterClock",toJson true),
    ("originalSourceHeadUnchanged",toJson true),("readOnlyPreparedInputs",toJson true),
    ("actualHookCalls",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
end CanonicalCodecBench

def main (args : List String) : IO Unit := do
  let [source,report] := args | throw (IO.userError "canonical codec bench SOURCE REPORT")
  CanonicalCodecBench.run (.mk source) (.mk report)
