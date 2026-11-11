import tools.research.StudyLocal

open Lean StudyLocal
namespace InterruptedRecoveryStudy

def practical := base/"practical-runtime"
def cohort := practical/"cohort"
def acquisition := cohort/"study/seed-1"
def root := practical/"interrupted-recovery"
def records := project/"docs/practical-runtime/recovery"
def driver := practical/"build/StudyMain"
def runtimeHash := "7cc1432d2d3931a26d60e3e614807545e3f6b522737838bdabc1b1c626e657ab"

def artifact (path : System.FilePath) : IO Json := do
  return Json.mkObj [("path",toJson path.toString),("sha256",toJson (← hash path))]

/-- This controller only reads files and seals metadata. Every DB operation,
replay, warm, hook and evidence audit runs in the already verified native CLI. -/
def prepare : IO Unit := do
  idle
  let stopped ← read (cohort/"seed-1.guard.json")
  check (stopped.getObjValD "state" == toJson "finished" &&
    stopped.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "acquisition is still owned by a live process"
  check (!(← root.pathExists)) "preserve the previous recovery trial"
  let plan ← read (acquisition/"plan.json")
  let runtime ← IO.ofExcept ((plan.getObjValD "runtime").getObjValAs? String "path")
  check ((← hash (.mk runtime)) == runtimeHash) "fixed product changed"
  check ((← read (project/"docs/practical-runtime/interrupted-source.json")).getObjValD "complete" == toJson true)
    "source publication ancestry is incomplete"
  IO.FS.createDirAll root
  IO.FS.createDirAll records
  let mut files : Array (String × String) := #[]
  for entry in ← (acquisition/"work.egg").readDir do
    let stat ← entry.path.symlinkMetadata
    if stat.type == .dir then continue
    check (stat.type == .file) "source publication contains a symbolic link"
    files := files.push (entry.fileName,← hash entry.path)
  files := files.qsort (·.1 < ·.1)
  let definitions ← IO.ofExcept ((← read (base.parent.get!/"task-definitions.json")).getArr?)
  let mut frozen := #[]
  for topic in definitions do
    let number ← IO.ofExcept (topic.getObjValAs? Nat "topic")
    let prompt := cohort/s!"prompts/topic-{number}.txt"
    let expected ← IO.ofExcept ((topic.getObjValD "prompt").getObjValAs? String "sha256")
    check ((← hash prompt) == expected) "question differs from the existing task definition"
    frozen := frozen.push (topic.setObjVal! "prompt" (← artifact prompt))
  write (root/"definitions.json") (toJson frozen)
  write (records/"before-delivery.json") (Json.mkObj [
    ("source",toJson (acquisition/"work.egg").toString),("sourceFiles",toJson files),
    ("definitions",← artifact (root/"definitions.json")),
    ("runtime",plan.getObjValD "runtime"),("seedAccepted",toJson false),
    ("purpose",toJson "source-only recovery of an interrupted actual Codex session"),
    ("answeringModelCalls",toJson (0 : Nat)),("mayEnterModelTrials",toJson false),
    ("productChanges",toJson (0 : Nat)),("adopted",toJson false)])
  let workspace ← IO.ofExcept (plan.getObjValAs? String "workspace")
  guard "practical-recovery-availability" #[driver.toString,"read-coverage",
    (acquisition/"work.egg").toString,workspace,(root/"definitions.json").toString,
    (root/"read-coverage.json").toString]

