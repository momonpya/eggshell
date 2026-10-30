import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
import Std.Data.HashMap
open Lean

private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let records := project / "docs/candidates/routing-scope/hooks"
  check (!(← records.pathExists)) "preserve completed routing hook comparison"
  IO.FS.createDir records
  for arm in ["baseline","candidate"] do
    let helper := root / ("routing-scope-hook-" ++ arm ++ "-build")
    let runtime := root / (if arm == "baseline" then "query-cache-baseline-build" else "routing-scope-runtime-build")
    let dependencies : Array (String × String) ← IO.ofExcept (fromJson? (← read (helper / "tools_research_RoutingScopeHookArm.dependencies")))
    let expected : Array (String × String) ← IO.ofExcept (fromJson? (← read (runtime / "Main.dependencies")))
    let expected := Std.HashMap.ofArray expected
    for (name,stamp) in dependencies do
      if let some value := expected[name]? then check (stamp == value) "hook helper and runtime differ"
  IO.FS.writeFile (records / "protocol.json") (Json.mkObj [("topic",toJson (1 : Nat)),
    ("repetitionsPerArm",toJson (2 : Nat)),("order",toJson #["baseline-0","candidate-0","candidate-1","baseline-1"]),
    ("sameFrozenSnapshotPromptAndNumericalRuntime",toJson true),("freshSessions",toJson true),
    ("notSecondLap",toJson true),("answeringModelCalls",toJson (0 : Nat)),
    ("tokenImprovementMeasured",toJson false),("adopted",toJson false)]).pretty
  let invoke := fun arm mode extra => do
    let response ← IO.Process.output {
      cmd := (root / ("routing-scope-hook-" ++ arm ++ "-build/StudyMain")).toString
      args := #[mode,arm] ++ extra
      env := #[("LEAN_NUM_THREADS",some "1"),("EGGSHELL_DATA_ROOT",some (root / "routing-scope-hook-trial" / arm / "data").toString)]}
    check (response.exitCode == 0) ("routing hook " ++ arm ++ ": " ++ toString (response.stderr.take 1024))
  for arm in ["baseline","candidate"] do
    invoke arm "describe" #[]
    invoke arm "prepare" #[]
  let mut expectedBody : Option String := none
  let mut results := #[]
  let mut passed := true
  for (arm,repetition) in [("baseline","0"),("candidate","0"),("candidate","1"),("baseline","1")] do
    invoke arm "run" #[repetition]
    let folder := records / arm / ("rep-" ++ repetition)
    let result ← read (folder / "result.json")
    let elapsed ← IO.ofExcept (result.getObjValAs? Nat "elapsedMs")
    let body ← IO.FS.readFile (folder / "body.txt")
    let same := expectedBody.all (· == body)
    if expectedBody.isNone then expectedBody := some body
    let delivered := result.getObjValD "availableDelivery"
    let valid := same && elapsed < 30000 && delivered.getObjValD "eligible" == toJson (3 : Nat) &&
      delivered.getObjValD "delivered" == toJson (2 : Nat)
    let row := result.setObjVal! "sameActualBody" (toJson same)
    results := results.push row
    IO.FS.writeFile (records / "progress.json") (toJson results).pretty
    IO.println s!"Actual routing hook {arm}/{repetition}: {elapsed} ms; same body={same}; no answering model"
    if !valid then passed := false; break
  IO.FS.writeFile (records / "results.json") (Json.mkObj [("results",toJson results),
    ("sameActualBodyWithinDeadline",toJson passed),("requiredEvidenceUnchanged",toJson (passed && results.size == 4)),
    ("answeringModelCalls",toJson (0 : Nat)),("tokenImprovementMeasured",toJson false),("adopted",toJson false)]).pretty
  check passed "stop on the first body difference, evidence regression or timeout"
