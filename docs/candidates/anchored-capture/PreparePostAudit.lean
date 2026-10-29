import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean
private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
def main : IO Unit := do
  let study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  let root := study / "shared-snapshot"
  let trial := root / "anchored-prepared-hook"
  let records : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/anchored-capture"
  let publication ← read (trial / "supplement-publication.json")
  let metadata := (publication.getObjValD "canonical").getObjValD "metadata"
  let identity ← IO.ofExcept ((metadata.getObjValD "source").getObjValAs? String "identity")
  let payload ← IO.ofExcept (metadata.getObjValAs? String "payload")
  let rows ← read (trial / "work.egg/derived" / identity / "canonical-source" / (payload ++ ".json"))
  IO.FS.writeFile (root / "anchored-capture/current-originals.json") (Json.mkObj [("canonicalRows",rows)]).compress
  let mut plans := #[]
  for entry in ← (trial / "data/receipts").readDir do
    let path := entry.path / "selection-plan.json"
    if ← path.pathExists then plans := plans.push (← read path)
  let some plan := plans.find? (fun row => ((row.getObjValD "data").getObjVal? "selectorInput").isOk) |
    throw (IO.userError "selector input missing")
  let data := plan.getObjValD "data"
  IO.FS.writeFile (records / "selector.json") (Json.mkObj [("data",Json.mkObj [
    ("selectorInput",data.getObjValD "selectorInput"),("families",data.getObjValD "families")])]).compress
  let gold ← read (study / "r0/stage1/preparation/audit-input.json")
  let source := gold.getObjValD "source"
  let requirements ← IO.ofExcept ((source.getObjValD "required").getArr?)
  IO.FS.writeFile (root / "anchored-capture/mandatory-audit-input.json") (Json.mkObj [
    ("source",source),("database",toJson (trial / "work.egg").toString),
    ("request",toJson (trial / "UserPromptSubmit/stdin").toString),
    ("stdout",toJson (trial / "UserPromptSubmit/stdout").toString),
    ("timing",toJson (trial / "UserPromptSubmit/record.json").toString),
    ("body",toJson (trial / "body.txt").toString)]).pretty
  IO.println (Json.mkObj [("families",data.getObjValD "families"),("canonicalRows",metadata.getObjValD "rows"),
    ("requiredItems",toJson requirements.size)]).compress
