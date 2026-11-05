import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
import Std.Data.HashMap
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def destination : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/session-dispatch"
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def arr (value : Json) (key : String) : Array Json := (value.getObjValAs? (Array Json) key).toOption.getD #[]
def digest (value : String) : IO String := do
  let output ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256"]} (some value)
  check (output.exitCode == 0) "cannot hash actual bytes"
  return (output.stdout.splitOn " ").headD ""
def compactReceipt (value : Json) : Json := Json.mkObj (
  ["session","receipt","operation-service","search-phase-semantic","search-phase-lexical","transport","ack","published","actorFailures"].filterMap fun key =>
    let field := value.getObjValD key
    if field == Json.null then none else some (key,field))
def number (value : Json) (key : String) := (value.getObjValAs? Nat key).toOption.getD 0
def distribution (values : Array Nat) : Json := Id.run do
  let sorted := values.qsort (· < ·)
  return Json.mkObj [("count",toJson sorted.size),("min",toJson sorted[0]?),
    ("median",toJson sorted[sorted.size/2]?),("max",toJson sorted.back?)]
def verify (evidence bodies : Array Json) : IO Unit := do
  for entry in bodies do
    let body ← IO.ofExcept (entry.getObjValAs? String "body")
    check (entry.getObjValD "sha256" == toJson (← digest body) &&
      entry.getObjValD "utf8Bytes" == toJson body.utf8ByteSize) "retained body bytes changed"
  let mut outputs := 0
  let mut results := #[]
  for run in evidence do
    for row in arr run "rowsIncludingPrime" do
      let some entry := bodies[number row "bodyRef"]? | throw (IO.userError "missing retained actual body")
      let body ← IO.ofExcept (entry.getObjValAs? String "body")
      let index := number row "case"
      let both := body.contains s!"\"observed-head-case-{index}-7b319c\"" &&
        body.contains s!"\"observed-tail-case-{index}-d82a04\""
      check (toJson both == row.getObjValD "bothFields" && entry.getObjValD "utf8Bytes" == row.getObjValD "bodyBytes") "retained evidence fields disagree"
      outputs := outputs+1
    let measured := (arr run "rowsIncludingPrime").filter fun row =>
      !((row.getObjValAs? String "session").toOption.getD "").startsWith "cpu-prime-"
    if measured.isEmpty then continue
    let observations := ((arr run "waves").filter (fun wave => wave.getObjValD "name" != toJson "prime")).flatMap (arr · "receipts")
    let complete := observations.filter fun receipt =>
      let phase := receipt.getObjValD "search-phase-semantic"
      phase.getObjValD "status" == toJson "completed" && phase.getObjValD "hasHandoff" == toJson true
    let passed := measured.filter fun row => row.getObjValD "bothFields" == toJson true &&
      row.getObjValD "acknowledged" == toJson true && number row "elapsedMs" < 30000
    results := results.push (Json.mkObj [("tag",run.getObjValD "tag"),("queries",toJson measured.size),
      ("requiredOriginalAndAck",toJson passed.size),("semanticCompletedWithHandoff",toJson complete.size),
      ("latencyMs",distribution (measured.map (number · "elapsedMs"))),
      ("queueMs",distribution (observations.filterMap fun receipt =>
        ((receipt.getObjValD "operation-service").getObjValAs? Nat "queueMs").toOption)),
      ("emptySemanticCompletions",toJson (observations.filter fun receipt =>
        let phase := receipt.getObjValD "search-phase-semantic"
        phase.getObjValD "status" == toJson "completed" && phase.getObjValD "hasHandoff" == toJson false).size)])
  check (outputs == 70) "fixed pair output domain changed"
  IO.FS.writeFile (destination/"verification.json") (Json.mkObj [("actualOutputs",toJson outputs),
    ("distinctBodyDigests",toJson bodies.size),("runs",toJson results),("adopted",toJson false)]).pretty
