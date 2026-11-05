import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
import Std.Data.HashMap
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def output := workspace/"docs/candidates/replay-mixed"
def root := base/"replay-mixed-native1-result"
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def hashText (value : String) : IO String := do
  let reply ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256"]} (some value)
  unless reply.exitCode == 0 do throw (IO.userError "cannot seal received text")
  return (reply.stdout.splitOn " ").head!
def hash (path : System.FilePath) : IO String := do
  let reply ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  unless reply.exitCode == 0 do throw (IO.userError "cannot seal file")
  return (reply.stdout.splitOn " ").head!
def distribution (values : Array Nat) : Json := Id.run do
  let sorted := values.qsort (· < ·)
  return Json.mkObj [("samples",toJson sorted.size),("minimum",toJson sorted[0]?),
    ("median",toJson sorted[sorted.size/2]?),("maximum",toJson sorted.back?)]
def analyse : IO Unit := do
  unless !(← (output/"analysis.json").pathExists) do throw (IO.userError "preserve completed analysis")
  let evidence ← read (output/"evidence.json")
  let stages ← IO.ofExcept (evidence.getObjValAs? (Array (String × Array (String × Json))) "stages")
  let mut services := #[]
  let mut phases : Std.HashMap String Nat := {}
  let mut numerical := #[]
  let mut lexical := 0
  for (_,events) in stages do
    for (name,value) in events do
      let data := value.getObjValD "data"
      if name == "operation-service.json" then services := services.push data
      if name.startsWith "search-phase-" then
        let status := (data.getObjValAs? String "status").toOption.getD "missing"
        let key := name++":"++status
        phases := phases.insert key (phases[key]?.getD 0+1)
      if name == "search-phase-lexical.json" && data.getObjValD "status" == toJson "finished" then lexical := lexical+1
      if name.startsWith "numerical-" then numerical := numerical.push data
  let values := fun key => services.filterMap fun row => (row.getObjValAs? Nat key).toOption
  let mut lanes := #[]
  for lane in [:3] do
    let rows := services.filter (fun row => row.getObjValD "lane" == toJson lane) |>.qsort fun a b =>
      (a.getObjValAs? Nat "startedAt").toOption.getD 0 < (b.getObjValAs? Nat "startedAt").toOption.getD 0
    lanes := lanes.push (Json.mkObj [("lane",toJson lane),("count",toJson rows.size),("first",toJson rows[0]?),
      ("subsequentWorkMs",distribution (rows.extract 1 rows.size |>.filterMap fun row =>
        (row.getObjValAs? Nat "workMs").toOption))])
  let mut indexTargets := #[]
  let mut synapticTargets := #[]
  let mut owners : Array String := #[]
  for directory in ["index-targets","synaptic-targets"] do
    for entry in ← (root/"private"/directory).readDir do
      if !entry.fileName.endsWith ".json" then continue
      let target ← read entry.path
      let owner ← IO.ofExcept ((target.getObjValD "owner").getObjValAs? String "database")
      if !owners.contains owner then owners := owners.push owner
      if directory == "index-targets" then indexTargets := indexTargets.push target
      else synapticTargets := synapticTargets.push target
  owners := owners.qsort (· < ·)
  let mut pairs := #[]
  let mut byOwner := #[]
  for target in synapticTargets do
    let owner ← IO.ofExcept ((target.getObjValD "owner").getObjValAs? String "database")
    let ingress := ((target.getObjValD "ingress").getObjValAs? String "database").toOption
    pairs := pairs.push (owners.findIdx? (· == owner),ingress.bind (fun value => owners.findIdx? (· == value)),target.getObjValD "storage")
  for owner in owners do
    byOwner := byOwner.push (Json.mkObj [("owner",toJson (owners.findIdx? (· == owner))),
      ("targets",toJson (synapticTargets.filter fun row => (row.getObjValD "owner").getObjValD "database" == toJson owner).size)])
  let summary := evidence.getObjValD "summary"
  let corrected := summary.setObjVal! "lexicalCompleted" (toJson lexical)
  let repair := Json.mkObj [("beforeSummarySha256",toJson (← hashText summary.compress)),
    ("reason",toJson "lexical phase records finished rather than completed; raw events and trial unchanged")]
  let analysis := Json.mkObj [("operationServiceObservations",toJson services.size),
    ("queueMs",distribution (values "queueMs")),("workMs",distribution (values "workMs")),
    ("readyMs",distribution (values "readyMs")),("lanes",toJson lanes),("phases",toJson phases.toArray),
    ("numerical",toJson numerical),("indexTargetCount",toJson indexTargets.size),
    ("synapticTargetCount",toJson synapticTargets.size),("owners",toJson owners),("pairs",toJson pairs),
    ("byOwner",toJson byOwner),("summaryRepair",repair)]
  IO.FS.writeFile (output/"analysis.json") analysis.pretty
  IO.FS.writeFile (output/"evidence.json") ((evidence.setObjVal! "summary" corrected
    |>.setObjVal! "summaryRepair" repair).compress++"\n")
  IO.FS.writeFile (output/"summary.json") corrected.pretty
  IO.println (Json.mkObj [("operationServiceObservations",toJson services.size),
    ("queueMs",distribution (values "queueMs")),("workMs",distribution (values "workMs")),
    ("indexTargets",toJson indexTargets.size),("synapticTargets",toJson synapticTargets.size),
    ("owners",toJson owners.size),("lexicalCompleted",toJson lexical)]).compress

