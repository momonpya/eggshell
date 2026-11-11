import tools.research.StudyLocal
open Lean StudyLocal
namespace RegisteredHookRecords

def root := base/"practical-runtime/registered-hooks"
def area := root/"run"
def records := project/"docs/practical-runtime/registered-hooks"

def stopped : IO Json := do
  let value ← read (base/"practical-registered-hooks-native.guard.json")
  check (value.getObjValD "state" == toJson "finished" &&
    value.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "traffic still owns processes"
  return value

def prepareInspect : IO Unit := do
  idle
  discard <| stopped
  discard <| finished "practical-registered-hooks-inspect-build"
  guard "practical-registered-hooks-inspection" #[(root/"build/StudyMain").toString,
    "shared-traffic-inspect",area.toString,(records/"source-inspection.json").toString]

def audit : IO Unit := do
  let frozen ← IO.ofExcept ((← read (area/"frozen-before-delivery.json")).getArr?)
  let mut audited := #[]
  for wave in [1,2] do
    let outcomes ← IO.ofExcept ((← read (area/s!"wave-{wave}-outcomes.json")).getObjValAs? (Array Json) "outcomes")
    for outcome in outcomes do
      if outcome.getObjValD "kind" != toJson "llvm-reader" then continue
      let number ← IO.ofExcept (outcome.getObjValAs? Nat "topic")
      let some topic := frozen.find? (fun row => row.getObjValD "topic" == toJson number) |
        throw (IO.userError "unknown frozen topic")
      let delivery := outcome.getObjValD "delivery"
      let session ← IO.ofExcept (delivery.getObjValAs? String "session")
      let call := area/"calls"/session/"prompt"
      let input := root/(session++"-postmortem-input.json")
      let output := records/(session++"-audit.json")
      check (!(← output.pathExists)) "preserve previous original-evidence audit"
      let specification := Json.mkObj [("source",topic.getObjValD "source"),("database",toJson (area/"llvm.egg").toString),
        ("request",toJson (call/"stdin").toString),("stdout",toJson (call/"stdout").toString),
        ("timing",toJson (call/"record.json").toString),("body",delivery.getObjValD "body")]
      if ← input.pathExists then check ((← read input) == specification) "existing audit input changed"
      else write input specification
      discard <| command (root/"build/StudyMain").toString #["audit","emit",input.toString,output.toString]
      let result ← read output
      check (result.getObjValD "availableEvidence" == topic.getObjValD "frozen") "frozen denominator changed"
      check ((result.getObjValD "requiredDelivery").getObjValD "targetMet" == toJson true &&
        (result.getObjValD "availableDelivery").getObjValD "targetMet" == toJson true) "required evidence omitted"
      audited := audited.push (Json.mkObj [("wave",toJson wave),("topic",toJson number),
        ("audit",result),("timing",← read (call/"record.json"))])
  check (audited.size == 6) "both completed waves required"
  write (records/"llvm-audits.json") (toJson audited)

def prepareAudits (tag : String) : IO Unit := do
  idle
  discard <| stopped
  discard <| finished "practical-registered-hooks-inspection"
  guard tag #["/usr/bin/env","LEAN_PATH="++(base/"study-local-lib").toString,
    (compiler/"bin/lean").toString,"-j1","-M768","--run",
    (project/"tools/research/RegisteredHookRecords.lean").toString,"__audit"]

def prepareResume (tag : String) : IO Unit := do
  idle
  discard <| stopped
  discard <| finished "practical-registered-hooks-audits"
  let input ← read (root/"run-input.json")
  let environment : Array (String × Option String) ← IO.ofExcept
    (fromJson? ((input.getObjValD "installation").getObjValD "environment"))
  let unset := environment.filterMap fun (key,value) => if value.isNone then some key else none
  let assigned := environment.filterMap fun (key,value) => value.map (fun text => key++"="++text)
  guard tag (#["/usr/bin/env"] ++
    unset.flatMap (fun key => #["-u",key]) ++ assigned ++ #[(root/"build/StudyMain").toString,
      "shared-traffic-resume",(root/"run-input.json").toString,area.toString,(records/"resumed.json").toString])

