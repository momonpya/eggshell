import Eggshell.ProcessGroup
import Eggshell.FileSystem
import Eggshell.Sha256
import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson

open Lean Eggshell
namespace LocalJudgmentProbe
structure Artifact where
  path : String
  sha256 : String
  deriving FromJson, ToJson
structure Request where
  name : String
  body : Json
  expectedFirst : Option Nat := none
  deriving FromJson, ToJson, Inhabited
structure Plan where
  executable : Artifact
  model : Artifact
  runtimeFiles : Array Artifact
  output : String
  requests : Array Request
  contextTokens : Nat := 2048
  requestDeadlineSeconds : Nat := 30
  deriving FromJson, ToJson
private def check (value : Bool) (message : String) : IO Unit :=
  unless value do throw (IO.userError message)
private def write (path : System.FilePath) (value : Json) : IO Unit :=
  IO.FS.writeFile path value.compress
private def verify (artifact : Artifact) : IO Unit := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",artifact.path]}
  check (result.exitCode == 0 && (result.stdout.splitOn " ").headD "" == artifact.sha256)
    "numerical engine or model differs from its pinned bytes"
private def readBounded (handle : IO.FS.Handle) : IO String := do
  let mut bytes := ByteArray.empty
  repeat
    let next ← handle.read 4096
    if next.isEmpty then break
    check (bytes.size+next.size ≤ 16*1024*1024) "numerical server log exceeds 16 MiB"
    bytes := bytes++next
  let some text := String.fromUTF8? bytes | throw (IO.userError "numerical server log is not UTF-8")
  return text
