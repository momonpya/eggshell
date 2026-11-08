import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
namespace SearchCpuThin
abbrev Child := IO.Process.Child {stdin := .null,stdout := .inherit,stderr := .inherit}
def check (yes : Bool) (message : String) : IO Unit := unless yes do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= (IO.ofExcept ∘ Json.parse)
def write (path : System.FilePath) (value : Json) : IO Unit := IO.FS.writeFile path value.compress
def field (value : Json) (name : String) : IO String := IO.ofExcept (value.getObjValAs? String name)
def hash (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  check (result.exitCode == 0) "cannot hash diagnostic input"
  return (result.stdout.splitOn " ").headD ""
def digest (text : String) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256"]} (some text)
  check (result.exitCode == 0) "cannot bind diagnostic request"
  return (result.stdout.splitOn " ").headD ""
def rssSample (pid : Nat) : IO Json := do
  let began ← IO.monoMsNow
  let result ← IO.Process.output {cmd := "/bin/ps",args := #["-p",toString pid,"-o","rss="]}
  let finished ← IO.monoMsNow
  return Json.mkObj [("beganMs",toJson began),("finishedMs",toJson finished),("pid",toJson pid),
    ("rssKiB",toJson (if result.exitCode == 0 then result.stdout.trimAscii.toString.toNat? else none)),
    ("exitCode",toJson result.exitCode.toNat)]
structure Context where
  input : Json
  runtime : String
  root : System.FilePath
  environment : Array (String × Option String)
def runCommand (context : Context) (args : Array String) (stdin : String := "") : IO IO.Process.Output :=
  IO.Process.output {
    cmd := context.runtime
    args
    env := context.environment
    cwd := some (.mk ((context.input.getObjValAs? String "workspace").toOption.getD "/")) } (some stdin)
def spawn (context : Context) (args : Array String) : IO Child := IO.Process.spawn {
  cmd := context.runtime
  args
  env := context.environment
  stdin := .null
  stdout := .inherit
  stderr := .inherit
  setsid := true }
def ready (child : Child) (path : System.FilePath) : IO Json := do
  let deadline := (← IO.monoMsNow)+15000
  repeat
    check ((← child.tryWait).isNone) "diagnostic service exited before readiness"
    if ← path.pathExists then
      let endpoint ← read path
      check (endpoint.getObjValD "pid" == toJson child.pid.toNat) "diagnostic endpoint belongs to another process"
      return endpoint
    check ((← IO.monoMsNow) < deadline) "diagnostic service did not become ready"
    IO.sleep 5
  throw (IO.userError "unreachable readiness")
def stop (context : Context) (child : Child) (args : Array String) (path : System.FilePath) : IO Unit := do
  let result ← runCommand context args
  let deadline := (← IO.monoMsNow)+15000
  let mut exit : Option UInt32 := none
  while exit.isNone && (← IO.monoMsNow) < deadline do
    exit ← child.tryWait
    if exit.isNone then IO.sleep 5
  if exit.isNone then
    child.kill
    exit := some (← child.wait)
  write path (Json.mkObj [("pid",toJson child.pid.toNat),("commandExitCode",toJson result.exitCode.toNat),
    ("exitCode",toJson (exit.map UInt32.toNat)),("processExited",toJson true)])
  check (result.exitCode == 0 && exit == some 0) "diagnostic service required forced shutdown"
def hook (context : Context) (session event prompt label : String) (expected : Option Json := none) : IO Json := do
  let receipt ← digest (context.root.toString++":"++label)
  let tracePath := (context.input.getObjValAs? String "traceFile").toOption.map System.FilePath.mk
  let traceOffset := do
    match tracePath with
    | some path => if ← path.pathExists then return (← path.metadata).byteSize.toNat else return 0
    | none => return 0
  let traceFirst ← traceOffset
  let began ← IO.monoMsNow
  let deadline := began+30000
  let payload := Json.mkObj [("session_id",toJson session),("turn_id",toJson "first"),
    ("cwd",context.input.getObjValD "workspace"),("_eggshell_config",context.input.getObjValD "config"),
    ("hook_event_name",toJson event),("prompt",toJson prompt)]
  let result ← runCommand context #["codex-hook-child",toString deadline,receipt] payload.compress
  check (result.exitCode == 0) ("diagnostic hook failed: "++result.stderr)
  let reply ← IO.ofExcept (Json.parse result.stdout)
  let text ← field reply "output"
  let output := text.trimAscii.toString++"\n"
  IO.FS.writeFile (context.root/(label++".stdout")) output
  let body ← match expected with
    | none => pure ""
    | some topic => do
      let parsed ← IO.ofExcept (Json.parse output)
      let body ← field (parsed.getObjValD "hookSpecificOutput") "additionalContext"
      let original ← IO.FS.readFile (.mk (← field topic "body"))
      check (body == original) "sampled hook changed its frozen original body"
      pure body
  let publication := Json.mkObj [("output",toJson output),("bytes",toJson output.utf8ByteSize),
    ("sha256",toJson (← digest output)),("replyComplete",toJson true),
    ("startedMs",toJson began),("flushedMs",toJson (← IO.monoMsNow)),("deadlineMs",toJson deadline)]
  let ack ← runCommand context #["codex-rpc","receipt"] (Json.mkObj [("receipt",toJson receipt),
    ("publication",publication),("ack",reply.getObjValD "ack"),
    ("_eggshell_rpc_deadline",toJson deadline)]).compress
  check (ack.exitCode == 0) "sampled stdout receipt was not acknowledged"
  if expected.isSome then
    let data : System.FilePath := .mk (← field context.input "data")
    let acknowledgement := (← read (data/"receipts"/receipt/"ack.json")).getObjValD "data"
    check (acknowledgement.getObjValD "rpcCompleted" == toJson true &&
      acknowledgement.getObjValD "offerAccepted" == toJson true) "sampled original handoff ACK was rejected"
  let value := Json.mkObj [("session",toJson session),("receipt",toJson receipt),("event",toJson event),
    ("startedMs",toJson began),("finishedMs",toJson (← IO.monoMsNow)),
    ("elapsedMs",toJson ((← IO.monoMsNow)-began)),("bodyBytes",toJson body.utf8ByteSize),
    ("frozenBodyByteEqual",toJson expected.isSome),("ackCommandExitCode",toJson ack.exitCode.toNat),
    ("traceFirstByte",toJson traceFirst),("traceLastByte",toJson (← traceOffset))]
  write (context.root/(label++".json")) value
  return value
