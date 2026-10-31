import Lean
import Std.Data.HashSet
open Lean

private def ensure (ok : Bool) (message : String) : IO Unit :=
  unless ok do throw (IO.userError message)
private def read (path : System.FilePath) : IO Json :=
  IO.FS.readFile path >>= fun text => IO.ofExcept (Json.parse text)
private def hash (path : System.FilePath) : IO String := do
  let found ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256",path.toString]}
  ensure (found.exitCode == 0) "cannot hash protected project metadata input"
  return (found.stdout.splitOn " ").headD ""
private def fields (value : Json) (names : List String) : Json :=
  Json.mkObj (names.map fun name => (name,value.getObjValD name))
private partial def remove (path : System.FilePath) : IO (Nat × Nat) := do
  let metadata ← path.symlinkMetadata
  if metadata.type != .dir then
    IO.FS.removeFile path
    return (1,if metadata.type == .file then metadata.byteSize.toNat else 0)
  let mut total := (0,0)
  for child in ← path.readDir do
    let next ← remove child.path
    total := (total.1+next.1,total.2+next.2)
  IO.FS.removeDir path
  return total

def main : IO Unit := do
  let project : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
  let root : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/shared-snapshot"
  let records := project / "docs/candidates/project-metadata"
  ensure (!(← (records / "retired.json").pathExists) && !(← (records / "result.json").pathExists))
    "preserve terminal project metadata evidence"
  for name in ["runtime-build-2","hook-build-resumed","hook-describe","hook-prepare","hook-topic-1"] do
    let stopped ← read (records / (name ++ ".guard.json"))
    ensure (stopped.getObjValD "state" == toJson "finished" && stopped.getObjValD "exitCode" == toJson (0 : Nat) &&
      stopped.getObjValD "guardTriggered" == toJson false && stopped.getObjValD "ownedPids" == toJson (#[] : Array Nat))
      ("project metadata job did not finish cleanly: " ++ name)
  let componentGuard ← read (records / "audit.guard.json")
  ensure (componentGuard.getObjValD "exitCode" == toJson (0 : Nat) &&
    componentGuard.getObjValD "reason" == toJson "leftover-processes" &&
    componentGuard.getObjValD "ownedPids" == toJson (#[] : Array Nat))
    "component execution differs from the recorded guard interference"
  let originals : Array (String × String) ← IO.ofExcept ((← read
    (project / "docs/candidates/read-signal-trace/native-seal.json")).getObjValAs? _ "verifiedOriginalFilesAndRuntimes")
  for (path,expected) in originals do
    ensure ((← hash (.mk path)) == expected) "protected source/runtime changed"
  let mut inputs : Std.HashSet String := {}
  let mut binaries := #[]
  let helpers := ["project-metadata-audit-build","project-metadata-hook-candidate-build"]
  for name in ["project-metadata-runtime-build","prepared-view-runtime-build","published-plan-runtime-build",
      "service-plan-runtime-build","source-plan-runtime-build","owner-palette-runtime-build","owner-palette-build",
      "receipt-reconciliation-runtime-build","query-cache-baseline-build"] do
    let directory := root / name
    binaries := binaries.push (directory / "StudyMain",← hash (directory / "StudyMain"))
    for line in (← IO.FS.readFile (directory / "runtime.rsp")).splitOn "\n" do
      if line.trimAscii.isEmpty then continue
      let path ← IO.ofExcept (Json.parse line >>= Json.getStr?)
      ensure (!(helpers.any (fun helper => path.contains helper))) "active runtime borrows a terminal helper"
      if path.endsWith ".o" then
        ensure (← System.FilePath.pathExists path) "active native input is missing"
        inputs := inputs.insert path
  let closurePath := records / "audit-native-closure.json"
  let closure ← IO.Process.output {
    cmd := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0/bin/lean",
    args := #["-M1024","--run",(project / "tools/research/StudyBuildClosureAudit.lean").toString,
      "inspect",(root / "project-metadata-audit-build").toString,closurePath.toString]}
  ensure (closure.exitCode == 0) "binding audit native inputs differ"
  let described ← read (records / "hooks/candidate-runtime.json")
  let runtime := described.getObjValD "runtime"
  ensure (runtime.getObjValD "sha256" == toJson (← hash (root / "project-metadata-runtime-build/StudyMain")))
    "measured runtime changed"
  let directory := records / "hooks/candidate/rep-0/topic-1"
  let actual ← read (directory / "result.json")
  let before ← read (directory / "before-gold.json")
  let reference := project / "docs/candidates/source-plan/bodies/topic-1.txt"
  let body ← IO.FS.readFile (directory / "body.txt")
  let sha ← hash (directory / "body.txt")
  ensure ((← IO.FS.readFile reference) == body && actual.getObjValD "bodySha256" == toJson sha &&
    before.getObjValD "bodySha256" == toJson sha && before.getObjValD "goldRead" == toJson false)
    "connection changed the parent body or pre-label freeze"
  let mut shutdowns := #[]
  for path in [directory / "shutdown.json",directory / "publisher-shutdown.json",
      records / "hooks/candidate/prepare-shutdown.json"] do
    let report ← read path
    ensure (["acknowledged","processExited","endpointRemoved"].all
      (fun field => report.getObjValD field == toJson true) && report.getObjValD "daemonExitCode" == toJson (0 : Nat))
      "project metadata service did not close"
    shutdowns := shutdowns.push (Json.mkObj [("stage",toJson path.fileName.get!), ("report",report)])
  IO.FS.writeFile (records / "shutdowns.json") (toJson shutdowns).pretty
  let preparation ← read (records / "hooks/candidate/prepared-source.json")
  let warm ← read (records / "hooks/candidate/warm/stdout")
  let warmRecord ← read (records / "hooks/candidate/warm/record.json")
  IO.FS.writeFile (records / "preparation.json") (Json.mkObj [
    ("sourceIndex",preparation),("warm",warm),("wholeWarm",warmRecord),
    ("freshDiagnosticFork",toJson true),("dailyDeltaMeasurement",toJson false)]).pretty
  let mut timelines := #[]
  for entry in ← (root / "project-metadata-trial/candidate/data/receipts").readDir do
    if !(← (entry.path / "request.json").pathExists) then continue
    let request ← read (entry.path / "request.json")
    if (request.getObjValD "data").getObjValD "event" != toJson "UserPromptSubmit" then continue
    let mut events := #[]
    for name in ["request","keyed-request","keyed-nominations","canonical-source-input","delivery-domain",
        "selection-plan","synaptic-delivery","search","dispatch","transport","published"] do
      let path := entry.path / (name ++ ".json")
      if !(← path.pathExists) then continue
      let value ← read path
      let data := value.getObjValD "data"
      let kept := if name == "search" then fields data ["trace","searchStartedMs","semanticReadyMs","disposition"]
        else if name == "synaptic-delivery" then fields data ["complete","bindingComplete","bindingRequests",
          "bindingBytes","bindingUnresolved","unlocatedFileOwners","originalRecipeOwners"]
        else if name == "selection-plan" then fields data ["candidateUnits","families","requiredSourceRows","jointBindings"]
        else Json.null
      events := events.push (Json.mkObj [("stage",toJson name),("observedMs",value.getObjValD "observedMs"),
        ("pid",value.getObjValD "pid"),("summary",kept)])
    timelines := timelines.push (Json.mkObj [("session",(request.getObjValD "data").getObjValD "session"),
      ("events",toJson events)])
  IO.FS.writeFile (records / "receipt-timeline.json") (toJson timelines).pretty
  IO.FS.writeFile (records / "runtime.json") described.pretty
  IO.FS.writeFile (records / "result.json") (Json.mkObj [
    ("runtime",runtime),("topic",toJson (1 : Nat)),("elapsedMs",actual.getObjValD "elapsedMs"),
    ("availableDelivery",actual.getObjValD "availableDelivery"),("bodySha256",toJson sha),
    ("bodyReference",toJson reference.toString),("sameParentBody",toJson true),("beforeGold",before),
    ("nativeDeliveryAudit",actual.getObjValD "nativeDeliveryAudit"),
    ("actualHooks",toJson (1 : Nat)),("firstSessionsOnly",toJson true),("historyRoundRun",toJson false),
    ("answeringModelCalls",toJson (0 : Nat)),("newSeeds",toJson (0 : Nat)),("adopted",toJson false),
    ("componentGuardClean",toJson false),("latencyComparisonMeasured",toJson false),
    ("p99Measured",toJson false),("tokenImprovementMeasured",toJson false),
    ("sustained80PersonWorkloadVerified",toJson false)]).pretty
  let mut deleted := #[]
  for path in [root / "project-metadata-trial",records / "hooks",root / "project-metadata-audit-trial",
      root / "project-metadata-audit-build",root / "project-metadata-hook-candidate-build"] do
    if ← path.pathExists then
      let (files,bytes) ← remove path
      deleted := deleted.push (Json.mkObj [("path",toJson path.toString),("files",toJson files),("logicalBytes",toJson bytes)])
  for name in ["BindingPageAudit","ProjectMetadataHook"] do
    let path := root / "project-metadata-core/tools/research" / (name ++ ".lean")
    if ← path.pathExists then IO.FS.removeFile path
  for path in inputs do ensure (← System.FilePath.pathExists path) "cleanup removed an active native input"
  for (path,expected) in binaries do ensure ((← hash path) == expected) "cleanup changed an active runtime"
  for (path,expected) in originals do ensure ((← hash (.mk path)) == expected) "cleanup changed a protected source"
  IO.FS.writeFile (records / "retired.json") (Json.mkObj [("deleted",toJson deleted),
    ("retainedNativeInputs",toJson inputs.size),("sourceAndRuntimesUnchanged",toJson true),
    ("compressedOrArchived",toJson false)]).pretty
  IO.println "Preserved unchanged delivery and completed component evidence; deleted ended experiment DBs, caches, helpers and logs"
