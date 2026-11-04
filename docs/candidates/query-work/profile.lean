import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def heads (source : System.FilePath) : IO (Array Json) :=
  (List.range 16).toArray.mapM fun i => read (source/"work.project/owners"/toString i/"source.egg/head")
def sampleWorker (runtime : String) (root : System.FilePath) : IO Json := do
  IO.sleep 2200
  let endpoint ← read (root/"private/publisher/endpoint.json")
  let server ← IO.ofExcept (endpoint.getObjValAs? Nat "pid")
  let children ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","pid=,ppid=,command="]}
  unless children.exitCode == 0 do throw (IO.userError "could not observe owned query workers")
  let selected := (children.stdout.splitOn "\n").filterMap fun line =>
    let parts := (line.splitOn " ").filter (!·.isEmpty)
    if parts[1]?.bind String.toNat? == some server && line.contains (runtime++" codex-worker search") then
      parts.head?.bind String.toNat?
    else none
  let [pid] := selected | throw (IO.userError "sample requires one verified child query worker")
  let sampled ← IO.Process.output {cmd := "/usr/bin/sample",args := #[toString pid,"2","1","-file",(root/"worker.sample.txt").toString]}
  return Json.mkObj [("pid",toJson pid),("parent",toJson server),("exitCode",toJson sampled.exitCode.toNat),
    ("stdout",toJson sampled.stdout),("stderr",toJson sampled.stderr),("seconds",toJson (2 : Nat))]
def main (args : List String) : IO Unit := do
  let (runtime,sourceName,rootName,sampling,lexical) ← match args with
    | [runtime,sourceName,rootName] => pure (runtime,sourceName,rootName,false,false)
    | [runtime,sourceName,rootName,"sample"] => pure (runtime,sourceName,rootName,true,false)
    | [runtime,sourceName,rootName,"lexical"] => pure (runtime,sourceName,rootName,false,true)
    | _ => throw (IO.userError "runtime, retained source, fresh output and optional sample required")
  let source : System.FilePath := .mk sourceName
  let root : System.FilePath := .mk rootName
  unless !(← root.pathExists) do throw (IO.userError "preserve earlier profile")
  IO.FS.createDirAll root
  let expected := (← read (source/"frozen-readback.json")).getObjValD "sourceHeads"
  unless toJson (← heads source) == expected do throw (IO.userError "profile source changed")
  let identity ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",runtime]}
  unless identity.exitCode == 0 do throw (IO.userError "cannot freeze runtime")
  IO.FS.writeFile (root/"runtime.sha256") identity.stdout
  let config := root/"eggshell.toml"
  IO.FS.writeFile config ("default = \"work\"\n"++(if lexical then "semantic_matcher = false\n" else "")++"[eggs]\nwork = \""++(source/"work.project").toString++
    "\"\n[profiles.work]\nread = [\"work\"]\nwrite = \"work\"\nhandoff_chars = 120000\n")
  let env := #[("EGGSHELL_DATA_ROOT",some (root/"private").toString),("EGGSHELL_CONFIG",some config.toString),
    ("PLUGIN_ROOT",some (root/"no-plugin-bundle").toString),("LEAN_NUM_THREADS",some "1"),
    ("EGGSHELL_TRACE_SERVICE_PROFILE",some "1"),("EGGSHELL_HANDOFF_TRACE",some (root/"handoff.trace").toString)]
  let mut rows := #[]
  try
    let began ← IO.monoMsNow
    let warm ← IO.Process.output {cmd := runtime,args := #["egg","warm",(source/"work.project").toString],env := env}
    IO.FS.writeFile (root/"warm-stdout.json") warm.stdout
    IO.FS.writeFile (root/"warm-stderr.txt") warm.stderr
    IO.FS.writeFile (root/"warm-result.json") (Json.mkObj [("exitCode",toJson warm.exitCode.toNat),
      ("elapsedMs",toJson ((← IO.monoMsNow)-began))]).compress
    unless warm.exitCode == 0 do throw (IO.userError "profile warm failed")
    for name in ["cold-frontend","running-frontend"] do
      let before ← if ← (root/"handoff.trace").pathExists then IO.FS.readFile (root/"handoff.trace") else pure ""
      let input := Json.mkObj [("session_id",toJson ("query-work-"++name)),("turn_id",toJson "turn"),
        ("cwd",toJson source.toString),("hook_event_name",toJson "UserPromptSubmit"),
        ("_eggshell_config",toJson config.toString),
        ("prompt",toJson "Return the recorded head and tail facts for support case-79.")]
      let began ← IO.monoMsNow
      let spawned ← IO.Process.spawn {
        cmd := runtime
        args := #["codex-hook"]
        env := env
        stdin := .piped
        stdout := .piped
        stderr := .piped }
      let child ← do
        let (writer,child) ← spawned.takeStdin
        writer.putStr input.compress
        writer.flush
        pure child
      let sampler ← if sampling && name == "running-frontend" then do
          some <$> IO.asTask (sampleWorker runtime root) .dedicated
        else pure none
      let stdout ← child.stdout.readToEnd
      let stderr ← child.stderr.readToEnd
      let code ← child.wait
      let elapsed := (← IO.monoMsNow)-began
      IO.FS.writeFile (root/(name++"-stdout.json")) stdout
      IO.FS.writeFile (root/(name++"-stderr.txt")) stderr
      if let some sampler := sampler then
        let sampled ← match ← IO.wait sampler with
          | .ok value => pure value
          | .error error => pure (Json.mkObj [("error",toJson error.toString)])
        IO.FS.writeFile (root/"sampler.json") sampled.compress
        unless sampled.getObjValD "exitCode" == toJson (0 : Nat) do throw (IO.userError "native worker sampling failed")
      let trace ← IO.FS.readFile (root/"handoff.trace")
      unless trace.startsWith before do throw (IO.userError "profile trace lost its prefix")
      IO.FS.writeFile (root/(name++"-trace.txt")) (trace.drop before.length).toString
      let value ← IO.ofExcept (Json.parse stdout)
      let body := ((value.getObjValD "hookSpecificOutput").getObjValAs? String "additionalContext").toOption.getD ""
      let head := body.contains "\"observed-head-case-79-7b319c\""
      let tail := body.contains "\"observed-tail-case-79-d82a04\""
      rows := rows.push (Json.mkObj [("name",toJson name),("exitCode",toJson code.toNat),
        ("hookProcessMs",toJson elapsed),("head",toJson head),("tail",toJson tail),("bodyBytes",toJson body.utf8ByteSize)])
      IO.FS.writeFile (root/"rows.json") (toJson rows).compress
      unless toJson (← heads source) == expected do throw (IO.userError "profile changed original heads")
      unless code == 0 && head && tail do throw (IO.userError "profile did not deliver the frozen original fields")
  finally
    for command in [#["codex-daemon","shutdown"],#["publication-control","shutdown"]] do
      let stopped ← IO.Process.output {cmd := runtime,args := command,env := env}
      unless stopped.exitCode == 0 do throw (IO.userError "profile service did not exit normally")
  let mut stages := #[]
  for receipt in ← (root/"private/receipts").readDir do
    if !(← receipt.path.isDir) then continue
    let mut records := #[]
    for entry in ← receipt.path.readDir do
      if !entry.fileName.endsWith ".json" then continue
      if entry.fileName.endsWith "-profile.json" ||
          ["numerical-","discovery-counters-","operation-","search-phase-"].any (fun stem => entry.fileName.startsWith stem) ||
          ["search.json","transport.json","failure.json","prepared-inputs-turn.json","canonical-source-reuse.json"].contains entry.fileName then
        records := records.push (entry.fileName,← read entry.path)
    if !records.isEmpty then stages := stages.push (receipt.fileName,records)
  IO.FS.writeFile (root/"stages.json") (toJson stages).compress
  IO.FS.writeFile (root/"report.json") (Json.mkObj [("allOriginalHeadsUnchanged",toJson true),
    ("rows",toJson rows),("lexicalOnly",toJson lexical),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false),
    ("scope",toJson "Two sequential actual hooks with existing tracing enabled, not a speedup comparison or p99.")]).compress
  IO.println (toJson rows).compress