def run (inputPath : System.FilePath) : IO Unit := do
  let input ← read inputPath
  let runtime ← field input "runtime"
  check (input.getObjValD "runtimeSha256" == toJson (← hash (.mk runtime))) "sampled runtime differs from the frozen input"
  let root : System.FilePath := .mk (← field input "output")
  check (!(← root.pathExists)) "preserve the previous CPU observation"
  let environment ← IO.ofExcept (input.getObjValAs? (Array (String × Option String)) "environment")
  let context : Context := ⟨input,runtime,root,environment⟩
  let data : System.FilePath := .mk (← field input "data")
  check (!(← (data/"publisher/endpoint.json").pathExists) && !(← (data/"daemon.json").pathExists))
    "a service already owns the diagnostic scope"
  IO.FS.createDirAll root
  IO.FS.writeFile (.mk (← field input "config")) ("default = \"work\"\nsemantic_matcher = "++
    (toJson #[runtime,"search-provider"]).compress++"\n[eggs]\nwork = "++
    (input.getObjValD "project").compress++"\n[profiles.work]\nread = [\"work\"]\nhandoff_chars = 500000\n")
  let topics ← IO.ofExcept (input.getObjValAs? (Array Json) "topics")
  check (topics.size == 3 && input.getObjValD "counts" == toJson (#[(4 : Nat)])) "fixed three-topic diagnostic required"
  for topic in topics do
    let path ← field topic "body"
    check (topic.getObjValD "sha256" == toJson (← hash (.mk path))) "frozen body changed"
  let publisher ← spawn context #["codex-publication-daemon"]
  let rssOnly := input.getObjValD "rssOnly" == toJson true
  let traceOnly := input.getObjValD "traceOnly" == toJson true
  let samplingStopped ← IO.mkRef false
  let rssRows ← IO.mkRef (#[] : Array Json)
  let rssTask ← if rssOnly then do
      let task ← IO.asTask (do
        while !(← samplingStopped.get) do
          let rows ← rssRows.get
          check (rows.size < 4096) "bounded RSS observation exceeded its sample count"
          let row ← rssSample publisher.pid.toNat
          rssRows.modify (·.push row)
          IO.sleep 50) .dedicated
      pure (some task)
    else pure none
  try
    let endpoint ← ready publisher (data/"publisher/endpoint.json")
    let warm ← runCommand context #["egg","warm","work"]
    IO.FS.writeFile (root/"warm.stdout") warm.stdout
    check (warm.exitCode == 0) "sampled project warm failed"
    let frontend ← spawn context #["codex-daemon","search-cpu-host"]
    try
      discard <| ready frontend (data/"daemon.json")
      for index in [:topics.size] do
        let session := "cpu-prime-"++(← digest (root.toString++toString index))
        discard <| hook context session "SessionStart" "" s!"prime-{index}-start"
        let topic := topics[index]!
        discard <| hook context session "UserPromptSubmit" (← field topic "prompt") s!"prime-{index}" (some topic)
      let mut sessions := #[]
      for index in [:4] do
        let session := "cpu-query-"++(← digest (root.toString++toString index))
        discard <| hook context session "SessionStart" "" s!"query-{index}-start"
        sessions := sessions.push session
      let observer ← IO.asTask (do
        if rssOnly || traceOnly then return
        IO.sleep 500
        for round in [:3] do
          let result ← IO.Process.output {
            cmd := "/usr/bin/sample"
            args := #[toString publisher.pid.toNat,"1","10","-mayDie","-file",(root/s!"cpu-{round}.txt").toString] }
          write (root/s!"cpu-{round}.json") (Json.mkObj [("exitCode",toJson result.exitCode.toNat),
            ("stdout",toJson result.stdout),("stderr",toJson result.stderr),
            ("publisherPid",endpoint.getObjValD "pid")])) .dedicated
      let tasks ← (Array.range 4).mapM fun index => IO.asTask (do
        let topic := topics[index%3]!
        hook context sessions[index]! "UserPromptSubmit" (← field topic "prompt") s!"query-{index}" (some topic)) .dedicated
      let results ← tasks.mapM fun task => do IO.ofExcept (← IO.wait task)
      IO.ofExcept (← IO.wait observer)
      let expected ← IO.ofExcept (input.getObjValAs? (Array (String × String)) "sourceFiles")
      let project : System.FilePath := .mk (← field input "project")
      for (name,sha) in expected do check ((← hash (project/name)) == sha) "CPU observation changed original bytes"
      write (root/"report.json") (Json.mkObj [("runtimeSha256",input.getObjValD "runtimeSha256"),
        ("queries",toJson results),("allFourFrozenBodiesByteEqual",toJson true),("originalSourceFilesUnchanged",toJson true),
        ("usesActualUnmodifiedProduct",toJson true),("cliDiagnosticNotNativeCapacityHarness",toJson true),
        ("rssOnly",toJson rssOnly),("traceOnly",toJson traceOnly),
        ("stageTracingPerturbsTiming",toJson traceOnly),("cpuSamplingPerturbsTiming",toJson (!rssOnly && !traceOnly)),
        ("rssSamplingPerturbsTiming",toJson rssOnly),("performanceImprovementEstablished",toJson false),
        ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
    finally stop context frontend #["codex-daemon","shutdown"] (root/"frontend-shutdown.json")
  finally
    samplingStopped.set true
    if let some task := rssTask then
      let result ← IO.wait task
      write (root/"rss-timeline.json") (Json.mkObj [("samples",toJson (← rssRows.get)),
        ("publisherPid",toJson publisher.pid.toNat),
        ("samplingError",toJson (match result with | .ok _ => none | .error error => some error.toString)),
        ("sampledRssNotLiveHeap",toJson true)])
    stop context publisher #["publication-control","shutdown"] (root/"publisher-shutdown.json")
end SearchCpuThin
def main (args : List String) : IO Unit := do
  let [input] := args | throw (IO.userError "CPU observation INPUT")
  SearchCpuThin.run (.mk input)
