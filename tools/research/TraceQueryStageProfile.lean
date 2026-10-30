import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson
import Std.Data.HashMap
open Lean

private def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def hash (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  check (result.exitCode == 0) "cannot seal file observation"
  return (result.stdout.splitOn " ").headD ""

def main (args : List String) : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let records := project / "docs/candidates/query-stage-profile"
  let helper := root / "query-stage-trace-candidate-build"
  let runtime := root / "query-stage-file-runtime-build"
  let trace := records / "trace-events.jsonl"
  let resume := args == ["resume"]
  check (args.isEmpty || resume) "only resume before any actual hook is supported"
  check (!(← trace.pathExists) && !(← (records / "trace-summary.json").pathExists)) "preserve previous observation"
  if resume then
    check (← (records / "trace/candidate-runtime.json").pathExists) "missing completed runtime description"
    check (!(← (records / "trace/candidate/rep-0").pathExists)) "never repeat an actual hook"
  else check (!(← (records / "trace").pathExists)) "preserve previous trace preparation"
  let a : Array (String × String) ← IO.ofExcept (fromJson? (← read (helper / "tools_research_QueryStageTraceArm.dependencies")))
  let b : Array (String × String) ← IO.ofExcept (fromJson? (← read (runtime / "Main.dependencies")))
  let b := Std.HashMap.ofArray b
  for (name,stamp) in a do
    if let some expected := b[name]? then check (stamp == expected) "native trace producer mismatch"
  let files : Array (String × String) ← IO.ofExcept ((← read
    (project / "docs/candidates/read-signal-trace/native-seal.json")).getObjValAs? _ "verifiedOriginalFilesAndRuntimes")
  for (path,expected) in files do check ((← hash (.mk path)) == expected) "original/runtime changed before trace"
  let previous ← read (records / "hooks/candidate-runtime.json")
  let stopped ← read (records / "hooks/candidate/rep-0/publisher-shutdown.json")
  check (stopped.getObjValD "processExited" == toJson true) "previous service still live"
  let fork := root / "query-stage-hook-trial/candidate"
  let copied ← IO.Process.output {cmd := "/bin/cp",args := #["-c",(runtime / "StudyMain").toString,
    (fork / "prefix/libexec/eggshell").toString]}
  check (copied.exitCode == 0) "cannot install diagnostic-only observer"
  for mode in (if resume then ["run"] else ["describe","run"]) do
    if mode == "run" then
      let target := records / "trace/candidate/ready.json"
      check (!(← target.pathExists)) "preserve reused source preparation"
      let ready ← read (records / "hooks/candidate/ready.json")
      let described ← read (records / "trace/candidate-runtime.json")
      check ((previous.getObjValD "runtime").getObjValD "generation" ==
        (described.getObjValD "runtime").getObjValD "generation") "prepared publication contract changed"
      IO.FS.createDirAll target.parent.get!
      IO.FS.writeFile target ((ready.setObjVal! "runtime" (described.getObjValD "runtime"))
        |>.setObjVal! "reusedOriginalSourcePreparation" (toJson true)).pretty
    let response ← IO.Process.output {
      cmd := (helper / "StudyMain").toString
      args := #[mode,"candidate"] ++ (if mode == "run" then #["0"] else #[])
      env := #[("LEAN_NUM_THREADS",some "1"),("EGGSHELL_DATA_ROOT",some (fork / "data").toString)]}
    let exitPath := records / ("trace-" ++ mode ++ (if resume then "-resumed" else "") ++ "-exit.json")
    check (!(← exitPath.pathExists)) "preserve previous helper exit"
    IO.FS.writeFile exitPath (Json.mkObj [("exitCode",toJson response.exitCode.toNat)]).pretty
    check (response.exitCode == 0) ("trace helper failed: " ++ toString (response.stderr.takeEnd 1024))
    if mode == "describe" then
      let next ← read (records / "trace/candidate-runtime.json")
      check ((previous.getObjValD "runtime").getObjValD "generation" ==
        (next.getObjValD "runtime").getObjValD "generation") "observation changed the prepared publication contract"
  let result ← read (records / "trace/candidate/rep-0/result.json")
  let body := records / "trace/candidate/rep-0/body.txt"
  let digest ← hash body
  check (digest == "098a283dac9194d1c83196fba0ad8c4f601cfca6bb7b37bf8cbc16e88d11d481" &&
    result.getObjValD "bodySha256" == toJson digest) "file observation changed actual original delivery"
  let mut events : Array Json := #[]
  let mut summary : Std.HashMap String (Nat × Nat) := {}
  for line in (← IO.FS.readFile trace).splitOn "\n" do
    if line.trimAscii.isEmpty then continue
    let value ← IO.ofExcept (Json.parse line)
    let name ← IO.ofExcept (value.getObjValAs? String "stage")
    let elapsed ← IO.ofExcept (value.getObjValAs? Nat "elapsedNs")
    let prior := summary[name]?.getD (0,0)
    summary := summary.insert name (prior.1+1,prior.2+elapsed)
    events := events.push value
  check (events.size > 0 && summary.contains "plan.total" && summary.contains "render.total" &&
    summary.contains "transport.total") "stage observation incomplete"
  for (path,expected) in files do check ((← hash (.mk path)) == expected) "original/runtime changed after trace"
  IO.FS.writeFile (records / "trace-summary.json") (Json.mkObj [("stages",toJson (summary.toArray.map fun (name,(count,elapsedNs)) =>
    Json.mkObj [("stage",toJson name),("count",toJson count),("inclusiveNs",toJson elapsedNs)])),
    ("actualHook",result),("sameBaselineBody",toJson true),("events",toJson events.size),
    ("nestedInclusiveTimesMustNotBeAdded",toJson true),("preparedDbReused",toJson true),
    ("sourcePreparationRetakes",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat)),
    ("protectedHashesBeforeAndAfter",toJson true),("adopted",toJson false)]).pretty
  IO.println (Json.mkObj [("elapsedMs",result.getObjValD "elapsedMs"),("stages",toJson summary.toArray),
    ("sameActualBody",toJson true)]).compress
