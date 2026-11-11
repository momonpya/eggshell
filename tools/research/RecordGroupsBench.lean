import tools.research.PreparedRecordGroups
import Lean.Data.Json.FromToJson
open Lean Eggshell Eggshell.Research.PreparedRecordGroups

namespace Eggshell.Research.RecordGroupsBench

def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)

def reference (records : List (List Nat)) (requested : List Nat) : List Nat :=
  hashDistinct (requested ++ (records.filter fun record => record.any requested.contains).flatten)

def measure (records : List (List Nat)) (index : Index records) (requested : List Nat)
    (method : String) (expected : List Nat) : IO Json := do
  let records ← (← IO.mkRef records).get
  let requested ← (← IO.mkRef requested).get
  let start ← IO.monoNanosNow
  let result := if method == "reference" then reference records requested
    else if method == "indexed" then hashDistinct (requested ++ (index.recordsFor requested).flatten)
    else if method == "adaptive" then index.expand requested
    else hashDistinct (requested ++ (dense records requested).flatten)
  let result ← (← IO.mkRef result).get
  let elapsed := (← IO.monoNanosNow)-start
  check (result == expected) "native record expansion changed order, duplicates or row IDs"
  return Json.mkObj [("method",toJson method),("elapsedUs",toJson (elapsed/1000)),
    ("outputRows",toJson result.length),("exactOrderedOutput",toJson true)]

def run (path : System.FilePath) (adaptive : Bool := false) : IO Unit := do
  check (path.isAbsolute && !(← path.pathExists)) "fresh native component output required"
  IO.FS.createDirAll path
  let cases := #[("small-sparse",128,8,1),("sparse",2048,16,8),
    ("absent",8192,32,128),("dense",4096,32,8192)]
  let orders := if adaptive then #[#["reference","indexed","dense","adaptive"],
    #["dense","adaptive","indexed","reference"],#["indexed","reference","adaptive","dense"],
    #["adaptive","dense","reference","indexed"]] else
    #[#["reference","indexed","dense"],#["dense","indexed","reference"],#["indexed","reference","dense"]]
  let mut results := #[]
  for (label,count,width,queries) in cases do
    let records := (List.range count).map fun i =>
      (List.range width).map fun j => (i*13+j*7)%(count*2)
    let records := records ++ [[],[0,0,count*4],[0,0,count*4]]
    let requested := (List.range queries).map fun i => if label == "absent" then count*4+1+i else i
    let preparedAt ← IO.monoNanosNow
    let index ← (← IO.mkRef (prepare records)).get
    let preparation := ((← IO.monoNanosNow)-preparedAt)/1000
    let expected := reference records requested
    let mut measurements := #[]
    for order in orders do
      for method in order do measurements := measurements.push (← measure records index requested method expected)
    let row := Json.mkObj [("case",toJson label),("records",toJson records.length),
      ("memberships",toJson (records.foldl (fun n record => n+record.length) 0)),
      ("requested",toJson requested.length),("prepareUs",toJson preparation),("measurements",toJson measurements)]
    results := results.push row
    IO.FS.writeFile (path/"progress.json") (toJson results).compress
  IO.FS.writeFile (path/"report.json") (Json.mkObj [("cases",toJson results),
    ("orders",toJson orders),("syntheticOnly",toJson true),("actualHookCalls",toJson (0 : Nat)),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).compress

end Eggshell.Research.RecordGroupsBench
