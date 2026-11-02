import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser

open Lean

private def check (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun raw => IO.ofExcept (Json.parse raw)
private def sha (path : System.FilePath) : IO String := do
  let out ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  check (out.exitCode == 0) "cannot seal the history audit input"
  return (out.stdout.splitOn " ").head!
private partial def removeTree (path : System.FilePath) : IO Unit := do
  if (← path.symlinkMetadata).type == .dir then
    for entry in ← path.readDir do removeTree entry.path
    IO.FS.removeDir path
  else IO.FS.removeFile path

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
  let target := project / "docs/candidates/history-feedback"
  IO.FS.createDirAll target
  let write := fun (name : String) (value : Json) => do
    let path := target / name
    if ← path.pathExists then check ((← read path) == value) "existing history evidence differs"
    else IO.FS.writeFile path value.pretty
  let checks ← read (root / "history-feedback-native2/result.json")
  check (checks.getObjValD "actualFeedbackFactsPerArm" == toJson (1 : Nat) &&
    checks.getObjValD "mismatchedClassifierRejected" == toJson true) "native feedback fork checks failed"
  let actual ← read (root / "history-feedback-actual2/result.json")
  check (actual.getObjValD "identicalFactsInBothArms" == toJson true &&
    actual.getObjValD "sourceAndPrivateInputsUnchanged" == toJson true) "actual acquired input comparison failed"
  let mut resources := #[]
  for name in ["history-feedback-compile","history-feedback-compile2","history-feedback-compile3",
      "history-feedback-checks","history-feedback-actual","history-feedback-checks2","history-feedback-actual2"] do
    let guard ← read (root / (name ++ ".guard.json"))
    check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "exitCode" == toJson (0 : Nat) &&
      guard.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "a history audit is not successfully terminal"
    resources := resources.push guard
  write "checks.json" checks
  write "actual.json" actual
  write "resources.json" (toJson resources)
  write "initial-checks.json" (← read (root / "history-feedback-native/result.json"))
  write "initial-actual.json" (← read (root / "history-feedback-actual/result.json"))
  write "proof-axioms.json" (Json.mkObj [("output",toJson (← IO.FS.readFile
    (root / "history-feedback-build/tools_research_HistoryFeedbackAudit-lean.stdout")))])
  let plan ← read (root / "seed-1.plan.json")
  let mut sealedInputs ← IO.ofExcept (plan.getObjValAs? (Array Json) "harness")
  for field in ["runtime","runner"] do sealedInputs := sealedInputs.push (plan.getObjValD field)
  for artifact in sealedInputs do
    let path ← IO.ofExcept (artifact.getObjValAs? String "path")
    check (toJson (← sha (.mk path)) == artifact.getObjValD "sha256") "a sealed runtime or harness input changed"
  let originalInputs : Array (String × String) ← IO.ofExcept ((← read (project / "docs/candidates/read-signal-trace/native-seal.json")).getObjValAs?
    _ "verifiedOriginalFilesAndRuntimes")
  for (path,digest) in originalInputs do check ((← sha (.mk path)) == digest) "protected source or runtime changed"
  let mut sources := #[]
  for name in ["StudyHistory","StudyHistoryChecks","HistoryFeedbackAudit"] do
    let source := project / "tools/research" / (name ++ ".lean")
    let compiled := root / "history-feedback-core/tools/research" / (name ++ ".lean")
    let stamp ← IO.ofExcept ((← read (root / "history-feedback-build" / ("tools_research_" ++ name ++ ".source"))).getArr?)
    check (stamp[0]? == some (toJson (← IO.FS.readFile compiled)) && (← sha source) == (← sha compiled))
      "native source stamp differs from the reviewed harness"
    sources := sources.push (name,← sha source)
  write "manifest.json" (Json.mkObj [("runtimeSha256",toJson (← sha (root / "history-feedback-build/StudyMain"))),
    ("sources",toJson sources),("sealedHarnessAndRuntimeInputs",toJson sealedInputs),
    ("protectedOriginals",toJson originalInputs),("answeringModelCalls",toJson (0 : Nat)),
    ("sealedControllerReplaced",toJson false),("productionRuntimeChanged",toJson false),
    ("initialBuildMainStampMismatchRefreshedBeforeExecution",toJson true),
    ("tokenImprovementMeasured",toJson false),("adopted",toJson false)])
  let complete ← read (project / "docs/candidates/fixed-frame-price/result.json")
  let runtime := complete.getObjValD "runtime"
  let binary ← IO.ofExcept (runtime.getObjValAs? String "binary")
  check (toJson (← sha (.mk binary)) == runtime.getObjValD "sha256")
    "retained complete-delivery runtime differs"
  let mut deliveries := #[]
  for topic in ← IO.ofExcept (complete.getObjValAs? (Array Json) "actuals") do
    let result := topic.getObjValD "result"
    let bodyPath ← IO.ofExcept (topic.getObjValAs? String "bodyReference")
    let bodySha ← sha (.mk bodyPath)
    let available := result.getObjValD "availableDelivery"
    check (toJson bodySha == result.getObjValD "bodySha256" &&
      available.getObjValD "delivered" == available.getObjValD "eligible" &&
      (topic.getObjValD "beforeGold").getObjValD "goldRead" == toJson false)
      "retained delivery body or its frozen-denominator result differs"
    deliveries := deliveries.push (Json.mkObj [("topic",topic.getObjValD "topic"),
      ("elapsedMs",result.getObjValD "elapsedMs"),("availableDelivery",available),
      ("bodySha256",toJson bodySha),("bodyReference",toJson bodyPath)])
  write "retained-complete-delivery.json" (Json.mkObj [("runtime",runtime),("topics",toJson deliveries),
    ("currentFilesMatchRecordedDigests",toJson true),("newHookCalls",toJson (0 : Nat)),
    ("newSeedOrSecondRoundValidated",toJson false),("sustained80PersonWorkloadValidated",toJson false)])
  let processes ← IO.Process.output {cmd := "/bin/ps",args := #["-axo","command="]}
  check (processes.exitCode == 0 && !(processes.stdout.splitOn "\n").any (·.startsWith (root / "history-feedback-build/StudyMain").toString))
    "native history audit is still live"
  for name in ["history-feedback-native","history-feedback-actual","history-feedback-native2","history-feedback-actual2",
      "history-feedback-core","history-feedback-build"] do
    removeTree (root / name)
  for suffix in ["stdout","stderr"] do
    for name in ["history-feedback-compile","history-feedback-compile2","history-feedback-compile3",
        "history-feedback-checks","history-feedback-actual","history-feedback-checks2","history-feedback-actual2"] do
      let path := root / (name ++ "." ++ suffix)
      if ← path.pathExists then IO.FS.removeFile path
  for artifact in sealedInputs do
    let path ← IO.ofExcept (artifact.getObjValAs? String "path")
    check (toJson (← sha (.mk path)) == artifact.getObjValD "sha256") "cleanup changed a sealed input"
  for (path,digest) in originalInputs do check ((← sha (.mk path)) == digest) "cleanup changed a protected original"
  write "cleanup.json" (Json.mkObj [("endedAuditDatabasesAndCachesRemoved",toJson true),
    ("oneOffCoreBuildRuntimeAndFullLogsRemoved",toJson true),("protectedInputsUnchanged",toJson true),
    ("archiveCreated",toJson false)])
  IO.println "Retained full-delivery candidate and private feedback copies verified; ended audit data removed."
