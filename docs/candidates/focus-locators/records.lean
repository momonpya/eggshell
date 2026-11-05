import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
import Std.Data.HashMap
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def destination := workspace/"docs/candidates/focus-locators"
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def save (path : System.FilePath) (value : Json) : IO Unit := IO.FS.writeFile path value.pretty
def arr (value : Json) (key : String) : Array Json := (value.getObjValAs? (Array Json) key).toOption.getD #[]
def number (value : Json) (key : String) := (value.getObjValAs? Nat key).toOption.getD 0
def phases (report : Json) : Array Json :=
  (#[report.getObjValD "first",report.getObjValD "second"]++arr report "remaining").filter (· != Json.null)
def rows (report : Json) := (phases report).flatMap (arr · "rows")
def passed (row : Json) := row.getObjValD "bothFields" == toJson true &&
  row.getObjValD "complete" == toJson true && row.getObjValD "acknowledged" == toJson true &&
  number row "elapsedMs" < 30000
def distribution (values : Array Nat) : Json := Id.run do
  let sorted := values.qsort (· < ·)
  return Json.mkObj [("count",toJson sorted.size),("min",toJson sorted[0]?),
    ("median",toJson sorted[sorted.size/2]?),("max",toJson sorted.back?)]
def group (all : Array Json) (known : Bool) : Json := Id.run do
  let selected := all.filter fun row => ((number row "case" < 32 || number row "case" == 79) == known)
  return Json.mkObj [("count",toJson selected.size),("passed",toJson (selected.filter passed).size),
    ("failedCases",toJson (selected.filter (!passed ·) |>.map (·.getObjValD "case")))]
def digestFile (path : System.FilePath) : IO String := do
  let reply ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  unless reply.exitCode == 0 do throw (IO.userError "cannot digest retained evidence")
  return (reply.stdout.splitOn " ").headD ""
def digestText (value : String) : IO String := do
  let reply ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256"]} (some value)
  unless reply.exitCode == 0 do throw (IO.userError "cannot digest body bytes")
  return (reply.stdout.splitOn " ").headD ""
def compactReceipt (receipt : Json) : Json := Id.run do
  if (receipt.getObjValD "delivery-domain").getObjValD "focusCount" != Json.null then return receipt
  let keys := ["session","receipt","operation-service","search-phase-semantic",
    "search-phase-lexical","transport","ack","published"]
  let mut fields := keys.filterMap fun key =>
    let value := receipt.getObjValD key
    if value == Json.null then none else some (key,value)
  let domain := receipt.getObjValD "delivery-domain"
  if domain != Json.null then
    let ranking := arr domain "focusRanking"
    let session := (receipt.getObjValAs? String "session").toOption.getD ""
    let index := (session.splitOn "-").getLast?.bind String.toNat?
    let target := match index with
      | some 0 => "v11478008332843232939"
      | some 28 => "v14007067449864327121"
      | _ => ""
    let mut summary := [("nominatedCount",toJson (arr domain "nominated").size),
      ("hydratedCount",toJson (arr domain "hydrated").size),("focusCount",toJson ranking.size),
      ("canonicalUsedCount",toJson (arr domain "canonicalUsed").size),
      ("synapticComplete",domain.getObjValD "synapticComplete")]
    if !target.isEmpty then
      let position := if ranking.contains (toJson target) then some (ranking.toList.idxOf (toJson target)) else none
      summary := summary++[("auditedOriginal",toJson target),("auditedFocusRank",toJson position),
        ("auditedWindowPositions",toJson ((arr domain "focusPositions").filter (fun row =>
          (row.getArr?).toOption.bind (·[0]?) == some (toJson target))))]
    fields := fields++[("delivery-domain",Json.mkObj summary)]
  return Json.mkObj fields
def compactRetained : IO Unit := do
  let path := destination/"evidence.json"
  let evidence ← read path
  unless evidence.getObjValD "receiptProjection" == Json.null do
    throw (IO.userError "retained observations are already compact")
  let compactArm := fun arm : Json => arm.setObjVal! "waves" (toJson ((arr arm "waves").map fun wave =>
    wave.setObjVal! "receipts" (toJson ((arr wave "receipts").map compactReceipt))))
  let pairs := (arr evidence "pairs").map fun pair => pair.setObjVal! "arms" (toJson ((arr pair "arms").map compactArm))
  let result := evidence.setObjVal! "pairs" (toJson pairs)
    |>.setObjVal! "burst" (toJson ((arr evidence "burst").map compactArm))
    |>.setObjVal! "receiptProjection" (toJson "retain exact operation/phase/ACK observations and original-domain counts; omit repeated full nomination and domain arrays")
  let temporary := destination/"evidence.compact.json"
  save temporary result
  IO.FS.rename temporary path
  IO.println "compacted repeated nomination/domain metadata; all actual output and timing observations retained"
def capture (root : System.FilePath) (report : Json) (bodies : Array Json)
    (indices : Std.HashMap String Nat) : IO (Json × Array Json × Std.HashMap String Nat) := do
  let mut bodies := bodies
  let mut indices := indices
  let mut captured := #[]
  let all := arr (report.getObjValD "prime") "rows"++rows report
  for row in all do
    let session ← IO.ofExcept (row.getObjValAs? String "session")
    let raw := root/(session++".stdout")
    unless toJson (← digestFile raw) == row.getObjValD "stdoutSha256" do
      throw (IO.userError "captured output bytes changed")
    let output ← read raw
    let body ← IO.ofExcept ((output.getObjValD "hookSpecificOutput").getObjValAs? String "additionalContext")
    let head := s!"\"observed-head-case-{number row "case"}-7b319c\""
    let tail := s!"\"observed-tail-case-{number row "case"}-d82a04\""
    unless toJson (body.contains head && body.contains tail) == row.getObjValD "bothFields" &&
        toJson body.utf8ByteSize == row.getObjValD "bodyBytes" do
      throw (IO.userError "independent actual-body audit disagrees")
    let index ← match indices[body]? with
      | some index => pure index
      | none => do
        let index := bodies.size
        bodies := bodies.push (Json.mkObj [("sha256",toJson (← digestText body)),
          ("utf8Bytes",toJson body.utf8ByteSize),("body",toJson body)])
        indices := indices.insert body index
        pure index
    captured := captured.push (row.setObjVal! "bodyRef" (toJson index))
  let observations := phases report |>.map fun phase =>
    let receipts := arr phase "receipts"
    Json.mkObj [("name",phase.getObjValD "name"),("persistentCpu",phase.getObjValD "persistentCpu"),
      ("latencyMs",distribution ((arr phase "rows").map (number · "elapsedMs"))),
      ("queueMs",distribution (receipts.filterMap (fun r => ((r.getObjValD "operation-service").getObjValAs? Nat "queueMs").toOption))),
      ("workMs",distribution (receipts.filterMap (fun r => ((r.getObjValD "operation-service").getObjValAs? Nat "workMs").toOption))),
      ("receipts",toJson (receipts.map compactReceipt))]
  let result := Json.mkObj [("runtimeSha256",report.getObjValD "runtimeSha256"),
    ("caseCount",report.getObjValD "caseCount"),("concurrentClients",report.getObjValD "concurrentClients"),
    ("known",group (rows report) true),("heldOut",group (rows report) false),
    ("measuredLatencyMs",distribution ((rows report).map (number · "elapsedMs"))),
    ("rowsIncludingPrime",toJson captured),("waves",toJson observations),
    ("originalHeadsUnchanged",report.getObjValD "originalHeadsUnchanged")]
  return (result,bodies,indices)
def verifyRetained : IO Unit := do
  let evidence ← read (destination/"evidence.json")
  let bodies : Array Json ← IO.ofExcept ((← read (destination/"bodies.json")).getArr?)
  for entry in bodies do
    let body ← IO.ofExcept (entry.getObjValAs? String "body")
    unless entry.getObjValD "sha256" == toJson (← digestText body) &&
        entry.getObjValD "utf8Bytes" == toJson body.utf8ByteSize do
      throw (IO.userError "retained body digest or extent changed")
  let arms := (arr evidence "pairs").flatMap (arr · "arms")++arr evidence "burst"
  let mut observed := 0
  for arm in arms do
    let all := arr arm "rowsIncludingPrime"
    unless all.size == 83 && arm.getObjValD "originalHeadsUnchanged" == toJson true do
      throw (IO.userError "retained arm is incomplete")
    for row in all do
      let index ← IO.ofExcept (row.getObjValAs? Nat "bodyRef")
      let some entry := bodies[index]? | throw (IO.userError "retained body reference missing")
      let body ← IO.ofExcept (entry.getObjValAs? String "body")
      let head := s!"\"observed-head-case-{number row "case"}-7b319c\""
      let tail := s!"\"observed-tail-case-{number row "case"}-d82a04\""
      unless toJson (body.contains head && body.contains tail) == row.getObjValD "bothFields" &&
          row.getObjValD "bodyBytes" == entry.getObjValD "utf8Bytes" do
        throw (IO.userError "retained body fields disagree with observations")
      observed := observed+1
    for wave in arr arm "waves" do
      let observations := arr wave "receipts"
      for key in ["queueMs","workMs"] do
        let values := observations.filterMap fun r => ((r.getObjValD "operation-service").getObjValAs? Nat key).toOption
        unless distribution values == wave.getObjValD key do
          throw (IO.userError "retained operation distribution includes missing observations")
  unless observed == 664 && arms.size == 8 do throw (IO.userError "retained comparison domain changed")
  let heads : Array (String × String × String) ← IO.ofExcept (fromJson? (← read (workspace/"docs/candidates/worker-cpu/heads.json")))
  unless heads.size == 16 do throw (IO.userError "retained original source count changed")
  for (path,text,sha256) in heads do
    unless (← IO.FS.readFile (.mk path)) == text && (← digestFile (.mk path)) == sha256 do
      throw (IO.userError "current original head changed")
  let before ← read (destination/"identity-before.json")
  for label in ["parent","candidate"] do
    let identity := before.getObjValD label
    let path ← IO.ofExcept (identity.getObjValAs? String "path")
    unless toJson (← digestFile (.mk path)) == identity.getObjValD "sha256" do
      throw (IO.userError "retained target runtime identity changed")
  let guards := (← IO.ofExcept ((← read (destination/"guards.json")).getArr?))++
    (← IO.ofExcept ((← read (workspace/"docs/candidates/frame-reserve/guards.json")).getArr?))
  unless guards.size == 13 do throw (IO.userError "guard evidence is incomplete")
  for guard in guards do
    let record := guard.getObjValD "record"
    unless record.getObjValD "state" == toJson "finished" &&
        record.getObjValD "ownedPids" == toJson (#[] : Array Nat) &&
        record.getObjValD "guardTriggered" == toJson false do
      throw (IO.userError "guard evidence is not terminal or exceeded resources")
  save (destination/"verification.json") (Json.mkObj [("actualOutputs",toJson observed),
    ("distinctBodyDigests",toJson bodies.size),("sourceHeads",toJson heads.size),
    ("runtimeDigestsUnchanged",toJson true),("operationDistributionsExact",toJson true),
    ("terminalGuards",toJson guards.size),("productAdopted",toJson false)])
  IO.println "retained bodies, operation observations, source heads and runtime identities verified"
def main (args : List String) : IO Unit := do
  let [runName] := args | throw (IO.userError "completed paired run name required")
  if runName == "verify" then return ← verifyRetained
  if runName == "compact" then return ← compactRetained
  let monitor ← read (base/(runName++".guard.json"))
  unless monitor.getObjValD "state" == toJson "finished" &&
      monitor.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
    throw (IO.userError "paired guard is not terminal and drained")
  let pid ← IO.ofExcept (monitor.getObjValAs? Nat "guardPid")
  let probe ← IO.Process.output {cmd := "/bin/ps",args := #["-p",toString pid,"-o","pid="]}
  unless probe.exitCode != 0 && probe.stdout.trimAscii.toString.isEmpty do
    throw (IO.userError "paired guard PID is still present")
  let mut bodies : Array Json := #[]
  let mut indices : Std.HashMap String Nat := {}
  let mut pairs := #[]
  let frozen := workspace/"docs/candidates/worker-cpu/heads.json"
  let expected ← read frozen
  for index in [:3] do
    let mut arms := #[]
    for arm in ["parent","candidate"] do
      let root := base/s!"{runName}-pair-{index}-{arm}-result"
      unless (← read (root/"heads.json")) == expected do throw (IO.userError "comparison changed frozen source boundary")
      let report ← read (root/"report.json")
      let (captured,next,updated) ← capture root report bodies indices
      bodies := next
      indices := updated
      arms := arms.push (captured.setObjVal! "arm" (toJson arm))
    pairs := pairs.push (Json.mkObj [("pair",toJson index),("arms",toJson arms)])
  let admission ← read (base/(runName++"-burst-admission.json"))
  let mut burst := #[]
  if admission.getObjValD "burstAdmitted" == toJson true then
    for arm in ["parent","candidate"] do
      let root := base/(runName++"-burst-"++arm++"-result")
      unless (← read (root/"heads.json")) == expected do throw (IO.userError "burst changed frozen source boundary")
      let (captured,next,updated) ← capture root (← read (root/"report.json")) bodies indices
      bodies := next
      indices := updated
      burst := burst.push (captured.setObjVal! "arm" (toJson arm))
  save (destination/"evidence.json") (Json.mkObj [("pairs",toJson pairs),
    ("burstAdmission",admission),("burst",toJson burst),("answeringModelCalls",toJson (0 : Nat)),
    ("paidMatchedComparisons",toJson "0/18"),("adopted",toJson false),
    ("receiptProjection",toJson "retain exact operation/phase/ACK observations and original-domain counts; omit repeated full nomination and domain arrays")])
  save (destination/"bodies.json") (toJson bodies)
  IO.println (Json.mkObj [("pairs",toJson pairs.size),("burstArms",toJson burst.size),
    ("distinctActualBodies",toJson bodies.size)]).compress
