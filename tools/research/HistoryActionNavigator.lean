import tools.research.HistoryDecision
import Eggshell.ProcessGroup
import Eggshell.FileSystem
import Lean.Data.Json.Parser
open Lean Eggshell HistoryAccess HistoryWorkspace HistoryDecision
namespace HistoryActionNavigator
structure Artifact where
  path : String
  sha256 : String
  deriving FromJson,ToJson
structure Question where
  name : String
  text : String
  expectedText : Option String := none
  deriving FromJson,ToJson,Inhabited
structure Plan where
  executable : Artifact
  model : Artifact
  runtimeFiles : Array Artifact
  dataset : Artifact
  questions : Array Question
  output : String
  deriving FromJson,ToJson
def check (value : Bool) (message : String) : IO Unit := unless value do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= (IO.ofExcept ∘ Json.parse)
def write (path : System.FilePath) (value : Json) : IO Unit := IO.FS.writeFile path value.compress
def verify (artifact : Artifact) : IO Unit := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",artifact.path]}
  check (result.exitCode == 0 && (result.stdout.splitOn " ").headD "" == artifact.sha256) "fixed native asset differs"
def drain (handle : IO.FS.Handle) : IO String := do
  let mut bytes := ByteArray.empty
  repeat
    let next ← handle.read 4096
    if next.isEmpty then break
    check (bytes.size+next.size ≤ 16*1024*1024) "native model log exceeds its bound"
    bytes := bytes++next
  let some text := String.fromUTF8? bytes | throw (IO.userError "native model log is not UTF-8")
  return text
def post (socket directory : System.FilePath) (name route : String) (request : Json) (deadline : Nat) : IO Json := do
  let now ← IO.monoMsNow
  check (now < deadline) "history decision deadline exceeded"
  let path := directory/(name++".json")
  write path request
  let result ← IO.Process.output {cmd := "/usr/bin/curl",args := #["--silent","--show-error","--fail-with-body",
    "--max-time",toString ((deadline-now+999)/1000),"--max-filesize","1048576","--unix-socket",socket.toString,
    "http://localhost"++route,"--header","Content-Type: application/json","--data-binary","@"++path.toString]}
  IO.FS.writeFile (directory/(name++".stdout")) result.stdout
  IO.FS.writeFile (directory/(name++".stderr")) result.stderr
  check (result.exitCode == 0) ("native history API request failed: "++result.stdout++result.stderr)
  IO.ofExcept (Json.parse result.stdout)

