import Eggshell.Receipt
import Lean.Data.Json.Parser
open Lean Eggshell
namespace Eggshell.Research.ReceiptPublicationProfile
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def distribution (values : Array Nat) : Json := Id.run do
  let sorted := values.qsort (· < ·)
  return Json.mkObj [("count",toJson sorted.size),("sum",toJson (values.foldl (·+·) 0)),
    ("min",toJson sorted[0]?),("median",toJson sorted[sorted.size/2]?),("max",toJson sorted.back?)]
def boundary : FileSystem.PublicationBoundary → String
  | .written => "written" | .synced => "synced" | .installed => "installed" | .durable => "durable"
def run (root : System.FilePath) : IO Unit := do
  check (root.isAbsolute && !(← root.pathExists)) "fresh absolute profile root required"
  FileSystem.privateDirectory root
  FileSystem.privateDirectory (root/"atomic")
  let mut groups := #[]
  for size in [0,256,4096,16384] do
    let payload := (toJson (String.ofList (List.replicate size 'x'))).compress.toUTF8
    for overwrite in [false,true] do
      let id ← Receipt.fresh
      let mut published := #[]
      let mut sync := #[]
      let mut receiptTimes := #[]
      let mut firstSteps := #[]
      for index in [:64] do
        let target := root/"atomic"/s!"{size}-{overwrite}-{if overwrite then 0 else index}"
        let steps ← IO.mkRef (#[] : Array (String × Nat))
        let began ← IO.monoNanosNow
        FileSystem.atomicExistingBytesWith target payload fun phase => do
          steps.modify (·.push (boundary phase,(← IO.monoNanosNow)-began))
        let elapsed := (← IO.monoNanosNow)-began
        let times ← steps.get
        check (times.map Prod.fst == #["written","synced","installed","durable"]) "publication boundary order changed"
        check ((← IO.FS.readBinFile target) == payload) "publication returned before exact bytes were visible"
        let syncNs := times[1]!.2-times[0]!.2+times[3]!.2-times[2]!.2
        published := published.push elapsed
        sync := sync.push syncNs
        if index == 0 then firstSteps := times
        let stage := s!"diagnostic-{size}-{if overwrite then 0 else index}"
        let data := Json.mkObj [("fixture",toJson true),("payload",toJson (String.ofList (List.replicate size 'x')))]
        let began ← IO.monoNanosNow
        Receipt.observe (some id) stage data
        receiptTimes := receiptTimes.push ((← IO.monoNanosNow)-began)
        let path := (← Paths.dataRoot)/"receipts"/id/(stage++".json")
        let record ← IO.ofExcept (Json.parse (← IO.FS.readFile path))
        check (record.getObjValD "data" == data) "observed receipt missing or incomplete"
      groups := groups.push (Json.mkObj [("payloadChars",toJson size),("overwrite",toJson overwrite),
        ("publicationNs",distribution published),("syncDataAndParentNs",distribution sync),
        ("receiptObserveNs",distribution receiptTimes),("firstBoundaryTimesNs",toJson firstSteps)])
  let report := Json.mkObj [("allPassed",toJson true),("groups",toJson groups),
    ("publicationCalls",toJson (512 : Nat)),("receiptObserveCalls",toJson (512 : Nat)),
    ("actualBytesAndReceiptDataExact",toJson true),("productChanged",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]
  IO.FS.writeFile (root/"report.json") report.pretty
  IO.println report.compress
end Eggshell.Research.ReceiptPublicationProfile
def main (args : List String) : IO Unit := do
  let [root] := args | throw (IO.userError "fresh profile root required")
  Eggshell.Research.ReceiptPublicationProfile.run (.mk root)
