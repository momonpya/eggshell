import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
open Lean
def main (args : List String) : IO Unit := do
  let active : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/feedback-pilot-20261028"
  let base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/verified-winner-20261027"
  let root := active / "storage-integration"
  let output := root / "ancestry-checks"
  if args == ["prepare"] then
    let settings := root / "ancestry-checks.settings.json"
    unless !(← settings.pathExists) do throw (IO.userError "preserve earlier ancestry checks")
    let command := #["/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean","-M1024","--run",
      "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/tools/research/CheckSourceAncestry.lean","run"]
    IO.FS.writeFile settings (Json.mkObj [("command",toJson command),
      ("cwd",toJson "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"),
      ("ownedPrefixes",toJson #[active.toString,base.toString]),("limitRssKiB",toJson (3670016 : Nat)),
      ("minFreeKiB",toJson (2097152 : Nat)),("record",toJson (root / "ancestry-checks.guard.json").toString)]).pretty
    return
  unless args == ["run"] && !(← output.pathExists) do throw (IO.userError "prepare | run once")
  IO.FS.createDirAll output
  let cases := #[
    ("original-c7","/Users/ovm/.codex/experiments/eggshell/study-services-20261026/common-seed-1/source.egg",false),
    ("current-copy",(active / "usage-history-start/work.egg").toString,false),
    ("current-runtime-source-only",(root / "generic/output.egg").toString,true)]
  let mut results := #[]
  for (label,database,expected) in cases do
    let report := output / (label ++ ".json")
    let run ← IO.Process.output {
      cmd := (base / "storage-controller-build/StudyMain").toString
      args := #["source-ancestry",database,report.toString]}
    unless run.exitCode == 0 do throw (IO.userError run.stderr)
    let result ← IO.ofExcept (Json.parse (← IO.FS.readFile report))
    unless result.getObjValD "complete" == toJson expected do
      throw (IO.userError s!"ancestry contract disagreed with the frozen case: {label}")
    results := results.push (Json.mkObj [("case",toJson label),("expectedComplete",toJson expected),("actual",result)])
  IO.FS.writeFile (output / "result.json") (Json.mkObj [
    ("cases",toJson results),("currentCodecAcceptedMissingFields",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("sourceWrites",toJson (0 : Nat))]).compress
  IO.println (toJson results).compress
