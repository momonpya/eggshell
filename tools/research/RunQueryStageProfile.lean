import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
import Std.Data.HashMap
open Lean

private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def hash (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  check (result.exitCode == 0) "cannot seal stage measurement"
  return (result.stdout.splitOn " ").headD ""
private def verify (files : Array (String × String)) : IO Unit := do
  for (path,expected) in files do check ((← hash (.mk path)) == expected) "protected original/runtime changed"

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let records := project / "docs/candidates/query-stage-profile"
  let helper := root / "query-stage-hook-candidate-build"
  let runtime := root / "query-stage-runtime-build"
  let destination := records / "hooks"
  check (!(← destination.pathExists)) "preserve completed diagnostic hook"
  IO.FS.createDirAll records
  let a : Array (String × String) ← IO.ofExcept (fromJson? (← read (helper / "tools_research_QueryStageHookArm.dependencies")))
  let b : Array (String × String) ← IO.ofExcept (fromJson? (← read (runtime / "Main.dependencies")))
  let b := Std.HashMap.ofArray b
  let mut common := 0
  for (name,stamp) in a do
    if let some expected := b[name]? then
      check (stamp == expected) "diagnostic helper and runtime differ"
      common := common+1
  let files : Array (String × String) ← IO.ofExcept ((← read
    (project / "docs/candidates/read-signal-trace/native-seal.json")).getObjValAs? _ "verifiedOriginalFilesAndRuntimes")
  let files := files.push ((root / "register-runtime-build/StudyMain").toString,
    "1bd3d15bb3c708a14785c983fcb8e1c95d650bc55f837202d84538de0bda787b")
  verify files
  IO.FS.writeFile (records / "protocol.json") (Json.mkObj [("runtimeSha256",toJson (← hash (runtime / "StudyMain"))),
    ("helperSha256",toJson (← hash (helper / "StudyMain"))),("commonNativeModules",toJson common),
    ("topic",toJson (1 : Nat)),("invocations",toJson (1 : Nat)),("timingInstrumentationOnly",toJson true),
    ("newSelectionPolicy",toJson false),("latencyImprovementComparison",toJson false),
    ("answeringModels",toJson (0 : Nat)),("adopted",toJson false)]).pretty
  let mut stages : Array (String × String) := #[]
  for mode in ["describe","prepare","run"] do
    let args := #[mode,"candidate"] ++ (if mode == "run" then #["0"] else #[])
    let result ← IO.Process.output {
      cmd := (helper / "StudyMain").toString,args
      env := #[("LEAN_NUM_THREADS",some "1"),("EGGSHELL_DATA_ROOT",some (root / "query-stage-hook-trial/candidate/data").toString)]}
    IO.FS.writeFile (records / (mode ++ "-stdout.txt")) result.stdout
    IO.FS.writeFile (records / (mode ++ "-stderr.txt")) result.stderr
    IO.FS.writeFile (records / (mode ++ "-exit.json")) (Json.mkObj [("exitCode",toJson result.exitCode.toNat)]).pretty
    for line in result.stderr.splitOn "\n" do
      if (line.splitOn "eggshell-stage:").length > 1 then stages := stages.push (mode,line)
    IO.FS.writeFile (records / "stages.json") (toJson stages).pretty
    verify files
    check (result.exitCode == 0) ("stage diagnostic failed in " ++ mode ++ ": " ++ toString (result.stderr.takeEnd 1024))
    IO.println ("Completed diagnostic " ++ mode)
  let actual := project / "docs/candidates/query-stage/hooks"
  check (!(← destination.pathExists) && (← actual.pathExists)) "preserve completed hook records"
  IO.FS.rename actual destination
  let result ← read (destination / "candidate/rep-0/result.json")
  let same := result.getObjValD "bodySha256" == toJson "098a283dac9194d1c83196fba0ad8c4f601cfca6bb7b37bf8cbc16e88d11d481"
  let delivery := result.getObjValD "availableDelivery"
  let valid := same && delivery.getObjValD "eligible" == toJson (3 : Nat) &&
    delivery.getObjValD "delivered" == toJson (2 : Nat)
  IO.FS.writeFile (records / "result.json") ((result.setObjVal! "sameBaselineBody" (toJson same))
    |>.setObjVal! "stageLines" (toJson stages.size)
    |>.setObjVal! "protectedHashesBeforeAndAfter" (toJson true)
    |>.setObjVal! "wholeHookCpuPercentages" (toJson false)).pretty
  check valid "timing-only instrumentation changed actual delivery"
  check (!stages.isEmpty) "native stage observer produced no observations"
  IO.println s!"Exact prior actual body and frozen 2/3 evidence; {stages.size} stage observations; no answering model"
