import tools.research.StudyStages
import tools.research.StudyRecordedRun

open Lean Eggshell Eggshell.Research
namespace Eggshell.Research.StudyStageClose

private def check (valid : Bool) (message : String) : IO Unit :=
  unless valid do throw (IO.userError message)

private def read (path : System.FilePath) : IO Json := StudyAdmission.readJson path.toString

private def artifact (row : Json) (field : String) : IO StudyAdmission.Artifact := do
  let value : StudyAdmission.Artifact ← IO.ofExcept (row.getObjVal? field >>= fromJson?)
  StudyAdmission.verifyArtifact value
  return value

/-- Monotonic times are recorded by the same host. This checks actual model
turn order, rather than trusting the order written into a stage manifest. -/
private def interval (path : System.FilePath) : IO (Nat × Nat) := do
  let input ← IO.FS.Handle.mk path .read
  let mut first : Option Nat := none
  let mut last : Option Nat := none
  repeat
    let line ← input.getLine
    if line.isEmpty then break
    check (line.utf8ByteSize ≤ 32*1024*1024) "recorded model packet exceeds its bound"
    let row ← IO.ofExcept (Json.parse line)
    let message := row.getObjValD "message"
    if message.getObjValD "method" == toJson "turn/start" then
      check first.isNone "multiple generation attempts in one sealed trial"
      first := some (← IO.ofExcept (row.getObjValAs? Nat "monotonic_ns"))
    if message.getObjValD "method" == toJson "turn/completed" then
      check last.isNone "multiple completed generations in one sealed trial"
      last := some (← IO.ofExcept (row.getObjValAs? Nat "monotonic_ns"))
  let some began := first | throw (IO.userError "recorded generation start is missing")
  let some ended := last | throw (IO.userError "recorded generation completion is missing")
  check (began < ended) "invalid recorded generation interval"
  return (began,ended)

private def replaceEnv (base updates : Array (String × Option String)) :=
  base.filter (fun row => !updates.any (·.1 == row.1)) ++ updates

