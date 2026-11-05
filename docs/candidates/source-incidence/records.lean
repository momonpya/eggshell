import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def output := workspace/"docs/candidates/source-incidence"
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def save (name : String) (value : Json) : IO Unit := IO.FS.writeFile (output/name) (value.pretty++"\n")
def hash (path : System.FilePath) : IO String := do
  let reply ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  unless reply.exitCode == 0 do throw (IO.userError "cannot seal diagnostic file")
  return (reply.stdout.splitOn " ").head!
def hashText (value : String) : IO String := do
  let reply ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256"]} (some value)
  unless reply.exitCode == 0 do throw (IO.userError "cannot seal actual stdout")
  return (reply.stdout.splitOn " ").head!
def distribution (values : Array Nat) : Json := Id.run do
  let rows := values.qsort (· < ·)
  return Json.mkObj [("count",toJson rows.size),("min",toJson rows[0]?),
    ("median",toJson rows[rows.size/2]?),("max",toJson rows.back?)]
def verifyOriginals : IO Unit := do
  let recorded ← if ← (base/"semantic-phase-worker-sample1-result/original-heads.json").pathExists then
      read (base/"semantic-phase-worker-sample1-result/original-heads.json")
    else pure ((← read (output/"evidence.json")).getObjValD "originalHeads")
  let originals ← IO.ofExcept (fromJson? recorded :
    Except String (Array (String × String × String)))
  for (raw,expected,digest) in originals do
    let path : System.FilePath := .mk raw
    unless (← IO.FS.readFile path) == expected && (← hash path) == digest do
      throw (IO.userError "active fixed original head changed")
  let controlsChecked ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256","-c",
    (workspace/"docs/candidates/project-cache/protected-after.sha256").toString],cwd := some base}
  unless controlsChecked.exitCode == 0 do throw (IO.userError "protected control identity changed")
def guards : IO (Array (String × Json × String)) := do
  let mut result := #[]
  for entry in ← base.readDir do
    if !(entry.fileName.startsWith "source-incidence-" || entry.fileName.startsWith "semantic-phase-worker-sample1.") ||
        !entry.fileName.endsWith ".guard.json" then continue
    let record ← read entry.path
    unless record.getObjValD "state" == toJson "finished" &&
        record.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
      throw (IO.userError "diagnostic guard is not terminal")
    let log := base/(entry.fileName.replace ".guard.json" ".log")
    let contents ← if ← log.pathExists then IO.FS.readFile log else pure ""
    result := result.push (entry.fileName,record,contents)
  return result
def phases (root : System.FilePath) (wanted : Option (Array String) := none) : IO (Array (String × Json)) := do
  let mut records := #[]
  let directory := root/"private/receipts"
  if !(← directory.pathExists) then return records
  for receipt in ← directory.readDir do
    if (← receipt.path.symlinkMetadata).type != .dir then continue
    if wanted.any (!·.contains receipt.fileName) then continue
    for entry in ← receipt.path.readDir do
      let keep := entry.fileName.startsWith "operation-" || entry.fileName.startsWith "search-phase-" ||
        ["source-plan-profile.json","render-selector-path.json","render-automatic-profile.json",
          "client-profile.json","prepared-reader-images.json"].contains entry.fileName
      if keep && entry.fileName.endsWith ".json" then
        records := records.push (receipt.fileName++"/"++entry.fileName,← read entry.path)
  return records
def patch : IO Unit := do
  let core := base/"interest-traffic-core"
  let parent := base/"source-incidence-baseline-core"
  let mut result := ""
  for name in ["Eggshell/Handoff.lean","Eggshell/OrderedIncidence.lean"] do
    let old := if name.endsWith "OrderedIncidence.lean" then System.FilePath.mk "/dev/null" else parent/name
    let current := core/name
    let reply ← IO.Process.output {cmd := "/usr/bin/git",args := #["diff","--no-index","--no-prefix","--unified=0",
      old.toString,current.toString]}
    unless reply.exitCode == 1 do throw (IO.userError "missing isolated product diff")
    let lines := reply.stdout.splitOn "\n"
    let normalized := lines.drop 1 |>.map fun line =>
      if line.startsWith "--- " then "--- "++(if old.toString == "/dev/null" then "/dev/null" else "a/"++name)
      else if line.startsWith "+++ " then "+++ b/"++name else line
    result := result++s!"diff --git a/{name} b/{name}\n"++"\n".intercalate normalized
  IO.FS.writeFile (output/"candidate.patch") result
  let checked ← IO.Process.output {cmd := "/usr/bin/git",args := #["apply","--check","--unidiff-zero",
    (output/"candidate.patch").toString],cwd := some parent}
  unless checked.exitCode == 0 do throw (IO.userError ("isolated patch does not apply: "++checked.stderr))
