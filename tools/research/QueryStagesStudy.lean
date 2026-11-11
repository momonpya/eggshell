import tools.research.StudyLocal
open Lean StudyLocal
namespace QueryStagesStudy
def parent := base/"canonical-decoder-runtime"
def root := base/"query-stage-isolation"
def records := project/"docs/candidates/query-stage-isolation"

def prepareDiscovery : IO Unit := do
  idle
  discard <| finished "query-stage-isolation"
  let area := root/"discovery"
  check (!(← area.pathExists)) "preserve direct discovery trace"
  IO.FS.createDirAll area
  let previous ← read (root/"input.json")
  let output := area/"run"
  let config := output/"config.toml"
  let environment : Array (String × Option String) ← IO.ofExcept (fromJson? (previous.getObjValD "environment"))
  let environment := environment.map fun (key,value) =>
    (key,if key == "EGGSHELL_HANDOFF_TRACE" then some (area/"discovery.log").toString
      else if key == "EGGSHELL_CONFIG" then some config.toString else value)
  let input := previous.setObjVal! "output" (toJson output.toString)
    |>.setObjVal! "config" (toJson config.toString)
    |>.setObjVal! "environment" (toJson environment)
  let runtime ← IO.ofExcept (input.getObjValAs? String "runtime")
  write (area/"input.json") input
  write (records/"direct-trace-plan.json") (Json.mkObj [("sameRuntimeSha256",input.getObjValD "runtimeSha256"),
    ("reason",toJson "Single-source indexedDiscovery does not forward onStage. Use its existing direct trace, separating serial primes from unassigned concurrent lines."),
    ("productsChanged",toJson false),("newNativeBuilds",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat))])
  let unsets := environment.foldl (fun args (key,value) => if value.isNone then args++#["-u",key] else args) (#[] : Array String)
  let assignments := environment.filterMap fun (key,value) => value.map (key++"="++·)
  guard "query-stage-direct-trace" (#["/usr/bin/env"]++unsets++assignments++
    #[runtime,"owned-selection-capacity",(area/"input.json").toString])

def prepare : IO Unit := do
  idle
  check (!(← root.pathExists)) "fresh diagnostic directory required"
  IO.FS.createDirAll root
  IO.FS.createDirAll records
  let previous ← read (parent/"preflight-input.json")
  let output := root/"run"
  let config := output/"config.toml"
  let environment : Array (String × Option String) ← IO.ofExcept (fromJson? (previous.getObjValD "environment"))
  let environment := environment.map fun (key,value) =>
    (key,if key == "EGGSHELL_TRACE_QUERY_STAGES" || key == "EGGSHELL_TRACE_SERVICE_PROFILE" then some "1"
      else if key == "EGGSHELL_CONFIG" then some config.toString else value)
  let input := previous.setObjVal! "output" (toJson output.toString)
    |>.setObjVal! "config" (toJson config.toString)
    |>.setObjVal! "environment" (toJson environment)
  let runtime ← IO.ofExcept (input.getObjValAs? String "runtime")
  check (input.getObjValD "runtimeSha256" == toJson (← hash (.mk runtime))) "native parent changed"
  write (root/"input.json") input
  write (records/"plan.json") (Json.mkObj [("runtimeSha256",input.getObjValD "runtimeSha256"),
    ("counts",input.getObjValD "counts"),("newNativeBuilds",toJson (0 : Nat)),
    ("productsChanged",toJson false),("timingObservationOnly",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  let unsets := environment.foldl (fun args (key,value) => if value.isNone then args++#["-u",key] else args) (#[] : Array String)
  let assignments := environment.filterMap fun (key,value) => value.map (key++"="++·)
  guard "query-stage-isolation" (#["/usr/bin/env"]++unsets++assignments++
    #[runtime,"owned-selection-capacity",(root/"input.json").toString])

def collect (direct : Bool := false) : IO Unit := do
  idle
  let area := if direct then root/"discovery" else root
  let monitor ← finished (if direct then "query-stage-direct-trace" else "query-stage-isolation")
  let input ← read (area/"input.json")
  let report ← read (area/"run/report.json")
  let primes ← IO.ofExcept ((← read (area/"run/prime.json")).getArr?)
  let phases ← IO.ofExcept (report.getObjValAs? (Array Json) "phases")
  let wave ← IO.ofExcept (phases[0]!.getObjValAs? (Array Json) "rows")
  let mut verified := #[]
  for (rows,label) in [(primes,"prime"),(wave,"phase-4")] do
    for row in rows do
      check (row.getObjValD "success" == toJson true) "hook was not successful"
      let client ← IO.ofExcept (row.getObjValAs? Nat "client")
      let topic ← IO.ofExcept (row.getObjValAs? Nat "topic")
      let receipt ← IO.ofExcept (row.getObjValAs? String "receipt")
      let raw := area/"run"/label/s!"client-{client}"/"stdout"
      let text ← IO.FS.readFile raw
      let directory := parent/"data/receipts"/receipt
      let publication := (← read (directory/"published.json")).getObjValD "data"
      check (publication.getObjValD "output" == toJson text &&
        publication.getObjValD "sha256" == toJson (← hash raw) &&
        publication.getObjValD "replyComplete" == toJson true) "publication bytes differ"
      let decoded ← IO.ofExcept (Json.parse text)
      let body ← IO.ofExcept ((decoded.getObjValD "hookSpecificOutput").getObjValAs? String "additionalContext")
      check (body == (← IO.FS.readFile (base/"snapshot-scheduling/diagnostic"/s!"topic-{topic}"/"body.txt")))
        "canonical body changed"
      let search := (← read (directory/"search.json")).getObjValD "data"
      let trace := search.getObjValD "trace"
      check (trace.getObjValD "route" == toJson "configured" &&
        trace.getObjValD "semantic" == toJson "completed") "semantic search failed"
      let synapse := (← read (directory/"synaptic-delivery.json")).getObjValD "data"
      check (synapse.getObjValD "complete" == toJson true &&
        synapse.getObjValD "packetVerified" == toJson true) "synaptic packet failed"
      let ack := (← read (directory/"ack.json")).getObjValD "data"
      check (ack.getObjValD "offerAccepted" == toJson true &&
        ack.getObjValD "rpcCompleted" == toJson true) "ACK failed"
      let pages := (← read (directory/"request-pages.json")).getObjValD "data"
      let stages : Array (String × Nat) ← IO.ofExcept (fromJson? (pages.getObjValD "queryStages"))
      check (stages.size > 20) "existing stage observer did not record the query"
      let mut spans := #[]
      for i in [1:stages.size] do
        let previous := stages[i-1]!
        let next := stages[i]!
        check (previous.2 ≤ next.2) "nonmonotone native stage times"
        spans := spans.push (Json.mkObj [("from",toJson previous.1),("to",toJson next.1),
          ("elapsedMs",toJson (next.2-previous.2))])
      verified := verified.push (row.setObjVal! "phase" (toJson label)
        |>.setObjVal! "stdoutSha256" (publication.getObjValD "sha256")
        |>.setObjVal! "queryStages" (toJson stages)
        |>.setObjVal! "stageSpans" (toJson spans)
        |>.setObjVal! "search" search)
  let files : Array (String × String) ← IO.ofExcept (fromJson? (input.getObjValD "sourceFiles"))
  let db ← IO.ofExcept (input.getObjValAs? String "project")
  for (relative,expected) in files do check ((← hash (.mk db/relative)) == expected) "original source changed"
  let publisher ← read (area/"run/publisher-shutdown.json")
  let frontend ← read (area/"run/frontend-shutdown.json")
  for service in [publisher,frontend] do
    check (service.getObjValD "processExited" == toJson true && service.getObjValD "daemonExitCode" == toJson (0 : Nat))
      "service did not stop normally"
  write (records/(if direct then "direct-result.json" else "result.json")) (Json.mkObj [("guard",monitor),("report",report),("rows",toJson verified),
    ("publisherShutdown",publisher),("frontendShutdown",frontend),
    ("allSevenBodiesAndAcksEqual",toJson (verified.size == 7)),("originalSourceFiles",toJson files),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
  IO.println "Collected unchanged native stages, 7 bodies and ACKs."

def close : IO Unit := do
  idle
  let direct ← finished "query-stage-direct-trace"
  let first ← finished "query-stage-isolation"
  for name in ["result.json","direct-result.json"] do
    check ((← read (records/name)).getObjValD "allSevenBodiesAndAcksEqual" == toJson true) "retain collected evidence first"
  let lines := (← IO.FS.readFile (root/"discovery/discovery.log")).splitOn "\n"
  let mut groups : Array (Array (Nat × String)) := #[]
  for line in lines do
    if line.isEmpty then continue
    let [number,label] := line.splitOn "ms " | throw (IO.userError "unexpected direct trace line")
    let some ms := number.toNat? | throw (IO.userError "invalid trace clock")
    if label == "start" then
      if groups.size == 3 then break
      groups := groups.push #[]
    check (!groups.isEmpty) "direct trace must begin at discovery start"
    let index := groups.size-1
    let prior := groups[index]!
    check (prior.isEmpty || prior.back!.1 ≤ ms) "serial discovery clock changed order"
    groups := groups.set! index (prior.push (ms,label))
  check (groups.size == 3 && groups.all fun group => group.back!.2 == "original release:end")
    "cannot assign three completed sequential traces"
  write (records/"serial-discovery.json") (toJson (groups.mapIdx fun index rows =>
    let spans := (rows.zip (rows.extract 1 rows.size)).map fun ((before,earlier),(after,later)) =>
      Json.mkObj [("from",toJson earlier),("to",toJson later),("elapsedMs",toJson (after-before))]
    Json.mkObj [("topic",toJson (index+1)),("times",toJson rows),("spans",toJson spans)]))
  write (records/"resources.json") (toJson #[first,direct])
  let prior ← read (base/"citation-gate-parent-retirement-input.json")
  let config := prior.setObjVal! "closedDirectories" (toJson #[root.toString,
      (parent/"data/sessions").toString,(parent/"data/receipts").toString,(parent/"data/confirmed-delivery").toString])
    |>.setObjVal! "plan" (toJson (base/"query-stage-retirement-plan.json").toString)
    |>.setObjVal! "receipt" (toJson (records/"retirement.json").toString)
  write (base/"query-stage-retirement-input.json") config

def main (args : List String) : IO Unit := match args with
  | ["prepare"] => prepare
  | ["collect"] => collect
  | ["prepare-discovery"] => prepareDiscovery
  | ["collect-discovery"] => collect true
  | ["close"] => close
  | _ => throw (IO.userError "prepare|collect required")
end QueryStagesStudy
def main := QueryStagesStudy.main
