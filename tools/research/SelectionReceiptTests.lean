import tools.research.SelectionReceipt
open Lean Eggshell

namespace Eggshell.Research.SelectionReceiptTests
private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def rejected (action : IO Json) : IO Bool := do
  try let _ ← action; return false catch _ => return true

def run : IO Unit := do
  let id ← Receipt.fresh
  let directory := (← Paths.dataRoot) / "receipts" / id
  let rows := (List.range 2501).toArray.map toJson
  let original := Json.mkObj [("selectorInput",Json.mkObj [("costs",Json.arr rows),("limit",toJson (9 : Nat))]),
    ("selectionWitness",Json.mkObj [("sourceNodes",Json.arr rows)]),("preserved",toJson "metadata")]
  try
    Receipt.observeSelection (some id) true original
    let reassembled ← Receipt.readSelection directory
    check (reassembled.getObjValD "selectorInput" == original.getObjValD "selectorInput" &&
      reassembled.getObjValD "selectionWitness" == original.getObjValD "selectionWitness" &&
      reassembled.getObjValD "preserved" == original.getObjValD "preserved") "multipart roundtrip changed array order or metadata"
    let part := directory / "selection-selectorInput-costs-1.json"
    let saved ← IO.FS.readFile part
    IO.FS.removeFile part
    check (← rejected (Receipt.readSelection directory)) "missing part silently accepted"
    IO.FS.writeFile part saved
    let parsed ← IO.ofExcept (Json.parse saved)
    IO.FS.writeFile part (parsed.setObjVal! "receipt" (toJson (← Receipt.fresh))).compress
    check (← rejected (Receipt.readSelection directory)) "foreign receipt silently accepted"
    IO.FS.writeFile part (parsed.setObjVal! "data" (Json.arr rows)).compress
    check (← rejected (Receipt.readSelection directory)) "wrong part length silently accepted"
    IO.FS.writeFile part saved
    let manifest := directory / "selection-plan.json"
    let manifestText ← IO.FS.readFile manifest
    let manifestValue ← IO.ofExcept (Json.parse manifestText)
    let data := manifestValue.getObjValD "data"
    let descriptors ← IO.ofExcept ((data.getObjValD "diagnosticParts").getArr?)
    let repeated := descriptors.push descriptors[0]!
    IO.FS.writeFile manifest (manifestValue.setObjVal! "data" (data.setObjVal! "diagnosticParts" (Json.arr repeated))).compress
    check (← rejected (Receipt.readSelection directory)) "duplicate field silently accepted"
    Receipt.observeSelection (some id) false original
    check ((← Receipt.readSelection directory) == original) "ordinary receipt changed"
    IO.println "selection receipt: roundtrip, missing, foreign, length, duplicate and ordinary checks passed"
  finally if ← directory.pathExists then IO.FS.removeDirAll directory

end Eggshell.Research.SelectionReceiptTests
