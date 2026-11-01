import tools.research.StudyAcquire
open Lean Eggshell.Research
private def artifact (path : System.FilePath) : IO StudyAdmission.Artifact := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  unless result.exitCode == 0 do throw (IO.userError "cannot seal immutable acquisition input")
  return ⟨path.toString,(result.stdout.splitOn " ").headD ""⟩
def main : IO Unit := do
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
  let records : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/fixed-frame-study"
  unless !(← (records / "seed-plans.json").pathExists) do throw (IO.userError "preserve sealed seed cohort")
  let first ← IO.ofExcept (fromJson? (α := StudyAcquire.Plan) (← StudyAdmission.readJson (root / "seed-1.plan.json").toString))
  unless first.handoffChars == 500000 && first.model == "gpt-5.6-luna" && first.effort == "xhigh" do
    throw (IO.userError "candidate acquisition treatment changed")
  let budget ← artifact (root / "seed-1.limits.json")
  let mut plans := #[← artifact (root / "seed-1.plan.json")]
  for index in [2,3] do
    let file := root / s!"seed-{index}.plan.json"
    unless !(← file.pathExists) do throw (IO.userError "do not replace an existing seed plan")
    let plan : StudyAcquire.Plan := {first with
      label := s!"new-native-seed-{index}",output := (root / s!"study/seed-{index}").toString,
      guardRecord := (root / s!"seed-{index}.guard.json").toString}
    IO.FS.writeFile file (toJson plan).pretty
    let sealed ← artifact file
    plans := plans.push sealed
    IO.FS.writeFile (root / s!"seed-{index}.settings.json") (toJson ({
      record := plan.guardRecord,cwd := root.toString,ownedPrefixes := #[root.toString],
      limitRssKiB := 3670016,minFreeKiB := 2097152,
      command := #[first.runner.path,"acquire-bounded",sealed.path,sealed.sha256,budget.path,budget.sha256]
    } : ResourceGuard.Settings)).pretty
  IO.FS.writeFile (records / "seed-plans.json") (Json.mkObj [
    ("plans",toJson plans),("limits",toJson budget),("runtime",toJson first.runtime),
    ("runner",toJson first.runner),("handoffChars",toJson first.handoffChars),
    ("answeringModelCallsBeforeSeal",toJson (0 : Nat)),("seeds",toJson (3 : Nat)),
    ("stagesPerBlock",toJson (6 : Nat)),("armsPerStage",toJson (3 : Nat)),
    ("checkpoint",toJson "Each stage gives fresh/current/candidate the same prompt/source; the two memory arms receive the same frozen source/private-history checkpoint. Candidate trajectory is predeclared, not a best repetition."),
    ("noAutomaticRetry",toJson true),("adopted",toJson false)]).pretty
