import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def source := base/"frontend-quiescence-fixture-small1/work.project"
def runtime := base/"grouped-ingress-traffic-build/StudyMain"
def selectedRuntime : IO System.FilePath := do
  return (← IO.getEnv "EGGSHELL_PROFILE_RUNTIME").map System.FilePath.mk |>.getD runtime
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def save (path : System.FilePath) (value : Json) : IO Unit := IO.FS.writeFile path (value.compress++"\n")
def hash (path : System.FilePath) : IO String := do
  let reply ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  unless reply.exitCode == 0 do throw (IO.userError "cannot seal phase-profile input")
  return (reply.stdout.splitOn " ").head!
def command (args : Array String) (input : Option String := none) : IO IO.Process.Output := do
  IO.Process.output {cmd := (← selectedRuntime).toString,args} input
def sampleWorker (root : System.FilePath) : IO (Option (Task (Except IO.Error Unit))) := do
  if (← IO.getEnv "EGGSHELL_PROFILE_SAMPLE") != some "1" then return none
  let engine := (← selectedRuntime).toString
  let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axww","-o","pid=,command="]}
  let pids := processes.stdout.splitOn "\n" |>.filterMap fun line => do
    let words := line.trimAscii.toString.splitOn " " |>.filter (!·.isEmpty)
    let first :: rest := words | none
    if (" ".intercalate rest).startsWith (engine++" codex-worker search") then first.toNat? else none
  save (root/"sample-targets.json") (toJson pids)
  let [pid] := pids | return none
  return some (← IO.asTask (do
    IO.sleep 1000
    let started ← IO.monoMsNow
    let sampled ← IO.Process.output {cmd := "/usr/bin/sample",args := #[toString pid,"2","1","-file",(root/"worker.sample.txt").toString]}
    save (root/"sample-result.json") (Json.mkObj [("pid",toJson pid),("exitCode",toJson sampled.exitCode.toNat),
      ("elapsedMs",toJson ((← IO.monoMsNow)-started)),("stdout",toJson sampled.stdout),("stderr",toJson sampled.stderr)])
    pure ()) .dedicated)
def main (args : List String) : IO Unit := do
  let [raw] := args | throw (IO.userError "fresh absolute phase-profile root required")
  let root : System.FilePath := .mk raw
  unless root.isAbsolute && !(← root.pathExists) do throw (IO.userError "preserve previous profile")
  IO.FS.createDirAll root
  let owners ← (source/"owners").readDir
  let heads ← owners.mapM fun owner => do
    let path := owner.path/"source.egg/head"
    return (path.toString,← IO.FS.readFile path,← hash path)
  save (root/"original-heads.json") (toJson heads)
  IO.FS.writeFile (root/"eggshell.toml") ("default = \"work\"\n[eggs]\nwork = \""++source.toString++
    "\"\n[profiles.work]\nread = [\"work\"]\nwrite = \"work\"\nhandoff_chars = 120000\n")
  let identity ← hash (← selectedRuntime)
  let mut rows := #[]
  try
    let started ← IO.monoMsNow
    let warm ← command #["egg","warm",source.toString]
    save (root/"warm.json") (Json.mkObj [("elapsedMs",toJson ((← IO.monoMsNow)-started)),
      ("exitCode",toJson warm.exitCode.toNat),("stdout",toJson warm.stdout),("stderr",toJson warm.stderr)])
    unless warm.exitCode == 0 do throw (IO.userError "explicit phase-profile warm failed")
    for i in [:2] do
      let session := s!"phase-profile-{i}"
      IO.FS.withFile (root/"handoff.trace") .append fun file => file.putStrLn s!"request {i}"
      let input := Json.mkObj [("session_id",toJson session),("turn_id",toJson "turn"),
        ("cwd",toJson root.toString),("hook_event_name",toJson "UserPromptSubmit"),
        ("_eggshell_config",toJson (root/"eggshell.toml").toString),
        ("prompt",toJson "Return the recorded head and tail facts for support case-79.")]
      let began ← IO.monoMsNow
      let sampler ← if i == 1 then sampleWorker root else pure none
      let reply ← try command #["codex-hook"] (some input.compress)
        finally if let some sampler := sampler then IO.ofExcept (← IO.wait sampler)
      let elapsed := (← IO.monoMsNow)-began
      IO.FS.writeFile (root/s!"hook-{i}.json") reply.stdout
      IO.FS.writeFile (root/s!"hook-{i}.stderr") reply.stderr
      let output ← IO.ofExcept (Json.parse reply.stdout)
      let body ← IO.ofExcept ((output.getObjValD "hookSpecificOutput").getObjValAs? String "additionalContext")
      let complete := body.contains "\"observed-head-case-79-7b319c\"" &&
        body.contains "\"observed-tail-case-79-d82a04\""
      rows := rows.push (Json.mkObj [("session",toJson session),("elapsedMs",toJson elapsed),
        ("exitCode",toJson reply.exitCode.toNat),("bothOriginalFields",toJson complete),
        ("stdoutSha256",toJson (← hash (root/s!"hook-{i}.json"))),("body",toJson body)])
      save (root/"rows.json") (toJson rows)
      unless reply.exitCode == 0 && complete && elapsed < 30000 do
        throw (IO.userError "single diagnostic hook failed; retain its actual body")
    for (path,expected,_) in heads do
      unless (← IO.FS.readFile (.mk path)) == expected do throw (IO.userError "profile changed an original head")
    save (root/"report.json") (Json.mkObj [("runtimeSha256",toJson identity),("rows",toJson rows),
      ("originalHeadsUnchanged",toJson true),("answeringModelCalls",toJson (0 : Nat)),
      ("diagnosticOnly",toJson true),("adopted",toJson false)])
  finally
    let stopped ← command #["codex-daemon","shutdown"]
    let published ← command #["publication-control","shutdown"]
    save (root/"shutdown.json") (Json.mkObj [("frontendExit",toJson stopped.exitCode.toNat),
      ("publicationExit",toJson published.exitCode.toNat)])