def retainBodies : IO Unit := do
  idle
  discard <| stopped
  IO.FS.createDirAll (records/"bodies")
  IO.FS.createDirAll (records/"responses")
  let mut retained := #[]
  for wave in [1,2] do
    let outcomes ← IO.ofExcept ((← read (area/s!"wave-{wave}-outcomes.json")).getObjValAs? (Array Json) "outcomes")
    for outcome in outcomes do
      if outcome.getObjValD "kind" == toJson "writer" then continue
      let delivery := outcome.getObjValD "delivery"
      let session ← IO.ofExcept (delivery.getObjValAs? String "session")
      let body := System.FilePath.mk (← IO.ofExcept (delivery.getObjValAs? String "body"))
      let call := area/"calls"/session/"prompt"
      let timing ← read (call/"record.json")
      let digest ← hash body
      let stdoutDigest ← hash (call/"stdout")
      check (delivery.getObjValD "bodySha256" == toJson digest &&
        timing.getObjValD "stdoutSha256" == toJson stdoutDigest) "actual delivery changed"
      let (retainedBody,retainedReply) ← if outcome.getObjValD "kind" == toJson "llvm-reader" then do
          let topic ← IO.ofExcept (outcome.getObjValAs? Nat "topic")
          let previous := project/"docs/practical-runtime/recovery"/s!"topic-{topic}"
          check ((← hash (previous/"body.txt")) == digest && (← hash (previous/"stdout.json")) == stdoutDigest)
            "previous original bytes differ from the current installed-command reply"
          pure (previous/"body.txt",previous/"stdout.json")
        else do
          let target := records/"bodies"/(digest++".txt")
          let reply := records/"responses"/(stdoutDigest++".json")
          if !(← target.pathExists) then IO.FS.writeBinFile target (← IO.FS.readBinFile body)
          if !(← reply.pathExists) then IO.FS.writeBinFile reply (← IO.FS.readBinFile (call/"stdout"))
          check ((← hash target) == digest && (← hash reply) == stdoutDigest) "retained actual reply differs"
          pure (target,reply)
      retained := retained.push (Json.mkObj [("wave",toJson wave),("kind",outcome.getObjValD "kind"),
        ("topic",outcome.getObjValD "topic"),("delivery",delivery),("request",← read (call/"stdin")),
        ("timing",timing),("retainedBody",toJson retainedBody.toString),("retainedStdout",toJson retainedReply.toString)])
  check (retained.size == 12) "both completed traffic waves required"
  write (records/"deliveries.json") (toJson retained)

def pendingSummary (value : Json) : Json := Json.mkObj [
  ("session",value.getObjValD "sessionId"),("turn",value.getObjValD "turnId"),
  ("closed",value.getObjValD "closed"),("hasFinalMessage",toJson (value.getObjValD "finalMessage" != Json.null)),
  ("tools",toJson ((value.getObjValAs? (Array Json) "tools").toOption.map Array.size |>.getD 0))]

