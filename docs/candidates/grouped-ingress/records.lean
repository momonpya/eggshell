import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def output := workspace/"docs/candidates/grouped-ingress"
def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
def hash (path : System.FilePath) : IO String := do
  let reply ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  unless reply.exitCode == 0 do throw (IO.userError "cannot seal candidate file")
  return (reply.stdout.splitOn " ").head!
def changed := ["Eggshell/SynapseJournal.lean","Eggshell/PreparationRegistry.lean","Eggshell/Worker.lean",
  "Eggshell/PreparationPlan.lean","Eggshell/PreparationService.lean","Eggshell/ContractAudit.lean",
  "tools/research/ProjectContextChecks.lean","tools/research/ProjectPreparationChecks.lean",
  "tools/research/FrontTrafficChecks.lean"]
def writePatch : IO Unit := do
  let parent := base/"grouped-ingress-baseline-core"
  let core := base/"interest-traffic-core"
  let mut patch := ""
  for name in changed do
    let reply ← IO.Process.output {
      cmd := "/usr/bin/git"
      args := #["diff","--no-index","--no-prefix","--unified=0","--",(parent/name).toString,(core/name).toString]}
    unless reply.exitCode ≤ 1 && reply.stderr.isEmpty do throw (IO.userError "cannot capture native delta")
    patch := patch++(reply.stdout.replace (parent.toString++"/") "a/" |>.replace (core.toString++"/") "b/"
      |>.replace ((parent.toString.drop 1).toString++"/") "a/"
      |>.replace ((core.toString.drop 1).toString++"/") "b/")
  IO.FS.writeFile (output/"candidate.patch") patch
def hashText (value : String) : IO String := do
  let reply ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256"]} (some value)
  unless reply.exitCode == 0 do throw (IO.userError "cannot seal received body")
  return (reply.stdout.splitOn " ").head!
def distribution (values : Array Nat) : Json := Id.run do
  let sorted := values.qsort (· < ·)
  return Json.mkObj [("samples",toJson sorted.size),("minimum",toJson sorted[0]?),
    ("median",toJson sorted[sorted.size/2]?),("maximum",toJson sorted.back?)]
def mixedEvidence : IO Json := do
  let root := base/"grouped-ingress-mixed1-result"
  let mut fixture := #[]
  for name in ["seed-originals.json","writers-originals.json","retained-original-audit.json",
      "seed-drain.json","writers-drain.json","frozen-seed.json","frozen-readback.json","report.json"] do
    if ← (root/name).pathExists then fixture := fixture.push (name,← read (root/name))
  let mut readers := #[]
  let mut writers := #[]
  let mut stages := #[]
  let mut bodies : Array (String × String) := #[]
  let mut elapsedValues := #[]
  let mut queueValues := #[]
  let mut workValues := #[]
  let mut delivered := 0
  let mut semantic := 0
  let mut lexical := 0
  let mut admitted := 0
  let mut captured := 0
  for entry in ← root.readDir do
    let reader := entry.fileName.startsWith "reader-" && entry.fileName.endsWith "-readback-UserPromptSubmit-measurement.json"
    let writer := entry.fileName.startsWith "writer-" && entry.fileName.endsWith "-measurement.json"
    if !reader && !writer then continue
    let row ← read entry.path
    let body ← IO.ofExcept (row.getObjValAs? String "body")
    let digest ← hashText body
    let received ← IO.FS.readFile (root/(entry.fileName.replace "-measurement.json" ".json"))
    unless received.endsWith "\n" && toJson (← hashText (received.dropEnd 1).toString) == row.getObjValD "outputSha256" do
      throw (IO.userError "actual mixed hook bytes differ from receipt")
    let compact := row.setObjVal! "body" Json.null |>.setObjVal! "bodySha256" (toJson digest)
      |>.setObjVal! "bodyBytes" (toJson body.utf8ByteSize)
    if !bodies.any (·.1 == digest) then bodies := bodies.push (digest,body)
    if writer then
      writers := writers.push (entry.fileName,compact)
      continue
    let head := body.contains "\"observed-head-case-79-7b319c\""
    let tail := body.contains "\"observed-tail-case-79-d82a04\""
    let elapsed ← IO.ofExcept (row.getObjValAs? Nat "elapsedMs")
    elapsedValues := elapsedValues.push elapsed
    if head && tail && row.getObjValD "complete" == toJson true && elapsed < 30000 then delivered := delivered+1
    readers := readers.push (entry.fileName,compact.setObjVal! "head" (toJson head) |>.setObjVal! "tail" (toJson tail))
    let receipt ← IO.ofExcept (row.getObjValAs? String "receipt")
    let mut events := #[]
    for event in ← (root/"private/receipts"/receipt).readDir do
      if !event.fileName.endsWith ".json" then continue
      let keep := ["operation-","search-phase-","numerical-","worker-","provider-"].any (fun start => event.fileName.startsWith start) ||
        ["prepared-inputs-turn.json","prepared-reader-images.json","prepared-owner-bindings.json","search.json",
          "source-pin-groups-profile.json","handoff-cost-profile.json","failure.json","operation-service.json"].contains event.fileName
      if !keep then continue
      let value ← read event.path
      let data := value.getObjValD "data"
      if event.fileName == "search-phase-semantic.json" && data.getObjValD "status" == toJson "completed" then semantic := semantic+1
      if event.fileName == "search-phase-lexical.json" && data.getObjValD "status" == toJson "finished" then lexical := lexical+1
      if event.fileName == "prepared-inputs-turn.json" && data.getObjValD "status" == toJson "complete" then captured := captured+1
      if event.fileName.endsWith "-admitted.json" then admitted := admitted+1
      if event.fileName == "operation-service.json" then
        if let .ok n := data.getObjValAs? Nat "queueMs" then queueValues := queueValues.push n
        if let .ok n := data.getObjValAs? Nat "workMs" then workValues := workValues.push n
      events := events.push (event.fileName,value)
    stages := stages.push (entry.fileName,events)
  let results ← #["writers-results.json","readers-results.json"].filterMapM fun (name : String) => do
    if !(← (root/System.FilePath.mk name).pathExists) then return none
    let value ← read (root/System.FilePath.mk name)
    let rows := (value.getObjValAs? (Array Json) "rows").toOption.getD #[]
    return some (name,Json.mkObj [("successes",toJson rows.size),("errors",value.getObjValD "errors")])
  let summary := Json.mkObj [("readersObserved",toJson readers.size),("deliveredWithin30s",toJson delivered),
    ("semanticCompleted",toJson semantic),("lexicalCompleted",toJson lexical),
    ("completeCaptures",toJson captured),("admitted",toJson admitted),
    ("operationServiceObservations",toJson queueValues.size),
    ("failureInclusiveHookMs",distribution elapsedValues),("observedQueueMs",distribution queueValues),
    ("observedWorkMs",distribution workValues),("results",toJson results)]
  IO.FS.writeFile (output/"mixed-summary.json") summary.pretty
  return Json.mkObj [("runtimeSha256",toJson (← hash (base/"grouped-ingress-traffic-build/StudyMain"))),
    ("harnessSha256",toJson (← hash (workspace/"tools/research/FrontTrafficChecks.lean"))),
    ("summary",summary),("fixture",toJson fixture),("readerMeasurements",toJson readers),
    ("writerMeasurements",toJson writers),("stages",toJson stages),("actualBodies",toJson bodies),
    ("sameSnapshotCausalComparison",toJson false),("answeringModelCalls",toJson (0 : Nat))]
partial def erase (path : System.FilePath) : IO Nat := do
  let metadata ← path.symlinkMetadata
  if metadata.type == .dir then
    let mut bytes := 0
    for entry in ← path.readDir do bytes := bytes+(← erase entry.path)
    IO.FS.removeDir path
    return bytes
  unless metadata.type == .file || metadata.type == .symlink do throw (IO.userError "special file in ended fixture")
  IO.FS.removeFile path
  return metadata.byteSize.toNat
def cleanup : IO Unit := do
  unless (← (output/"evidence.json").pathExists) && !(← (output/"cleanup.json").pathExists) do
    throw (IO.userError "seal evidence before cleanup and preserve prior receipt")
  let mut removed := #[]
  for entry in ← base.readDir do
    if !entry.fileName.startsWith "grouped-ingress-" || !entry.fileName.endsWith ".guard.json" then continue
    let guard ← read entry.path
    unless guard.getObjValD "state" == toJson "finished" &&
        guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do throw (IO.userError "live native work")
  for tag in ["checks1","checks2","checks3","context1","context2","mixed1"] do
    let path := base/("grouped-ingress-"++tag++"-result")
    if ← path.pathExists then removed := removed.push (path.toString,← erase path)
  for entry in ← base.readDir do
    if entry.fileName.startsWith "grouped-ingress-" &&
        (entry.fileName.endsWith ".guard.json" || entry.fileName.endsWith ".guard-settings.json" ||
          entry.fileName.endsWith ".log") then removed := removed.push (entry.path.toString,← erase entry.path)
  IO.FS.writeFile (output/"cleanup.json") (Json.mkObj [("removed",toJson removed),
    ("apparentBytes",toJson (removed.foldl (fun n row => n+row.2) (0 : Nat))),
    ("activeOriginalsSourcesAndBuildInputsRetained",toJson true),("archiveCreated",toJson false)]).pretty
  IO.println (Json.mkObj [("removedPaths",toJson removed.size),
    ("apparentBytes",toJson (removed.foldl (fun n row => n+row.2) (0 : Nat))),("archiveCreated",toJson false)]).compress
def main (args : List String) : IO Unit := do
  if args == ["repair-patch"] then
    let evidence ← read (output/"evidence.json")
    let before ← hash (output/"candidate.patch")
    unless evidence.getObjValD "candidatePatchSha256" == toJson before do throw (IO.userError "prior patch identity changed")
    writePatch
    let after ← hash (output/"candidate.patch")
    let repaired := evidence.setObjVal! "candidatePatchSha256" (toJson after)
      |>.setObjVal! "patchPathRepair" (Json.mkObj [("beforeSha256",toJson before),("afterSha256",toJson after),
        ("previous",evidence.getObjValD "patchPathRepair"),
        ("reason",toJson "portable paths and zero-context patch for clean whitespace checks; native evidence unchanged")])
    IO.FS.writeFile (output/"evidence.json") (repaired.compress++"\n")
    IO.println (repaired.getObjValD "patchPathRepair").compress
    return
  if args == ["cleanup"] then return ← cleanup
  unless args.isEmpty do throw (IO.userError "only optional cleanup is supported")
  unless !(← (output/"evidence.json").pathExists) do throw (IO.userError "preserve sealed candidate evidence")
  let mut guards := #[]
  for entry in ← base.readDir do
    if !entry.fileName.startsWith "grouped-ingress-" || !entry.fileName.endsWith ".guard.json" then continue
    let guard ← read entry.path
    unless guard.getObjValD "state" == toJson "finished" &&
        guard.getObjValD "ownedPids" == toJson (#[] : Array Nat) do throw (IO.userError "candidate still owns running work")
    let tag := entry.fileName.replace ".guard.json" ""
    let text ← IO.FS.readFile (base/(tag++".log"))
    let lines := text.splitOn "\n"
    let errors := lines.filter (fun line => line.contains "error:" || line.contains "uncaught exception")
    guards := guards.push (entry.fileName,guard,Json.mkObj [("errors",toJson errors),
      ("tail",toJson (String.intercalate "\n" (lines.drop (lines.length-12)))),
      ("logSha256",toJson (← hash (base/(tag++".log"))))])
  let mut reports := #[]
  for path in [base/"grouped-ingress-checks3-result/result.json",
      base/"grouped-ingress-checks3-result/reference-proof/report.json",
      base/"grouped-ingress-context2-result/report.json",
      base/"grouped-ingress-context2-result/preparation-service-report.json"] do
    unless ← path.pathExists do throw (IO.userError s!"required native report missing: {path}")
    reports := reports.push (path.toString,← read path,← hash path)
  let core := base/"interest-traffic-core"
  let mut sources := #[]
  for name in ["SynapseJournal","PreparationRegistry","Worker","PreparationPlan","PreparationService","ContractAudit"] do
    let path := "Eggshell/"++name++".lean"
    sources := sources.push (path,← hash (base/"grouped-ingress-baseline-core"/path),← hash (core/path))
  let mut helpers := #[]
  for name in ["GroupedIngressChecks","ProjectContextChecks","ProjectPreparationChecks","FrontTrafficChecks"] do
    let path := "tools/research/"++name++".lean"
    -- Parent-native helpers already contain CLI adapters absent from the
    -- workspace entry points. Bind the actual compiled source explicitly.
    helpers := helpers.push (path,← hash (core/path),← hash (workspace/path))
  writePatch
  let mixed ← mixedEvidence
  let evidence := Json.mkObj [("candidate",toJson "grouped ingress"),("adopted",toJson false),
    ("runtimeSha256",toJson (← hash (base/"grouped-ingress-build/StudyMain"))),
    ("componentAndContextRuntimeSha256",toJson "96a55b1986a5409e3e55168449a65ce27e6d0ead331c7cbba5373e99cf372f96"),
    ("candidatePatchSha256",toJson (← hash (output/"candidate.patch"))),
    ("sources",toJson sources),("helpers",toJson helpers),("reports",toJson reports),
    ("guards",toJson guards),("mixed",mixed),
    ("recordingAttempts",toJson #["first: controller syntax/type errors before execution",
      "second: 512 MiB interpreter ceiling while retaining unneeded receipt trees; filter to measured phases",
      "third: polymorphic startsWith needed an explicit lambda; rejected before execution"]),
    ("answeringModelCalls",toJson (0 : Nat)),
    ("paidMatchedComparisonsCompleted",toJson (0 : Nat)),("sustained80PersonCapacityValidated",toJson false),
    ("currentCandidateMixed80TrialRecorded",toJson true),("real98PercentDeliveryValidated",toJson false)]
  IO.FS.writeFile (output/"evidence.json") (evidence.compress++"\n")
  IO.println (Json.mkObj [("sealedReports",toJson reports.size),("guards",toJson guards.size),
    ("runtimeSha256",evidence.getObjValD "runtimeSha256"),("adopted",toJson false)]).compress