def query (store : Store) (socket output : System.FilePath) (question : Question) : IO Json := do
  IO.FS.createDir output
  let started ← IO.monoMsNow
  let deadline := started+25000
  let mut state ← IO.ofExcept (HistoryWorkspace.empty store)
  let mut usage : Array Json := #[]
  let mut counts : Array Json := #[]
  let mut events : Array Json := #[]
  let mut latest := toJson (#[] : Array Json)
  let checkpoint ← IO.mkRef (state,usage,counts,events)
  let mut finished := false
  let mut failure := Json.null
  try
    for step in [:8] do
      let request := HistoryDecision.request store state question.text (8-step) latest
      let counted ← post socket output s!"count-{step}" "/v1/chat/completions/input_tokens" request deadline
      let tokens ← IO.ofExcept (counted.getObjValAs? Nat "input_tokens")
      counts := counts.push (Json.mkObj [("step",toJson step),("inputTokens",toJson tokens),
        ("openedPages",toJson state.pages.size),("fullReadCharacters",toJson state.session.readCharacters)])
      checkpoint.set (state,usage,counts,events)
      check (tokens > 0 && HistoryDecision.contextFits tokens) "complete read workspace exceeds model context; no text was dropped"
      let response ← post socket output s!"request-{step}" "/v1/chat/completions" request deadline
      let cost := response.getObjValD "usage"
      usage := usage.push cost
      checkpoint.set (state,usage,counts,events)
      let prompt ← IO.ofExcept (cost.getObjValAs? Nat "prompt_tokens")
      let completion ← IO.ofExcept (cost.getObjValAs? Nat "completion_tokens")
      let total ← IO.ofExcept (cost.getObjValAs? Nat "total_tokens")
      check (prompt == tokens && total == prompt+completion && completion ≤ 384)
        "model usage differs from its complete counted request or output bound"
      let choices ← IO.ofExcept (response.getObjValAs? (Array Json) "choices")
      check (choices.size == 1) "one structured history decision required"
      check (choices[0]!.getObjValD "finish_reason" == toJson "stop") "structured history action did not finish"
      let assistant := choices[0]!.getObjValD "message"
      let content ← IO.ofExcept (assistant.getObjValAs? String "content")
      let decision := Json.parse content
      match decision >>= HistoryDecision.run store state (8-step) with
      | .ok (next,results,done) =>
        state := next
        latest := results
        finished := done
        let values ← IO.ofExcept (results.getArr?)
        for value in values do
          events := events.push (Json.mkObj [("step",toJson step),("name",value.getObjValD "action"),
            ("arguments",value.getObjValD "arguments"),("reply",value.getObjValD "reply")])
      | .error error =>
        latest := Json.mkObj [("error",toJson error)]
        events := events.push (Json.mkObj [("step",toJson step),("name",toJson "invalid-decision"),
          ("error",toJson error),("content",toJson content)])
      checkpoint.set (state,usage,counts,events)
      if finished then break
    check finished "history decision exhausted its fixed eight decisions"
  catch error => failure := toJson error.toString
  let (observed,recordedUsage,recordedCounts,recordedEvents) ← checkpoint.get
  let result := Json.mkObj [("name",toJson question.name),("elapsedMs",toJson ((← IO.monoMsNow)-started)),
    ("finished",toJson finished),("error",failure),("usage",toJson recordedUsage),("counts",toJson recordedCounts),
    ("events",toJson recordedEvents),("payload",HistoryAccess.payload store observed.session),
    ("actualHookDelivery",toJson false),("adopted",toJson false)]
  write (output/"result.json") result
  return result

def run (path : System.FilePath) : IO Unit := do
  let plan : Plan ← IO.ofExcept (fromJson? (← read path))
  let output := System.FilePath.mk plan.output
  check (output.isAbsolute && !(← output.pathExists)) "fresh isolated decision output required"
  check (!plan.questions.isEmpty && plan.questions.size ≤ 3) "three or fewer frozen questions required"
  for artifact in #[plan.executable,plan.model,plan.dataset]++plan.runtimeFiles do verify artifact
  let dataset ← read (.mk plan.dataset.path)
  let documents ← IO.ofExcept (dataset.getObjValAs? (Array Document) "documents")
  let mut neighbors : Std.HashMap Nat (Array Json) := {}
  for row in (dataset.getObjValAs? (Array Json) "neighbors").toOption.getD #[] do
    neighbors := neighbors.insert (← IO.ofExcept (row.getObjValAs? Nat "document"))
      (← IO.ofExcept (row.getObjValAs? (Array Json) "edges"))
  let prepared ← IO.monoMsNow
  let store := prepare ((dataset.getObjValD "head").compress) documents neighbors
  check (store.originals.size == documents.size) "immutable history preparation failed"
  let preparationMs := (← IO.monoMsNow)-prepared
  IO.FS.createDir output
  let ipc := System.FilePath.mk s!"/tmp/egg-actions-{← IO.Process.getPID}-{← IO.monoNanosNow}"
  IO.FS.createDir ipc
  FileSystem.privateDirectory ipc
  let socket := ipc/"server.sock"
  let args := #["--model",plan.model.path,"--host",socket.toString,"--jinja","--ctx-size","8192",
    "--parallel","1","--threads","2","--threads-batch","2","--batch-size","512",
    "--ubatch-size","512","--gpu-layers","99"]
  write (output/"invocation.json") (Json.mkObj [("plan",toJson plan),("arguments",toJson args)])
  let started ← IO.monoMsNow
  let child ← IO.Process.spawn {
    cmd := plan.executable.path
    args := args
    cwd := some output
    stdin := .null
    stdout := .piped
    stderr := .piped
    setsid := true }
  let out ← IO.asTask (drain child.stdout) .dedicated
  let err ← IO.asTask (drain child.stderr) .dedicated
  let exited ← IO.mkRef (none : Option UInt32)
  try
    let mut ready := false
    for _ in [:300] do
      if let some code ← child.tryWait then
        exited.set (some code)
        throw (IO.userError "native history model exited before readiness")
      check ((← IO.monoMsNow) < started+60000) "native history model readiness deadline exceeded"
      let health ← IO.Process.output {cmd := "/usr/bin/curl",args := #["--silent","--fail","--max-time","1",
        "--unix-socket",socket.toString,"http://localhost/health"]}
      if health.exitCode == 0 then ready := true; break
      IO.sleep 100
    check ready "native history model did not become ready"
    let startupMs := (← IO.monoMsNow)-started
    let mut results := #[]
    for index in [:plan.questions.size] do
      results := results.push (← query store socket (output/s!"question-{index}") plan.questions[index]!)
    write (output/"result.json") (Json.mkObj [("startupMs",toJson startupMs),("preparationMs",toJson preparationMs),
      ("results",toJson results),("actualHookDelivery",toJson false),("answeringModelCalls",toJson (0 : Nat)),
      ("adopted",toJson false)])
  finally
    ProcessGroup.kill child
    if (← exited.get).isNone then exited.set (some (← child.wait))
    let deadline := (← IO.monoMsNow)+10000
    while !(← IO.hasFinished out) || !(← IO.hasFinished err) do
      check ((← IO.monoMsNow) < deadline) "native model log pipes did not close"
      IO.sleep 5
    IO.FS.writeFile (output/"server.stdout") (← IO.ofExcept (out.get.mapError IO.Error.toString))
    IO.FS.writeFile (output/"server.stderr") (← IO.ofExcept (err.get.mapError IO.Error.toString))
    if ← socket.pathExists then IO.FS.removeFile socket
    IO.FS.removeDir ipc
    write (output/"shutdown.json") (Json.mkObj [("ownedPid",toJson child.pid.toNat),
      ("exitCode",toJson ((← exited.get).map UInt32.toNat)),("pipesJoined",toJson true),
      ("ipcRemoved",toJson (!(← ipc.pathExists)))])
end HistoryActionNavigator
def main : List String → IO Unit
  | [plan] => HistoryActionNavigator.run (.mk plan)
  | _ => throw (IO.userError "HistoryActionNavigator PLAN")