def summary : IO Unit := do
  let calls ← IO.ofExcept ((← read (records/"actual-hooks.json")).getArr?)
  let mut timing := #[]
  for event in ["UserPromptSubmit","PreToolUse","PostToolUse","Stop","PostCompact","Interrupt","SessionEnd"] do
    let selected := calls.filter fun row => (row.getObjValD "registration").getObjValD "event" == toJson event
    let elapsed ← selected.mapM fun row => IO.ofExcept ((row.getObjValD "timing").getObjValAs? Nat "elapsedMs")
    timing := timing.push (Json.mkObj [("event",toJson event),("count",toJson elapsed.size),
      ("minMs",toJson (elapsed.foldl min 30000)),("maxMs",toJson (elapsed.foldl max 0)),
      ("stderrNonempty",toJson (selected.filter (fun row => row.getObjValD "stderr" != toJson "")).size)])
  let source ← read (records/"source-inspection.json")
  let audits ← IO.ofExcept ((← read (records/"llvm-audits.json")).getArr?)
  let traffic ← IO.ofExcept ((← read (records/"failed-traffic.json")).getObjValAs? (Array Json) "waves")
  let counts := audits.map fun row => Json.mkObj [("topic",row.getObjValD "topic"),
    ("required",(row.getObjValD "audit").getObjValD "requiredDelivery"),
    ("partialIncluded",(row.getObjValD "audit").getObjValD "availableDelivery")]
  let resumed ← if ← (records/"resumed.json").pathExists then do
      let value := (← read (records/"resumed.json")).getObjValD "result"
      pure (Json.mkObj [("success",value.getObjValD "success"),("elapsedMs",value.getObjValD "elapsedMs"),
        ("observations",(value.getObjValD "census").getObjValD "count"),("answers",value.getObjValD "answers")])
    else pure Json.null
  let result := Json.mkObj [("timing",toJson timing),("observationsBeforeResume",source.getObjValD "observations"),
    ("answersBeforeResume",toJson ((source.getObjValAs? (Array String) "answerSessions").toOption.map Array.size)),
    ("wavesMs",toJson (traffic.map (·.getObjValD "elapsedMs"))),
    ("llvm",toJson counts),("resume",resumed)]
  write (records/"summary.json") result
  IO.println result.compress

def settle : IO Unit := do
  idle
  let mut guards := []
  for name in ["practical-registered-hooks-inspection","practical-registered-hooks-audits",
      "practical-registered-hooks-continuation"] do guards := guards ++ [(name,← finished name)]
  write (records/"postmortem-guards.json") (Json.mkObj guards)
  write (records/"resume-stopped.json") (Json.mkObj [("frontend",← read (area/"resume-frontend-stop.json")),
    ("publisher",← read (area/"resume-publisher-stop.json"))])
  summary

partial def remove (path : System.FilePath) : IO (Nat × Nat) := do
  let metadata ← path.symlinkMetadata
  if metadata.type == .dir then
    let mut count := (0,0)
    for entry in ← path.readDir do
      let part ← remove entry.path
      count := (count.1+part.1,count.2+part.2)
    IO.FS.removeDir path
    return count
  IO.FS.removeFile path
  return (1,if metadata.type == .file then metadata.byteSize.toNat else 0)

