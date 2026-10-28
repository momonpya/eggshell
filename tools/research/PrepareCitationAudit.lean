import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean

def main : IO Unit := do
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  let read := fun (p : System.FilePath) => IO.FS.readFile p >>= fun s => IO.ofExcept (Json.parse s)
  let audit ← read (root / "r0/stage1/preparation/audit-input.json")
  let inventory ← read (root / "seed-citations-complete.json")
  let citations ← IO.ofExcept (inventory.getObjValAs? (Array Json) "citations")
  let required := citations.mapIdx fun index row =>
    (row.getObjValD "citation").setObjVal! "name" (toJson s!"seed-citation-{index+1}")
  let source := (audit.getObjValD "source").setObjVal! "required" (toJson required)
  let trace := root / "delivery-replay-verified"
  let result := Json.mkObj [("source",source),("database",toJson (trace / "work.egg").toString),
    ("request",toJson (trace / "UserPromptSubmit/stdin").toString),
    ("stdout",toJson (trace / "UserPromptSubmit/stdout").toString),
    ("timing",toJson (trace / "UserPromptSubmit/record.json").toString),
    ("body",toJson (root / "r0/stage1/trial/packet-0.txt").toString)]
  let target := root / "all-citations-audit-input.json"
  unless !(← target.pathExists) do throw (IO.userError "preserve original audit input")
  IO.FS.writeFile target result.pretty
