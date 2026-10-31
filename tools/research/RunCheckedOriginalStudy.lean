import Lean
open Lean
private def ensure (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let records := project / "docs/candidates/checked-original/hooks"
  ensure (!(← records.pathExists)) "preserve previous checked original hooks"
  for arm in ["baseline","candidate"] do
    let helper := root / ("checked-original-hook-" ++ arm ++ "-build")
    let runtime := root / (if arm == "baseline" then "query-cache-baseline-build" else "checked-original-runtime-build")
    let dependencies : Array (String × String) ← IO.ofExcept
      (fromJson? (← read (helper / "tools_research_CheckedOriginalHook.dependencies")))
    let expected : Array (String × String) ← IO.ofExcept (fromJson? (← read (runtime / "Main.dependencies")))
    let expected := Std.HashMap.ofArray expected
    for (name,stamp) in dependencies do
      if let some saved := expected[name]? then ensure (stamp == saved) ("runtime/helper native mismatch: " ++ name)
    for (kind,directory) in [("helper",helper),("runtime",runtime)] do
      let inspected ← IO.Process.output {
        cmd := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean"
        args := #["-M3072","--run",(project / "tools/research/StudyBuildClosureAudit.lean").toString,
          "inspect",directory.toString,(records.parent.get! / (arm ++ "-" ++ kind ++ "-native-closure.json")).toString]}
      ensure (inspected.exitCode == 0) "native closure rejected checked original study"
  IO.FS.createDirAll records
  let invoke := fun arm mode extra => do
    IO.FS.writeFile (records / "phase.json") (Json.mkObj [
      ("arm",toJson arm),("mode",toJson mode),("args",toJson extra)]).pretty
    let result ← IO.Process.output {
      cmd := (root / ("checked-original-hook-" ++ arm ++ "-build/StudyMain")).toString
      args := #[mode,arm] ++ extra
      env := #[("LEAN_NUM_THREADS",some "1"),
        ("EGGSHELL_DATA_ROOT",some (root / "checked-original-hook-trial" / arm / "data").toString)]}
    ensure (result.exitCode == 0) ("checked original hook step failed: " ++ result.stderr)
  for arm in ["baseline","candidate"] do
    invoke arm "describe" #[]
    invoke arm "prepare" #[]
  let mut comparison := none
  let mut results := #[]
  for (arm,repetition) in [("baseline","0"),("candidate","0"),("candidate","1"),("baseline","1")] do
    invoke arm "run" #[repetition,"1"]
    let folder := records / arm / ("rep-" ++ repetition) / "topic-1"
    let body ← IO.FS.readFile (folder / "body.txt")
    let presentation ← read (folder / "original-presentation.json")
    let result ← read (folder / "result.json")
    let available := result.getObjValD "availableDelivery"
    ensure ((← IO.ofExcept (result.getObjValAs? Nat "elapsedMs")) < 30000) "actual hook exceeded deadline"
    ensure (available.getObjValD "eligible" == toJson (3 : Nat)) "frozen original denominator changed"
    let current := (body,presentation,available)
    match comparison with
    | none => comparison := some current
    | some previous => ensure (current == previous) "stop after first actual body/original/coverage difference"
    results := results.push result
    IO.FS.writeFile (records / "progress.json") (toJson results).pretty
    IO.println s!"{arm}/{repetition}: {result.compress}"
  IO.FS.writeFile (records / "results.json") (Json.mkObj [
    ("trials",toJson results),("sameBodyAndOriginalRanges",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false),
    ("fullPlannerInService",toJson false),("tokenImprovementMeasured",toJson false)]).pretty
