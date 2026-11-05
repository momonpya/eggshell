import Main
open Lean Eggshell Eggshell.Plugin
namespace Eggshell.Research.SourceProtocolProbe
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def save (path : System.FilePath) (value : Json) : IO Unit := IO.FS.writeFile path value.pretty
def hash (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  check (result.exitCode == 0) "cannot seal native protocol participant"
  return (result.stdout.splitOn " ").headD ""
def exchange (endpoint : Daemon.Endpoint) (kind : String) (payload : Json) (deadline : Nat) : IO Json := do
  IO.ofExcept (Json.parse (← Daemon.exchangeBefore endpoint kind payload deadline))
structure Source where
  directory : String
  source : Json
  storage : Json
  captured : Json
  deriving ToJson
structure Acquired where
  index : Nat
  elapsedMs : Nat
  refs : Array Json
  errors : Array String
  complete : Bool
def acquire (endpoint : Daemon.Endpoint) (sources : Array Source) (index start deadline holdUntil : Nat) : IO Acquired := do
  let mut refs := #[]
  let mut errors := #[]
  try
    let now ← IO.monoMsNow
    check (now < deadline) "source acquisition expired before send"
    let requests := sources.map fun row => Json.mkObj [
      ("directory",toJson row.directory),("source",row.source),("storage",row.storage),
      ("captured",row.captured),("holdUntil",toJson (some holdUntil))]
    let values ← IO.ofExcept (← exchange endpoint "prepare-source-batch"
      (Json.mkObj [("budgetMs",toJson (deadline-now)),("requests",toJson requests)]) deadline).getArr?
    check (values.size == sources.size) "source batch changed inventory"
    for (source,row) in sources.zip values do
      if let .ok error := row.getObjValAs? String "error" then
        errors := errors.push error
        continue
      let value := row.getObjValD "value"
      if value == Json.null then errors := errors.push "source unavailable"; continue
      check (value.getObjValD "source" == source.source && value.getObjValD "metadata" == source.captured)
        "response changed full captured Head or manifest"
      for field in ["retained","scope","capability"] do
        let text ← IO.ofExcept (value.getObjValAs? String field)
        check (text.length == 64 && text.toList.all (fun c => c.isDigit || ('a' ≤ c && c ≤ 'f')))
          "response omitted a bounded source capability"
      refs := refs.push value
  catch error => errors := errors.push error.toString
  return ⟨index,(← IO.monoMsNow)-start,refs,errors,refs.size == sources.size && errors.isEmpty⟩
def release (endpoint : Daemon.Endpoint) (refs : Array Json) (deadline : Nat) : IO (Option String) := do
  if refs.isEmpty then return none
  try
    let now ← IO.monoMsNow
    check (now < deadline) "release expired before send"
    let requests := refs.map fun row => Json.mkObj [("secret",row.getObjValD "capability"),
      ("database",row.getObjValD "database"),("scope",row.getObjValD "scope"),("retained",row.getObjValD "retained")]
    let values ← IO.ofExcept (fromJson? (α := Array Bool) (← exchange endpoint "release-retained-source-batch"
      (Json.mkObj [("budgetMs",toJson (deadline-now)),("requests",toJson requests)]) deadline))
    check (values.size == refs.size && values.all id) "release inventory not acknowledged"
    return none
  catch error => return some error.toString
def wave (root : System.FilePath) (endpoint : Daemon.Endpoint) (sources : Array Source) (label : String) (count : Nat) : IO Json := do
  let started ← IO.monoMsNow
  let holdUntil := started+28800
  -- The same quarter of the original remaining lifetime as prepareMany;
  -- neither a fresh clock nor a larger acquisition window is supplied.
  let deadline := started+(holdUntil-started)/4
  let tasks ← (List.range count).toArray.mapM fun index =>
    IO.asTask (acquire endpoint sources index started deadline holdUntil) .dedicated
  let rows ← tasks.mapM fun task => do IO.ofExcept (← IO.wait task)
  let acquiredAt ← IO.monoMsNow
  let full ← exchange endpoint "stats" Json.null holdUntil
  let releaseTasks ← rows.mapM fun row => IO.asTask (release endpoint row.refs holdUntil) .dedicated
  let releases ← releaseTasks.mapM fun task => do IO.ofExcept (← IO.wait task)
  let drained ← exchange endpoint "stats" Json.null holdUntil
  let latency := rows.map (·.elapsedMs) |>.qsort (· < ·)
  let report := Json.mkObj [("name",toJson label),("queries",toJson count),("sourcesPerCut",toJson sources.size),
    ("originalLifetimeMs",toJson (28800 : Nat)),("acquisitionBudgetMs",toJson (deadline-started)),
    ("acquisitionWallMs",toJson (acquiredAt-started)),("completeCuts",toJson (rows.filter (·.complete)).size),
    ("returnedTokens",toJson (rows.foldl (fun total row => total+row.refs.size) 0)),
    ("latencyMs",Json.mkObj [("min",toJson latency[0]?),("median",toJson latency[count/2]?),("max",toJson latency.back?)]),
    ("rows",toJson (rows.map fun row => Json.mkObj [("index",toJson row.index),("elapsedMs",toJson row.elapsedMs),
      ("tokens",toJson row.refs.size),("errors",toJson row.errors),("complete",toJson row.complete)])),
    ("full",full),("drained",drained),("releaseErrors",toJson releases)]
  save (root/(label++".json")) report
  return report
def awaitEndpoint (root : System.FilePath) (pid : Nat) : IO Daemon.Endpoint := do
  let deadline := (← IO.monoMsNow)+15000
  repeat
    if ← (root/"private/publisher/endpoint.json").pathExists then
      let endpoint ← IO.ofExcept (fromJson? (α := Daemon.Endpoint) (← read (root/"private/publisher/endpoint.json")))
      check (endpoint.pid == pid && endpoint.session == "publisher" && endpoint.compatible (← Publication.generation))
        "protocol owner differs from selected process/implementation"
      return endpoint
    check ((← IO.monoMsNow) < deadline) "source service did not publish endpoint"
    IO.sleep 5
  throw (IO.userError "unreachable source startup")
def run (root runtime : System.FilePath) (expected mode : String) : IO Unit := do
  check (!(← root.pathExists) && root.isAbsolute && (mode == "external" || mode == "hosted")) "fresh source protocol root/mode required"
  check ((← hash runtime) == expected) "source protocol runtime changed"
  check ((← IO.getEnv "EGGSHELL_DATA_ROOT") == some (root/"private").toString) "private protocol data root differs"
  IO.FS.createDirAll root
  let project := base/"frontend-quiescence-fixture-small1/work.project"
  IO.FS.writeFile (root/"eggshell.toml") ("default = \"work\"\n[eggs]\nwork = \""++project.toString++
    "\"\n[profiles.work]\nread = [\"work\"]\nwrite = \"work\"\nhandoff_chars = 120000\n")
  let heads ← IO.ofExcept (fromJson? (← read (workspace/"docs/candidates/worker-cpu/heads.json")) :
    Except String (Array (String × String × String)))
  let unchanged : IO Unit := do
    for (path,bytes,sha) in heads do
      check ((← IO.FS.readFile (.mk path)) == bytes && (← hash (.mk path)) == sha)
        "protocol study changed original source"
  unchanged
  let warmed ← IO.Process.output {cmd := runtime.toString,args := #["egg","warm",project.toString]}
  save (root/"warm.json") (Json.mkObj [("exitCode",toJson warmed.exitCode.toNat),("stdout",toJson warmed.stdout),("stderr",toJson warmed.stderr)])
  check (warmed.exitCode == 0) "protocol inputs are not prepared"
  let prepared ← IO.ofExcept (Json.parse warmed.stdout)
  let databases ← IO.ofExcept (prepared.getObjValAs? (Array Json) "databases")
  check (databases.size == 1) "source preparation changed project domain"
  let entries ← IO.ofExcept (databases[0]!.getObjValAs? (Array Json) "sources")
  let sources ← entries.mapM fun entry => do
    let input := entry.getObjValD "prepared"
    let original := input.getObjValD "source"
    let some row := heads.find? (fun (_,bytes,_) => (Json.parse bytes).toOption == some original) |
      throw (IO.userError "prepared input not in frozen original cut")
    let canonical ← IO.ofExcept (input.getObjValD "canonical").getArr?
    check (canonical.size == 2) "prepared original has no canonical manifest"
    return (⟨(System.FilePath.mk row.1).parent.get!.toString,original,canonical[0]!,canonical[1]!⟩ : Source)
  check (sources.size == 16) "complete source cut changed"
  save (root/"frozen-sources.json") (toJson sources)
  let child ← if mode == "external" then
      some <$> IO.Process.spawn {cmd := runtime.toString,args := #["codex-publication-daemon"],stdin := .null,stdout := .null,stderr := .inherit}
    else pure none
  let task ← if mode == "hosted" then
      some <$> IO.asTask (Numerical.withDefaultKeeper Publication.Service.run 1000) .dedicated
    else pure none
  let pid := child.map (·.pid.toNat) |>.getD (← IO.Process.getPID).toNat
  let endpoint ← awaitEndpoint root pid
  try
    let prime ← wave root endpoint sources "prime" 1
    check (prime.getObjValD "completeCuts" == toJson (1 : Nat)) "protocol priming did not acquire full cut"
    let eighty ← wave root endpoint sources "eighty" 80
    unchanged
    save (root/"report.json") (Json.mkObj [("mode",toJson mode),("runtimeSha256",toJson expected),
      ("controllerSha256",toJson (← hash (← IO.appPath))),("prime",prime),("eighty",eighty),
      ("originalHeadsUnchanged",toJson true),("searchesSubmitted",toJson (0 : Nat)),
      ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  finally
    let shutdown ← try
      let _ ← exchange endpoint "shutdown" Json.null ((← IO.monoMsNow)+5000)
      pure true
      catch _ => pure false
    let deadline := (← IO.monoMsNow)+10000
    let mut exited := false
    repeat
      exited ← match child,task with
        | some child,_ => (fun status => status.isSome) <$> child.tryWait
        | _,some task => IO.hasFinished task
        | _,_ => pure false
      if exited || (← IO.monoMsNow) ≥ deadline then break
      IO.sleep 5
    save (root/"shutdown.json") (Json.mkObj [("ack",toJson shutdown),("ownerExited",toJson exited)])
    check exited "protocol service did not stop"
    if let some task := task then check ((← IO.ofExcept (← IO.wait task)) == 0) "hosted protocol owner failed"
def observeOverlap (root runtime : System.FilePath) (expected : String) : IO Unit := do
  check (!(← root.pathExists) && root.isAbsolute) "fresh overlap observation required"
  check ((← hash runtime) == expected) "overlap runtime changed"
  let client := base/"session-dispatch-client-build/StudyMain"
  check ((← hash client) == "9b69f9b541a5b04a431350cd39a13410ec2d2f5c54ec7625da29aab4bec76c8a")
    "sealed actual-hook client changed"
  let child ← IO.Process.spawn {
    cmd := client.toString,args := #[root.toString,runtime.toString,expected,"burst80"],
    stdin := .null,stdout := .null,stderr := .inherit}
  let deadline := (← IO.monoMsNow)+60000
  while !(← (root/"prime.json").pathExists) do
    check ((← child.tryWait).isNone && (← IO.monoMsNow) < deadline) "overlap priming did not finish"
    IO.sleep 20
  let endpoint ← IO.ofExcept (fromJson? (α := Daemon.Endpoint) (← read (root/"private/publisher/endpoint.json")))
  let prime ← read (root/"prime.json")
  let processes ← IO.ofExcept (prime.getObjValAs? (Array Json) "after")
  check (processes.any fun process => process.getObjValD "pid" == toJson endpoint.pid &&
    process.getObjValD "role" == toJson "publication-service") "sample target is not the primed source owner"
  let sampler ← IO.asTask (do
    IO.sleep 750
    IO.Process.output {cmd := "/usr/bin/sample",args := #[toString endpoint.pid,"2","1","-file",(root/"overlap.sample.txt").toString]}) .dedicated
  let code ← child.wait
  let observed ← IO.ofExcept (← IO.wait sampler)
  save (root/"observer.json") (Json.mkObj [("runtimeSha256",toJson expected),
    ("controllerSha256",toJson (← hash (← IO.appPath))),("clientExitCode",toJson code.toNat),
    ("samplePid",toJson endpoint.pid),("sampleExitCode",toJson observed.exitCode.toNat),
    ("sampleStdout",toJson observed.stdout),("sampleStderr",toJson observed.stderr),
    ("unmodifiedSearchClient",toJson true),("sampleMayPerturbTiming",toJson true),("adopted",toJson false)])
  check (code == 0 && observed.exitCode == 0) "actual hook or overlap sampler failed"
end Eggshell.Research.SourceProtocolProbe
def main (args : List String) : IO UInt32 := do
  match args with
  | ["observe-source-overlap",root,runtime,sha] =>
    Eggshell.Research.SourceProtocolProbe.observeOverlap (.mk root) (.mk runtime) sha
    return 0
  | ["source-protocol-study",root,runtime,sha,mode] =>
    Eggshell.Research.SourceProtocolProbe.run (.mk root) (.mk runtime) sha mode
    return 0
  | other => sourceRouteEngine other
