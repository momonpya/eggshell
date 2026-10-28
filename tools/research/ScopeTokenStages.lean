import Lean.Data.Json.Parser
import Lean.Data.Json.FromToJson

open Lean

private def root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028"
private def controller := (root / "controller-build/StudyMain").toString

private def read (path : System.FilePath) : IO Json := do IO.ofExcept (Json.parse (← IO.FS.readFile path))
private def field (value : Json) (key : String) : IO Json := IO.ofExcept (value.getObjVal? key)
private def string (value : Json) (key : String) : IO String := IO.ofExcept (value.getObjValAs? String key)
private def save (path : System.FilePath) (value : Json) : IO Unit := do
  unless !(← path.pathExists) do throw (IO.userError s!"preserve {path}")
  IO.FS.writeFile path (value.pretty ++ "\n")

private def run (args : Array String) : IO Unit := do
  let result ← IO.Process.output {cmd := controller,args}
  unless result.exitCode == 0 do throw (IO.userError (result.stderr ++ result.stdout))

private def artifact (path : System.FilePath) : IO Json := do
  unless path.fileName != some "auth.json" do throw (IO.userError "credentials are not evidence")
  let result ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  unless result.exitCode == 0 do throw (IO.userError result.stderr)
  let digest := ((result.stdout.splitOn " ").headD "").trimAscii.toString
  unless digest.length == 64 do throw (IO.userError "missing artifact digest")
  return Json.mkObj [("path",toJson path.toString),("sha256",toJson digest)]

private def guarded (command : Array String) (record : System.FilePath) (minimum : Nat := 2097152) : Json :=
  Json.mkObj [("command",toJson command),("record",toJson record.toString),
    ("cwd",toJson "/Users/ovm/Code/eggshell-benchmarks/aamas-2027/sources/llvm-project"),
    ("ownedPrefixes",toJson #[root.toString,controller]),("limitRssKiB",toJson (3670016 : Nat)),
    ("minFreeKiB",toJson minimum)]

private def retireDeadPublisher (plan : Json) (directory : System.FilePath) : IO Json := do
  let data ← string plan "dataRoot"
  let endpoint := System.FilePath.mk data / "publisher/endpoint.json"
  if !(← endpoint.pathExists) then return plan
  let record ← read endpoint
  let pid ← IO.ofExcept (record.getObjValAs? Nat "pid")
  let process ← IO.Process.output {cmd := "/bin/ps",args := #["-p",toString pid,"-o","pid="]}
  unless process.exitCode == 1 && process.stdout.trimAscii.isEmpty do
    throw (IO.userError "refuse to retire a live publisher endpoint")
  let files ← IO.ofExcept (plan.getObjValAs? (Array (String × String)) "privateFiles")
  let some previous := files.find? (·.1 == "publisher/endpoint.json") |
    throw (IO.userError "stale endpoint was not in the sealed private snapshot")
  let sealed ← artifact endpoint
  unless (sealed.getObjValAs? String "sha256").toOption == some previous.2 do
    throw (IO.userError "publisher endpoint changed after preparation")
  IO.FS.rename endpoint (directory / "retired-dead-publisher.endpoint.json")
  save (directory / "retired-dead-publisher.json") (Json.mkObj [
    ("pid",toJson pid),("wasAlive",toJson false),("sourceFactsChanged",toJson false)])
  return plan.setObjVal! "privateFiles" (toJson (files.filter (·.1 != "publisher/endpoint.json")))

private def definitions : IO Unit := do
  let template ← read "/Users/ovm/.codex/experiments/eggshell/source-complete-seed-20261028/task-definitions.json"
  let rows ← IO.ofExcept template.getArr?
  let updated ← rows.mapM fun row => do
    let topic ← IO.ofExcept (row.getObjValAs? Nat "topic")
    return row.setObjVal! "prompt" (← artifact (root / s!"prompts/topic-{topic}.txt"))
  save (root / "task-definitions.json") (toJson updated)

private def prepareFeedbackBuild : IO Unit := do
  let original ← read (root / "drain-build.guard-settings.json")
  save (root / "drain-feedback-build.guard-settings.json")
    (original.setObjVal! "record" (toJson (root / "drain-feedback-build.guard.json").toString))

private def gate : IO Unit := do
  let _ ← artifact (.mk controller)
  IO.FS.writeFile (root / "controller/build.json") (← IO.FS.readFile (root / "controller-build/build.json"))
  -- Keep the failed, uncharged old-controller gate as evidence.
  for name in #["native-gate","native-gate.guard.json"] do
    if ← (root / name).pathExists then
      unless !(← (root / (name ++ ".old-controller")).pathExists) do
        throw (IO.userError "old controller gate already retained")
      IO.FS.rename (root / name) (root / (name ++ ".old-controller"))
  save (root / "native-gate-current.settings.json") (guarded #[controller,"seed-checks-generic",
    (root / "native-gate-input.json").toString,(root / "native-gate").toString] (root / "native-gate.guard.json"))

private def replacementSeed : IO Unit := do
  let failure ← read (root / "study/seed-1/failure.json")
  unless (failure.getObjValAs? String "runError").toOption == some "observed inclusive token limit reached; retain all charged usage" do
    throw (IO.userError "this replacement is only for the insufficient seed cap")
  let original ← read (root / "seed-1.plan.json")
  let mut plan := original.setObjVal! "label" (toJson "new-native-seed-2")
  plan := plan.setObjVal! "output" (toJson (root / "study/seed-2").toString)
  plan := plan.setObjVal! "guardRecord" (toJson (root / "seed-2.guard.json").toString)
  save (root / "seed-2.plan.json") plan
  save (root / "seed-2.limits.json") (Json.mkObj [("inclusiveTokens",toJson (15000000 : Nat)),("answerMs",toJson (900000 : Nat))])
  let sealed ← artifact (root / "seed-2.plan.json")
  let limits ← artifact (root / "seed-2.limits.json")
  save (root / "seed-2.settings.json") (guarded #[controller,"acquire-bounded",← string sealed "path",← string sealed "sha256",
    ← string limits "path",← string limits "sha256"] (root / "seed-2.guard.json"))
  save (root / "active-seed.json") (Json.mkObj [
    ("acquisition",toJson (root / "study/seed-2").toString),("plan",toJson (root / "seed-2.plan.json").toString),
    ("failedAttempt",← artifact (root / "study/seed-1/failure.json")),
    ("failedUsage",← field failure "usage"),("reason",toJson "seed-only token cap increased before memory measurements; no runtime or prompt change")])
  unless !(← (root / "study/seed-2").pathExists) do throw (IO.userError "second acquisition already started")
  for extension in #["json","stdout","stderr"] do
    let path := root / ("driver/seed-2." ++ extension)
    if ← path.pathExists then IO.FS.rename path (root / ("driver/seed-2.before-plan." ++ extension))

