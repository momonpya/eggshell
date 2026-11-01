import Lean
open Lean
private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def digest (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  check (result.exitCode == 0) "cannot fingerprint withdrawn plan"
  return (result.stdout.splitOn " ").headD ""
def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
  let records := project / "docs/candidates/fixed-frame-study"
  let withdrawal := records / "unexecuted-plan-withdrawal.json"
  check (!(← withdrawal.pathExists)) "preserve withdrawal evidence"
  let mut old := #[]
  let mut paths := #[]
  for index in [1,2,3] do
    check (!(← (root / s!"study/seed-{index}").pathExists) && !(← (root / s!"seed-{index}.guard.json").pathExists))
      "a seed was submitted; do not change its harness or plans"
    for suffix in ["plan.json","settings.json"] do
      let path := root / s!"seed-{index}.{suffix}"
      old := old.push (path.toString,← digest path)
      paths := paths.push path
  let limits := root / "seed-1.limits.json"
  old := old.push (limits.toString,← digest limits)
  paths := paths.push limits
  let record := Json.mkObj [("reason",toJson "Before generation: separate measured reference from candidate adoption gate, and own the publisher throughout preparation. Product runtime remains a109b39d; no acquisition directory or guard exists."),
    ("files",toJson old),("modelCalls",toJson (0 : Nat)),("archive",toJson false)]
  IO.FS.writeFile withdrawal (record.setObjVal! "completed" (toJson false)).pretty
  for path in paths do IO.FS.removeFile path
  IO.FS.removeFile (records / "seed-plans.json")
  for name in ["StudyAdmission","StudyStages","StudyProfileChecks","StudyPrepare","StudyPreparationChecks","StudyMain"] do
    IO.FS.writeFile (root / s!"core/tools/research/{name}.lean")
      (← IO.FS.readFile (project / s!"tools/research/{name}.lean"))
  let settings ← read (root / "controller-build.settings.json")
  IO.FS.writeFile (root / "controller-admission.settings.json")
    (settings.setObjVal! "record" (toJson (records / "controller-admission.guard.json").toString)).pretty
  let test ← read (root / "profile-checks.settings.json")
  let args ← IO.ofExcept (test.getObjValAs? (Array String) "command")
  let args := args.set! 2 (root / "profile-role-checks").toString
  IO.FS.writeFile (root / "profile-role-checks.settings.json")
    (test.setObjVal! "record" (toJson (records / "profile-role-checks.guard.json").toString)
      |>.setObjVal! "command" (toJson args)).pretty
  let fixture := test.setObjVal! "record" (toJson (records / "preparation-check.guard.json").toString)
    |>.setObjVal! "command" (toJson #[(root / "controller/StudyMain").toString,"preparation-check",root.toString])
  IO.FS.writeFile (root / "preparation-check.settings.json") fixture.pretty
  IO.FS.writeFile withdrawal (record.setObjVal! "completed" (toJson true)).pretty
