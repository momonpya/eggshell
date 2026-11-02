import tools.research.StudyAcquire
open Lean Eggshell.Research
private def artifact (path : System.FilePath) : IO StudyAdmission.Artifact := do
  unless path.isAbsolute && path.fileName != some "auth.json" do
    throw (IO.userError "absolute non-credential artifact required")
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  unless result.exitCode == 0 do throw (IO.userError "cannot seal immutable acquisition input")
  return ⟨path.toString,(result.stdout.splitOn " ").headD ""⟩
def main (args : List String) : IO Unit := do
  let [root,records] := args | throw (IO.userError "SealFixedFrameSeeds COHORT RECORDS")
  let root := System.FilePath.mk root
  let records := System.FilePath.mk records
  unless root.isAbsolute && records.isAbsolute do throw (IO.userError "absolute cohort and evidence paths required")
  IO.FS.createDirAll records
  unless !(← (records / "seed-plans.json").pathExists) do throw (IO.userError "preserve sealed seed cohort")
  let first ← IO.ofExcept (fromJson? (α := StudyAcquire.Plan) (← StudyAdmission.readJson (root / "seed-1.plan.json").toString))
  unless first.handoffChars == 500000 && first.model == "gpt-5.6-luna" && first.effort == "xhigh" do
    throw (IO.userError "candidate acquisition treatment changed")
  for index in [1,2,3] do
    unless !(← (root / s!"study/seed-{index}").pathExists) && !(← (root / s!"seed-{index}.guard.json").pathExists) do
      throw (IO.userError "freeze the complete cohort before any acquisition")
  -- This metadata-only sealer runs in the Lean interpreter. The authoritative
  -- opened-file/version check remains in the native acquisition controller,
  -- before any charged dispatch; do not call its native-only FFI here.
  for frozen in #[first.runtime,first.runner] do
    unless (← artifact (.mk frozen.path)).sha256 == frozen.sha256 do
      throw (IO.userError "frozen cohort executable changed")
  let ownedScope := root.parent.get!
  for frozen in #[first.runtime,first.runner] do
    unless StudyRuntime.inside ownedScope (← IO.FS.realPath (.mk frozen.path)) do
      throw (IO.userError "cohort executable is outside its monitored experiment")
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
      record := plan.guardRecord,cwd := root.toString,ownedPrefixes := #[ownedScope.toString],
      limitRssKiB := 3670016,minFreeKiB := 2097152,
      command := #[first.runner.path,"acquire-bounded",sealed.path,sealed.sha256,budget.path,budget.sha256]
    } : ResourceGuard.Settings)).pretty
  let firstSettings := root / "seed-1.settings.json"
  let settings ← StudyAdmission.readJson firstSettings.toString
  IO.FS.writeFile firstSettings ((settings.setObjVal! "ownedPrefixes" (toJson #[ownedScope.toString])).pretty)
  IO.FS.writeFile (records / "seed-plans.json") (Json.mkObj [
    ("plans",toJson plans),("limits",toJson budget),("runtime",toJson first.runtime),
    ("runner",toJson first.runner),("handoffChars",toJson first.handoffChars),
    ("processOwnershipRoot",toJson ownedScope.toString),
    ("answeringModelCallsBeforeSeal",toJson (0 : Nat)),("seeds",toJson (3 : Nat)),
    ("stagesPerBlock",toJson (6 : Nat)),("armsPerStage",toJson (3 : Nat)),
    ("checkpoint",toJson "Each stage gives fresh/current/candidate the same prompt/source; the two memory arms receive the same frozen source/private-history checkpoint. Candidate trajectory is predeclared, not a best repetition."),
    ("noAutomaticRetry",toJson true),("adopted",toJson false)]).pretty
