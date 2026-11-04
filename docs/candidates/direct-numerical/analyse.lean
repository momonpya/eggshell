import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def folder : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/direct-numerical"
def read (name : String) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile (folder/name)))
def path (row : Json) (keys : List String) : Json := keys.foldl Json.getObjValD row
def range (rows : Array Json) (keys : List String) : Json := Id.run do
  let values := (rows.toList.filterMap fun row => (fromJson? (path row keys) : Except String Nat).toOption).mergeSort (· ≤ ·)
  if values.isEmpty then return Json.null
  return Json.mkObj [("n",toJson values.length),("min",toJson values.head!),
    ("p50",toJson values[values.length/2]!),("max",toJson values.getLast!)]
def counts (rows : Array Json) (keys : List String) : Json := Id.run do
  let mut values : List (String × Nat) := []
  for row in rows do
    let label := (path row keys).compress
    if values.any (·.1 == label) then values := values.map fun (name,n) => (name,n+if name == label then 1 else 0)
    else values := values++[(label,1)]
  return toJson values
def main : IO Unit := do
  let rows ← IO.ofExcept (fromJson? (← read "native-stages.json") : Except String (Array Json))
  let mut output := #[]
  for trial in ["readers1","small1"] do
    let initial := rows.filter fun row => row.getObjValD "trial" == toJson trial &&
      ((row.getObjValAs? String "hook").toOption.getD "").endsWith "-initial-UserPromptSubmit-measurement.json"
    for complete in [true,false] do
      let selected := initial.filter (·.getObjValD "complete" == toJson complete)
      output := output.push (Json.mkObj [("trial",toJson trial),("complete",toJson complete),("count",toJson selected.size),
        ("hookMs",range selected ["hookMs"]),("inputStatus",counts selected ["turnInputs","status"]),
        ("referenceMs",range selected ["turnInputs","referenceMs"]),("ownerMs",range selected ["turnInputs","ownerMs"]),
        ("transportRpcMs",range selected ["transport","rpcMs"]),("transportManagerMs",range selected ["transport","managerMs"]),
        ("queueMs",range selected ["service","queueMs"]),("workMs",range selected ["service","workMs"]),
        ("reply",counts selected ["service","reply"]),("semantic",counts selected ["search","trace","semantic"])])
  IO.FS.writeFile (folder/"stage-summary.json") ((toJson output).compress++"\n")
  IO.println (toJson output).compress
