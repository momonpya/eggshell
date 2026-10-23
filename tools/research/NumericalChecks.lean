import tools.research.StudyPrepare
import Eggshell.Numerical

open Lean Eggshell Eggshell.Research

private def check (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw (IO.userError message)

private abbrev Client := IO.Process.Child {stdin := .piped,stdout := .piped,stderr := .inherit}

private def ask (child : Client) (kind : String) (body : Json) : IO Json := do
  child.stdin.putStrLn (kind ++ body.compress)
  child.stdin.flush
  let response ← IO.ofExcept (Json.parse (← child.stdout.getLine))
  if let .ok error := response.getObjValAs? String "error" then throw (IO.userError error)
  return response

private def close (child : Client) : IO Unit := do
  child.stdin.putStr "C\n"
  child.stdin.flush
  let deadline := (← IO.monoMsNow)+10000
  repeat
    if let some code ← child.tryWait then
      check (code == 0) "numerical client did not exit successfully"
      return
    check ((← IO.monoMsNow) < deadline) "numerical client did not exit before its deadline"
    IO.sleep 5

private def absent (pid : Nat) : IO Bool := do
  let probe ← IO.Process.output {cmd := "/bin/kill",args := #["-0",toString pid],stdin := .null}
  return probe.exitCode != 0

/-- Real CLI clients share an actual service; this executable cannot start a
model turn. Frozen requests retain their original batch boundaries. -/
def main (args : List String) : IO Unit := do
  let [template,requests,expected,directory] := args |
    throw (IO.userError "NumericalChecks TEMPLATE REQUESTS EXPECTED NEW-DIRECTORY")
  let plan ← IO.ofExcept (fromJson? (α := StudyAdmission.Plan) (← StudyAdmission.readJson template))
  let root := System.FilePath.mk directory
  check (root.isAbsolute && !(← root.pathExists)) "new absolute numerical fixture directory required"
  check ((← IO.getEnv "EGGSHELL_DATA_ROOT") == some (root / "data").toString) "isolated numerical data root required"
  StudyAdmission.verifyArtifact plan.runtime
  IO.FS.createDirAll (root / "data")
  let some config ← Numerical.defaultConfig? | throw (IO.userError "pinned MiniLM runtime required")
  let environment := plan.environment.filter (fun row => row.1 != "EGGSHELL_DATA_ROOT") |>.push
    ("EGGSHELL_DATA_ROOT",some (root / "data").toString)
  let session := "numerical-resource-check"
  let managed ← StudyRuntime.startManaged (.mk plan.runtime.path) (.mk plan.pluginRoot) session
    (root / "data/sessions" / session / "daemon.json") environment
  let spawn : IO Client := IO.Process.spawn {
    cmd := plan.runtime.path,args := #["codex-numerical-client",config.model,config.models.toString,config.python.toString]
    env := environment,stdin := .piped,stdout := .piped,stderr := .inherit}
  let first ← spawn
  let second ← spawn
  let firstClosed ← IO.mkRef false
  let secondClosed ← IO.mkRef false
  let daemonClosed ← IO.mkRef false
  try
    check ((← Numerical.endpoint? config).isNone) "model service started without an embedding request"
    let unit := toJson "000000000000f03f0000000000000000"
    let scores ← ask first "S" (Json.mkObj [("queries",toJson #[unit]),("candidates",toJson #[#[unit]])])
    check ((scores.getObjValAs? (Array Float) "scores").toOption == some #[1.0]) "cache-only score changed"
    check ((← Numerical.endpoint? config).isNone) "cache-only score started a model service"
    let inputs := ((← IO.FS.readFile (.mk requests)).splitOn "\n").filter (!·.isEmpty)
    let mut numerical := #[]
    let mut vectors := 0
    for (input,index) in inputs.zipIdx do
      let request ← IO.ofExcept (Json.parse input)
      let response ← ask (if index % 2 == 0 then first else second) "E" request
      let texts ← IO.ofExcept (request.getObjValAs? (Array String) "texts")
      let groups ← IO.ofExcept (response.getObjValAs? (Array (Array (Array Float))) "vectors")
      check (groups.size == texts.size && groups.all (fun group => !group.isEmpty &&
        group.all (fun vector => vector.size == 384 && vector.all Float.isFinite))) "invalid numerical vector groups"
      vectors := vectors + groups.foldl (fun count group => count+group.size) 0
      numerical := numerical.push (Json.mkObj [
        ("vectors",← IO.ofExcept (response.getObjVal? "vectors")),
        ("coverage",← IO.ofExcept (response.getObjVal? "coverage"))])
    let bytes := ((toJson numerical).compress ++ "\n").toUTF8
    IO.FS.writeBinFile (root / "values.json") bytes
    check (bytes == (← IO.FS.readBinFile (.mk expected))) "shared model changed frozen vectors or token coverage"
    let some endpoint ← Numerical.endpoint? config | throw (IO.userError "missing shared numerical endpoint")
    let stats ← IO.ofExcept (Json.parse (← Plugin.Daemon.exchange endpoint "stats"))
    check ((stats.getObjValAs? Nat "modelStarts").toOption == some 1) "clients did not share one numerical model"
    let modelPid ← IO.ofExcept (stats.getObjValAs? Nat "modelPid")
    first.kill
    let _ ← first.wait
    firstClosed.set true
    check (!(← absent endpoint.pid) && !(← absent modelPid)) "one client killed another client's model"
    let _ ← ask second "E" (Json.mkObj [("texts",toJson #["shared numerical ownership remains live"] )])
    let after ← IO.ofExcept (Json.parse (← Plugin.Daemon.exchange endpoint "stats"))
    check (after == stats) "surviving client started another model"
    close second
    secondClosed.set true
    check (!(← absent endpoint.pid) && !(← absent modelPid)) "live chat lost its resident numerical model"
    StudyRuntime.stopManaged managed (root / "shutdown.json")
    daemonClosed.set true
    check ((← Numerical.endpoint? config).isNone && (← absent endpoint.pid) && (← absent modelPid))
      "last chat left a numerical service or model running"
    IO.FS.writeFile (root / "result.json") ((Json.mkObj [
      ("runtime",toJson plan.runtime),("requests",toJson inputs.length),("vectors",toJson vectors),
      ("checkedScalars",toJson (vectors*384)),("modelStarts",toJson (1 : Nat)),
      ("valuesSha256",toJson (Sha256.hex bytes)),("vectorsAndCoverageByteIdentical",toJson true),
      ("cacheOnlyDidNotStartModel",toJson true),("survivedClientExit",toJson true),
      ("lastChatStoppedModel",toJson true),("answeringModelCalls",toJson (0 : Nat))]).compress ++ "\n")
  finally
    if !(← firstClosed.get) then first.kill; let _ ← first.wait; pure ()
    if !(← secondClosed.get) then second.kill; let _ ← second.wait; pure ()
    if !(← daemonClosed.get) then StudyRuntime.abort managed