def retire : IO Unit := do
  idle
  let failed ← stopped
  check (failed.getObjValD "exitCode" == toJson (1 : Nat)) "preserve the original failed outcome"
  discard <| finished "practical-registered-hooks-continuation"
  discard <| finished "practical-registered-hooks-audits"
  check (!(← (records/"retired.json").pathExists)) "preserve previous retirement"
  let deliveries ← IO.ofExcept ((← read (records/"deliveries.json")).getArr?)
  check (deliveries.size == 12 && (← (records/"queued-at-stop.json").pathExists)) "retain the failed actual lifecycle first"
  for row in deliveries do
    let body ← IO.ofExcept (row.getObjValAs? String "retainedBody")
    let stdout ← IO.ofExcept (row.getObjValAs? String "retainedStdout")
    check ((row.getObjValD "delivery").getObjValD "bodySha256" == toJson (← hash (.mk body))) "retained body changed"
    check ((row.getObjValD "timing").getObjValD "stdoutSha256" == toJson (← hash (.mk stdout))) "retained stdout changed"
  let saved ← read (project/"docs/practical-runtime/recovery/before-delivery.json")
  let original ← IO.ofExcept (saved.getObjValAs? String "source")
  let sourceFiles : Array (String × String) ← IO.ofExcept (saved.getObjValAs? _ "sourceFiles")
  let practical := base/"practical-runtime"
  let artifacts := #[practical/"coordinated-warm/build/StudyMain",practical/"build/StudyMain",
    base/"canonical-decoder-runtime/build/StudyMain",practical/"package/prefix/libexec/eggshell"]
  let before ← artifacts.mapM fun path => do pure (path,← hash path)
  for (name,digest) in sourceFiles do check ((← hash (System.FilePath.mk original/name)) == digest) "protected original changed"
  let processes ← command "/bin/ps" #["-axo","command="]
  check (!(processes.splitOn "\n").any fun line => line.trimAscii.toString.startsWith (base.toString++"/"))
    "experiment service or client is live"
  for build in [practical/"coordinated-warm/build",practical/"build",base/"canonical-decoder-runtime/build"] do
    for line in (← IO.FS.readFile (build/"runtime.rsp")).splitOn "\n" do
      if line.trimAscii.isEmpty then continue
      let path : System.FilePath := .mk (← IO.ofExcept (Json.parse line >>= Json.getStr?))
      if path.isAbsolute then
        check (!(← IO.FS.realPath path).toString.startsWith (root.toString++"/")) "current native input belongs to ended trial"
  check (!(← IO.FS.realPath (practical/"coordinated-warm/prefix/share/eggshell/minilm")).toString.startsWith (root.toString++"/"))
    "current model belongs to ended trial"
  let removed ← remove root
  for (path,digest) in before do check ((← hash path) == digest) "protected runtime changed"
  for (name,digest) in sourceFiles do check ((← hash (System.FilePath.mk original/name)) == digest) "protected original changed during removal"
  write (records/"retired.json") (Json.mkObj [("files",toJson removed.1),("logicalBytes",toJson removed.2),
    ("archiveCreated",toJson false),("protectedHashesUnchanged",toJson true),("failedTrafficRemainsFailed",toJson true)])

def tidy : IO Unit := do
  idle
  let names := ["first-build.guard.json","first-build-errors.txt","second-build.guard.json","second-build-errors.txt",
    "audit-start-failure.guard.json","audit-dispatch-failure.guard.json","recovery-build-failure.guard.json",
    "recovery-build-errors.txt","recovery-argument-failure.guard.json","recovery-argument-errors.txt",
    "recovery-scan-failure.guard.json"]
  let mut failures := []
  for name in names do
    let value ← if name.endsWith ".json" then read (records/name)
      else toJson <$> IO.FS.readFile (records/name)
    failures := failures ++ [(name,value)]
  let merged := Json.mkObj failures
  check (!(← (records/"helper-failures.json").pathExists)) "preserve previous helper-failure summary"
  write (records/"helper-failures.json") merged
  check ((← read (records/"helper-failures.json")) == merged) "helper failures changed during consolidation"
  for name in names do IO.FS.removeFile (records/name)
  for row in ← IO.ofExcept ((← read (records/"llvm-audits.json")).getArr?) do
    let wave ← IO.ofExcept (row.getObjValAs? Nat "wave")
    let topic ← IO.ofExcept (row.getObjValAs? Nat "topic")
    let file := records/s!"reader-{wave}-{topic+2}-audit.json"
    check ((← read file) == row.getObjValD "audit") "individual original audit differs from retained combined record"
    IO.FS.removeFile file

