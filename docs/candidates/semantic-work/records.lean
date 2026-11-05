import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def output := workspace/"docs/candidates/semantic-work"
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def arr (value : Json) (key : String) : Array Json := (value.getObjValAs? (Array Json) key).toOption.getD #[]
def number (value : Json) (key : String) := (value.getObjValAs? Nat key).toOption.getD 0
def dist (values : Array Nat) : Json := Id.run do
  let sorted := values.qsort (· < ·)
  return Json.mkObj [("count",toJson sorted.size),("min",toJson sorted[0]?),
    ("median",toJson sorted[sorted.size/2]?),("max",toJson sorted.back?)]
def hashFile (path : System.FilePath) : IO String := do
  let reply ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  unless reply.exitCode == 0 do throw (IO.userError "cannot digest diagnostic artifact")
  return (reply.stdout.splitOn " ").headD ""
def main : IO Unit := do
  let root := base/"semantic-work-profile1-result"
  let report ← read (root/"report.json")
  let phases := #[report.getObjValD "prime",report.getObjValD "first",report.getObjValD "second"]
  let rows := phases.flatMap (arr · "rows")
  let receipts := phases.flatMap (arr · "receipts")
  unless rows.size == 35 && rows.all (fun row => row.getObjValD "bothFields" == toJson true &&
      row.getObjValD "acknowledged" == toJson true && number row "elapsedMs" < 30000) do
    throw (IO.userError "diagnostic lacks complete actual deliveries")
  let known : Array Json ← IO.ofExcept ((← read (workspace/"docs/candidates/focus-locators/bodies.json")).getArr?)
  let mut actual := #[]
  let mut extraBodies : Array Json := #[]
  for row in rows do
    let session ← IO.ofExcept (row.getObjValAs? String "session")
    let path := root/(session++".stdout")
    unless toJson (← hashFile path) == row.getObjValD "stdoutSha256" do throw (IO.userError "actual output changed")
    let body ← IO.ofExcept (((← read path).getObjValD "hookSpecificOutput").getObjValAs? String "additionalContext")
    let head := s!"\"observed-head-case-{number row "case"}-7b319c\""
    let tail := s!"\"observed-tail-case-{number row "case"}-d82a04\""
    unless body.contains head && body.contains tail do throw (IO.userError "actual original field missing")
    let reference ← match (known.toList.zipIdx).find? (fun (entry,_) => entry.getObjValD "body" == toJson body) with
      | some (entry,index) => pure (Json.mkObj [("artifact",toJson "../focus-locators/bodies.json"),
          ("index",toJson index),("sha256",entry.getObjValD "sha256")])
      | none => do
        let index := extraBodies.size
        extraBodies := extraBodies.push (Json.mkObj [("body",toJson body),("utf8Bytes",toJson body.utf8ByteSize)])
        pure (Json.mkObj [("artifact",toJson "new-bodies.json"),("index",toJson index)])
    actual := actual.push (row.setObjVal! "bodyReference" reference)
  let semantic := receipts.map (·.getObjValD "search-phase-semantic")
  let start := (semantic.map (number · "startedAt")).foldl min 1000000000000000000
  let finish := (semantic.map (number · "finishedAt")).foldl max 0
  let mut profiles := #[]
  let mut numerical := #[]
  for directory in ← (root/"private/receipts").readDir do
    if (← directory.path.symlinkMetadata).type != .dir then continue
    for entry in ← directory.path.readDir do
      if entry.fileName.endsWith "-profile.json" then
        let value ← read entry.path
        let data := value.getObjValD "data"
        if start ≤ number data "startedMs" && number data "finishedMs" ≤ finish then
          profiles := profiles.push (Json.mkObj [("stage",value.getObjValD "stage"),("data",data)])
      if entry.fileName.startsWith "numerical-" && entry.fileName.endsWith ".json" then
        numerical := numerical.push ((← read entry.path).getObjValD "data")
  let mut numericGroups := #[]
  let purposes := numerical.toList.map (fun row =>
    ((row.getObjValD "corpus").getObjValAs? String "purpose").toOption.getD "unspecified") |>.eraseDups
  for purpose in purposes do
    let selected := numerical.filter fun row =>
      ((row.getObjValD "corpus").getObjValAs? String "purpose").toOption.getD "unspecified" == purpose
    unless selected.isEmpty do
      numericGroups := numericGroups.push (Json.mkObj [("purpose",toJson purpose),
        ("elapsedMs",dist (selected.map (number · "elapsedMs"))),
        ("hostScoreMs",dist (selected.filterMap fun row => ((row.getObjValD "counters").getObjValAs? Nat "scoreMs").toOption)),
        ("encoderScoreUs",dist (selected.filterMap fun row =>
          (((row.getObjValD "counters").getObjValD "encoder").getObjValAs? Nat "scoreUs").toOption))])
  let mut stageGroups := #[]
  let stages := profiles.toList.map (fun row => (row.getObjValAs? String "stage").toOption.getD "") |>.eraseDups
  for stage in stages do
    let selected := profiles.filter (fun row => row.getObjValD "stage" == toJson stage) |>.map (·.getObjValD "data")
    let mut fields := #[]
    for key in ["queryMs","prepareMs","serviceAndFinishMs","fetchMs","finishMs","selectMs","materializeMs",
        "receiveMs","connectMs","sendMs","encodeMs","headerMs","payloadMs","verifyMs","utf8Ms"] do
      let values := selected.filterMap (fun value => (value.getObjValAs? Nat key).toOption)
      unless values.isEmpty do fields := fields.push (key,dist values)
    stageGroups := stageGroups.push (Json.mkObj [("stage",toJson stage),("observations",toJson selected.size),
      ("fields",toJson fields)])
  let samplePath := root/"worker.sample.txt"
  let sample ← IO.FS.readFile samplePath
  let top := (sample.splitOn "Sort by top of stack, same collapsed (when >= 5):").drop 1 |>.headD ""
  let top := (top.splitOn "Binary Images:").headD ""
  IO.FS.writeFile (output/"sample-top.txt") (top.trimAscii.toString++"\n")
  if !extraBodies.isEmpty then IO.FS.writeFile (output/"new-bodies.json") (toJson extraBodies).pretty
  IO.FS.writeFile (output/"evidence.json") (Json.mkObj [("actualOutputs",toJson actual),
    ("semanticObservations",toJson semantic),("semanticElapsedMs",dist (semantic.map (number · "elapsedMs"))),
    ("numericGroups",toJson numericGroups),("numericalObservations",toJson numerical),
    ("stageGroups",toJson stageGroups),("profiles",toJson profiles),
    ("sampleSha256",toJson (← hashFile samplePath)),("sampleTarget",← read (root/"sample-target.json")),
    ("sampleResult",← read (root/"sample-result.json")),("originalHeadsUnchanged",report.getObjValD "originalHeadsUnchanged"),
    ("stageAttribution",toJson "time-window observations; nested durations are not additive or per-request causal attribution"),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)]).pretty
  IO.println (Json.mkObj [("actualOutputs",toJson actual.size),("newBodies",toJson extraBodies.size),
    ("numericObservations",toJson numerical.size),("stageProfiles",toJson profiles.size)]).compress
