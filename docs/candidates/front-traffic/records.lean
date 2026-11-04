import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean

def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def output : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/front-traffic"
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def save (name : String) (value : Json) : IO Unit := IO.FS.writeFile (output/name) (value.pretty++"\n")
def hashFile (path : System.FilePath) : IO String := do
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  unless result.exitCode == 0 do throw (IO.userError "hash command failed")
  pure ((result.stdout.splitOn " ").head!)
def keep (name : String) : IO Unit := do IO.FS.writeFile (output/name) (← IO.FS.readFile (base/name))
def hashOutput (text : String) : IO String := do
  let scratch := base/"front-traffic-receiver-output"
  IO.FS.writeFile scratch text
  try hashFile scratch finally IO.FS.removeFile scratch
def hasFields (body : String) (labels : List String) : Bool := labels.all fun label =>
  body.contains ("observed-head-"++label++"-7b319c") && body.contains ("observed-tail-"++label++"-d82a04")
def trial (tag : String) (clients : Nat) : IO Json := do
  let root := base/("front-traffic-fixture-"++tag)
  let mut hooks : Array Json := #[]
  let mut outputs : Array (String × String) := #[]
  let mut delivered : Array Nat := #[]
  let mut promptTimes : Array Nat := #[]
  let mut errors : Array (String × Nat) := #[]
  for entry in ← root.readDir do
    if !entry.fileName.endsWith "-measurement.json" then continue
    let row ← read entry.path
    let path := root/(entry.fileName.replace "-measurement.json" ".json")
    let expected ← IO.ofExcept (row.getObjValAs? String "outputSha256")
    if !(outputs.any (·.1 == expected)) then
      let received ← IO.FS.readFile path
      unless received.endsWith "\n" do throw (IO.userError "receiver file lost its recorded terminator")
      let native := (received.dropEnd 1).toString
      unless (← hashOutput native) == expected do throw (IO.userError s!"actual receiver output hash changed: {path}")
      outputs := outputs.push (expected,native)
    let body := (row.getObjValAs? String "body").toOption.getD ""
    let isInitial := entry.fileName.startsWith "writer-" && entry.fileName.endsWith "-initial-UserPromptSubmit-measurement.json"
    let complete := !body.startsWith "EGGSHELL SEARCH INCOMPLETE"
    if isInitial then
      let ms ← IO.ofExcept (row.getObjValAs? Nat "elapsedMs")
      promptTimes := promptTimes.push ms
      if hasFields body ["seed-alpha","seed-tail"] then delivered := delivered.push ms
      let id ← IO.ofExcept (row.getObjValAs? String "receipt")
      let path := root/"private"/"receipts"/id/"dispatch.json"
      if ← path.pathExists then
        let dispatch ← read path
        if let .ok text := (dispatch.getObjValD "data").getObjValAs? String "error" then
          let key := if text.contains "state.guard" then "terminal state.guard error; not time-attributed" else text
          if let some index := errors.findIdx? (·.1 == key) then errors := errors.modify index fun (key,n) => (key,n+1)
          else errors := errors.push (key,1)
    hooks := hooks.push (Json.mkObj [("file",toJson entry.fileName),("event",row.getObjValD "event"),
      ("session",row.getObjValD "session"),("receipt",row.getObjValD "receipt"),
      ("elapsedMs",row.getObjValD "elapsedMs"),("outputSha256",toJson expected),
      ("hasAllSeedFields",if isInitial then toJson (hasFields body ["seed-alpha","seed-tail"]) else Json.null),
      ("completeNoticeCheck",toJson complete),("acknowledged",row.getObjValD "acknowledged"),
      ("ackRequested",row.getObjValD "ackRequested"),("ackError",row.getObjValD "ackError")])
  save (tag++"-delivery.json") (Json.mkObj [("hooks",toJson hooks),("actualOutputsBySha256",toJson outputs)])
  let mut artifacts := #[]
  for name in ["frozen-seed.json","seed-originals.json","seed-drain.json","writers-originals.json",
      "writers-drain.json","frozen-readback.json","report.json","retained-original-audit.json"] do
    if ← (root/name).pathExists then
      let value ← read (root/name)
      let value ← if name.endsWith "-drain.json" then do
          let rows ← IO.ofExcept (fromJson? (α := Array Json) value)
          let samples := rows.map fun row => Json.mkObj (["elapsedMs","queuesEmpty","preparedSources","preparation","operations"].map fun field => (field,row.getObjValD field))
          pure (Json.mkObj [("rawSha256",toJson (← hashFile (root/name))),
            ("samples",toJson samples)])
        else pure value
      artifacts := artifacts.push (name,value)
  save (tag++"-originals.json") (toJson artifacts)
  let writers ← if ← (root/"writers-results.json").pathExists then read (root/"writers-results.json") else pure Json.null
  let errorRows := (writers.getObjValAs? (Array Json) "errors").toOption.getD #[]
  let loops := (writers.getObjValAs? (Array Json) "rows").toOption.getD #[]
  let mut bounds := #[]
  for event in ["UserPromptSubmit","PreToolUse","PostToolUse","Stop"] do
    let values := hooks.filter (fun row => row.getObjValD "event" == toJson event)
    let times := values.map fun row => (row.getObjValAs? Nat "elapsedMs").toOption.getD 0
    bounds := bounds.push (Json.mkObj [("event",toJson event),("observations",toJson times.size),
      ("minMs",if times.isEmpty then Json.null else toJson (times.foldl min 999999)),
      ("maxMs",if times.isEmpty then Json.null else toJson (times.foldl max 0))])
  return Json.mkObj [("trial",toJson tag),("clients",toJson clients),
    ("writerLoops",toJson loops.size),("writerErrors",toJson errorRows),
    ("initialBodiesWithAllFourFields",toJson delivered.size),("initialPrompts",toJson promptTimes.size),
    ("initialMinMs",toJson (promptTimes.foldl min 999999)),("initialMaxMs",toJson (promptTimes.foldl max 0)),
    ("terminalDispatchErrors",toJson errors),("eventObservedBounds",Json.arr bounds),
    ("guard",← read (base/("front-traffic-"++tag++".guard.json")))]

