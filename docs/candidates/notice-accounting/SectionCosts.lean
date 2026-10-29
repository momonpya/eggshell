import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean
def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let body ← IO.FS.readFile (project / "docs/candidates/anchored-capture/hook/body.txt")
  let extractSection := fun (first last : String) =>
    match body.splitOn first with
    | _::rest::_ => first ++ (rest.splitOn last).head! ++ last
    | _ => ""
  let header := (body.splitOn "EGGSHELL SHARED SOURCE DATA").head!
  let measure := fun (text : String) => (text.length,text.utf8ByteSize)
  let output := Json.mkObj [("body",toJson (measure body)),("prefix",toJson (measure header)),
    ("graphStatuses",toJson (measure (extractSection "SOURCE CHECKS BY GRAPH\n" "END SOURCE CHECKS BY GRAPH\n"))),
    ("graphLinks",toJson (measure (extractSection "RELATED SOURCE GRAPH\n" "END RELATED SOURCE GRAPH\n"))),
    ("locators",toJson (measure (extractSection "SAVED SOURCE POSITIONS\n" "END SAVED SOURCE POSITIONS\n"))),
    ("models",toJson (0 : Nat)),("diagnosticOnly",toJson true)]
  IO.FS.writeFile (project / "docs/candidates/available-evidence/body-section-costs.json") output.pretty
  IO.println output.compress
