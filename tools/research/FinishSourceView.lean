import Lean
import Std.Data.HashSet
open Lean
private def ensure (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= fun value => IO.ofExcept (Json.parse value)
private def hash (path : System.FilePath) : IO String := do
  let found ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  ensure (found.exitCode == 0) "cannot seal source-view evidence"
  return (found.stdout.splitOn " ").headD ""
private def fields (value : Json) (names : List String) : Json :=
  Json.mkObj (names.map fun name => (name,value.getObjValD name))
private partial def remove (path : System.FilePath) : IO (Nat × Nat) := do
  let info ← path.symlinkMetadata
  if info.type != .dir then
    IO.FS.removeFile path
    return (1,if info.type == .file then info.byteSize.toNat else 0)
  let mut total := (0,0)
  for entry in ← path.readDir do
    let next ← remove entry.path
    total := (total.1+next.1,total.2+next.2)
  IO.FS.removeDir path
  return total

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let records := project / "docs/candidates/prepared-view"
  ensure (!(← (records / "result.json").pathExists) && !(← (records / "retired.json").pathExists))
    "preserve final source-view evidence"
  for name in ["runtime-build-5","storage-audit","final-audit","hook-build","hook-describe","hook-prepare",
      "hook-topic-1","hook-topic-2","hook-topic-3"] do
    let stopped ← read (records / (name ++ ".guard.json"))
    ensure (stopped.getObjValD "state" == toJson "finished" && stopped.getObjValD "exitCode" == toJson (0 : Nat) &&
      stopped.getObjValD "ownedPids" == toJson (#[] : Array Nat)) ("nonterminal source-view process: " ++ name)
  let originals : Array (String × String) ← IO.ofExcept ((← read
    (project / "docs/candidates/read-signal-trace/native-seal.json")).getObjValAs? _ "verifiedOriginalFilesAndRuntimes")
  for (path,expected) in originals do ensure ((← hash (.mk path)) == expected) "protected original changed"
  let mut inputs : Std.HashSet String := {}
  let mut binaries := #[]
  for name in ["prepared-view-runtime-build","published-plan-runtime-build","service-plan-runtime-build","source-plan-runtime-build",
      "owner-palette-runtime-build","owner-palette-build","receipt-reconciliation-runtime-build","query-cache-baseline-build"] do
    let directory := root / name
    binaries := binaries.push (directory / "StudyMain",← hash (directory / "StudyMain"))
    for line in (← IO.FS.readFile (directory / "runtime.rsp")).splitOn "\n" do
      if line.trimAscii.isEmpty then continue
      let path ← IO.ofExcept (Json.parse line >>= Json.getStr?)
      ensure (!["prepared-view-audit-build","prepared-view-storage-audit-build","prepared-view-hook-candidate-build"].any
        (fun needle => path.contains needle)) "active runtime borrows a terminal helper"
      if path.endsWith ".o" then
        ensure (← System.FilePath.pathExists path) "active native input is missing"
        inputs := inputs.insert path
  for (build,output) in [("prepared-view-storage-audit-build","storage-native-closure.json"),
      ("prepared-view-audit-build","metadata-native-closure.json")] do
    let checked ← IO.Process.output {
      cmd := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean",
      args := #["-M1024","--run",(project / "tools/research/StudyBuildClosureAudit.lean").toString,
        "inspect",(root / build).toString,(records / output).toString]}
    ensure (checked.exitCode == 0) "source-view helper native closure differs"
  let described ← read (records / "hooks/candidate-runtime.json")
  let runtime := described.getObjValD "runtime"
  ensure (runtime.getObjValD "sha256" == toJson (← hash (root / "prepared-view-runtime-build/StudyMain")))
    "runtime changed after actual hooks"
  let mut results := #[]
  let mut closed := #[]
  for topic in [1,2,3] do
    let directory := records / "hooks/candidate/rep-0" / s!"topic-{topic}"
    let actual ← read (directory / "result.json")
    let before ← read (directory / "before-gold.json")
    let reference := project / "docs/candidates/source-plan/bodies" / s!"topic-{topic}.txt"
    let body ← IO.FS.readFile (directory / "body.txt")
    let sha ← hash (directory / "body.txt")
    ensure ((← IO.FS.readFile reference) == body && actual.getObjValD "bodySha256" == toJson sha &&
      before.getObjValD "bodySha256" == toJson sha && before.getObjValD "goldRead" == toJson false)
      "actual body or pre-label freeze differs"
    results := results.push (Json.mkObj [("topic",toJson topic),
      ("elapsedMs",actual.getObjValD "elapsedMs"),("availableDelivery",actual.getObjValD "availableDelivery"),
      ("bodySha256",toJson sha),("bodyReference",toJson reference.toString),
      ("sameParentBody",toJson true),("beforeGold",before),
      ("nativeDeliveryAudit",actual.getObjValD "nativeDeliveryAudit")])
    for name in ["shutdown.json","publisher-shutdown.json"] do
      let report ← read (directory / name)
      ensure (["acknowledged","processExited","endpointRemoved"].all
        (fun field => report.getObjValD field == toJson true) && report.getObjValD "daemonExitCode" == toJson (0 : Nat))
        "actual source-view service did not close"
      closed := closed.push (Json.mkObj [("topic",toJson topic),("stage",toJson name),("report",report)])
  let preparationShutdown ← read (records / "hooks/candidate/prepare-shutdown.json")
  ensure (["acknowledged","processExited","endpointRemoved"].all
    (fun field => preparationShutdown.getObjValD field == toJson true)) "preparation service did not close"
  closed := closed.push (Json.mkObj [("stage",toJson "preparation"),("report",preparationShutdown)])
  let sourcePreparation ← read (records / "hooks/candidate/prepared-source.json")
  let warm ← read (records / "hooks/candidate/warm/stdout")
  let warmReceipt ← read (records / "hooks/candidate/warm/record.json")
  let warmRows ← IO.ofExcept (warm.getObjValAs? (Array Json) "databases")
  let some warmRow := warmRows[0]? | throw (IO.userError "warm report missing")
  IO.FS.writeFile (records / "preparation.json") (Json.mkObj [
    ("sourceIndexMs",sourcePreparation.getObjValD "elapsedMs"),("wholeWarm",warmReceipt),
    ("canonical",warmRow.getObjValD "canonical"),("freshDiagnosticFork",toJson true),
    ("dailyDeltaMeasurement",toJson false)]).pretty
  let receiptRoot := root / "prepared-view-trial/candidate/data/receipts"
  let mut timelines := #[]
  for entry in ← receiptRoot.readDir do
    let requestPath := entry.path / "request.json"
    if !(← requestPath.pathExists) then continue
    let request ← read requestPath
    let data := request.getObjValD "data"
    if data.getObjValD "event" != toJson "UserPromptSubmit" then continue
    let mut events := #[]
    for name in ["request","keyed-request","keyed-nominations","canonical-source-input","delivery-domain",
        "selection-plan","synaptic-delivery","search","dispatch","transport","published"] do
      let path := entry.path / (name ++ ".json")
      if !(← path.pathExists) then continue
      let value ← read path
      let payload := value.getObjValD "data"
      let kept := if name == "search" then fields payload ["trace","searchStartedMs","semanticReadyMs","disposition"]
        else if name == "synaptic-delivery" then fields payload ["complete","bindingComplete","bindingRequests",
          "bindingBytes","bindingUnresolved","unlocatedFileOwners","originalRecipeOwners"]
        else if name == "selection-plan" then fields payload ["candidateUnits","families","requiredSourceRows","jointBindings"]
        else Json.null
      events := events.push (Json.mkObj [("stage",toJson name),("observedMs",value.getObjValD "observedMs"),
        ("pid",value.getObjValD "pid"),("summary",kept)])
    timelines := timelines.push (Json.mkObj [("session",data.getObjValD "session"),("events",toJson events)])
  IO.FS.writeFile (records / "receipt-timeline.json") (toJson timelines).pretty
  IO.FS.writeFile (records / "runtime.json") described.pretty
  IO.FS.writeFile (records / "shutdowns.json") (toJson closed).pretty
  IO.FS.writeFile (records / "result.json") (Json.mkObj [
    ("runtime",runtime),("topics",toJson results),("actualHooks",toJson (3 : Nat)),
    ("firstSessionsOnly",toJson true),("historyRoundRun",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("newSeeds",toJson (0 : Nat)),
    ("latencyComparisonMeasured",toJson false),("p99Measured",toJson false),
    ("tokenImprovementMeasured",toJson false),("sustained80PersonWorkloadVerified",toJson false),
    ("adopted",toJson false)]).pretty
  let mut deleted := #[]
  for path in [root / "prepared-view-trial",records / "hooks",root / "prepared-view-audit-db",
      root / "prepared-view-final-audit-db",root / "prepared-view-storage-trial",root / "prepared-view-audit-build",
      root / "prepared-view-storage-audit-build",root / "prepared-view-hook-candidate-build"] do
    if ← path.pathExists then
      let (files,bytes) ← remove path
      deleted := deleted.push (Json.mkObj [("path",toJson path.toString),("files",toJson files),("logicalBytes",toJson bytes)])
  for name in ["SourceViewHook","SourceViewStorageAudit","PreparedSourceViewAudit"] do
    let path := root / "prepared-view-core/tools/research" / (name ++ ".lean")
    if ← path.pathExists then IO.FS.removeFile path
  for input in inputs do ensure (← System.FilePath.pathExists input) "cleanup removed an active native dependency"
  for (path,expected) in binaries do ensure ((← hash path) == expected) "cleanup changed an active runtime"
  for (path,expected) in originals do ensure ((← hash (.mk path)) == expected) "cleanup changed a protected original"
  IO.FS.writeFile (records / "retired.json") (Json.mkObj [("deleted",toJson deleted),
    ("retainedNativeInputs",toJson inputs.size),("sourceAndRuntimesUnchanged",toJson true),
    ("compressedOrArchived",toJson false)]).pretty
  IO.println "Retained actual delivery/metadata evidence; deleted terminal DBs, caches, helpers and duplicate logs"
