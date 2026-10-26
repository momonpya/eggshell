import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

private def read (path : System.FilePath) : IO Json := do
  IO.ofExcept (Json.parse (← IO.FS.readFile path))

private def compact : Nat → Json → Json
  | 0,.arr values => Json.mkObj [("entries",toJson values.size)]
  | 0,.obj values => Json.mkObj [("fields",toJson (values.toArray.map Prod.fst))]
  | _ ,.str value => if value.length ≤ 256 then toJson value else Json.mkObj [("characters",toJson value.length)]
  | depth+1,.arr values => if values.size ≤ 8 then .arr (values.map (compact depth))
    else Json.mkObj [("entries",toJson values.size)]
  | depth+1,.obj values => Json.mkObj (values.toArray.toList.map fun (name,value) => (name,compact depth value))
  | _,value => value

def main (args : List String) : IO Unit := do
  let [trialPath,outputPath] := args | throw (IO.userError "TraceSynapticSource TRIAL NEW-REPORT")
  let root := System.FilePath.mk trialPath
  let output := System.FilePath.mk outputPath
  unless output.isAbsolute && !(← output.pathExists) do throw (IO.userError "new absolute stage report required")
  let mut traces := #[]
  for entry in ← (root / "data/receipts").readDir do
    let request ← read (entry.path / "request.json")
    let fields := request.getObjValD "data"
    if (fields.getObjValAs? String "event").toOption != some "UserPromptSubmit" then continue
    let mut events := #[]
    for file in ← entry.path.readDir do
      if !file.fileName.endsWith ".json" then continue
      let record ← read file.path
      let some time := (record.getObjValAs? Nat "observedMs").toOption | continue
      events := events.push (time,file.fileName,compact 2 (record.getObjValD "data"))
    let ordered := events.qsort fun a b => a.1 < b.1
    let first := ordered[0]?.map Prod.fst |>.getD 0
    traces := traces.push (Json.mkObj [("receipt",toJson entry.fileName),
      ("session",fields.getObjValD "session"),("events",toJson (ordered.map fun (time,name,data) =>
        Json.mkObj [("ms",toJson (time-first)),("event",toJson name),("data",data)]))])
  IO.FS.writeFile output (toJson traces).pretty
  IO.println (toJson traces).compress