private def fork (rep : Nat) : IO Unit := do
  unless rep < 2 do throw (IO.userError "only the two predeclared repetitions")
  let manifest ← artifact (root / "initial-history/history.json")
  run #["history","fork",← string manifest "path",← string manifest "sha256",(root / s!"r{rep}").toString]
  let database := (root / s!"r{rep}/work.egg").toString
  let runtime := (root / "prefix/libexec/eggshell").toString
  let config := "default = \"work\"\nsemantic_matcher = " ++
    (toJson #[runtime,"search-provider"]).compress ++ "\n[eggs]\nwork = " ++
    (toJson database).compress ++ "\n[profiles.work]\nread = [\"work\"]\nwrite = \"work\"\nhandoff_chars = 120000\n"
  IO.FS.writeFile (root / s!"r{rep}/config.toml") config

private def stage (rep number : Nat) : IO Unit := do
  unless rep < 2 && 1 ≤ number && number ≤ 6 do throw (IO.userError "outside the frozen two-by-six design")
  let branch := root / s!"r{rep}"
  let directory := branch / s!"stage{number}"
  unless !(← directory.pathExists) do throw (IO.userError "preserve previous stage")
  if number > 1 then
    let previous ← read (branch / s!"stage{number-1}/trial/result.json")
    unless (previous.getObjValAs? Bool "completed").toOption == some true do
      throw (IO.userError "previous stage did not complete; preserve its cost and stop")
  IO.FS.createDir directory
  run #["history","freeze",(branch / "work.egg").toString,(branch / "data").toString,(directory / "history").toString]
  let history ← read (directory / "history/history.json")
  let active ← read (root / "active-seed.json")
  let plan ← read (.mk (← string active "plan"))
  let topic := (number-1)%3+1
  let rows ← IO.ofExcept ((← read (root / "task-definitions.json")).getArr?)
  let some definition := rows.find? (fun row => (row.getObjValAs? Nat "topic").toOption == some topic) |
    throw (IO.userError "undefined topic")
  save (directory / "audit-prototype.json") (Json.mkObj [("source",Json.mkObj [
    ("required",← field definition "referenceRanges")])])
  let prototype ← artifact (directory / "audit-prototype.json")
  let preparation := Json.mkObj ((["input","stdout","timing","body","state","shutdown","search","auditInput","auditReport"].map
    fun key => (key,prototype)) ++ [("session",toJson "pending"),("numerical",toJson (#[] : Array Json))])
  let mut fields := []
  for key in #["model","effort","workspace","sourceCommit","runner","cliWrapper","nativeCli","runtime","accountConfiguration","harness","pluginRoot","pluginFiles"] do
    let value ← if key == "accountConfiguration" then read (root / "measurement-account.json") else field plan key
    fields := fields ++ [(key,value)]
  let baseEnv ← IO.ofExcept (plan.getObjValAs? (Array (String × Option String)) "environment")
  let updates : Array (String × Option String) := #[
    ("EGGSHELL_CONFIG",some (branch / "config.toml").toString),("EGGSHELL_DATA_ROOT",some (branch / "data").toString),
    ("EGGSHELL_PROFILE",some "work")]
  let env := baseEnv.filter (fun item => !updates.any (·.1 == item.1)) ++ updates
  let files ← field history "sourceFiles"
  let draft := Json.mkObj (fields ++ [
    ("label",toJson s!"scope-stage{number}-r{rep}"),("purpose",toJson "pilot"),
    ("topic",toJson topic),("stage",toJson number),("repetition",toJson rep),
    ("prompt",← artifact (root / s!"prompts/topic-{topic}.txt")),
    ("configuration",← artifact (branch / "config.toml")),
    ("sourceSnapshot",toJson (directory / "history/source.egg").toString),("sourceFiles",files),
    ("database",toJson (branch / "work.egg").toString),("databaseFiles",files),
    ("dataRoot",toJson (branch / "data").toString),("privateFiles",toJson (#[] : Array Json)),
    ("environment",toJson env),("preparation",preparation),
    ("output",toJson (directory / "trial").toString),("guardRecord",toJson (directory / "trial.guard.json").toString)])
  save (directory / "draft.json") draft
  save (directory / "prepare.settings.json") (guarded #[controller,"prepare-live",(directory / "draft.json").toString,
    (directory / "preparation").toString] (directory / "prepare.guard.json"))

private def sealTrial (rep number : Nat) : IO Unit := do
  let directory := root / s!"r{rep}/stage{number}"
  let guardReport ← read (directory / "prepare.guard.json")
  unless (guardReport.getObjValAs? Nat "exitCode").toOption == some 0 &&
      (guardReport.getObjValAs? (Array Nat) "ownedPids").toOption == some #[] do
    throw (IO.userError "preparation did not terminate successfully")
  let prepared ← read (directory / "preparation/plan.json")
  let qualified ← retireDeadPublisher prepared directory
  save (directory / "preparation/drained-plan.json") qualified
  let plan ← artifact (directory / "preparation/drained-plan.json")
  save (directory / "limits.json") (Json.mkObj [("inclusiveTokens",toJson (5000000 : Nat)),("answerMs",toJson (900000 : Nat))])
  let limits ← artifact (directory / "limits.json")
  save (directory / "trial.settings.json") (guarded #[controller,"trial-bounded",← string plan "path",← string plan "sha256",
    ← string limits "path",← string limits "sha256"] (directory / "trial.guard.json"))

private def resumeBeforeTurn : IO Unit := do
  let directory := root / "r0/stage1"
  let failure ← read (directory / "trial/failure.json")
  unless (failure.getObjValAs? String "runError").toOption == some "a publisher already owns this study scope" do
    throw (IO.userError "only the known stale publisher failure can resume here")
  let exchange ← IO.FS.readFile (directory / "trial/rpc/exchange.jsonl")
  unless !(exchange.contains "turn/start") do throw (IO.userError "generation already started; preserve its usage")
  let original ← read (directory / "preparation/qualified-plan.json")
  let plan ← retireDeadPublisher original directory
  save (directory / "preparation/drained-qualified-plan.json") plan
  let sealed ← artifact (directory / "preparation/drained-qualified-plan.json")
  let limits ← artifact (directory / "limits.json")
  save (directory / "drained-trial.settings.json") (guarded #[controller,"trial-bounded",← string sealed "path",← string sealed "sha256",
    ← string limits "path",← string limits "sha256"] (directory / "trial.guard.json"))
  IO.FS.rename (directory / "trial") (directory / "trial-preturn-publisher-failure")
  IO.FS.rename (directory / "trial.guard.json") (directory / "trial-preturn-publisher-failure.guard.json")
  for extension in #["json","stdout","stderr"] do
    IO.FS.rename (root / ("driver/trial-r0-stage1." ++ extension))
      (root / ("driver/trial-r0-stage1.preturn-publisher-failure." ++ extension))
  save (directory / "preturn-publisher-failure.json") (Json.mkObj [
    ("answeringModelCalls",toJson (0 : Nat)),("runtimeChanged",toJson false),("failure",failure)])

private def retireUnstartedSession : IO Unit := do
  let directory := root / "r0/stage1"
  let before := directory / "trial-preturn-publisher-failure"
  let exchange ← IO.FS.readFile (before / "rpc/exchange.jsonl")
  unless !(exchange.contains "turn/start") do throw (IO.userError "a model turn already started")
  let thread ← read (before / "thread.json")
  let session ← field thread "thread" >>= (fun value => string value "id")
  unless !session.contains '/' && !session.isEmpty do throw (IO.userError "invalid session")
  let path := root / "r0/data/sessions" / session
  let record ← read (path / "daemon.json")
  let pid ← IO.ofExcept (record.getObjValAs? Nat "pid")
  let process ← IO.Process.output {cmd := "/bin/ps",args := #["-p",toString pid,"-o","pid="]}
  unless process.exitCode == 1 && process.stdout.trimAscii.isEmpty do throw (IO.userError "session is still alive")
  let files ← path.readDir
  for entry in files do
    let metadata ← entry.path.symlinkMetadata
    unless metadata.type == .file && (entry.fileName == "daemon.json" ||
        (entry.fileName.endsWith ".guard" && metadata.byteSize == 0)) do
      throw (IO.userError "unstarted session contains durable history; do not remove it")
  for entry in files do IO.FS.removeFile entry.path
  IO.FS.removeDir path
  save (directory / "unstarted-session-cleanup.json") (Json.mkObj [
    ("session",toJson session),("pid",toJson pid),("wasAlive",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("durableHistoryRemoved",toJson false)])
  IO.FS.rename (directory / "trial.guard.json") (directory / "trial-preadmission-session-failure.guard.json")
  for extension in #["json","stdout","stderr"] do
    IO.FS.rename (root / ("driver/trial-r0-stage1." ++ extension))
      (root / ("driver/trial-r0-stage1.preadmission-session-failure." ++ extension))

private def retireUnstartedEnd : IO Unit := do
  let directory := root / "r0/stage1"
  let before := directory / "trial-preturn-publisher-failure"
  unless !((← IO.FS.readFile (before / "rpc/exchange.jsonl")).contains "turn/start") do
    throw (IO.userError "a model turn already started")
  let thread ← read (before / "thread.json")
  let session ← field thread "thread" >>= (fun value => string value "id")
  let receipts := root / "r0/data/receipts"
  let mut removed := #[]
  for receipt in ← receipts.readDir do
    let request ← read (receipt.path / "request.json")
    let data ← field request "data"
    if (data.getObjValAs? String "session").toOption != some session then continue
    unless (data.getObjValAs? String "event").toOption == some "SessionEnd" do
      throw (IO.userError "unstarted session contains another event")
    for file in ← receipt.path.readDir do
      unless (← file.path.symlinkMetadata).type == .file do throw (IO.userError "unexpected receipt data")
      removed := removed.push (← artifact file.path)
    for file in ← receipt.path.readDir do IO.FS.removeFile file.path
    IO.FS.removeDir receipt.path
  save (directory / "unstarted-session-end-cleanup.json") (Json.mkObj [
    ("session",toJson session),("answeringModelCalls",toJson (0 : Nat)),("removed",toJson removed)])
  IO.FS.rename (directory / "trial.guard.json") (directory / "trial-preadmission-receipt-failure.guard.json")
  for extension in #["json","stdout","stderr"] do
    IO.FS.rename (root / ("driver/trial-r0-stage1." ++ extension))
      (root / ("driver/trial-r0-stage1.preadmission-receipt-failure." ++ extension))

private def collect (rep number : Nat) : IO Unit := do
  let baseline ← read "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell/docs/candidates/fresh-baseline-reuse.json"
  let fresh ← IO.ofExcept (baseline.getObjValAs? (Array Json) "existingFresh")
  let mut cells := #[]
  for repetition in [0:2] do
    for stageNumber in [1:7] do
      let directory := root / s!"r{repetition}/stage{stageNumber}"
      let terminal := if ← (directory / "trial/result.json").pathExists then directory / "trial/result.json"
        else directory / "trial/failure.json"
      if !(← terminal.pathExists) then continue
      let result ← read terminal
      let usage ← field result "usage"
      let total ← field usage "total"
      let input ← IO.ofExcept (total.getObjValAs? Nat "inputTokens")
      let output ← IO.ofExcept (total.getObjValAs? Nat "outputTokens")
      let inclusive ← IO.ofExcept (total.getObjValAs? Nat "totalTokens")
      unless inclusive == input+output do throw (IO.userError "usage must include input and output exactly once")
      let some control := fresh.find? (fun row =>
        (row.getObjValAs? Nat "stage").toOption == some stageNumber &&
        (row.getObjValAs? Nat "repetition").toOption == some repetition) |
        throw (IO.userError "missing predeclared fresh control")
      let freshUsage ← field control "usage"
      let controlTokens ← IO.ofExcept (freshUsage.getObjValAs? Nat "totalTokens")
      let saved := 100.0*(1.0-inclusive.toFloat/controlTokens.toFloat)
      let audit ← read (directory / "preparation/audit-report.json")
      cells := cells.push (Json.mkObj [
        ("repetition",toJson repetition),("stage",toJson stageNumber),("topic",toJson ((stageNumber-1)%3+1)),
        ("lap",toJson ((stageNumber-1)/3+1)),("completed",← field result "completed"),
        ("freshTotalTokens",toJson controlTokens),("memoryTotalTokens",toJson inclusive),
        ("savingsPercent",toJson saved),("usage",total),("knownOmissions",← field result "knownOmissions"),
        ("initialBodyMatched",← field usage "initialBodyMatched"),("finalUsageKnown",← field usage "finalUsageKnown"),
        ("terminal",← artifact terminal),("audit",audit)])
  let active ← read (root / "active-seed.json")
  let seed ← read (System.FilePath.mk (← string active "acquisition") / "result.json")
  save (root / s!"results-r{rep}-stage{number}.json") (Json.mkObj [
    ("cells",toJson cells),("seedUsage",← field seed "usage"),("failedSeedUsage",← field active "failedUsage"),("freshIsHistorical",toJson true),
    ("causalAdoptionComparison",toJson false),("productionAdoption",toJson false),
    ("failedChargedAttemptsIncluded",toJson true)])
  for cell in cells do
    let stage ← IO.ofExcept (cell.getObjValAs? Nat "stage")
    let repetition ← IO.ofExcept (cell.getObjValAs? Nat "repetition")
    let memory ← IO.ofExcept (cell.getObjValAs? Nat "memoryTotalTokens")
    let control ← IO.ofExcept (cell.getObjValAs? Nat "freshTotalTokens")
    let savings ← IO.ofExcept (cell.getObjValAs? Float "savingsPercent")
    IO.println s!"r{repetition} stage{stage}: {memory}/{control} = {savings}% saved"

private def natural (value : String) : IO Nat :=
  match value.toNat? with
  | some value => pure value
  | none => throw (IO.userError "expected a natural number")

def main (args : List String) : IO Unit := do
  match args with
  | ["definitions"] => definitions
  | ["prepare-feedback-build"] => prepareFeedbackBuild
  | ["gate"] => gate
  | ["replacement-seed"] => replacementSeed
  | ["resume-before-turn"] => resumeBeforeTurn
  | ["retire-unstarted-session"] => retireUnstartedSession
  | ["retire-unstarted-end"] => retireUnstartedEnd
  | ["fork",rep] => fork (← natural rep)
  | ["stage",rep,number] => stage (← natural rep) (← natural number)
  | ["seal-trial",rep,number] => sealTrial (← natural rep) (← natural number)
  | ["collect",rep,number] => collect (← natural rep) (← natural number)
  | _ => throw (IO.userError "ScopeTokenStages definitions | fork REP | stage REP NUMBER | seal-trial REP NUMBER")