def capture : IO Unit := do
  idle
  let guardResult ← stopped
  let mut calls := #[]
  let mut sessions := #[]
  for session in ← (area/"calls").readDir do
    for call in ← session.path.readDir do
      if !(← (call.path/"registration.json").pathExists) then continue
      let registration ← read (call.path/"registration.json")
      let timing ← read (call.path/"record.json")
      let response ← IO.FS.readFile (call.path/"stdout")
      check (timing.getObjValD "stdoutSha256" == toJson (← hash (call.path/"stdout"))) "actual reply changed"
      let event := registration.getObjValD "event"
      let compact := call.fileName == "compact-start"
      let terminal := ["Stop","PostCompact","Interrupt","SessionEnd"].any (fun name => event == toJson name)
      let empty := (Json.parse response).toOption == some (Json.mkObj [])
      if terminal || compact then check empty "registered fast hook returned an incomplete notice"
      let elapsed ← IO.ofExcept (timing.getObjValAs? Nat "elapsedMs")
      let budget ← IO.ofExcept (registration.getObjValAs? Nat "timeoutMs")
      check (timing.getObjValD "exitCode" == toJson (0 : Nat) && elapsed < budget) "installed budget violated"
      calls := calls.push (Json.mkObj [("session",toJson session.fileName),("label",toJson call.fileName),
        ("registration",registration),("timing",timing),("emptyCompletion",toJson empty),
        ("stderr",toJson (← IO.FS.readFile (call.path/"stderr")))])
    if !session.fileName.startsWith "traffic-" then continue
    check (!(← (session.path/"keep").pathExists)) "manual keep masked automatic saving"
    let directory := area/"data/sessions"/session.fileName
    let pending ← read (directory/"pending.json")
    let mut queued := #[]
    for name in ["checkpoints","deferred"] do
      let path := directory/name
      if !(← path.pathExists) then continue
      for entry in ← path.readDir do
        if !entry.fileName.endsWith ".json" then continue
        queued := queued.push (Json.mkObj [("queue",toJson name),("name",toJson entry.fileName),
          ("sha256",toJson (← hash entry.path)),("pending",pendingSummary (← read entry.path))])
    sessions := sessions.push (Json.mkObj [("session",toJson session.fileName),
      ("pending",pendingSummary pending),("queued",toJson queued)])
  let mut waves := #[]
  for wave in [1,2] do
    let value ← read (area/s!"wave-{wave}-outcomes.json")
    let mut outcomes := #[]
    for row in ← IO.ofExcept (value.getObjValAs? (Array Json) "outcomes") do
      if row.getObjValD "kind" == toJson "writer" then
        outcomes := outcomes.push (Json.mkObj [("kind",row.getObjValD "kind"),
          ("session",(row.getObjValD "output").getObjValD "session"),
          ("startedMs",row.getObjValD "startedMs"),("finishedMs",row.getObjValD "finishedMs")])
      else outcomes := outcomes.push row
    waves := waves.push (Json.mkObj [("wave",toJson wave),("elapsedMs",value.getObjValD "elapsedMs"),
      ("allProcessesSucceeded",value.getObjValD "allProcessesSucceeded"),("outcomes",toJson outcomes)])
  write (records/"actual-hooks.json") (toJson calls)
  write (records/"queued-at-stop.json") (toJson sessions)
  write (records/"failed-traffic.json") (Json.mkObj [("guard",guardResult),("waves",toJson waves),
    ("failedStage",toJson "second wave timed observation census"),("wholeSeriesPassed",toJson false),
    ("manualKeepUsed",toJson false),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false),
    ("frontendStop",← read (area/"frontend-stop.json")),("publisherStop",← read (area/"publisher-stop.json"))])
  write (records/"frozen-before-delivery.json") (← read (area/"frozen-before-delivery.json"))
  for name in ["baseline-auto-answers.json","baseline-facts.json","wave-1-auto-answers.json",
      "wave-1-census.json","wave-1-facts.json","wave-1-fast-events.json"] do
    write (records/name) (← read (area/name))
  IO.println (Json.mkObj [("hookCalls",toJson calls.size),("writerSessions",toJson sessions.size)]).compress

def main : List String → IO Unit
  | ["prepare-inspect"] => prepareInspect
  | ["prepare-audits",tag] => prepareAudits tag
  | ["prepare-resume",tag] => prepareResume tag
  | ["retain-bodies"] => retainBodies
  | ["summary"] => summary
  | ["settle"] => settle
  | ["retire"] => retire
  | ["tidy"] => tidy
  | ["__audit"] => audit
  | ["capture"] => capture
  | _ => throw (IO.userError "RegisteredHookRecords prepare-inspect|prepare-audits|capture")
end RegisteredHookRecords
def main := RegisteredHookRecords.main
