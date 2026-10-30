import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)

def main (args : List String) : IO Unit := do
  let [input,output] := args | throw (IO.userError "completed receipt directory and new timeline required")
  let directory : System.FilePath := .mk input
  let target : System.FilePath := .mk output
  check (!(← target.pathExists)) "preserve completed timeline"
  let mut timeline : Array (Nat × Json) := #[]
  let mut numerical := #[]
  for entry in ← directory.readDir do
    if !entry.fileName.endsWith ".json" then continue
    let value ← IO.ofExcept (Json.parse (← IO.FS.readFile entry.path))
    check (value.getObjValD "receipt" == toJson directory.fileName.get!) "receipt crossed query identity"
    let stage ← IO.ofExcept (value.getObjValAs? String "stage")
    let observed ← IO.ofExcept (value.getObjValAs? Nat "observedMs")
    let data := value.getObjValD "data"
    let details := if stage.startsWith "numerical-" then
        Json.mkObj [("elapsedMs",data.getObjValD "elapsedMs"),("status",data.getObjValD "status")]
      else if stage.startsWith "discovery-counters-" then data else Json.null
    if stage.startsWith "numerical-" then numerical := numerical.push details
    timeline := timeline.push (observed,Json.mkObj [("stage",toJson stage),("observedMs",toJson observed),
      ("pid",value.getObjValD "pid"),("details",details)])
  IO.FS.writeFile target (Json.mkObj [("receipt",toJson directory.fileName.get!),
    ("timeline",toJson ((timeline.qsort (fun a b => a.1 < b.1)).map Prod.snd)),
    ("numerical",toJson numerical),("observationTimesAreNotExclusiveCpuTimes",toJson true),
    ("repeatedHookOrModel",toJson false)]).pretty
  IO.println (toJson numerical).compress