def main (args : List String) : IO Unit := do
  if args == ["analyse"] then return ← analyse
  unless args.isEmpty do throw (IO.userError "optional analyse action only")
  unless !(← (output/"evidence.json").pathExists) do throw (IO.userError "preserve prior evidence")
  let original ← read (root/"retained-original-audit.json")
  unless original.getObjValD "allSavedInputOutputExact" == toJson true &&
      original.getObjValD "postedNotPublished" == toJson (#[] : Array String) do
    throw (IO.userError "restarted original audit failed")
  let mut guards := #[]
  for entry in ← base.readDir do
    if !entry.fileName.startsWith "replay-mixed-" || !entry.fileName.endsWith ".guard.json" ||
        entry.fileName.contains "records" || entry.fileName.contains "cleanup" then continue
    let guard ← read entry.path
    unless guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
      throw (IO.userError "live controlled work")
    let text ← IO.FS.readFile (base/(entry.fileName.replace ".guard.json" ".log"))
    let lines := text.splitOn "\n"
    guards := guards.push (entry.fileName,guard,String.intercalate "\n" (lines.drop (lines.length-12)))
  let mut samples := #[]
  for phase in ["seed","writers"] do
    let raw ← IO.ofExcept (fromJson? (← read (root/(phase++"-drain.json"))) : Except String (Array Json))
    let mut previous : Std.HashMap String Json := {}
    let mut changes := #[]
    for sample in raw do
      let replay := sample.getObjValD "replay"
      let sources ← IO.ofExcept (replay.getObjValAs? (Array Json) "sources")
      let mut updated := #[]
      for source in sources do
        let key ← IO.ofExcept (source.getObjValAs? String "source")
        if previous[key]? != some source then updated := updated.push source
        previous := previous.insert key source
      changes := changes.push (sample.setObjVal! "replay" (replay.setObjVal! "sources" (toJson updated)))
    samples := samples.push (phase,Json.mkObj [("sourceRowsAreDeltas",toJson true),("samples",toJson changes)])
  let mut bodies : Array (String × String) := #[]
  let mut readers := #[]
  let mut writerHooks := #[]
  let mut stages := #[]
  let mut elapsedValues := #[]
  let mut queueValues := #[]
  let mut workValues := #[]
  let mut readyValues := #[]
  let mut semantic := 0
  let mut lexical := 0
  let mut captures := 0
  let mut admitted := 0
  let mut delivered := 0
  let mut completedOperations := 0
  for entry in ← root.readDir do
    let isReader := entry.fileName.startsWith "reader-" && entry.fileName.endsWith "-readback-UserPromptSubmit-measurement.json"
    let isWriter := entry.fileName.startsWith "writer-" && entry.fileName.endsWith "-measurement.json"
    if !isReader && !isWriter then continue
    let row ← read entry.path
    let body ← IO.ofExcept (row.getObjValAs? String "body")
    let bodyHash ← hashText body
    let received ← IO.FS.readFile (root/(entry.fileName.replace "-measurement.json" ".json"))
    unless received.endsWith "\n" && toJson (← hashText (received.dropEnd 1).toString) == row.getObjValD "outputSha256" do
      throw (IO.userError "actual received hook bytes changed")
    let compact := row.setObjVal! "body" Json.null |>.setObjVal! "bodySha256" (toJson bodyHash)
      |>.setObjVal! "bodyBytes" (toJson body.utf8ByteSize)
    if isWriter then
      writerHooks := writerHooks.push (entry.fileName,compact)
      continue
    let head := body.contains "\"observed-head-case-79-7b319c\""
    let tail := body.contains "\"observed-tail-case-79-d82a04\""
    let elapsed ← IO.ofExcept (row.getObjValAs? Nat "elapsedMs")
    elapsedValues := elapsedValues.push elapsed
    if head && tail && row.getObjValD "complete" == toJson true && elapsed < 30000 then delivered := delivered+1
    readers := readers.push (entry.fileName,compact.setObjVal! "head" (toJson head) |>.setObjVal! "tail" (toJson tail))
    if !bodies.any (·.1 == bodyHash) then bodies := bodies.push (bodyHash,body)
    let receipt ← IO.ofExcept (row.getObjValAs? String "receipt")
    let mut events := #[]
    let directory := root/"private/receipts"/receipt
    for event in ← directory.readDir do
      let name := event.fileName
      let keep := ["operation-","search-phase-","numerical-","worker-","provider-"].any (fun start => name.startsWith start) ||
        ["prepared-inputs-turn.json","prepared-reader-images.json","prepared-owner-bindings.json","search.json",
          "source-pin-groups-profile.json","handoff-cost-profile.json","failure.json","operation-service.json"].contains name
      if !keep || !name.endsWith ".json" then continue
      let value ← read event.path
      let data := value.getObjValD "data"
      if name.endsWith "-admitted.json" then admitted := admitted+1
      if name == "prepared-inputs-turn.json" && data.getObjValD "status" == toJson "complete" then captures := captures+1
      if name == "search-phase-semantic.json" && data.getObjValD "status" == toJson "completed" then semantic := semantic+1
      if name == "search-phase-lexical.json" && data.getObjValD "status" == toJson "finished" then lexical := lexical+1
      if name.startsWith "operation-" && name.endsWith "-finished.json" then
        completedOperations := completedOperations+1
        if let .ok n := data.getObjValAs? Nat "queueMs" then queueValues := queueValues.push n
        if let .ok n := data.getObjValAs? Nat "workMs" then workValues := workValues.push n
        if let .ok n := data.getObjValAs? Nat "readyMs" then readyValues := readyValues.push n
      events := events.push (name,value)
    stages := stages.push (entry.fileName,events)
  let fixtureFiles ← #["seed-originals.json","writers-originals.json","seed-ready.json","writers-ready.json",
      "frozen-seed.json","frozen-readback.json"].filterMapM fun (name : String) => do
    let path := root/System.FilePath.mk name
    if ← path.pathExists then pure (some (name,← read path)) else pure none
  let readResults ← read (root/"readers-results.json")
  let writeResults ← read (root/"writers-results.json")
  let summary := Json.mkObj [("readersObserved",toJson readers.size),("deliveredWithin30s",toJson delivered),
    ("wholeReaderSuccess",toJson ((readResults.getObjValAs? (Array Json) "rows").toOption.getD #[]).size),
    ("writerLoops",toJson ((writeResults.getObjValAs? (Array Json) "rows").toOption.getD #[]).size),
    ("admitted",toJson admitted),("completeCaptures",toJson captures),("semanticCompleted",toJson semantic),
    ("lexicalCompleted",toJson lexical),("finishedOperationObservations",toJson completedOperations),
    ("failureInclusiveHookMs",distribution elapsedValues),("observedQueueMs",distribution queueValues),
    ("observedWorkMs",distribution workValues),("observedReadyMs",distribution readyValues)]
  let evidence := Json.mkObj [("runtimeSha256",toJson (← hash (base/"replay-mixed-build/StudyMain"))),
    ("harnessSha256",toJson (← hash (workspace/"tools/research/FrontTrafficChecks.lean"))),
    ("guards",toJson guards),("summary",summary),("originalAudit",original),("fixture",toJson fixtureFiles),
    ("drain",toJson samples),("readerMeasurements",toJson readers),("writerMeasurements",toJson writerHooks),
    ("readerErrors",readResults.getObjValD "errors"),("writerErrors",writeResults.getObjValD "errors"),
    ("stages",toJson stages),("actualBodies",toJson bodies),("answeringModelCalls",toJson (0 : Nat)),
    ("matchedPaidComparisons",toJson (0 : Nat)),("adopted",toJson false)]
  IO.FS.writeFile (output/"evidence.json") (evidence.compress++"\n")
  IO.FS.writeFile (output/"summary.json") summary.pretty
  IO.println summary.compress