def main (tags : List String) : IO Unit := do
  let evidencePath := destination/"evidence.json"
  let bodiesPath := destination/"bodies.json"
  let mut evidence : Array Json := #[]
  if ← evidencePath.pathExists then evidence := arr (← read evidencePath) "runs"
  let mut bodies : Array Json := #[]
  if ← bodiesPath.pathExists then bodies ← IO.ofExcept (← read bodiesPath).getArr?
  if tags == ["verify"] then return ← verify evidence bodies
  let mut indices : Std.HashMap String Nat := {}
  for entry in bodies.zipIdx do
    let body ← IO.ofExcept (entry.1.getObjValAs? String "body")
    indices := indices.insert body entry.2
  for tag in tags do
    check (tag.startsWith "session-dispatch-" && !evidence.any (fun run => run.getObjValD "tag" == toJson tag)) "fresh dispatch record required"
    let guard ← read (base/(tag++".guard.json"))
    check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "guard is not drained"
    let pid ← IO.ofExcept (guard.getObjValAs? Nat "guardPid")
    let probe ← IO.Process.output {cmd := "/bin/ps",args := #["-p",toString pid,"-o","pid="]}
    check (probe.exitCode != 0 && probe.stdout.trimAscii.isEmpty) "guard process still live"
    let root := base/(tag++"-result")
    let report ← if ← (root/"report.json").pathExists then read (root/"report.json") else pure Json.null
    let waves := (#[report.getObjValD "prime",report.getObjValD "first",report.getObjValD "second"]++arr report "remaining").filter (· != Json.null)
    let mut captured := #[]
    let mut observations := #[]
    for wave in waves do
      for row in arr wave "rows" do
        let session ← IO.ofExcept (row.getObjValAs? String "session")
        let raw ← IO.FS.readFile (root/(session++".stdout"))
        check (toJson (← digest raw) == row.getObjValD "stdoutSha256") "actual stdout changed"
        let output ← IO.ofExcept (Json.parse raw)
        let body := ((output.getObjValD "hookSpecificOutput").getObjValAs? String "additionalContext").toOption.getD ""
        let index ← match indices[body]? with
          | some index => pure index
          | none => do
            let index := bodies.size
            bodies := bodies.push (Json.mkObj [("body",toJson body),("sha256",toJson (← digest body)),("utf8Bytes",toJson body.utf8ByteSize)])
            indices := indices.insert body index
            pure index
        let indexCase ← IO.ofExcept (row.getObjValAs? Nat "case")
        let both := body.contains s!"\"observed-head-case-{indexCase}-7b319c\"" &&
          body.contains s!"\"observed-tail-case-{indexCase}-d82a04\""
        check (toJson both == row.getObjValD "bothFields" && toJson body.utf8ByteSize == row.getObjValD "bodyBytes") "independent original-field/body audit differs"
        captured := captured.push (row.setObjVal! "bodyRef" (toJson index))
      observations := observations.push (Json.mkObj [("name",wave.getObjValD "name"),("serviceStats",wave.getObjValD "serviceStats"),
        ("persistentCpu",wave.getObjValD "persistentCpu"),("receipts",toJson ((arr wave "receipts").map compactReceipt))])
    let mut fields := [("tag",toJson tag),("guard",guard),("rowsIncludingPrime",toJson captured),("waves",toJson observations)]
    for key in ["runtimeSha256","caseCount","concurrentClients","requestOwnedActors","originalHeadsUnchanged","independentSearchActors",
      "sameChatSequential","metadataAndCountBounds","saveLanesRemainIndependent","staleTokensRejected",
      "cancelledTaskJoinedPeerCompleted","expiredTaskJoined","actualHookCapacityTested"] do
      if report.getObjValD key != Json.null then fields := fields++[(key,report.getObjValD key)]
    if ← (base/(tag++".log")).pathExists then
      let log ← IO.FS.readFile (base/(tag++".log"))
      fields := fields++[("logSha256",toJson (← digest log))]
      if guard.getObjValD "exitCode" != toJson (0 : Nat) then fields := fields++[("failureLog",toJson log)]
    evidence := evidence.push (Json.mkObj fields)
  IO.FS.writeFile bodiesPath (toJson bodies).pretty
  IO.FS.writeFile evidencePath (Json.mkObj [("runs",toJson evidence),("actualBodies",toJson bodies.size),
    ("answeringModelCalls",toJson (0 : Nat)),("paidMatchedComparisons",toJson "0/18"),("adopted",toJson false)]).pretty
