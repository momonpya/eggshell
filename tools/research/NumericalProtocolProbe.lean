import Main
import Eggshell.SearchProvider
import Eggshell.GraphStore
import Eggshell.ContractAudit
open Lean Eggshell Eggshell.Plugin.Daemon
namespace NumericalProtocolProbe
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def source := base/"real-source-search-read-trial-result/work.egg"
def fixedInput := base/"shared-model-capacity-80-input.json"
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def save (path : System.FilePath) (value : Json) : IO Unit := IO.FS.writeFile path value.pretty
def hash (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  check (result.exitCode == 0) "cannot hash fixed input"
  return (result.stdout.splitOn " ").headD ""
def questions : IO (Array String) := do
  let input ← read fixedInput
  check (input.getObjValD "project" == toJson source.toString) "numerical probe left the fixed actual DB"
  let topics ← IO.ofExcept (input.getObjValAs? (Array Json) "topics")
  check (topics.map (·.getObjValD "topic") == #[toJson (1 : Nat),toJson (2 : Nat),toJson (3 : Nat)])
    "retain all three actual questions"
  topics.mapM fun topic => IO.ofExcept (topic.getObjValAs? String "prompt")

def queryBody (question : String) : Json :=
  Json.mkObj [("texts",toJson (SearchRank.windows question))]

def encodedValue (result : Json) : Json :=
  Json.mkObj [("vectors",result.getObjValD "vectors"),("coverage",result.getObjValD "coverage")]

/-- Same authenticated framing and absolute RPC deadline as exchangeBefore.
Only timestamps and byte counts differ; no replay or alternate source exists. -/
def exchangeObserved (endpoint : Endpoint) (kind body : String) (deadline : Nat) : IO (Json × Json) := do
  let events ← IO.mkRef (#[] : Array (String × Nat))
  let mark := fun label => do
    let now ← IO.monoMsNow
    events.modify (·.push (label,now))
  mark "connect:start"
  let client ← connectBefore endpoint deadline
  mark "connect:end"
  let payload := (request endpoint.secret kind (toJson (Numerical.requestBody body))).compress.toUTF8
  mark "send:start"
  sendFrameBefore client payload deadline
  mark "send:end"
  mark "receive:start"
  let header ← receiveExactly client 4 deadline
  mark "header-ready"
  let length := decodeLength header
  check (length ≤ maxFrameBytes) "numerical response exceeds transport bound"
  let bytes ← receiveExactly client length deadline
  mark "body-ready"
  let some text := String.fromUTF8? bytes | throw (IO.userError "non-UTF8 numerical response")
  let outer ← IO.ofExcept (Json.parse text)
  check (outer.getObjValD "ok" == toJson true) ((outer.getObjValAs? String "error").toOption.getD "numerical request failed")
  let output ← IO.ofExcept (outer.getObjValAs? String "output")
  mark "outer-decoded"
  let received ← IO.monoMsNow
  let result ← IO.ofExcept (Json.parse output)
  mark "inner-decoded"
  -- Preserve Client.request's trace-enabled parse/repack and the provider's
  -- subsequent parse. Otherwise this probe would silently remove loaded work.
  let metadata := result.getObjValD "numericalTrace"
  let recorded ← events.get
  let copied := if metadata == Json.null then output else
    let metadata := metadata.setObjVal! "clientStartedAt" (toJson recorded[0]!.2)
      |>.setObjVal! "clientReceivedAt" (toJson received)
    (result.setObjVal! "numericalTrace" metadata).compress++"\n"
  mark "client-repacked"
  let result ← IO.ofExcept (Json.parse copied)
  mark "provider-decoded"
  if let .ok error := result.getObjValAs? String "error" then throw (IO.userError error)
  return (result,Json.mkObj [("kind",toJson kind),("events",toJson (← events.get)),
    ("requestBytes",toJson payload.size),("responseBytes",toJson bytes.size),
    ("outputBytes",toJson output.utf8ByteSize),("server",result.getObjValD "numericalTrace")])

def projectQuery (result : Json) : IO (Array String) := do
  let vectors ← IO.ofExcept (result.getObjValAs? (Array Json) "vectors")
  let coverage ← IO.ofExcept (result.getObjValAs? (Array SearchProvider.EncodingCoverage) "coverage")
  check (!vectors.isEmpty && vectors.size == coverage.size) "query source shape changed"
  (vectors.zip coverage).mapM fun (vector,measured) => do
    check measured.valid "query coverage invalid"
    let group ← IO.ofExcept vector.getArr?
    let packed ← IO.ofExcept (group.mapM SearchProvider.packVector)
    IO.ofExcept (WindowCentroid.project packed measured.sourceTokens (measured.contextTokens-2) measured.overlapTokens)

def inputs : IO (Array BlockScore.Input × Json) := do
  let fixed ← read fixedInput
  let expected ← IO.ofExcept (fixed.getObjValAs? (Array (String × String)) "sourceFiles")
  let some expectedHead := expected.find? (·.1 == "head") | throw (IO.userError "fixed source lacks its head digest")
  check (expectedHead.2 == (← hash (source/"head"))) "actual source no longer matches the frozen delivery DB"
  let mut rows : Array BlockScore.Input := #[]
  let mut originals := #[]
  let mut documents := 0
  for path in [source] do
    let snapshot ← DB.PageMap.pin path
    let docs ← Persistence.Store.searchDocuments snapshot
    originals := originals.push (Json.mkObj [("path",toJson path.toString),("head",toJson snapshot.head),
      ("headBytes",toJson (← IO.FS.readFile (path/"head"))),("headSha256",toJson (← hash (path/"head")))])
    documents := documents+docs.length
    for document in docs do
      let some owner := document.cache | throw (IO.userError "durable source lost its owner")
      for window in document.windows do rows := rows.push (.indexed owner window)
  check (documents == 40 && rows.size == 1933) "fixed actual scoring domain changed"
  return (rows,Json.mkObj [("sources",toJson originals),("documents",toJson documents),("rows",toJson rows.size),
    ("rowOrderSha256",toJson (Sha256.hex (toJson rows).compress.toUTF8))])

def verifyHeads (frozen : Json) : IO Unit := do
  let sources ← IO.ofExcept (frozen.getObjValAs? (Array Json) "sources")
  for source in sources do
    let path : System.FilePath := .mk (← IO.ofExcept (source.getObjValAs? String "path"))
    check (source.getObjValD "headBytes" == toJson (← IO.FS.readFile (path/"head")) &&
      source.getObjValD "headSha256" == toJson (← hash (path/"head"))) "fixed original changed"

def scorePass (endpoint : Endpoint) (queries : Array String) (rows : Array BlockScore.Input)
    (deadline : Nat) (profiles : IO.Ref (Array Json)) : IO (Array Json) := do
  let mut scores := #[]
  for offset in [0:rows.size:256] do
    let batch := rows.extract offset (min rows.size (offset+256))
    let payload := Json.mkObj [("queries",toJson queries),("blockRows",toJson batch)]
    let (result,profile) ← exchangeObserved endpoint "blocks" payload.compress (min deadline ((← IO.monoMsNow)+24000))
    let values ← IO.ofExcept (result.getObjValAs? (Array Json) "scores")
    let coverages ← IO.ofExcept (result.getObjValAs? (Array (Option String)) "coverage")
    check (values.size == batch.size && coverages.size == batch.size && coverages.all Option.isSome) "score response lost a durable row"
    scores := scores++values
    profiles.modify (·.push (profile.setObjVal! "rows" (toJson batch.size)))
  return scores

def query (config : Numerical.Config) (rows : Array BlockScore.Input) (question : String) (index topic : Nat) : IO Json := do
  let started ← IO.monoMsNow
  let deadline := started+28800
  let profiles ← IO.mkRef (#[] : Array Json)
  try
    let client ← Numerical.openClient config
    try
      let endpoint ← Numerical.resolve config
      let body := queryBody question
      let (encoded,profile) ← exchangeObserved endpoint "encode" body.compress
        (min deadline ((← IO.monoMsNow)+24000))
      profiles.modify (·.push profile)
      let projections ← projectQuery encoded
      let first ← scorePass endpoint projections rows deadline profiles
      let (encodedAgain,profile) ← exchangeObserved endpoint "encode" body.compress
        (min deadline ((← IO.monoMsNow)+24000))
      profiles.modify (·.push profile)
      check (encodedValue encoded == encodedValue encodedAgain) "second actual query encoding changed vectors or coverage"
      let second ← scorePass endpoint (← projectQuery encodedAgain) rows deadline profiles
      check (first == second && first.size == rows.size) "same exact query and rows changed scores"
      check ((← IO.monoMsNow) < deadline) "standalone query expired after decoding"
      return Json.mkObj [("case",toJson index),("topic",toJson topic),("completed",toJson true),("elapsedMs",toJson ((← IO.monoMsNow)-started)),
        ("scores",toJson first.size),("scoreSha256",toJson (Sha256.hex (toJson first).compress.toUTF8)),
        ("encodingSha256",toJson (Sha256.hex (encodedValue encoded).compress.toUTF8)),
        ("queryWindows",toJson projections.size),("encodes",toJson (2 : Nat)),
        ("identicalRepeatedScores",toJson true),("profiles",toJson (← profiles.get))]
    finally client.close
  catch error =>
    return Json.mkObj [("case",toJson index),("topic",toJson topic),("completed",toJson false),("elapsedMs",toJson ((← IO.monoMsNow)-started)),
      ("error",toJson error.toString),("profiles",toJson (← profiles.get))]

def cpu (endpoint : Endpoint) : IO Json := do
  let json ← IO.ofExcept (Json.parse (← exchange endpoint "stats"))
  let models ← IO.ofExcept (json.getObjValAs? (Array Nat) "modelPids")
  check (json.getObjValD "modelCapacity" == toJson (1 : Nat) &&
    json.getObjValD "computeCapacity" == toJson (2 : Nat) && models.size == 1) "fixed shared numerical capacity changed"
  let pids := #[some (← IO.Process.getPID).toNat,some endpoint.pid,
    (json.getObjValAs? Nat "rawPid").toOption].filterMap id ++ models
  let report ← IO.Process.output {cmd := "/bin/ps",args := #["-p",String.intercalate "," (pids.toList.map toString),
    "-o","pid=,ppid=,time=,utime=,stime=,rss="]}
  check (report.exitCode == 0) "cannot observe numerical processes"
  return Json.mkObj [("stats",json),("daemonPid",toJson endpoint.pid),
    ("clientPid",toJson (← IO.Process.getPID).toNat),("ps",toJson report.stdout),("observedAt",toJson (← IO.monoMsNow))]

def run (root : System.FilePath) (count : Nat) : IO Unit := do
  check (root.isAbsolute && !(← root.pathExists) && (count == 16 || count == 80)) "fresh numerical protocol root/count required"
  IO.FS.createDirAll root
  check ((← Paths.dataRoot) == base/"real-source-search-read-trial-result/data")
    "numerical protocol must use the actual prepared project read-cache"
  let (rows,frozen) ← inputs
  let questions ← questions
  save (root/"frozen.json") (frozen.setObjVal! "questions" (toJson questions)
    |>.setObjVal! "inputSha256" (toJson (← hash fixedInput)))
  let some config ← Numerical.defaultConfig? | throw (IO.userError "MiniLM runtime unavailable")
  let keeper ← Numerical.keep config
  let servicePid ← IO.mkRef (none : Option Nat)
  try
    let endpoint ← Numerical.resolve config
    servicePid.set (some endpoint.pid)
    let control ← Numerical.openClient config
    try
      let request := queryBody questions[0]!
      let ordinary ← IO.ofExcept (Json.parse (← control.request 69 request.compress))
      let (observed,_) ← exchangeObserved endpoint "encode" request.compress ((← IO.monoMsNow)+24000)
      check (ordinary.getObjValD "vectors" == observed.getObjValD "vectors" &&
        ordinary.getObjValD "coverage" == observed.getObjValD "coverage") "observer changed actual encoding"
      let projected ← projectQuery observed
      let batch := rows.extract 0 256
      let scoreRequest := Json.mkObj [("queries",toJson projected),("blockRows",toJson batch)]
      let ordinary ← IO.ofExcept (Json.parse (← control.request 66 scoreRequest.compress))
      let (observed,_) ← exchangeObserved endpoint "blocks" scoreRequest.compress ((← IO.monoMsNow)+24000)
      check (ordinary.getObjValD "scores" == observed.getObjValD "scores" &&
        ordinary.getObjValD "coverage" == observed.getObjValD "coverage") "observer changed actual block scores"
      let references ← questions.mapIdxM fun index question => do
        let result ← query config rows question index (index+1)
        check (result.getObjValD "completed" == toJson true) "actual numerical reference query failed"
        return result
      save (root/"references.json") (toJson references)
      let before ← cpu endpoint
      let entered ← Std.Mutex.new (0 : Nat)
      let start ← IO.Promise.new
      let tasks ← (Array.range count).mapM fun index => IO.asTask (do
        entered.atomically (modify (·+1))
        discard <| IO.wait start.result!
        let topic := index % questions.size
        let result ← query config rows questions[topic]! index (topic+1)
        let matched := result.getObjValD "completed" == toJson true &&
          result.getObjValD "encodingSha256" == references[topic]!.getObjValD "encodingSha256" &&
          result.getObjValD "scoreSha256" == references[topic]!.getObjValD "scoreSha256"
        return result.setObjVal! "referenceEqual" (toJson matched)) .dedicated
      let (results,elapsed) ← try
          let barrierDeadline := (← IO.monoMsNow)+5000
          while (← entered.atomically get) < count do
            check ((← IO.monoMsNow) < barrierDeadline) "numerical burst launch barrier expired"
            IO.sleep 1
          let began ← IO.monoMsNow
          start.resolve ()
          let results ← tasks.mapM fun task => do IO.ofExcept (← IO.wait task)
          pure (results,(← IO.monoMsNow)-began)
        finally
          start.resolve ()
          for task in tasks do IO.cancel task
          for task in tasks do discard <| IO.wait task
      save (root/"results.json") (toJson results)
      let after ← cpu endpoint
      verifyHeads frozen
      save (root/"report.json") (Json.mkObj [("clients",toJson count),("wallMs",toJson elapsed),
        ("rows",toJson rows.size),("twoExactPassesPerQuery",toJson true),("results",toJson results),
        ("twoActualEncodesPerQuery",toJson true),("allQueriesReferenceEqual",toJson (results.all (fun result => result.getObjValD "referenceEqual" == toJson true))),
        ("before",before),("after",after),("originalHeadsUnchanged",toJson true),
        ("ordinaryAndObservedControlEqual",toJson true),("noWorkGraphComputation",toJson true),
        ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
    finally control.close
  finally Numerical.release keeper 10000
  let some pid ← servicePid.get | throw (IO.userError "numerical service never became ready")
  check (!(← Numerical.alive pid) && (← Numerical.endpoint? config).isNone) "standalone numerical service survived its last keeper"
  save (root/"shutdown.json") (Json.mkObj [("releasedLastKeeper",toJson true),("daemonPid",toJson pid),
    ("processExited",toJson true),("endpointRemoved",toJson true)])
end NumericalProtocolProbe
def main (args : List String) : IO UInt32 := do
  match args with
  | ["codex-numerical-daemon",model,models,python] => Numerical.serve ⟨model,.mk models,.mk python⟩
  | [root,count] =>
    let some count := count.toNat? | throw (IO.userError "count required")
    NumericalProtocolProbe.run (.mk root) count
    return 0
  | _ => throw (IO.userError "numerical protocol root/count required")