def prepareTopics : IO Unit := do
  idle
  discard <| finished "practical-recovery-availability"
  let coverage ← read (root/"read-coverage.json")
  check (coverage.getObjValD "publicationUnchanged" == toJson true &&
    coverage.getObjValD "payloadMismatches" == toJson (#[] : Array Json) &&
    coverage.getObjValD "conflictingCanonicalRows" == toJson (0 : Nat)) "raw source read audit failed"
  let seedPlan ← read (acquisition/"plan.json")
  let frozen ← read (records/"before-delivery.json")
  let baseTemplate ← read (base/"candidate-template.json")
  let topics ← IO.ofExcept ((← read (root/"definitions.json")).getArr?)
  for topic in topics do
    let number ← IO.ofExcept (topic.getObjValAs? Nat "topic")
    let area := root/s!"topic-{number}"
    IO.FS.createDirAll area
    write (area/"audit-prototype.json") (Json.mkObj [
      ("source",Json.mkObj [("required",topic.getObjValD "referenceRanges")])])
    let preparation := (baseTemplate.getObjValD "preparation").setObjVal! "auditInput" (← artifact (area/"audit-prototype.json"))
    let mut template := baseTemplate.setObjVal! "label" (toJson s!"interrupted-recovery-{number}")
      |>.setObjVal! "purpose" (toJson "compatibility")
      |>.setObjVal! "stage" (toJson (0 : Nat))
      |>.setObjVal! "topic" (toJson number)
      |>.setObjVal! "repetition" (toJson (0 : Nat))
      |>.setObjVal! "prompt" (topic.getObjValD "prompt")
      |>.setObjVal! "sourceSnapshot" (frozen.getObjValD "source")
      |>.setObjVal! "sourceFiles" (frozen.getObjValD "sourceFiles")
      |>.setObjVal! "database" (toJson (area/"work.egg").toString)
      |>.setObjVal! "output" (toJson (area/"no-model-trial").toString)
      |>.setObjVal! "guardRecord" (toJson (area/"no-model-trial.guard.json").toString)
      |>.setObjVal! "preparation" preparation
    for field in #["runtime","runner","cliWrapper","nativeCli","accountConfiguration","harness",
        "pluginRoot","pluginFiles","environment","model","effort","workspace","sourceCommit","handoffChars"] do
      template := template.setObjVal! field (seedPlan.getObjValD field)
    write (area/"template.json") template
  write (records/"availability.json") (Json.mkObj [
    ("nativeDocuments",coverage.getObjValD "nativeDocuments"),
    ("recordedRows",coverage.getObjValD "recordedRows"),
    ("unsupportedReadForms",coverage.getObjValD "unsupportedReadForms"),
    ("availability",coverage.getObjValD "availability"),
    ("sourceReportSha256",toJson (← hash (root/"read-coverage.json"))),
    ("definitionsSha256",toJson (← hash (root/"definitions.json"))),
    ("handoffBodiesRead",toJson (0 : Nat)),("answeringModelCalls",toJson (0 : Nat))])

def runTopic (number : Nat) : IO Unit := do
  idle
  check (1 ≤ number && number ≤ 3) "topic must be 1, 2 or 3"
  let area := root/s!"topic-{number}"
  if number == 1 then
    guard s!"practical-recovery-topic-{number}" #[driver.toString,"prepare",
      (area/"template.json").toString,(area/"preparation").toString]
  else
    discard <| finished s!"practical-recovery-topic-{number-1}"
    let ready := root/"topic-1/preparation"
    let template := (← read (area/"template.json"))
      |>.setObjVal! "database" (toJson (root/"topic-1/work.egg").toString)
      |>.setObjVal! "dataRoot" (toJson (ready/"data").toString)
      |>.setObjVal! "configuration" (← artifact (ready/"config.toml"))
    write (area/"shared-project-template.json") template
    guard s!"practical-recovery-topic-{number}" #[driver.toString,"prepare-live",
      (area/"shared-project-template.json").toString,(area/"preparation").toString]