def compactRecords : IO Unit := do
  for (suffix,target) in [("delivery","deliveries.json"),("originals","originals.json")] do
    let mut grouped := #[]
    for tag in ["preflight1","preflight2","preflight3","small1","small2","small3","profile1"] do
      let path := output/(tag++"-"++suffix++".json")
      grouped := grouped.push (tag,← read path)
    IO.FS.writeFile (output/target) ((toJson grouped).compress++"\n")
    for (tag,_) in grouped do IO.FS.removeFile (output/(tag++"-"++suffix++".json"))
  let mut validations := #[]
  for name in ["front-traffic-build8.guard.json","front-traffic-build9.guard.json","front-traffic-build12.guard.json",
      "front-traffic-proofs4.guard.json","front-traffic-contract2.guard.json","front-traffic-deadlines3.guard.json"] do
    validations := validations.push (name,← read (output/name))
  IO.FS.writeFile (output/"validation.json") ((toJson validations).compress++"\n")
  for (name,_) in validations do IO.FS.removeFile (output/name)
  let audit := output/"contract-audit.txt"
  let auditHash ← hashFile audit
  let lines := (← IO.FS.readFile audit).splitOn "\n"
  IO.FS.writeFile audit ("Full ContractAudit exited successfully; see validation.json.\nFull output SHA-256: "++auditHash++"\nFinal audit messages:\n"++String.intercalate "\n" (lines.drop (lines.length-11)))
  for name in ["runtime.sha256","candidate-runtime.sha256","profile-runtime.sha256"] do
    if ← (output/name).pathExists then IO.FS.removeFile (output/name)
  IO.println "Consolidated native records and actual outputs; no DB or cache archived."