def run (stage digest destination : String) (preparationRunner : Option String := none) : IO Unit := do
  StudyAdmission.verifyArtifact ⟨stage,digest⟩
  let stagePath := System.FilePath.mk stage
  let root := System.FilePath.mk destination
  check (stagePath.isAbsolute && root.isAbsolute && !(← root.pathExists)) "new absolute stage closure required"
  let prepared ← read stagePath
  let input ← artifact prepared "input"
  let request ← IO.ofExcept (fromJson? (α := StudyStages.Input) (← read (.mk input.path)))
  StudyAdmission.verifyArtifact request.definitions
  check (stagePath.parent == some (.mk request.output)) "prepared stage was moved from its sealed location"
  let seed ← IO.ofExcept (fromJson? (α := StudyAcquire.Plan) (← read (.mk request.controllerSeedPlan.path)))
  StudyAdmission.verifyArtifact request.controllerSeedPlan
  StudyAdmission.verifyArtifact seed.runner
  check ((← IO.FS.realPath (← IO.appPath)) ==
    (← IO.FS.realPath (.mk (preparationRunner.getD seed.runner.path))))
    "stage closure is not using its selected native preparation controller"
  let arms ← IO.ofExcept (prepared.getObjValAs? (Array Json) "arms")
  let labels ← arms.mapM fun row => IO.ofExcept (row.getObjValAs? String "arm")
  let expected := if request.purpose == "pilot" then #["fresh","candidate"] else #["fresh","current","candidate"]
  check (labels.size == expected.size && labels.toList.eraseDups.length == labels.size &&
    labels.all expected.contains) "stage has missing or duplicate experimental arms"
  let order ← IO.ofExcept (prepared.getObjValAs? (Array String) "order")
  check (order.size == expected.size && order.toList.eraseDups.length == order.size &&
    order.all expected.contains) "invalid declared model order"
  let mut summaries := #[]
  let mut recordedCandidate : Option StudyRecordedRun.Completed := none
  let mut previousEnd := 0
  for label in order do
    let some row := arms.find? (fun row => row.getObjValD "arm" == toJson label) |
      throw (IO.userError "declared experimental arm is absent")
    let sealed ← artifact row "plan"
    let planJson ← read (.mk sealed.path)
    let (output,guard,runtime) ← if label == "fresh" then do
      let plan ← IO.ofExcept (fromJson? (α := StudyAcquire.Plan) planJson)
      check (plan.kind == "fresh" && plan.model == seed.model && plan.effort == seed.effort)
        "fresh model conditions differ"
      pure (plan.output,plan.guardRecord,plan.runtime)
    else do
      let plan ← IO.ofExcept (fromJson? (α := StudyAdmission.Plan) planJson)
      check (plan.arm == (if label == "candidate" then .candidate else .reference) &&
        plan.purpose == request.purpose && plan.stage == request.stage && plan.topic == (request.stage-1)%3+1 &&
        plan.model == seed.model && plan.effort == seed.effort) "memory model conditions differ"
      if label == "candidate" then
        check (toJson plan.runtime == toJson seed.runtime) "candidate changed runtime after seed acquisition"
      pure (plan.output,plan.guardRecord,plan.runtime)
    StudyAdmission.verifyArtifact runtime
    let output := System.FilePath.mk output
    check ((← read (output/"plan.json")) == planJson) "actual model trial changed its sealed plan"
    let result ← read (output/"result.json")
    let monitor ← read (.mk guard)
    check (result.getObjValD "completed" == toJson true && monitor.getObjValD "state" == toJson "finished" &&
      monitor.getObjValD "exitCode" == toJson (0 : Nat) && monitor.getObjValD "ownedPids" == toJson (#[] : Array Nat) &&
      monitor.getObjValD "guardSha256" == toJson seed.runner.sha256) "model trial or owned cleanup is incomplete"
    let usage := result.getObjValD "usage"
    check (usage.getObjValD "protocolPassed" == toJson true && usage.getObjValD "unknownFinalUsage" == toJson false)
      "final inclusive model usage is unknown"
    let tokens ← IO.ofExcept (usage.getObjValAs? Nat "observedInclusiveTokens")
    let (first,last) ← interval (output/"rpc/exchange.jsonl")
    check (previousEnd ≤ first) "actual model attempts overlap or violate the declared order"
    previousEnd := last
    summaries := summaries.push (Json.mkObj [("arm",toJson label),("inclusiveTokens",toJson tokens),
      ("usage",usage),("firstMonotonicNs",toJson first),("lastMonotonicNs",toJson last)])
    if label == "candidate" then recordedCandidate := some (← StudyRecordedRun.read .memory output)
  let some candidate := recordedCandidate | throw (IO.userError "candidate source history is absent")
  check (toJson candidate.runner == toJson seed.runner) "candidate was executed by another controller"
  check (!(StudyRuntime.inside candidate.database root || StudyRuntime.inside candidate.data root ||
    StudyRuntime.inside root candidate.database || StudyRuntime.inside root candidate.data))
    "stage closure overlaps the retained source or private history"
  IO.FS.createDir root
  let environment := replaceEnv candidate.environment #[
    ("EGGSHELL_DATA_ROOT",some candidate.data.toString),("CODEX_THREAD_ID",none),("CODEX_TURN_ID",none)]
  let invoke := fun (args : Array String) (directory : System.FilePath) (timeout : Nat) => do
    let result ← StudyCommand.run (preparationRunner.getD seed.runner.path) args environment candidate.workspace "" directory timeout
    check (result.exitCode == 0) ("native stage closure failed: "++String.intercalate " " args.toList)
  let ready := root/"ready"
  invoke #["seed-finalize","--trial",candidate.root.toString,ready.toString] (root/"finalization") 720000
  let sourceAudit := root/"source-audit.json"
  invoke #["seed-audit","--trial",candidate.root.toString,request.definitions.path,
    (ready/"ready.egg").toString,sourceAudit.toString] (root/"source-audit") 120000
  let audit ← read sourceAudit
  check (audit.getObjValD "sourceAccepted" == toJson true && audit.getObjValD "handoffBodiesRead" == toJson (0 : Nat) &&
    audit.getObjValD "taskDefinitionsSha256" == toJson request.definitions.sha256 &&
    audit.getObjValD "runtime" == toJson candidate.runtime)
    "candidate observations are not complete enough to advance history"
  let readCoverage := root/"read-coverage.json"
  invoke #["read-coverage",candidate.database.toString,candidate.workspace,request.definitions.path,readCoverage.toString]
    (root/"read-coverage") 120000
  let history := root/"history"
  discard <| StudyHistory.freeze candidate.database candidate.data history
  let sourceArtifact ← StudyPrepare.artifact sourceAudit
  let nextHistory ← StudyPrepare.artifact (history/"history.json")
  IO.FS.writeFile (root/"closed.json") (Json.mkObj [
    ("completed",toJson true),("block",toJson request.block),("stage",toJson request.stage),
    ("purpose",toJson request.purpose),("preparedStage",toJson (⟨stage,digest⟩ : StudyAdmission.Artifact)),
    ("nextHistory",toJson nextHistory),("sourceAudit",toJson sourceArtifact),
    ("readCoverage",toJson (← StudyPrepare.artifact readCoverage)),("modelRuns",toJson summaries),
    ("seedCostIncluded",toJson false),("oneRecordedAttemptPerArm",toJson true),
    ("qualityAssessed",toJson false),("productionAdoption",toJson false)]).compress

