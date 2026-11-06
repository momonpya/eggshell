import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def arr (value : Json) (key : String) : Array Json := (value.getObjValAs? (Array Json) key).toOption.getD #[]
def nat (value : Json) (key : String) : Nat := (value.getObjValAs? Nat key).toOption.getD 0
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def hash (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  check (result.exitCode == 0) "cannot hash protocol evidence"
  return (result.stdout.splitOn " ").headD ""
def distribution (values : Array Nat) : Json := Id.run do
  let sorted := values.qsort (· < ·)
  return Json.mkObj [("count",toJson sorted.size),("min",toJson sorted[0]?),
    ("median",toJson sorted[sorted.size/2]?),("max",toJson sorted.back?)]
def events (value : Json) : IO (Array (String × Nat)) := do
  let values ← IO.ofExcept (fromJson? (value.getObjValD "events") : Except String (Array (String × Nat)))
  for index in [1:values.size] do check (values[index-1]!.2 ≤ values[index]!.2) "numerical event clock regressed"
  return values
def span (values : Array (String × Nat)) (first last : String) : Option Nat := do
  let a ← values.find? (·.1 == first)
  let b ← values.find? (·.1 == last)
  return b.2-a.2
def summarize (tag : String) (report : Json) : IO Json := do
  let mut spans : Array (String × Nat) := #[]
  let mut requests := #[]
  let mut responses := #[]
  let mut replies := 0
  for result in arr report "results" do
    if result.getObjValD "completed" == toJson true then
      check (nat result "elapsedMs" < 28800 && nat result "scores" == 1205 &&
        result.getObjValD "identicalRepeatedScores" == toJson true) "completed protocol result changed domain or deadline"
    for profile in arr result "profiles" do
      replies := replies+1
      let localEvents ← events profile
      let serverEvents ← events (profile.getObjValD "server")
      for (name,a,b) in [("connect","connect:start","connect:end"),("send","send:start","send:end"),
          ("wait-header","receive:start","header-ready"),("read-body","header-ready","body-ready"),
          ("decode-outer","body-ready","outer-decoded"),("decode-inner","outer-decoded","inner-decoded"),
          ("client-repack","inner-decoded","client-repacked"),("provider-reparse","client-repacked","provider-decoded")] do
        if let some ms := span localEvents a b then spans := spans.push (name,ms)
      for (name,a,b) in [("encode-admission","encode-admission:start","encode-admission:end"),
          ("encode-kernel","encode-kernel:start","encode-kernel:end"),
          ("score-admission","score-admission:start","score-admission:end"),
          ("score-prepare","score-prepare:start","score-prepare:end"),
          ("score-kernel","score-kernel:start","score-kernel:end")] do
        if let some ms := span serverEvents a b then spans := spans.push (name,ms)
      if let some ready := serverEvents.find? (·.1 == "output-ready") then
        let some body := localEvents.find? (·.1 == "body-ready") | throw (IO.userError "returned RPC lost body readiness")
        check (ready.2 ≤ body.2) "server/client monotone clock mismatch"
        spans := spans.push ("output-ready-to-body",body.2-ready.2)
      requests := requests.push (nat profile "requestBytes")
      responses := responses.push (nat profile "responseBytes")
  let names := spans.toList.map (·.1) |>.eraseDups |>.toArray
  let results := arr report "results"
  return Json.mkObj [("tag",toJson tag),("clients",report.getObjValD "clients"),("wallMs",report.getObjValD "wallMs"),
    ("completed",toJson (results.filter (fun result => result.getObjValD "completed" == toJson true)).size),
    ("latencyMs",distribution (results.map (nat · "elapsedMs"))),
    ("failures",toJson (results.filter (fun result => result.getObjValD "completed" != toJson true) |>.map fun result =>
      Json.mkObj [("case",result.getObjValD "case"),("elapsedMs",result.getObjValD "elapsedMs"),("error",result.getObjValD "error"),
        ("returnedProfiles",toJson (arr result "profiles").size)])),
    ("returnedRpcs",toJson replies),("requestBytes",distribution requests),("responseBytes",distribution responses),
    ("spans",toJson (names.map fun name => Json.mkObj [("stage",toJson name),
      ("wallMs",distribution (spans.filterMap fun (stage,ms) => if stage == name then some ms else none))])),
    ("overlappingWallSpansNotAdditive",toJson true),("failedCurrentRpcsUnobserved",toJson true)]
def main (_ : List String) : IO Unit := do
  let mut summaries := #[]
  let mut allRuns := #[]
  for study in ["numerical-protocol","numerical-capacity","owned-receive"] do
    let destination := workspace/"docs/candidates"/study
    let mut runs := #[]
    let mut guards := #[]
    for entry in ← base.readDir do
      unless entry.fileName.startsWith (study++"-") && entry.fileName.endsWith ".guard.json" &&
        !entry.fileName.contains "records" && !entry.fileName.contains "retire" && !entry.fileName.contains "completion" do continue
      let guard ← read entry.path
      check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "protocol workload not drained"
      let pid := nat guard "guardPid"
      let process ← IO.Process.output {cmd := "/bin/ps",args := #["-p",toString pid,"-o","command="]}
      let tag := entry.fileName.dropEnd 11 |>.toString
      check (!process.stdout.contains (base/(tag++".guard-settings.json")).toString) "protocol guard still live"
      let root := base/(tag++"-result")
      let log := base/(tag++".log")
      let logText ← if ← log.pathExists then IO.FS.readFile log else pure ""
      let errors := logText.splitOn "\n" |>.filter (fun line =>
        line.contains "error" || line.contains "failed" || line.contains "exception" || line.contains "Warning:") |>.take 20
      guards := guards.push (Json.mkObj [("tag",toJson tag),("guard",guard),
        ("logSha256",toJson (← hash log)),("errors",toJson errors)])
      unless ← (root/"report.json").pathExists do continue
      let report ← read (root/"report.json")
      if report.getObjValD "clients" == Json.null then continue
      let frozen ← read (root/"frozen.json")
      let shutdown ← read (root/"shutdown.json")
      check (report.getObjValD "ordinaryAndObservedControlEqual" == toJson true &&
        report.getObjValD "originalHeadsUnchanged" == toJson true && shutdown.getObjValD "releasedLastKeeper" == toJson true)
        "protocol control/source/lifecycle check failed"
      let run := Json.mkObj [("tag",toJson tag),("report",report),("frozen",frozen),
        ("prime",← read (root/"prime.json")),("shutdown",shutdown),("reportSha256",toJson (← hash (root/"report.json")))]
      runs := runs.push run
      allRuns := allRuns.push run
      summaries := summaries.push (← summarize tag report)
    let checks ← if study == "owned-receive" && (← (base/"owned-receive-checks1-result/waits.json").pathExists) then
      read (base/"owned-receive-checks1-result/waits.json") else pure Json.null
    IO.FS.writeFile (destination/(if study == "owned-receive" then "protocol-evidence.json" else "evidence.json")) (Json.mkObj [("runs",toJson runs),("guards",toJson guards),("nativeLifetimeChecks",checks),
      ("answeringModelCalls",toJson (0 : Nat)),("paidComparisons",toJson "0/18"),("adopted",toJson false)]).compress
  let mut comparisons := #[]
  for (leftStudy,rightStudy,suffix) in [("numerical-protocol","numerical-capacity","sixteen1"),
      ("numerical-protocol","numerical-capacity","eighty1"),("numerical-capacity","owned-receive","sixteen1"),
      ("numerical-capacity","owned-receive","eighty1")] do
    let left := allRuns.find? (fun row => row.getObjValD "tag" == toJson (leftStudy++"-"++suffix))
    let right := allRuns.find? (fun row => row.getObjValD "tag" == toJson (rightStudy++"-"++suffix))
    if let some left := left then
      if let some right := right then
        check ((left.getObjValD "frozen") == (right.getObjValD "frozen")) "capacity comparison changed fixed sources or row order"
        let parent := arr (left.getObjValD "report") "results"
        let candidate := arr (right.getObjValD "report") "results"
        let mut same := 0
        let mut regressions := #[]
        for prior in parent do
          let some next := candidate.find? (fun row => row.getObjValD "case" == prior.getObjValD "case") |
            throw (IO.userError "candidate lost a requested case")
          if prior.getObjValD "completed" == toJson true then
            if next.getObjValD "completed" != toJson true then regressions := regressions.push (next.getObjValD "case")
            else
              check (prior.getObjValD "scoreSha256" == next.getObjValD "scoreSha256") "original scores changed"
              same := same+1
        comparisons := comparisons.push (Json.mkObj [("parent",toJson leftStudy),("candidate",toJson rightStudy),
          ("wave",toJson suffix),("sameScoreDigests",toJson same),
          ("regressions",toJson regressions)])
  IO.FS.writeFile (workspace/"docs/candidates/numerical-protocol/summary.json") (Json.mkObj [("runs",toJson summaries),
    ("comparisons",toJson comparisons),("notWholeHookOrEvidenceDelivery",toJson true),("adopted",toJson false)]).pretty