def main (args : List String) : IO Unit := do
  if args == ["compact"] then return ← compactRecords
  for entry in ← base.readDir do
    if entry.fileName.startsWith "front-traffic-" && entry.fileName.endsWith ".guard.json" then
      let guard ← read entry.path
      unless guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do
        throw (IO.userError "work is still owned")
  let mut trials := #[]
  for (tag,count) in [("preflight1",1),("preflight2",1),("preflight3",1),("small1",80),("small2",80),("small3",80),("profile1",80)] do
    trials := trials.push (← trial tag count)
  save "native-trials.json" (Json.mkObj [("trials",Json.arr trials),("adopted",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("matchedPaidComparisons",toJson (0 : Nat))])
  for name in ["front-traffic-build8.guard.json","front-traffic-build9.guard.json","front-traffic-build12.guard.json",
      "front-traffic-proofs4.guard.json","front-traffic-contract2.guard.json","front-traffic-deadlines3.guard.json"] do keep name
  for (folder,name) in [("front-traffic-fixture-deadlines3/report.json","task-deadline-report.json"),
      ("front-traffic-fixture-deadlines3/fast-provider.json","task-deadline-fast-provider.json"),
      ("front-traffic-proofs4.log","task-deadline-laws.txt"),("front-traffic-contract2.log","contract-audit.txt")] do
    IO.FS.writeFile (output/name) (← IO.FS.readFile (base/folder))
  let mut patch := ""
  let mut identities := #[]
  for name in ["Daemon.lean","DaemonWire.lean","KeyedSearchClient.lean","Numerical.lean","SemanticMatcher.lean","TaskDeadline.lean"] do
    let old := base/"front-traffic-baseline-core"/"Eggshell"/name
    let current := base/"interest-traffic-core"/"Eggshell"/name
    let result ← IO.Process.output {cmd := "git",args := #["diff","--no-index","--",
      if ← old.pathExists then old.toString else "/dev/null",current.toString]}
    unless result.exitCode ≤ 1 do throw (IO.userError "source patch failed")
    patch := patch ++ (result.stdout.replace ("a"++(base/"front-traffic-baseline-core").toString++"/") "a/"
      |>.replace ("b"++(base/"interest-traffic-core").toString++"/") "b/"
      |>.replace ("a"++(base/"interest-traffic-core").toString++"/") "a/")
    identities := identities.push (name,← hashFile current)
  IO.FS.writeFile (output/"candidate.patch") patch
  save "core-identity.json" (toJson identities)
  let mut profiles := #[]
  for offset in [6000,16000,26000] do
    let path := base/"front-traffic-fixture-profile1"/s!"frontend-{offset}.sample.txt"
    let lines := (← IO.FS.readFile path).splitOn "\n" |>.toArray
    let fragments := ["Total number in stack", "l_Eggshell_OwnerViews_load_x3f", "l_Eggshell_Plugin_OperationWire_waitNative"].map fun target =>
      let index := (lines.findIdx? (·.contains target)).getD 0
      (target,index+1,lines.extract (index-5) (index+32))
    profiles := profiles.push (Json.mkObj [("offsetMs",toJson offset),("rawSha256",toJson (← hashFile path)),
      ("sample",← read (path.withExtension "json")),("fragments",toJson fragments)])
  save "profile-observations.json" (Json.mkObj [("profiles",toJson profiles),
    ("interpretation",toJson "Front-end samples show operation transport waiting and repeated prepared/owner metadata reads. Terminal state.guard errors do not attribute prior elapsed time to a state-lock holder. No causal speed or capacity claim from the sampled trial.")])
  for value in trials do
    IO.println (Json.mkObj (["trial","writerLoops","initialBodiesWithAllFourFields","initialPrompts","initialMinMs","initialMaxMs"].map fun field => (field,value.getObjValD field))).compress
  compactRecords