def run (path : String) : IO Unit := do
  let plan ← IO.ofExcept (fromJson? (α := Plan) (← IO.ofExcept (Json.parse (← IO.FS.readFile path))))
  let output := System.FilePath.mk plan.output
  check (output.isAbsolute && !(← output.pathExists)) "fresh absolute probe output required"
  check (!plan.requests.isEmpty && plan.requests.size ≤ 128) "bounded nonempty probe requests required"
  check (1024 ≤ plan.contextTokens && plan.contextTokens ≤ 4096) "bounded numerical context required"
  check (0 < plan.requestDeadlineSeconds && plan.requestDeadlineSeconds ≤ 120)
    "research numerical deadline must be between one and 120 seconds"
  for artifact in #[plan.executable,plan.model]++plan.runtimeFiles do verify artifact
  IO.FS.createDirAll output
  let ipc := System.FilePath.mk s!"/tmp/egg-judge-{← IO.Process.getPID}-{← IO.monoNanosNow}"
  check (!(← ipc.pathExists)) "probe IPC already exists"
  IO.FS.createDir ipc
  FileSystem.privateDirectory ipc
  let socket := ipc/"server.sock"
  let args := #["--model",plan.model.path,"--host",socket.toString,"--reranking",
    "--pooling","rank","--embd-normalize","-1","--ctx-size",toString plan.contextTokens,"--parallel","1",
    "--batch-size","512","--ubatch-size","512","--threads","2","--threads-batch","2",
    "--gpu-layers","99"]
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
  let out ← IO.asTask (readBounded child.stdout) .dedicated
  let err ← IO.asTask (readBounded child.stderr) .dedicated
  let exit ← IO.mkRef (none : Option UInt32)
  try
    let mut ready := false
    let mut healthChecks := #[]
    for number in [:300] do
      if let some code ← child.tryWait then
        exit.set (some code)
        throw (IO.userError "owned numerical server exited before readiness")
      check ((← IO.monoMsNow) < started+60000) "numerical server readiness exceeded 60 seconds"
      let response ← IO.Process.output {cmd := "/usr/bin/curl",args := #["--silent","--show-error",
        "--fail","--max-time","1","--unix-socket",socket.toString,"http://localhost/health"]}
      healthChecks := healthChecks.push (Json.mkObj [("attempt",toJson number),
        ("exitCode",toJson response.exitCode.toNat),("body",toJson response.stdout)])
      if response.exitCode == 0 then
        let health ← IO.ofExcept (Json.parse response.stdout)
        check (health.getObjValD "status" == toJson "ok") "unexpected numerical server health"
        ready := true
        break
      IO.sleep 100
    check ready "numerical server never became ready"
    let startupMs := (← IO.monoMsNow)-started
    write (output/"health.json") (toJson healthChecks)
    let mut measured := #[]
    for number in [:plan.requests.size] do
      let request := plan.requests[number]!
      let requestPath := output/s!"request-{number}.json"
      write requestPath request.body
      let requestStarted ← IO.monoMsNow
      let result ← IO.Process.output { cmd := "/usr/bin/curl", args := #["--silent","--show-error","--fail-with-body",
        "--max-time",toString plan.requestDeadlineSeconds,"--unix-socket",socket.toString,"http://localhost/reranking",
        "--max-filesize","1048576","--header","Content-Type: application/json",
        "--data-binary","@"++requestPath.toString], cwd := some output }
      let requestMs := (← IO.monoMsNow)-requestStarted
      IO.FS.writeFile (output/s!"reply-{number}.stdout") result.stdout
      IO.FS.writeFile (output/s!"reply-{number}.stderr") result.stderr
      check (result.exitCode == 0) ("native reranking request failed: "++result.stdout++result.stderr)
      let response ← IO.ofExcept (Json.parse result.stdout)
      let rows ← IO.ofExcept (response.getObjValAs? (Array Json) "results")
      let documents ← IO.ofExcept (request.body.getObjValAs? (Array Json) "documents")
      check (rows.size == documents.size) "numerical server omitted requested ranks"
      let mut indices := #[]
      let mut previous : Float := 1
      for row in rows do
        let index ← IO.ofExcept (row.getObjValAs? Nat "index")
        let score ← IO.ofExcept (row.getObjValAs? Float "relevance_score")
        check (index < documents.size && !(indices.contains index) && 0 ≤ score && score ≤ previous)
          "numerical ranks have invalid indices, nonfinite scores or inconsistent order"
        previous := score
        indices := indices.push index
      if let some expected := request.expectedFirst then
        check (indices[0]? == some expected) "synthetic relevance canary ranked the unrelated passage first"
      measured := measured.push (Json.mkObj [("name",toJson request.name),("elapsedMs",toJson requestMs),
        ("requestSha256",toJson (Sha256.hex request.body.compress.toUTF8)),("response",response)])
    write (output/"result.json") (Json.mkObj [("startupMs",toJson startupMs),("measurements",toJson measured),
    ("scope",toJson "isolated numerical probe; not an Eggshell delivery or total-token comparison"),
      ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  finally
    ProcessGroup.kill child
    if (← exit.get).isNone then exit.set (some (← child.wait))
    let deadline := (← IO.monoMsNow)+10000
    while !(← IO.hasFinished out) || !(← IO.hasFinished err) do
      check ((← IO.monoMsNow) < deadline) "numerical server pipes failed to close after group termination"
      IO.sleep 5
    let stdout ← IO.ofExcept (out.get.mapError IO.Error.toString)
    let stderr ← IO.ofExcept (err.get.mapError IO.Error.toString)
    IO.FS.writeFile (output/"server.stdout") stdout
    IO.FS.writeFile (output/"server.stderr") stderr
    if ← socket.pathExists then IO.FS.removeFile socket
    IO.FS.removeDir ipc
    write (output/"shutdown.json") (Json.mkObj [("ownedPid",toJson child.pid.toNat),
      ("exitCode",toJson ((← exit.get).map UInt32.toNat)),("pipesJoined",toJson true),
      ("ipcRemoved",toJson (!(← ipc.pathExists)))])
def prepareClaims (template originalConfig promptConfig destination : String) : IO Unit := do
  let decode (path : String) := IO.FS.readFile path >>= (IO.ofExcept ∘ Json.parse)
  let original ← IO.ofExcept (fromJson? (α := Artifact) (← decode originalConfig))
  verify original
  let exported ← decode original.path
  let documents ← IO.ofExcept (exported.getObjValAs? (Array Json) "documents")
  let mut claims := #[]
  let mut texts := #[]
  for document in documents do
    let native ← IO.ofExcept (document.getObjValAs? Bool "native")
    if native then continue
    let owner ← IO.ofExcept (document.getObjValAs? String "owner")
    let work ← IO.ofExcept (document.getObjValAs? String "work")
    let invocation ← IO.ofExcept (document.getObjValAs? String "invocation")
    let raw ← IO.ofExcept (document.getObjValAs? String "source")
    let text ← IO.ofExcept (document.getObjValAs? String "text")
    let mut start := 0
    for paragraph in text.splitOn "\n\n" do
      let stop := start+paragraph.length
      unless paragraph.trimAscii.isEmpty do
        claims := claims.push (Json.mkObj [("index",toJson texts.size),("owner",toJson owner),
          ("work",toJson work),("originalSha256",toJson (Sha256.hex raw.toUTF8)),
          ("decodedFirst",toJson start),("decodedStop",toJson stop),("paragraph",toJson paragraph)])
        texts := texts.push ("Recorded work:\n"++invocation++"\nRecorded claim:\n"++paragraph)
      start := stop+2
  check (!texts.isEmpty && texts.size ≤ 128) "bounded nonempty recorded claims required"
  let mut requests := #[]
  let mut prompts := #[]
  for item in ← IO.ofExcept ((← decode promptConfig).getArr?) do
    let artifact ← IO.ofExcept (fromJson? (α := Artifact) item)
    verify artifact
    let query ← IO.FS.readFile artifact.path
    prompts := prompts.push item
    requests := requests.push (Json.mkObj [("name",toJson s!"topic-{prompts.size}"),
      ("body",Json.mkObj [("query",toJson query),("documents",toJson texts),
        ("top_n",toJson texts.size)]),("expectedFirst",Json.null)])
  check (requests.size == 3) "freeze all three topic questions before judging"
  let output := System.FilePath.mk destination
  check (output.isAbsolute && !(← output.pathExists)) "fresh prepared claim input required"
  IO.FS.createDirAll output
  write (output/"claims.json") (Json.mkObj [("claims",toJson claims),("prompts",toJson prompts),
    ("originalExport",toJson original),("sourceHead",exported.getObjValD "head"),
    ("requiredEvidenceListRead",toJson false),("selectedBodyRead",toJson false)])
  let prepared := (← decode template).setObjVal! "requests" (toJson requests)
    |>.setObjVal! "output" (toJson (output/"run").toString)
    |>.setObjVal! "contextTokens" (toJson (4096 : Nat))
  write (output/"plan.json") prepared
end LocalJudgmentProbe
def main : List String → IO Unit
  | [path] => LocalJudgmentProbe.run path
  | ["prepare-claims",template,original,prompts,output] => LocalJudgmentProbe.prepareClaims template original prompts output
  | _ => throw (IO.userError "LocalJudgmentProbe INPUT")