def mixed : IO Json := do
  let root := base/"source-incidence-mixed1-result"
  let drain ← IO.ofExcept (fromJson? (← read (root/"writers-drain.json")) : Except String (Array Json))
  let entered ← (root/"frozen-readback.json").pathExists
  let frozen ← if entered then read (root/"frozen-readback.json") else
    pure (Json.mkObj [("sourceHeads",(drain.back?.getD Json.null).getObjValD "sourceHeads"),
      ("deliveryStageReached",toJson false)])
  let heads ← IO.ofExcept (frozen.getObjValAs? (Array Json) "sourceHeads")
  for owner in [:heads.size] do
    unless some (← read (root/"work.project/owners"/toString owner/"source.egg/head")) == heads[owner]? do
      throw (IO.userError "mixed readback changed its frozen original cut")
  let mut received := #[]
  let mut outputs : Array (String × String) := #[]
  let mut receipts : Array String := #[]
  let mut durations : Array Nat := #[]
  let mut delivered := 0
  for entry in ← root.readDir do
    if !entry.fileName.startsWith "reader-" || !entry.fileName.endsWith "-measurement.json" then continue
    let row ← read entry.path
    let body ← IO.ofExcept (row.getObjValAs? String "body")
    let digest ← IO.ofExcept (row.getObjValAs? String "outputSha256")
    let raw ← IO.FS.readFile (root/(entry.fileName.replace "-measurement.json" ".json"))
    unless raw.endsWith "\n" && (← hashText (raw.dropEnd 1).toString) == digest do
      throw (IO.userError "mixed receiver differs from its actual stdout")
    match outputs.find? (fun pair => pair.1 == digest) with
    | some (_,previous) => unless raw == previous do throw (IO.userError "stdout digest collision")
    | none => outputs := outputs.push (digest,raw)
    let complete := body.contains "\"observed-head-case-79-7b319c\"" &&
      body.contains "\"observed-tail-case-79-d82a04\""
    let elapsed ← IO.ofExcept (row.getObjValAs? Nat "elapsedMs")
    if complete && row.getObjValD "complete" == toJson true && elapsed < 30000 then delivered := delivered+1
    durations := durations.push elapsed
    receipts := receipts.push (← IO.ofExcept (row.getObjValAs? String "receipt"))
    received := received.push (entry.fileName,row.setObjVal! "body" Json.null
      |>.setObjVal! "bothOriginalFields" (toJson complete))
  let observed ← phases root (some receipts)
  let services := observed.filterMap fun (name,value) =>
    if name.endsWith "operation-service.json" then some (value.getObjValD "data") else none
  let values := fun key => services.filterMap fun value => (value.getObjValAs? Nat key).toOption
  let writers ← read (root/"writers-results.json")
  let readers ← if ← (root/"readers-results.json").pathExists then read (root/"readers-results.json")
    else pure (Json.mkObj [("rows",toJson (#[] : Array Json)),("errors",toJson (#[] : Array Json))])
  let summary := Json.mkObj [("readerMeasurements",toJson received.size),("deliveredWithin30s",toJson delivered),
    ("deliveryStageEntered",toJson entered),("readersNotRun",toJson (if entered then 0 else (80 : Nat))),
    ("writerSuccesses",toJson ((writers.getObjValAs? (Array Json) "rows").toOption.getD #[]).size),
    ("writerErrors",writers.getObjValD "errors"),("readerErrors",readers.getObjValD "errors"),
    ("semanticCompleted",toJson (observed.filter fun (name,value) =>
      name.endsWith "search-phase-semantic.json" && (value.getObjValD "data").getObjValD "status" == toJson "completed").size),
    ("lexicalCompleted",toJson (observed.filter fun (name,value) =>
      name.endsWith "search-phase-lexical.json" && (value.getObjValD "data").getObjValD "status" == toJson "finished").size),
    ("failureInclusiveHookMs",distribution durations),("observedServiceOperations",toJson services.size),
    ("observedQueueMs",distribution (values "queueMs")),("observedWorkMs",distribution (values "workMs")),
    ("readinessLast",toJson drain.back?),("savedCutHeadsUnchanged",toJson true)]
  save "mixed-summary.json" summary
  save "mixed-stdout.json" (toJson outputs)
  return Json.mkObj [("summary",summary),("received",toJson received),("readerPhases",toJson observed),
    ("capturedCut",frozen),("originalAudit",← if ← (root/"writers-originals.json").pathExists then
      read (root/"writers-originals.json") else pure Json.null),
    ("freshProcessAudit",← read (root/"retained-original-audit.json")),
    ("drainSampleCount",toJson drain.size),("drainFileSha256",toJson (← hash (root/"writers-drain.json"))),
    ("stdoutFile",toJson "mixed-stdout.json"),("stdoutSha256",toJson (← hash (output/"mixed-stdout.json")))]
def recordEvidence : IO Unit := do
  unless !(← (output/"evidence.json").pathExists) do throw (IO.userError "preserve sealed evidence")
  verifyOriginals
  let guarded ← guards
  let sample := base/"semantic-phase-worker-sample1-result"
  let sampled ← read (sample/"report.json")
  let profileRows ← IO.ofExcept (sampled.getObjValAs? (Array Json) "rows")
  let mut firstBody := none
  for row in profileRows do
    let body ← IO.ofExcept (row.getObjValAs? String "body")
    if let some previous := firstBody then
      unless body == previous do throw (IO.userError "sample changed actual body")
    else firstBody := some body
  let some body := firstBody | throw (IO.userError "sample omitted its actual body")
  IO.FS.writeFile (output/"actual-body.txt") body
  let sampleLines := (← IO.FS.readFile (sample/"worker.sample.txt")).splitOn "\n" |>.toArray
  let mut selected := #[]
  for i in [:sampleLines.size] do
    if (sampleLines[i]!.splitOn "sourceNeighborhood").length > 1 &&
        !sampleLines[i]!.startsWith " " then continue
    if (sampleLines[i]!.splitOn "sourceNeighborhood").length > 1 ||
        (sampleLines[i]!.splitOn "sourceNeighbors").length > 1 then
      for j in [i-5:min sampleLines.size (i+7)] do selected := selected.push j
  IO.FS.writeFile (output/"sample-stack.txt")
    ("Counts are recursive stack observations, not CPU percentages.\n"++
      "\n".intercalate ((selected.toList.eraseDups).map fun i => s!"{i+1}: {sampleLines[i]!}")++"\n")
  let pairs := base/"source-incidence-pairs1-result"
  let paired ← read (pairs/"report.json")
  let trials ← IO.ofExcept (paired.getObjValAs? (Array Json) "trials")
  let mut actual := #[]
  for trial in trials do
    let raw ← IO.ofExcept (trial.getObjValAs? String "directory")
    let root : System.FilePath := .mk raw
    let full ← read (root/"report.json")
    let rows ← IO.ofExcept (full.getObjValAs? (Array Json) "rows")
    for row in rows do
      unless row.getObjValD "body" == toJson body do throw (IO.userError "profile body differs from sealed original")
    actual := actual.push (trial.setObjVal! "phases" (toJson (← phases root))
      |>.setObjVal! "handoffTrace" (toJson (← IO.FS.readFile (root/"handoff.trace"))))
  let checksLog ← IO.FS.readFile (base/"source-incidence-checks2.log")
  let checked ← IO.ofExcept (Json.parse checksLog)
  unless checked.getObjValD "allPassed" == toJson true do throw (IO.userError "native source checks failed")
  let laws ← IO.FS.readFile (base/"source-incidence-build/tools_research_SourceIncidenceChecks-lean.stdout")
  IO.FS.writeFile (output/"laws.txt") laws
  patch
  save "evidence.json" (Json.mkObj [("sampleReport",sampled.setObjVal! "rows"
      (toJson (profileRows.map (·.setObjVal! "body" Json.null)))),
    ("sampleTarget",← read (sample/"sample-targets.json")),("sampleResult",← read (sample/"sample-result.json")),
    ("sampleSha256",toJson (← hash (sample/"worker.sample.txt"))),
    ("samplePhases",toJson (← phases sample)),("sampleTrace",toJson (← IO.FS.readFile (sample/"handoff.trace"))),
    ("originalHeads",← read (sample/"original-heads.json")),("guards",toJson guarded),
    ("checksLog",toJson checksLog),("paired",paired.setObjVal! "trials" (toJson actual)),("mixed",← mixed),
    ("actualBodyFile",toJson "actual-body.txt"),("actualBodySha256",toJson (← hash (output/"actual-body.txt"))),
    ("answeringModelCalls",toJson (0 : Nat)),("paidMatchedComparisons",toJson (0 : Nat)),
    ("adopted",toJson false),("fullGoalComplete",toJson false)])
  verifyOriginals
  IO.println "sealed source-incidence diagnostics"
partial def erase (path : System.FilePath) : IO Nat := do
  let metadata ← path.symlinkMetadata
  if metadata.type == .dir then
    let mut bytes := 0
    for entry in ← path.readDir do bytes := bytes+(← erase entry.path)
    IO.FS.removeDir path
    return bytes
  unless metadata.type == .file || metadata.type == .symlink do throw (IO.userError "special cleanup input")
  IO.FS.removeFile path
  return metadata.byteSize.toNat
def cleanup : IO Unit := do
  unless (← (output/"evidence.json").pathExists) && !(← (output/"cleanup.json").pathExists) do
    throw (IO.userError "seal first and preserve prior cleanup")
  let _ ← guards
  verifyOriginals
  let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axww","-o","command="]}
  unless processes.exitCode == 0 do throw (IO.userError "cannot audit live diagnostic users")
  for engine in [base/"source-incidence-build/StudyMain",base/"local-selection-traffic-build/StudyMain"] do
    if processes.stdout.splitOn "\n" |>.any (fun line =>
        let value := line.trimAscii.toString
        value == engine.toString || value.startsWith (engine.toString++" ")) then
      throw (IO.userError "diagnostic service still running")
  let mut removed := #[]
  for name in ["semantic-phase-worker-sample1-result","source-incidence-pairs1-result","source-incidence-mixed1-result"] do
    let path := base/name
    if ← path.pathExists then removed := removed.push (path.toString,← erase path)
  for entry in ← base.readDir do
    if (entry.fileName.startsWith "source-incidence-" || entry.fileName.startsWith "semantic-phase-worker-sample1.") &&
        [".guard.json",".guard-settings.json",".log"].any (fun ending => entry.fileName.endsWith ending) then
      removed := removed.push (entry.path.toString,← erase entry.path)
  let finishedBuild := base/"source-incidence-build"
  for entry in ← finishedBuild.readDir do
    if [".stdout",".stderr"].any (fun ending => entry.fileName.endsWith ending) then
      removed := removed.push (entry.path.toString,← erase entry.path)
  let finishedProof := base/"source-incidence-proof.olean"
  if ← finishedProof.pathExists then removed := removed.push (finishedProof.toString,← erase finishedProof)
  verifyOriginals
  let receipt := Json.mkObj [("removed",toJson removed),
    ("apparentBytes",toJson (removed.foldl (fun total row => total+row.2) (0 : Nat))),
    ("activeOriginalsAndBuildInputsRetained",toJson true),("archiveCreated",toJson false)]
  save "cleanup.json" receipt
  IO.println (receipt.setObjVal! "removed" Json.null).compress
def main (args : List String) : IO Unit := do
  match args with
  | ["seal"] => recordEvidence
  | ["cleanup"] => cleanup
  | _ => throw (IO.userError "source-incidence record action required")
