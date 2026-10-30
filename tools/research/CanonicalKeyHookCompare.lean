import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
import Std.Data.HashMap
open Lean

private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def read (p : System.FilePath) : IO Json := IO.FS.readFile p >>= fun s => IO.ofExcept (Json.parse s)

private def capacity (root : System.FilePath) : IO Nat := do
  let result ← IO.Process.output {cmd := "/bin/df",args := #["-Pk",root.toString]}
  check (result.exitCode == 0) "cannot inspect matched setup capacity"
  let some row := ((result.stdout.splitOn "\n").filter (!·.isEmpty)).getLast? |
    throw (IO.userError "missing filesystem capacity")
  let some available := ((row.splitOn " ").filter (!·.isEmpty))[3]?.bind String.toNat? |
    throw (IO.userError "invalid filesystem capacity")
  check (available ≥ 3145728) "matched setup requires the unchanged 3 GiB startup reserve"
  return available

private def commonInputs (helper runtime : System.FilePath) : IO Nat := do
  let a : Array (String × String) ← IO.ofExcept (fromJson? (← read (helper / "tools_research_CanonicalKeyHookArm.dependencies")))
  let b : Array (String × String) ← IO.ofExcept (fromJson? (← read (runtime / "Main.dependencies")))
  let left := Std.HashMap.ofArray a
  let right := Std.HashMap.ofArray b
  for name in ["Eggshell.Blake3","Eggshell.PublicationWire","Eggshell.GraphStore"] do
    check ((left[name]?).isSome && left[name]? == right[name]?) "arm helper differs from its runtime kernel"
  let mut count := 0
  for (name,stamp) in a do
    if let some expected := right[name]? then
      check (stamp == expected) "shared native module changed between producer and runtime"
      count := count+1
  return count

def main (args : List String) : IO Unit := do
  check args.isEmpty "fixed topic-1 key-directory refinement only"
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let study : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
  let root := study / "shared-snapshot"
  let records := project / "docs/candidates/canonical-keys/hooks"
  let protocol := records / "protocol.json"
  check (!(← protocol.pathExists) && !(← (root / "canonical-keys-hook-trial").pathExists)) "fresh matched hook experiment required"
  let available ← capacity root
  IO.FS.createDirAll records
  let arms := #["baseline","candidate"]
  let helpers := fun arm => root / ("canonical-keys-hook-" ++ arm ++ "-build")
  let runtime := fun arm => root / (if arm == "baseline" then "query-cache-baseline-build" else "canonical-keys-runtime-build")
  let mut kernelMatches := #[]
  for arm in arms do kernelMatches := kernelMatches.push (arm,← commonInputs (helpers arm) (runtime arm))
  IO.FS.writeFile protocol (Json.mkObj [("topic",toJson (1 : Nat)),("repetitions",toJson (2 : Nat)),
    ("orders",toJson #[#["baseline","candidate"],#["candidate","baseline"]]),
    ("freshSessions",toJson true),("sameFrozenSourceAndPrivateHistory",toJson true),
    ("commonKernelModules",toJson kernelMatches),("captureInput",toJson false),("rangeDiagnostics",toJson false),
    ("startupAvailableKiB",toJson available),("startupMinimumKiB",toJson (3145728 : Nat)),
    ("stopOnBodyChangeOrTimeout",toJson true),("speedAndRefinementDiagnosticOnly",toJson true),
    ("notSecondLap",toJson true),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
  let invoke := fun (arm mode : String) (more : Array String) => do
    IO.FS.writeFile (records / "phase.json") (Json.mkObj [("arm",toJson arm),("mode",toJson mode),("arguments",toJson more)]).pretty
    let command := #["LEAN_NUM_THREADS=1",
      "EGGSHELL_DATA_ROOT=" ++ (root / "canonical-keys-hook-trial" / arm / "data").toString,
      (helpers arm / "StudyMain").toString,mode,arm] ++ more
    let response ← IO.Process.output {cmd := "/usr/bin/env",args := command}
    check (response.exitCode == 0) ("isolated key-directory hook arm failed: " ++ arm ++ "/" ++ mode ++ ": " ++ toString (response.stderr.take 512))
  for arm in arms do invoke arm "describe" #[]
  for arm in arms do
    let _ ← capacity root
    invoke arm "prepare" #[]
  let mut results := #[]
  let mut body : Option String := none
  let mut valid := true
  for repetition in [0:2] do
    let order := if repetition == 0 then arms else arms.reverse
    for arm in order do
      invoke arm "run" #[toString repetition]
      let folder := records / arm / s!"rep-{repetition}"
      let current ← IO.FS.readFile (folder / "body.txt")
      let same := body.all (· == current)
      if body.isNone then body := some current
      let result ← read (folder / "result.json")
      let elapsed ← IO.ofExcept (result.getObjValAs? Nat "elapsedMs")
      results := results.push (result.setObjVal! "bodyUnchanged" (toJson same))
      IO.FS.writeFile (records / "progress.json") (toJson results).pretty
      IO.println s!"Actual hook {arm}/{repetition}: {elapsed} ms; same body {same}"
      if !same || elapsed ≥ 30000 then
        valid := false
        break
    if !valid then break
  IO.FS.writeFile (records / "result.json") (Json.mkObj [("results",toJson results),
    ("allBodiesUnchangedAndWithinDeadline",toJson valid),("notSecondLap",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("tokenImprovementMeasured",toJson false),("adopted",toJson false)]).pretty
