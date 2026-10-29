import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean
private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
def main : IO Unit := do
  let study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  let records : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/anchored-capture"
  let previous ← read (study / "r0/stage1/preparation/audit-input.json")
  IO.println (Json.mkObj [("priorRequirements",(previous.getObjValD "source").getObjValD "required")]).compress
  let missing ← IO.ofExcept ((← read (records / "missing-selection.json")).getObjValAs? (Array Json) "targets")
  let rows ← IO.ofExcept ((← read (study / "shared-snapshot/anchored-capture/current-originals.json")).getObjValAs? (Array Json) "canonicalRows")
  let mut knownRows : Std.HashSet (String × Nat) := {}
  for row in rows do
    let key := row.getObjValD "key"
    let path ← IO.ofExcept ((key.getObjValD "file").getObjValAs? String "relative")
    let line ← IO.ofExcept (key.getObjValAs? Nat "line")
    knownRows := knownRows.insert (path,line)
  let audit ← read (records / "hook/audit.json")
  let requirements ← IO.ofExcept ((audit.getObjValD "requirements").getArr?)
  let mut gaps := #[]
  for item in missing do
    let indexed ← IO.ofExcept (item.getObjValAs? Nat "indexedRows")
    let selected ← IO.ofExcept (item.getObjValAs? Nat "selectedRows")
    if indexed != selected then
      IO.println (Json.mkObj [("target",item.getObjValD "target"),("indexed",toJson indexed),("selected",toJson selected)]).compress
    else
      let target := item.getObjValD "target"
      if requirements.any (fun requirement => requirement.getObjValD "name" == target.getObjValD "name" &&
          requirement.getObjValD "bodyDelivered" == toJson false) then
        let path ← IO.ofExcept (target.getObjValAs? String "path")
        let first ← IO.ofExcept (target.getObjValAs? Nat "first")
        let last ← IO.ofExcept (target.getObjValAs? Nat "last")
        let source ← IO.FS.readFile (System.FilePath.mk "/Users/ovm/Code/eggshell-benchmarks/aamas-2027/sources/llvm-project" / path)
        let lines := (source.splitOn "\n").toArray
        let mut absent := #[]
        for line in [first:last+1] do
          if knownRows.contains (path,line) then continue
          let some text := lines[line-1]? | throw (IO.userError "reference line missing")
          absent := absent.push (line,text)
        gaps := gaps.push (Json.mkObj [("target",target),("allIndexedRowsSelected",toJson true),
          ("unlocatedLines",toJson absent),("allUnlocatedAreBlank",toJson (absent.all fun (_,text) => text.trimAscii.isEmpty))])
  IO.FS.writeFile (records / "unlocated-lines.json") (toJson gaps).pretty
  IO.println (Json.mkObj [("completeIndexedButIncompleteLiteralSpans",toJson gaps)]).compress
  let body ← read (records / "body-row-audit.json")
  let reports ← IO.ofExcept (body.getObjValAs? (Array Json) "byTarget")
  for report in reports do
    let name := (report.getObjValD "target").getObjValD "name"
    if ["seed-citation-21","seed-citation-23","seed-citation-46"].any (fun wanted => name == toJson wanted) then
      IO.println (Json.mkObj [("actualBodyRowAudit",report)]).compress
