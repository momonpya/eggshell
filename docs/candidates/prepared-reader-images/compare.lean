import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def body (value : Json) : String :=
  ((value.getObjValD "hookSpecificOutput").getObjValAs? String "additionalContext").toOption.getD ""
def main (args : List String) : IO Unit := do
  let [before,after] := args | throw (IO.userError "paired absolute roots required")
  let before : System.FilePath := .mk before
  let after : System.FilePath := .mk after
  unless before.isAbsolute && after.isAbsolute && !(← (after/"paired-bodies.json").pathExists) do
    throw (IO.userError "preserve prior paired observation")
  let mut rows := #[]
  for name in ["cold-frontend","running-frontend"] do
    let left := body (← read (before/(name++"-stdout.json")))
    let right := body (← read (after/(name++"-stdout.json")))
    unless !left.isEmpty && left == right do throw (IO.userError "actual paired delivery body differs")
    let digest ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256"]} (some left)
    unless digest.exitCode == 0 do throw (IO.userError "paired body identity unavailable")
    rows := rows.push (name,left.utf8ByteSize,(digest.stdout.splitOn " ").head!)
  IO.FS.writeFile (after/"paired-bodies.json") ((toJson rows).compress++"\n")
  IO.println (toJson rows).compress