def collect : IO Unit := do
  idle
  let mut rows := #[]
  let mut delivered := 0
  let mut eligible := 0
  let mut availableDelivered := 0
  let mut availableEligible := 0
  for number in [1,2,3] do
    let monitor ← finished s!"practical-recovery-topic-{number}"
    let area := root/s!"topic-{number}"/"preparation"
    let plan ← read (area/"plan.json")
    let audit ← read (area/"audit-report.json")
    let full := audit.getObjValD "requiredDelivery"
    let available := audit.getObjValD "availableDelivery"
    check (full.getObjValD "targetMet" == toJson true && available.getObjValD "targetMet" == toJson true)
      "a frozen original was omitted"
    delivered := delivered+(← IO.ofExcept (full.getObjValAs? Nat "delivered"))
    eligible := eligible+(← IO.ofExcept (full.getObjValAs? Nat "eligible"))
    availableDelivered := availableDelivered+(← IO.ofExcept (available.getObjValAs? Nat "delivered"))
    availableEligible := availableEligible+(← IO.ofExcept (available.getObjValAs? Nat "eligible"))
    let bodyHash ← hash (area/"chat-0/body.txt")
    check (bodyHash == (← hash (area/"chat-1/body.txt"))) "independent chats changed the delivered body"
    let mut chats := #[]
    for index in [0,1] do
      let chat := area/s!"chat-{index}"
      let timing ← read (chat/"UserPromptSubmit/record.json")
      let stop ← read (chat/"shutdown.json")
      check ((timing.getObjValAs? Nat "elapsedMs").toOption.any (· < 30000) &&
        timing.getObjValD "exitCode" == toJson (0 : Nat) &&
        stop.getObjValD "processExited" == toJson true && stop.getObjValD "daemonExitCode" == toJson (0 : Nat))
        "hook or service did not complete normally"
      chats := chats.push (Json.mkObj [("timing",timing),("shutdown",stop)])
    let preparation := plan.getObjValD "preparation"
    let searchPath ← IO.ofExcept ((preparation.getObjValD "search").getObjValAs? String "path")
    let search := (← read (.mk searchPath)).getObjValD "data"
    let receipt := (System.FilePath.mk searchPath).parent.get!
    let synapse := (← read (receipt/"synaptic-delivery.json")).getObjValD "data"
    let trace := search.getObjValD "trace"
    check (trace.getObjValD "semantic" == toJson "completed" &&
      synapse.getObjValD "complete" == toJson true && synapse.getObjValD "packetVerified" == toJson true)
      "semantic or synaptic delivery is incomplete"
    let publisher ← read (area/"publisher-shutdown.json")
    check (publisher.getObjValD "processExited" == toJson true && publisher.getObjValD "daemonExitCode" == toJson (0 : Nat))
      "publisher did not close"
    rows := rows.push (Json.mkObj [("topic",toJson number),("requiredDelivery",full),("availableDelivery",available),
      ("bodySha256",toJson bodyHash),("chats",toJson chats),("search",search),
      ("synapse",synapse),("publisherShutdown",publisher),("guard",monitor),
      ("warm",← read (area/"warm/record.json")),("auditSha256",toJson (← hash (area/"audit-report.json")))])
  write (records/"results.json") (Json.mkObj [("runtimeSha256",toJson runtimeHash),("topics",toJson rows),
    ("fullyStored",toJson (delivered,eligible)),("includingPartial",toJson (availableDelivered,availableEligible)),
    ("nativeChats",toJson (6 : Nat)),("sameWarmedProjectDatabaseReused",toJson true),
    ("completedSeed",toJson false),("modelStagesCompleted",toJson (0 : Nat)),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])

def retain : IO Unit := do
  idle
  check ((← read (records/"results.json")).getObjValD "fullyStored" == toJson ((14,14) : Nat × Nat))
    "collect the actual source-delivery result first"
  let mut retained := #[]
  for number in [1,2,3] do
    let area := root/s!"topic-{number}"/"preparation"
    let destination := records/s!"topic-{number}"
    IO.FS.createDirAll destination
    for (input,output) in [
      (area/"chat-0/body.txt","body.txt"),(area/"chat-0/UserPromptSubmit/stdout","stdout.json"),
      (area/"chat-0/UserPromptSubmit/stdin","request.json"),(area/"chat-0/UserPromptSubmit/record.json","timing.json"),
      (area/"audit-report.json","audit.json"),(area/"available-evidence.json","available-before.json"),
      (area/"warm/stdout","warm.json"),(area/"doctor/stdout","doctor.json")] do
      let before ← hash input
      IO.FS.writeBinFile (destination/output) (← IO.FS.readBinFile input)
      check ((← hash (destination/output)) == before) "retained output differs from the actual native record"
      retained := retained.push ((destination/output).toString,before)
  write (records/"retained.json") (Json.mkObj [("files",toJson retained),
    ("actualBodiesAndStdoutRetained",toJson true),("archive",toJson false)])
  let predecessor ← read (base/"practical-predecessors-retirement-input.json")
  let closed := #[
    (root/"topic-1/work.egg").toString,(root/"topic-1/preparation").toString,
    (root/"topic-2/preparation").toString,(root/"topic-3/preparation").toString,
    (practical/"package/validation").toString]
  let input := predecessor.setObjVal! "closedDirectories" (toJson closed)
    |>.setObjVal! "protectedFiles" (toJson (((predecessor.getObjValAs? (Array String) "protectedFiles").toOption.getD #[])++
      #[(practical/"package/prefix/libexec/eggshell").toString]))
    |>.setObjVal! "plan" (toJson (base/"practical-recovery-retirement-plan.json").toString)
    |>.setObjVal! "receipt" (toJson (records/"retired.json").toString)
  write (base/"practical-recovery-retirement-input.json") input

def main (args : List String) : IO Unit := match args with
  | ["prepare"] => prepare
  | ["prepare-topics"] => prepareTopics
  | ["collect"] => collect
  | ["retain"] => retain
  | ["topic",raw] => do
    let some number := raw.toNat? | throw (IO.userError "numeric topic required")
    runTopic number
  | _ => throw (IO.userError "InterruptedRecoveryStudy prepare|prepare-topics|topic NUMBER")
end InterruptedRecoveryStudy
def main := InterruptedRecoveryStudy.main
