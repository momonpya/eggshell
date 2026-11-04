import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def output : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/direct-numerical"
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def save (name : String) (value : Json) : IO Unit := IO.FS.writeFile (output/name) (value.compress++"\n")
def hash (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  unless result.exitCode == 0 do throw (IO.userError "hashing failed")
  return (result.stdout.splitOn " ").head!
def stage (root : System.FilePath) (receipt name : String) : IO Json := do
  let path := root/"private/receipts"/receipt/(name++".json")
  if !(← path.pathExists) then return Json.null
  return (← read path).getObjValD "data"

def main : IO Unit := do
  let mut guards := #[]
  let mut failures := #[]
  for entry in ← base.readDir do
    if ["direct-numerical-","front-input-","front-traffic-","front-manager-"].any (fun stem => entry.fileName.startsWith stem) &&
        entry.fileName.endsWith ".guard.json" then
      let guard ← read entry.path
      unless guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "controlled work is still owned")
      if entry.fileName.startsWith "direct-numerical-" then
        guards := guards.push (entry.fileName,guard)
        if guard.getObjValD "exitCode" != toJson (0 : Nat) then
          let log := base/(entry.fileName.replace ".guard.json" ".log")
          let lines ← if ← log.pathExists then do pure ((← IO.FS.readFile log).splitOn "\n") else pure []
          failures := failures.push (entry.fileName,String.intercalate "\n" (lines.drop (lines.length-22)))
  save "guards.json" (toJson guards)
  save "failed-attempts.json" (Json.mkObj [("attempts",toJson failures),
    ("interpretation",toJson "build1 failed in a research helper's branch return type; components1 detected a missing newline in the direct local-score frame and timed out. Neither is a passed capacity or adoption result.")])
  let mut patch := ""
  let mut changed := #[]
  for name in ["Numerical.lean","SearchProvider.lean"] do
    let prior := base/"direct-numerical-baseline-core/Eggshell"/name
    let current := base/"interest-traffic-core/Eggshell"/name
    let result ← IO.Process.output {cmd := "git",args := #["diff","--no-index","--",prior.toString,current.toString]}
    unless result.exitCode ≤ 1 do throw (IO.userError "source diff failed")
    patch := patch++(result.stdout.replace ("a"++(base/"direct-numerical-baseline-core").toString++"/") "a/"
      |>.replace ("b"++(base/"interest-traffic-core").toString++"/") "b/")
    changed := changed.push (name,← hash prior,← hash current)
  IO.FS.writeFile (output/"candidate.patch") patch
  let mut unchanged := #[]
  for name in ["MiniLM.lean","BlockScore.lean","GraphStore.lean","DB/PageMap.lean","NativePublication.lean",
      "Handoff.lean","SearchRank.lean","Matcher.lean","Extract.lean","KeyedSearchProvider.lean","SemanticMatcher.lean"] do
    let prior ← hash (base/"direct-numerical-baseline-core/Eggshell"/name)
    let current ← hash (base/"interest-traffic-core/Eggshell"/name)
    unless prior == current do throw (IO.userError "model, scoring, graph, ranking, or authority source changed")
    unchanged := unchanged.push (name,current)
  save "identity.json" (Json.mkObj [("parentRuntimeSha256",toJson (← hash (base/"front-input-build/StudyMain"))),
    ("candidateRuntimeSha256",toJson (← hash (base/"direct-numerical-build/StudyMain"))),
    ("changed",toJson changed),("unchanged",toJson unchanged)])
  let components := base/"direct-numerical-fixture-components3"
  if ← (components/"report.json").pathExists then
    let mut pairs := #[]
    for repetition in [:3] do
      for arm in ["pipe","direct"] do
        pairs := pairs.push (s!"pair-{repetition}-{arm}",← read (components/s!"pair-{repetition}-{arm}.json"))
    save "components.json" (Json.mkObj [("report",← read (components/"report.json")),("pairs",toJson pairs),
      ("ownership",← read (components/"ownership.json")),("frozenValuesSha256",toJson (← hash (components/"frozen-values.json")))])
    save "numerical-values.json" (← read (components/"frozen-values.json"))
  let replay := base/"direct-numerical-fixture-replay1"
  if ← (replay/"report.json").pathExists then
    save "replay.json" (← read (replay/"report.json"))
    save "frozen-request.json" (← read (replay/"frozen-request.json"))
    save "actual-response.json" (← read (replay/"pair-0-pipe.json"))
  for (tag,name) in [("direct-numerical-proofs1","laws.txt"),("direct-numerical-contract1","contract-audit.txt")] do
    let log := base/(tag++".log")
    if ← log.pathExists then
      let lines := (← IO.FS.readFile log).splitOn "\n"
      IO.FS.writeFile (output/name) ("Full output SHA-256: "++(← hash log)++"\n"++String.intercalate "\n" (lines.drop (lines.length-15)))
  let mut reports := #[]
  let mut trials := #[]
  let mut stages := #[]
  let mut outputs : Array (String × String) := #[]
  for name in ["readers1","small1","large1"] do
    let root := base/("direct-numerical-fixture-"++name)
    let file := if name == "readers1" then "input-report.json" else "report.json"
    if ← (root/file).pathExists then reports := reports.push (name,← read (root/file))
    if !(← root.pathExists) then continue
    let mut hooks := #[]
    let mut initial := 0
    let mut delivered := 0
    let mut maxInitialMs := 0
    for entry in ← root.readDir do
      if !entry.fileName.endsWith "-measurement.json" then continue
      let row ← read entry.path
      let receipt ← IO.ofExcept (row.getObjValAs? String "receipt")
      stages := stages.push (Json.mkObj [("trial",toJson name),("hook",toJson entry.fileName),
        ("hookMs",row.getObjValD "elapsedMs"),("complete",row.getObjValD "complete"),
        ("turnInputs",← stage root receipt "prepared-inputs-turn"),
        ("operationInputs",← stage root receipt "prepared-inputs-operation"),
        ("transport",← stage root receipt "transport"),("service",← stage root receipt "operation-service"),
        ("search",← stage root receipt "search")])
      let digest ← IO.ofExcept (row.getObjValAs? String "outputSha256")
      if !outputs.any (·.1 == digest) then
        let path := root/(entry.fileName.replace "-measurement.json" ".json")
        let written ← IO.FS.readFile path
        unless written.endsWith "\n" do throw (IO.userError "receiver framing changed")
        let actual := (written.dropEnd 1).toString
        let temporary := base/"direct-numerical-output-hash"
        IO.FS.writeFile temporary actual
        let checked ← try hash temporary finally IO.FS.removeFile temporary
        unless checked == digest do throw (IO.userError "receiver output differs from receipt")
        outputs := outputs.push (digest,actual)
      if entry.fileName.endsWith "-initial-UserPromptSubmit-measurement.json" then
        initial := initial+1
        let elapsed ← IO.ofExcept (row.getObjValAs? Nat "elapsedMs")
        maxInitialMs := max maxInitialMs elapsed
        let body ← IO.ofExcept (row.getObjValAs? String "body")
        let present := ["observed-head-seed-alpha-7b319c","observed-tail-seed-alpha-d82a04",
          "observed-head-seed-tail-7b319c","observed-tail-seed-tail-d82a04"].all (fun field => body.contains field)
        if row.getObjValD "complete" == toJson true && elapsed < 30000 && present then delivered := delivered+1
      hooks := hooks.push (entry.fileName,row.setObjVal! "body" Json.null)
    let errors := root/(if name == "readers1" then "input-readers-results.json" else "writers-results.json")
    let errors ← if ← errors.pathExists then do pure ((← read errors).getObjValD "errors") else pure Json.null
    trials := trials.push (Json.mkObj [("trial",toJson name),("initialReceipts",toJson initial),
      ("allFrozenInitialFieldsDelivered",toJson delivered),("maxInitialMs",toJson maxInitialMs),
      ("errors",errors),("hooks",toJson hooks)])
  save "native-reports.json" (toJson reports)
  save "native-trials.json" (Json.mkObj [("trials",toJson trials),("actualOutputsBySha256",toJson outputs)])
  save "native-stages.json" (toJson stages)
  IO.println (toJson (trials.map fun row => Json.mkObj (
    ["trial","initialReceipts","allFrozenInitialFieldsDelivered","maxInitialMs","errors"].map fun field =>
      (field,row.getObjValD field)))).compress
  IO.println (Json.mkObj [("guards",toJson guards.size),("failures",toJson failures.size),
    ("reports",toJson reports.size)]).compress
