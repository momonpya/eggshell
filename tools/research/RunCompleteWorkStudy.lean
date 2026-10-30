import Lean
open Lean
private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let records := project / "docs/candidates/complete-work/hooks"
  check (!(← records.pathExists)) "preserve previous complete Work hooks"
  let helper := root / "complete-work-hook-candidate-build"
  let runtime := root / "complete-work-runtime-build"
  let dependencies : Array (String × String) ← IO.ofExcept (fromJson? (← read (helper / "tools_research_CompleteWorkHook.dependencies")))
  let expected : Array (String × String) ← IO.ofExcept (fromJson? (← read (runtime / "Main.dependencies")))
  let expected := Std.HashMap.ofArray expected
  for (name,stamp) in dependencies do
    if let some original := expected[name]? then check (stamp == original) "producer/runtime native code mismatch"
  check ((Std.HashMap.ofArray dependencies)["Eggshell.Handoff"]? == expected["Eggshell.Handoff"]?)
    "producer and runtime have different Handoff"
  for (name,directory) in [("runtime",runtime),("helper",helper)] do
    let inspected ← IO.Process.output {
      cmd := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean"
      args := #["-M3072","--run",(project / "tools/research/StudyBuildClosureAudit.lean").toString,
        "inspect",directory.toString,(records.parent.get! / (name ++ "-native-closure.json")).toString]}
    check (inspected.exitCode == 0) ("native closure rejected " ++ name)
  IO.FS.createDirAll records
  let invoke := fun mode extra => do
    IO.FS.writeFile (records / "phase.json") (Json.mkObj [("mode",toJson mode),("args",toJson extra)]).pretty
    let result ← IO.Process.output {
      cmd := (helper / "StudyMain").toString,args := #[mode,"candidate"] ++ extra,
      env := #[("LEAN_NUM_THREADS",some "1"),
        ("EGGSHELL_DATA_ROOT",some (root / "complete-work-hook-trial/candidate/data").toString)]}
    check (result.exitCode == 0) ("complete Work stage failed: " ++ toString (result.stderr.take 1200))
  invoke "describe" #[]
  invoke "prepare" #[]
  let mut results := #[]
  for topic in [1,2,3] do
    invoke "run" #["0",toString topic]
    let folder := records / "candidate/rep-0" / s!"topic-{topic}"
    let result ← read (folder / "result.json")
    let elapsed ← IO.ofExcept (result.getObjValAs? Nat "elapsedMs")
    let plans ← IO.ofExcept (result.getObjValAs? Nat "completePlanReceipts")
    let covered := result.getObjValD "availableDelivery"
    results := results.push (result.setObjVal! "topic" (toJson topic))
    IO.FS.writeFile (records / "progress.json") (toJson results).pretty
    IO.println s!"Complete Work topic {topic}: {elapsed} ms; complete receipts {plans}; {covered.compress}"
    check (covered.getObjValD "targetMet" == toJson true && elapsed < 30000 && plans > 0)
      "stop after first missing original, partial path or deadline"
  IO.FS.writeFile (records / "results.json") (Json.mkObj [("topics",toJson results),
    ("sameFrozenR40",toJson true),("capacityAndSelectionBothChanged",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("tokenImprovementMeasured",toJson false),
    ("adopted",toJson false)]).pretty