/-- Exercise the controller with an actual recorded RPC stream. Mutated
metadata fixtures are labelled as such and never dispatch a generation. -/
def checks (exchange failedRun output : String) : IO Unit := do
  let root := System.FilePath.mk output
  check (!(← root.pathExists)) "preserve earlier stage-controller checks"
  let (began,ended) ← interval (.mk exchange)
  IO.FS.createDir root
  let input ← IO.FS.Handle.mk (.mk exchange) .read
  let mut beginning : Option Json := none
  let mut ending : Option Json := none
  repeat
    let line ← input.getLine
    if line.isEmpty then break
    let row ← IO.ofExcept (Json.parse line)
    let method := (row.getObjValD "message").getObjValD "method"
    if method == toJson "turn/start" then beginning := some row
    if method == toJson "turn/completed" then ending := some row
  let some beginningRow := beginning | throw (IO.userError "actual start packet is absent")
  let some endingRow := ending | throw (IO.userError "actual completion packet is absent")
  let cases := #[
    ("duplicate-start",#[beginningRow,beginningRow,endingRow]),
    ("missing-end",#[beginningRow]),
    ("reversed-clock",#[beginningRow.setObjVal! "monotonic_ns" (toJson (ended+1)),endingRow])]
  let mut rejected := #[]
  for (name,rows) in cases do
    let path := root/(name++".jsonl")
    IO.FS.writeFile path (String.intercalate "\n" (rows.toList.map (·.compress))++"\n")
    let invalid ← try let _ ← interval path; pure false catch _ => pure true
    check invalid ("invalid recorded interval was accepted: "++name)
    rejected := rejected.push name
  let failure := root/"failed-record"
  IO.FS.createDir failure
  for (source,target) in [("plan.json","plan.json"),("failure.json","result.json")] do
    IO.FS.writeFile (failure/target) (← IO.FS.readFile (System.FilePath.mk failedRun/source))
  let invalid ← try
    let _ ← StudyRecordedRun.read .seed failure
    pure false
    catch error => pure (error.toString.contains "completed recorded generation")
  check invalid "a failed generation was accepted or rejected by the wrong gate"
  IO.FS.writeFile (root/"result.json") (Json.mkObj [
    ("actualRecordedInterval",toJson (began,ended)),("rejectedIntervals",toJson rejected),
    ("failedGenerationRejected",toJson true),("syntheticMetadataOnly",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("allPassed",toJson true),
    ("sixModelStagesCompleted",toJson (0 : Nat)),("adopted",toJson false)]).compress

end Eggshell.Research.StudyStageClose
