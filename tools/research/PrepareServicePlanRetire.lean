import Lean
open Lean
private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def once (source before after : String) : IO String := do
  check ((source.splitOn before).length == 2) ("service retirement anchor changed: " ++ toString (before.take 70))
  return source.replace before after

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let target := project / "tools/research/RetireServicePlanTrial.lean"
  check (!(← target.pathExists)) "preserve service retirement source"
  let mut source := (← IO.FS.readFile (project / "tools/research/RetireSourcePlanTrial.lean"))
    |>.replace "source-plan" "service-plan"
  source ← once source "let builds := #[\"owner-palette-runtime-build\",\"service-plan-runtime-build\""
    "let builds := #[\"owner-palette-runtime-build\",\"source-plan-runtime-build\",\"service-plan-runtime-build\""
  source ← once source "  let compact := evidence / \"bodies\""
    "  let compact := project / \"docs/candidates/source-plan/bodies\""
  source ← once source "    IO.FS.writeFile canonical body"
    "    check ((← IO.FS.readFile canonical) == body) \"actual body differs from the retained parent body\""
  let auditStart := "  let auditBody ← IO.FS.readFile (evidence / \"hooks/candidate/audit/topic-1/body.txt\")\n"
  let heads := source.splitOn auditStart
  check (heads.length == 2) "service retirement audit start"
  let tails := heads[1]!.splitOn "  IO.FS.writeFile (evidence / \"delivered.json\")"
  check (tails.length == 2) "service retirement audit end"
  source := heads[0]! ++
    "  for arm in [\"baseline\",\"candidate\"] do\n" ++
    "    let directory := evidence / \"hooks\" / arm / \"audit/topic-1\"\n" ++
    "    let body ← IO.FS.readFile (directory / \"body.txt\")\n" ++
    "    check (body == (← IO.FS.readFile (compact / \"topic-1.txt\"))) \"audit body differs\"\n" ++
    "    for name in [\"shutdown\",\"publisher-shutdown\"] do\n" ++
    "      stopped := stopped.push (← closed (arm ++ \"-audit-\" ++ name) (directory / (name ++ \".json\")))\n" ++
    "  IO.FS.writeFile (evidence / \"delivered.json\")" ++ tails[1]!
  source ← once source "root / \"service-plan-hook-candidate-build\"] do"
    "root / \"service-plan-hook-candidate-build\",root / \"service-plan-view-checks-build\"] do"
  source ← once source "for name in [\"owner-palette-core\",\"service-plan-core\"] do"
    "for name in [\"source-plan-core\",\"service-plan-core\"] do"
  source := source.replace "tools/research/SourcePlanHook.lean" "tools/research/ServicePlanHook.lean"
  source ← once source "  for file in retained do check"
    ("  let mut executions := #[]\n" ++
     "  for entry in ← evidence.readDir do\n" ++
     "    if entry.fileName.endsWith \"-exit.json\" then\n" ++
     "      let record ← read entry.path\n" ++
     "      check (record.getObjValD \"exitCode\" == toJson (0 : Nat)) \"failed execution cannot be discarded\"\n" ++
     "      executions := executions.push (Json.mkObj [(\"stage\",toJson entry.fileName),(\"record\",record)])\n" ++
     "      IO.FS.removeFile entry.path\n" ++
     "  IO.FS.writeFile (evidence / \"executions.json\") (toJson executions).pretty\n" ++
     "  if ← (evidence / \"progress.json\").pathExists then IO.FS.removeFile (evidence / \"progress.json\")\n" ++
     "  for file in retained do check")
  IO.FS.writeFile target source
  IO.println "Prepared exact-source checks and deletion of completed service-plan trials; no archive"
