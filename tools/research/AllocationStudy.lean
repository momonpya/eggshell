import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
open Lean
namespace AllocationStudy
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def compiler : System.FilePath := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
def source := base/"allocation-probe-source"
def build := base/"allocation-probe-build"
def folder := workspace/"docs/candidates/allocation-probe"
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= (IO.ofExcept ∘ Json.parse)
def write (path : System.FilePath) (value : Json) : IO Unit := IO.FS.writeFile path value.compress
def command (cmd : String) (args : Array String) : IO String := do
  let result ← IO.Process.output {cmd,args,cwd := some workspace}
  check (result.exitCode == 0) (result.stdout++result.stderr)
  return result.stdout
def hash (path : System.FilePath) : IO String :=
  return ((← command "/usr/bin/shasum" #["-a","256",path.toString]).splitOn " ").headD ""
def drained : IO Unit := do
  let rows := (← command "/bin/ps" #["-axo","command="]).splitOn "\n"
  check (!(rows.any fun row => row.contains base.toString && !row.contains "AllocationStudy.lean"))
    "an experiment owner is live"
def guard (tag : String) (args : Array String) : IO Unit := do
  let path := base/(tag++".guard-settings.json")
  check (!(← path.pathExists)) "preserve existing diagnostic guard"
  write path (Json.mkObj [("command",toJson args),("cwd",toJson workspace.toString),
    ("record",toJson (base/(tag++".guard.json")).toString),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])
partial def ensureAt (destination : System.FilePath) (name : String) (seen : IO.Ref (Std.HashSet String)) : IO Unit := do
  if ["Init","Std","Lean"].any (fun rootName => name == rootName || name.startsWith (rootName++".")) then return
  if (← seen.get).contains name then return
  seen.modify (·.insert name)
  let relative := name.replace "." "/"++".lean"
  let path := destination/relative
  if !(← path.pathExists) then
    let original := base/"resident-source-source"/relative
    check (← original.pathExists) ("missing frozen module: "++name)
    IO.FS.createDirAll path.parent.get!
    IO.FS.writeFile path (← IO.FS.readFile original)
  for line in (← IO.FS.readFile path).splitOn "\n" do
    let line := line.trimAscii.toString
    let introducer := if line.startsWith "public import " then "public import " else "import "
    if !line.startsWith introducer then continue
    let words := ((line.drop introducer.length).toString.splitOn " ").filter (!·.isEmpty)
    let words := if words.head? == some "all" then words.drop 1 else words
    if let some imported := words.head? then ensureAt destination imported seen
def ensure (name : String) (seen : IO.Ref (Std.HashSet String)) : IO Unit := ensureAt source name seen
def prepare : IO Unit := do
  drained
  check (!(← source.pathExists) && !(← build.pathExists)) "fresh diagnostic source required"
  IO.FS.createDirAll folder
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",
    (workspace/"tools/research/DiscoveryStagesStudy.lean").toString,"materialize-native",
    (base/"resident-source-auditor-build").toString,source.toString,build.toString,
    "tools.research.AllocationMain",(base/"allocation-probe-settings.json").toString]
  ensure "tools.research.ReplayReadinessChecks" (← IO.mkRef {})
  ensure "tools.research.RealDeliveryProbe" (← IO.mkRef {})
  for (relative,before,after) in [
      ("tools/research/ReplayReadinessChecks.lean","def main := Eggshell.Research.ReplayReadinessChecks.main",
        "def allocationProductMain := Eggshell.Research.ReplayReadinessChecks.main"),
      ("tools/research/RealDeliveryProbe.lean","def main (args : List String) : IO Unit := do",
        "def allocationStudyMain (args : List String) : IO Unit := do")] do
    let path := source/relative
    let text ← IO.FS.readFile path
    check ((text.splitOn before).length == 2) "diagnostic entry alias changed"
    IO.FS.writeFile path (text.replace before after)
  IO.FS.writeFile (source/"tools/research/AllocationMeasure.lean")
    (← IO.FS.readFile (workspace/"tools/research/AllocationMeasure.lean"))
  write (folder/"plan.json") (Json.mkObj [("diagnosticOnly",toJson true),("adopted",toJson false),
    ("counter",toJson "IO.getNumHeartbeats: current-thread small allocations, not bytes/live objects/RSS"),
    ("parentRuntimeSha256",toJson (← hash (base/"resident-source-build/StudyMain"))),
    ("purpose",toJson "fixed source/query stage allocation and cold pure-family construction; no sixteen/eighty load")])
def setup (action tag : String) : IO Unit := do
  drained
  if action == "build" then guard tag #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
    (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"allocation-probe-settings.json").toString]
  else throw (IO.userError "unknown allocation action")
def moduleNames (root : System.FilePath) : IO (Std.HashSet String) := do
  let map ← IO.ofExcept ((← read (root/"object-mapping.json")).getObj?)
  let mut mapping : Std.HashMap String String := {}
  for (path,name) in map.toArray do mapping := mapping.insert path (← IO.ofExcept name.getStr?)
  let build ← read (root/"build.json")
  for row in ← IO.ofExcept ((build.getObjValD "modules").getArr?) do
    mapping := mapping.insert (← IO.ofExcept (row.getObjValAs? String "object"))
      (← IO.ofExcept (row.getObjValAs? String "module"))
  let mut names := {}
  for line in (← IO.FS.readFile (root/"runtime.rsp")).splitOn "\n" do
    if line.trimAscii.isEmpty then continue
    let object ← IO.ofExcept (Json.parse line >>= Json.getStr?)
    if let some name := mapping[object]? then names := names.insert name
  return names
def audit : IO Unit := do
  drained
  let tool := (workspace/"tools/research/StudyBuildClosureAudit.lean").toString
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",tool,"inspect",build.toString,
    (folder/"native-closure.json").toString]
  let sdk := base/"resident-source-auditor-build"
  let product := base/"resident-source-build"
  let parentNames := (← moduleNames sdk).erase "tools.research.RealDeliveryProbe"
  let unionNames := (← moduleNames product).fold (fun found name => found.insert name) (← moduleNames sdk)
    |>.insert "tools.research.AllocationMeasure"
  let additions := unionNames.toArray.filter (!parentNames.contains ·) |>.qsort (· < ·)
  discard <| command (compiler/"bin/lean").toString (#["-j1","-M768","--run",tool,"compare-sources",sdk.toString,build.toString,
    (folder/"native-sources.json").toString,"Eggshell.Handoff","Eggshell.PublicationClient",
    "Eggshell.PublicationService","Eggshell.PublicationWire"]++additions.map ("+"++·))
  check ((← read (folder/"native-sources.json")).getObjValD "exactExpectedChangeSet" == toJson true) "unexpected probe sources"
  let nativeText := fun (root : System.FilePath) (name : String) => do
    let row ← IO.ofExcept ((← read (root/(name++".source"))).getArr?)
    IO.ofExcept row[0]!.getStr?
  let productEntry ← nativeText product "tools_research_ReplayReadinessChecks"
  let studyEntry ← nativeText sdk "tools_research_RealDeliveryProbe"
  check ((← nativeText build "tools_research_ReplayReadinessChecks") == productEntry.replace
    "def main := Eggshell.Research.ReplayReadinessChecks.main" "def allocationProductMain := Eggshell.Research.ReplayReadinessChecks.main")
    "probe changed product entry beyond its alias"
  check ((← nativeText build "tools_research_RealDeliveryProbe") == studyEntry.replace
    "def main (args : List String) : IO Unit := do" "def allocationStudyMain (args : List String) : IO Unit := do")
    "probe changed study driver beyond its alias"
  for name in ["AllocationMain","AllocationMeasure"] do
    check ((← nativeText build ("tools_research_"++name)) == (← IO.FS.readFile (workspace/"tools/research"/(name++".lean"))))
      "compiled instrumentation does not match its source"
  write (folder/"entry-source.json") (Json.mkObj [("productAndStudyAlgorithmsUnchangedBeyondEntryAliases",toJson true),
    ("measurementAndMainSourcesExact",toJson true)])
  for relative in ["Eggshell/Handoff.lean","Eggshell/PublicationClient.lean","Eggshell/PublicationService.lean","Eggshell/PublicationWire.lean"] do
    let result ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","--label","a/"++relative,"--label","b/"++relative,
      (base/"resident-source-source"/relative).toString,(source/relative).toString]}
    check (result.exitCode == 1) "declared diagnostic patch missing"
    IO.FS.writeFile (folder/(relative.replace "/" "_"++".patch")) result.stdout
def prepareTrials : IO Unit := do
  drained
  check ((← read (folder/"native-sources.json")).getObjValD "exactExpectedChangeSet" == toJson true) "seal instrumentation first"
  let installation := base/"allocation-probe-prefix"
  let manifest := base/"allocation-probe-install.json"
  let digest ← hash (build/"StudyMain")
  write manifest (Json.mkObj [("root",toJson installation.toString),
    ("runtime",Json.mkObj [("path",toJson (build/"StudyMain").toString),("sha256",toJson digest)]),
    ("models",toJson (base/"prefix/share/eggshell/minilm").toString)])
  let installArgs := #[(build/"StudyMain").toString,"allocation-install",manifest.toString]
  let installGuard := base/"allocation-probe-install1.guard-settings.json"
  if ← installGuard.pathExists then
    check ((← read installGuard).getObjValD "command" == toJson installArgs) "existing installer differs"
  else guard "allocation-probe-install1" installArgs
  let original ← read (base/"resident-source-cells2.json")
  let root := base/"allocation-probe-cells-result"
  let probes ← IO.ofExcept (original.getObjValAs? (Array Json) "probes")
  let probes ← probes.mapM fun probe => do
    let cell := (System.FilePath.mk (← IO.ofExcept (probe.getObjValAs? String "destination"))).fileName.get!
    let inputArtifact ← IO.ofExcept (probe.getObjValAs? Json "originalInput")
    let originalInput ← read (.mk (← IO.ofExcept (inputArtifact.getObjValAs? String "path")))
    let env ← IO.ofExcept (originalInput.getObjValAs? (Array (String × Option String)) "environment")
    check (!(env.any fun (name,_) => name == "EGGSHELL_RESEARCH_ALLOCATIONS" || name == "EGGSHELL_TRACE_SERVICE_PROFILE"))
      "frozen input shadows inherited measurement flags"
    return probe.setObjVal! "destination" (toJson (root/cell).toString)
      |>.setObjVal! "runtime" (Json.mkObj [("path",toJson (installation/"libexec/eggshell").toString),("sha256",toJson digest)])
      |>.setObjVal! "pluginRoot" (toJson (installation/"share/eggshell/codex-plugin").toString)
  let input := base/"allocation-probe-cells.json"
  write input (Json.mkObj [("output",toJson root.toString),("probes",toJson probes)])
  guard "allocation-probe-cells1" #["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_RESEARCH_ALLOCATIONS=1",
    "EGGSHELL_TRACE_SERVICE_PROFILE=1",(build/"StudyMain").toString,"allocation-cells",input.toString]
def collectMeasurements : IO Unit := do
  drained
  let delivery ← read (folder/"delivery-cells.json")
  check (delivery.getObjValD "actualDeliveryAllSixPassed" == toJson true &&
    delivery.getObjValD "allParentBodiesByteEqual" == toJson true) "actual body parity is required"
  let mut cells : Array Json := #[]
  for topic in [1:4] do
    for repetition in [:2] do
      let root := base/"allocation-probe-cells-result"/s!"topic-{topic}-chat-{repetition}"
      let receipt ← read (root/"receipt.json")
      let stages ← IO.ofExcept (receipt.getObjValAs? (Array Json) "stages")
      let some marker := stages.find? (fun row => row.getObjValD "name" == toJson "provider-keyed-profile.json") |
        throw (IO.userError "missing owned publisher marker")
      let pid ← IO.ofExcept ((marker.getObjValD "record").getObjValAs? Nat "pid")
      let times := stages.filterMap fun row =>
        let value := row.getObjValD "record"
        if value.getObjValD "pid" == toJson pid then (value.getObjValAs? Nat "observedMs").toOption else none
      check (!times.isEmpty) "publisher time interval missing"
      let low := times.foldl min times[0]!
      let high := times.foldl max times[0]!
      cells := cells.push (Json.mkObj [("topic",toJson topic),("repetition",toJson repetition),
        ("pid",toJson pid),("firstMs",toJson low),("lastMs",toJson high),("profiles",toJson (#[] : Array Json))])
  let data := base/"real-source-search-read-trial-result/data/receipts"
  let mut selectedFiles := #[]
  for entry in ← data.readDir do
    if !(← entry.path.isDir) then continue
    for item in ← entry.path.readDir do
      if !(item.fileName.startsWith "allocation-" || ["render-client-profile.json","source-plan-profile.json",
          "source-fetch-allocations.json"].contains item.fileName) then continue
      let value ← read item.path
      let pid ← IO.ofExcept (value.getObjValAs? Nat "pid")
      let observed ← IO.ofExcept (value.getObjValAs? Nat "observedMs")
      let matched := (Array.range cells.size).filter fun index =>
        let cell := cells[index]!
        cell.getObjValD "pid" == toJson pid &&
          (cell.getObjValAs? Nat "firstMs").toOption.getD 0 ≤ observed &&
          observed ≤ (cell.getObjValAs? Nat "lastMs").toOption.getD 0
      check (matched.size ≤ 1) "metric cannot belong to two requests"
      if let some index := matched[0]? then
        let cell := cells[index]!
        let profiles ← IO.ofExcept (cell.getObjValAs? (Array Json) "profiles")
        let kept := Json.mkObj [("file",toJson item.path.toString),("sha256",toJson (← hash item.path)),
          ("record",value)]
        cells := cells.set! index (cell.setObjVal! "profiles" (toJson (profiles.push kept)))
        selectedFiles := selectedFiles.push item.path.toString
  for cell in cells do
    let rows ← IO.ofExcept (cell.getObjValAs? (Array Json) "profiles")
    for required in ["allocation-family-inputs","source-plan-profile","render-client-profile","source-fetch-allocations"] do
      check ((rows.filter (fun row => (row.getObjValD "record").getObjValD "stage" == toJson required)).size == 1)
        ("missing or repeated measurement: "++required)
  write (folder/"measurements.json") (Json.mkObj [("cells",toJson cells),("selectedFiles",toJson selectedFiles),
    ("joinedByPublisherPidAndObservedTime",toJson true),("counterIsNotBytesOrRss",toJson true),
    ("missingColonNamedDiscoveryCheckpoints",toJson true),("newLoadRuns",toJson (0 : Nat)),("adopted",toJson false)])

/-- Compare the witnesses of objects actually selected by the linker. Reading
the mutable source tree alone would not rule out a stale encoder object. -/
def linkedWitnesses (root : System.FilePath) : IO (Std.HashMap String String) := do
  let mapping ← IO.ofExcept ((← read (root/"object-mapping.json")).getObj?)
  let mut modules : Std.HashMap String String := {}
  for (path,name) in mapping.toArray do
    modules := modules.insert path (← IO.ofExcept name.getStr?)
  for row in ← IO.ofExcept ((← read (root/"build.json")).getObjValD "modules").getArr? do
    modules := modules.insert (← IO.ofExcept (row.getObjValAs? String "object"))
      (← IO.ofExcept (row.getObjValAs? String "module"))
  let mut result : Std.HashMap String String := {}
  for line in (← IO.FS.readFile (root/"runtime.rsp")).splitOn "\n" do
    if line.trimAscii.isEmpty then continue
    let path ← IO.ofExcept (Json.parse line >>= Json.getStr?)
    let some name := modules[path]? | continue
    let witness ← IO.FS.readFile (System.FilePath.mk path |>.withExtension "source")
    if let some prior := result[name]? then check (prior == witness) "conflicting linked encoder witnesses"
    result := result.insert name witness
  return result

def encoderAudit (currentName : String := "resident-source") (outputName : String := "allocation-probe") : IO Unit := do
  drained
  let validated := base/"typed-plan-build"
  let current := base/(currentName++"-build")
  let controls ← read (workspace/"docs/candidates/typed-plan/encoder-controls.json")
  check (controls.getObjValD "runtimeSha256" == toJson (← hash (validated/"StudyMain")))
    "numerical controls belong to another binary"
  let report := controls.getObjValD "controls"
  check (report.getObjValD "all48RepliesExactVectorsAndCoverage" == toJson true)
    "exact concurrent vectors are not established"
  let original ← linkedWitnesses validated
  let mut compared := #[]
  for root in (if currentName == "resident-source" then [current,build] else [current]) do
    let actual ← linkedWitnesses root
    for name in ["Eggshell.Numerical","Eggshell.MiniLM","Eggshell.TaskDeadline",
        "tools.research.SharedEncoder","tools.research.EncoderPool","tools.research.EventScope"] do
      let some expected := original[name]? | throw (IO.userError ("missing validated boundary: "++name))
      let some found := actual[name]? | throw (IO.userError ("missing current boundary: "++name))
      check (found == expected) ("compiled encoder boundary changed: "++name)
      compared := compared.push (Json.mkObj [("runtime",toJson root.toString),("module",toJson name),
        ("linkedSourceAndLiteralsEqual",toJson true)])
  let mut waves := #[]
  for name in ["coldWave","warmWave"] do
    let wave := report.getObjValD name
    let stats := wave.getObjValD "endStats"
    check (wave.getObjValD "sharedModelRequestIntervalsOverlap" == toJson true &&
      stats.getObjValD "modelStarts" == toJson (1 : Nat) &&
      stats.getObjValD "computeCapacity" == toJson (2 : Nat)) "parallel inference is not established"
    waves := waves.push (Json.mkObj [("name",toJson name),("requests",wave.getObjValD "requests"),
      ("wallMs",wave.getObjValD "wallMs"),("overlap",toJson true),
      ("modelProcesses",toJson (1 : Nat)),("computeCapacity",toJson (2 : Nat))])
  let destination := workspace/"docs/candidates"/outputName
  IO.FS.createDirAll destination
  write (destination/"encoder-boundary.json") (Json.mkObj [("validatedRuntimeSha256",controls.getObjValD "runtimeSha256"),
    ("currentRuntimeSha256",toJson (← hash (current/"StudyMain"))),
    ("compiledBoundary",toJson compared),("previousNativeWaves",toJson waves),
    ("all48RepliesExactVectorsAndCoverage",toJson true),("newEncoderRuns",toJson (0 : Nat)),
    ("entireReadPathLockFree",toJson false),("eightyUsersValidated",toJson false),("adopted",toJson false)])

def measurementSummary : IO Unit := do
  let evidence ← read (folder/"measurements.json")
  let mut cells := #[]
  for cell in ← IO.ofExcept (evidence.getObjValAs? (Array Json) "cells") do
    let profiles ← IO.ofExcept (cell.getObjValAs? (Array Json) "profiles")
    let profile := fun name => ((profiles.find? fun row =>
      (row.getObjValD "record").getObjValD "stage" == toJson name).getD Json.null).getObjValD "record" |>.getObjValD "data"
    let render := profile "render-client-profile"
    let fetch := profile "source-fetch-allocations"
    let families ← IO.ofExcept ((profile "allocation-family-inputs").getObjValAs? (Array Json) "families")
    let sum := fun name field => families.foldl (fun total row => total+
      ((row.getObjValD name).getObjValAs? Nat field).toOption.getD 0) 0
    let mut allocations := #[]
    for name in ["query","select","fetchRequests","fetch","materialize","finish"] do
      allocations := allocations.push (name,((render.getObjValD "allocations").getObjValD name).getObjValD "smallAllocations")
    cells := cells.push (Json.mkObj [("topic",cell.getObjValD "topic"),("repetition",cell.getObjValD "repetition"),
      ("sourceKeys",render.getObjValD "sourceKeys"),("queryMs",render.getObjValD "queryMs"),
      ("selectMs",render.getObjValD "selectMs"),("fetchMs",render.getObjValD "fetchMs"),
      ("materializeMs",render.getObjValD "materializeMs"),("finishMs",render.getObjValD "finishMs"),
      ("smallAllocations",Json.mkObj allocations.toList),
      ("nestedFetchMergeSmallAllocations",(fetch.getObjValD "merge").getObjValD "smallAllocations"),
      ("independentCharacterProbeUs",toJson (sum "independentCharacterIndexProbe" "elapsedUs")),
      ("independentPreparationProbeUs",toJson (sum "actualCandidatePreparation" "elapsedUs"))])
  write (folder/"measurement-summary.json") (Json.mkObj [("cells",toJson cells),
    ("nestedPhasesMustNotBeAddedAgain",toJson true),("independentProbesExcludedFromProductionTotals",toJson true),
    ("smallAllocationsAreNotBytesOrLiveHeap",toJson true),("adopted",toJson false)])

def cleanupMeasurements : IO Unit := do
  drained
  check (← (folder/"measurement-summary.json").pathExists) "collect scalar evidence before deletion"
  let evidence ← read (folder/"measurements.json")
  let receiptRoot := base/"real-source-search-read-trial-result/data/receipts"
  let mut verified : Array (System.FilePath × String) := #[]
  for cell in ← IO.ofExcept (evidence.getObjValAs? (Array Json) "cells") do
    for profile in ← IO.ofExcept (cell.getObjValAs? (Array Json) "profiles") do
      let path := System.FilePath.mk (← IO.ofExcept (profile.getObjValAs? String "file"))
      check (path.parent.bind System.FilePath.parent == some receiptRoot) "profile escaped the ended receipt domain"
      let digest ← IO.ofExcept (profile.getObjValAs? String "sha256")
      check ((← hash path) == digest) "profile changed after collection"
      verified := verified.push (path,digest)
  let mut removed := #[]
  for (path,digest) in verified do
    IO.FS.removeFile path
    if (← path.parent.get!.readDir).isEmpty then IO.FS.removeDir path.parent.get!
    removed := removed.push (Json.mkObj [("path",toJson path.toString),("sha256",toJson digest)])
  write (folder/"measurement-cleanup.json") (Json.mkObj [("removed",toJson removed),
    ("savedScalarProfiles",toJson true),("archiveCreated",toJson false),("originalAndProjectCacheUnchanged",toJson true)])

def canonicalSetup (tag : String) : IO Unit := do
  drained
  let candidate := base/"canonical-order-source"
  let destination := workspace/"docs/candidates/canonical-order"
  IO.FS.createDirAll destination
  IO.FS.writeFile (candidate/"tools/research/CanonicalOrderChecks.lean")
    (← IO.FS.readFile (workspace/"tools/research/CanonicalOrderChecks.lean"))
  let entry := candidate/"tools/research/ReplayReadinessChecks.lean"
  let text ← IO.FS.readFile entry
  unless text.contains "import tools.research.CanonicalOrderChecks" do
    let marker := "import tools.research.ResidentSourceChecks"
    check ((text.splitOn marker).length == 2) "actual parent entry changed"
    IO.FS.writeFile entry (text.replace marker (marker++"\nimport tools.research.CanonicalOrderChecks") |>.replace
      "  | [\"resident-source-check\",fixture,sha,output] =>"
      ("  | [\"canonical-order-check\",fixture,sha,output] =>\n"++
       "    Eggshell.Research.CanonicalOrderChecks.run (.mk fixture) sha (.mk output); return 0\n"++
       "  | [\"resident-source-check\",fixture,sha,output] =>"))
  write (destination/"plan.json") (Json.mkObj [("parentRuntimeSha256",toJson (← hash (base/"resident-source-build/StudyMain"))),
    ("change",toJson "memoize exact per-origin and per-file ordering values; retain validation, full order and all provenance"),
    ("duplicateNormalizationStillPresent",toJson true),("adopted",toJson false),("answeringModelCalls",toJson (0 : Nat))])
  guard tag #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
    (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"canonical-order-settings.json").toString]

def canonicalComponent (tag : String) : IO Unit := do
  drained
  let fixture := base/"real-source-search-read-trial-result/data/reply-witnesses/affacad8c38e209788a0eafb78d716bda6237f42a0b995594a4af87c9089a6f2.json"
  guard tag #["/usr/bin/env","LEAN_NUM_THREADS=1",(base/"canonical-order-build/StudyMain").toString,
    "canonical-order-check",fixture.toString,(← hash fixture),(base/(tag++"-result.json")).toString]

def canonicalAudit : IO Unit := do
  drained
  let target := base/"canonical-order-build"
  let destination := workspace/"docs/candidates/canonical-order"
  let auditTool := (workspace/"tools/research/StudyBuildClosureAudit.lean").toString
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",auditTool,
    "inspect",target.toString,(destination/"native-closure.json").toString]
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",auditTool,
    "compare-sources",(base/"resident-source-build").toString,target.toString,
    (destination/"native-sources.json").toString,"Eggshell.CanonicalSourceDelivery","+tools.research.CanonicalOrderChecks"]
  check ((← read (destination/"native-sources.json")).getObjValD "exactExpectedChangeSet" == toJson true)
    "canonical ordering changed unrelated native sources"
  let entryName := "tools_research_ReplayReadinessChecks.source"
  let nativeEntry ← IO.ofExcept ((← read (target/entryName)).getArr?)
  let parentEntry ← IO.ofExcept ((← read (base/"resident-source-build"/entryName)).getArr?)
  let before ← IO.ofExcept parentEntry[0]!.getStr?
  let expected := before.replace "import tools.research.ResidentSourceChecks"
      "import tools.research.ResidentSourceChecks\nimport tools.research.CanonicalOrderChecks" |>.replace
    "  | [\"resident-source-check\",fixture,sha,output] =>"
    ("  | [\"canonical-order-check\",fixture,sha,output] =>\n"++
     "    Eggshell.Research.CanonicalOrderChecks.run (.mk fixture) sha (.mk output); return 0\n"++
     "  | [\"resident-source-check\",fixture,sha,output] =>")
  check (nativeEntry[0]! == toJson expected) "entry changed beyond the comparison dispatch"
  let checks ← IO.ofExcept ((← read (target/"tools_research_CanonicalOrderChecks.source")).getArr?)
  check (checks[0]! == toJson (← IO.FS.readFile (workspace/"tools/research/CanonicalOrderChecks.lean")))
    "native checks differ from recorded independent parent"
  let relative := "Eggshell/CanonicalSourceDelivery.lean"
  let difference ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","--label","a/"++relative,"--label","b/"++relative,
    (base/"resident-source-source"/relative).toString,(base/"canonical-order-source"/relative).toString]}
  check (difference.exitCode == 1) "expected ordering refinement is absent"
  IO.FS.writeFile (destination/"CanonicalSourceDelivery.patch") difference.stdout
  write (destination/"entry-source.json") (Json.mkObj [("onlyComparisonDispatchAdded",toJson true),
    ("independentParentAndNativeChecksExact",toJson true)])

def canonicalCollectComponent (tag : String) : IO Unit := do
  drained
  let destination := workspace/"docs/candidates/canonical-order"
  let g ← read (base/(tag++".guard.json"))
  check (g.getObjValD "state" == toJson "finished" && g.getObjValD "exitCode" == toJson (0 : Nat) &&
    g.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "component did not finish and release its owners"
  let report ← read (base/(tag++"-result.json"))
  write (destination/"component.json") (Json.mkObj [("report",report),("guard",g),
    ("runtimeSha256",toJson (← hash (base/"canonical-order-build/StudyMain"))),
    ("adopted",toJson false),("answeringModelCalls",toJson (0 : Nat))])

def canonicalPrepareAuditor : IO Unit := do
  drained
  let destination := workspace/"docs/candidates/canonical-order"
  check ((← read (destination/"native-sources.json")).getObjValD "exactExpectedChangeSet" == toJson true)
    "verify the product before the actual delivery driver"
  let candidate := base/"canonical-order-source"
  let target := base/"canonical-order-build"
  ensureAt candidate "tools.research.RealDeliveryProbe" (← IO.mkRef {})
  let settings ← read (base/"canonical-order-settings.json")
  let parents ← IO.ofExcept (settings.getObjValAs? (Array String) "parents")
  write (base/"canonical-order-auditor-settings.json") (settings.setObjVal! "output"
      (toJson (base/"canonical-order-auditor-build").toString)
    |>.setObjVal! "mainModule" (toJson "tools.research.RealDeliveryProbe")
    |>.setObjVal! "parents" (toJson (#[target.toString]++parents))
    |>.setObjVal! "baselineResponse" (toJson (target/"runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (target/"tools_research_ReplayReadinessChecks.o").toString))
  guard "canonical-order-auditor-build1" #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
    (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"canonical-order-auditor-settings.json").toString]

def canonicalPrepareCells : IO Unit := do
  drained
  let target := base/"canonical-order-build"
  let auditor := base/"canonical-order-auditor-build"
  let destination := workspace/"docs/candidates/canonical-order"
  let auditTool := (workspace/"tools/research/StudyBuildClosureAudit.lean").toString
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",auditTool,
    "inspect",auditor.toString,(destination/"auditor-closure.json").toString]
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",auditTool,
    "common-sources",target.toString,auditor.toString,(destination/"auditor-sources.json").toString]
  let proof ← read (destination/"auditor-sources.json")
  check (proof.getObjValD "allProductCorePresent" == toJson true && proof.getObjValD "commonSourcesUnchanged" == toJson true)
    "actual delivery driver differs from product core"
  let installation := base/"canonical-order-prefix"
  let digest ← hash (target/"StudyMain")
  let manifest := base/"canonical-order-install.json"
  write manifest (Json.mkObj [("root",toJson installation.toString),
    ("runtime",Json.mkObj [("path",toJson (target/"StudyMain").toString),("sha256",toJson digest)]),
    ("models",toJson (base/"prefix/share/eggshell/minilm").toString)])
  guard "canonical-order-install1" #[(auditor/"StudyMain").toString,"install-prefix",manifest.toString]
  let original ← read (base/"resident-source-cells2.json")
  let root := base/"canonical-order-cells-result"
  let probes ← IO.ofExcept (original.getObjValAs? (Array Json) "probes")
  let probes ← probes.mapM fun probe => do
    let cell := (System.FilePath.mk (← IO.ofExcept (probe.getObjValAs? String "destination"))).fileName.get!
    return probe.setObjVal! "destination" (toJson (root/cell).toString)
      |>.setObjVal! "runtime" (Json.mkObj [("path",toJson (installation/"libexec/eggshell").toString),("sha256",toJson digest)])
      |>.setObjVal! "pluginRoot" (toJson (installation/"share/eggshell/codex-plugin").toString)
  write (base/"canonical-order-cells.json") (Json.mkObj [("output",toJson root.toString),("probes",toJson probes)])
  guard "canonical-order-cells1" #["/usr/bin/env","LEAN_NUM_THREADS=1",(auditor/"StudyMain").toString,
    "cells",(base/"canonical-order-cells.json").toString]

def canonicalRetire : IO Unit := do
  drained
  let destination := workspace/"docs/candidates/canonical-order"
  check ((← read (destination/"capacity-80-cleanup.json")).getObjValD "completed" == toJson true &&
    (← read (destination/"delivery-cells.json")).getObjValD "allParentBodiesByteEqual" == toJson true)
    "preserve and clean ended owners before retiring their scratch data"
  for path in [destination/"capacity-small-cleanup.json",destination/"delivery-cleanup.json",
      folder/"delivery-cleanup.json",folder/"measurement-cleanup.json"] do
    check (← path.pathExists) "ended receipts are not yet accounted for"
  let oldDigest ← IO.ofExcept ((← read (folder/"installed-runtime.json")).getObjValAs? String "sha256")
  let capacityDigest ← IO.ofExcept ((← read (destination/"capacity-sources.json")).getObjValAs? String "auditorSha256")
  let mut executables := #[]
  for (path,expected) in [(base/"allocation-probe-build/StudyMain",oldDigest),
      (base/"allocation-probe-prefix/libexec/eggshell",oldDigest),
      (base/"canonical-order-capacity-build/StudyMain",capacityDigest)] do
    check ((← hash path) == expected) "ended executable changed or is not the recorded runtime"
    executables := executables.push (Json.mkObj [("path",toJson path.toString),("sha256",toJson expected),
      ("logicalBytes",toJson (← path.metadata).byteSize.toNat)])
  let directories := #[base/"allocation-probe-cells-result",base/"canonical-order-capacity-small-result",
    base/"canonical-order-capacity-80-result"]
  for path in directories do check (← path.isDir) "ended scratch directory disappeared unexpectedly"
  let mut logs : Array (System.FilePath × String) := #[]
  for tag in ["canonical-order-build1","canonical-order-build2","canonical-order-build3",
      "canonical-order-auditor-build1","canonical-order-install1","canonical-order-cells1","canonical-order-capacity-build1"] do
    let saved ← read (destination/(tag++".json"))
    for extension in ["stdout","stderr"] do
      let path := base/(tag++"."++extension)
      check ((← IO.FS.readFile path) == (← IO.ofExcept (saved.getObjValAs? String extension)))
        "raw log differs from its preserved ended record"
      logs := logs.push (path,← hash path)
  for mode in ["small","80"] do
    let tag := "canonical-order-capacity-"++mode++"1"
    let stdoutPath := base/(tag++".stdout")
    check ((← IO.FS.readFile stdoutPath).isEmpty) "uncollected capacity stdout"
    let stderrPath := base/(tag++".stderr")
    check ((← IO.FS.readFile stderrPath) == (← IO.FS.readFile (destination/("capacity-"++mode++"-stderr.txt"))))
      "capacity stderr differs from preserved evidence"
    logs := logs.push (stdoutPath,← hash stdoutPath) |>.push (stderrPath,← hash stderrPath)
  for extension in ["stdout","stderr"] do
    let path := base/("canonical-order-component1."++extension)
    check ((← IO.FS.readFile path).isEmpty) "uncollected component output"
    logs := logs.push (path,← hash path)
  let record := Json.mkObj [("executables",toJson executables),("scratchDirectories",toJson (directories.map (·.toString))),
    ("duplicateLogs",toJson (logs.map fun (path,digest) => Json.mkObj [("path",toJson path.toString),("sha256",toJson digest)])),
    ("archiveCreated",toJson false),("sizesAreLogicalNotReclaimedPhysicalBytes",toJson true),
    ("currentProductAuditorNativeInputsOriginalDbProjectCacheModelsAndEvidenceRetained",toJson true)]
  write (destination/"retired-ended-artifacts.json") (record.setObjVal! "completed" (toJson false))
  for row in executables do IO.FS.removeFile (.mk (← IO.ofExcept (row.getObjValAs? String "path")))
  for (path,_) in logs do IO.FS.removeFile path
  for path in directories do IO.FS.removeDirAll path
  write (destination/"retired-ended-artifacts.json") (record.setObjVal! "completed" (toJson true))
def main (args : List String) : IO Unit := do
  match args with
  | ["prepare"] => prepare
  | ["setup",action,tag] => setup action tag
  | ["refresh-measure"] =>
    drained
    IO.FS.writeFile (source/"tools/research/AllocationMeasure.lean")
      (← IO.FS.readFile (workspace/"tools/research/AllocationMeasure.lean"))
  | ["audit"] => audit
  | ["prepare-trials"] => prepareTrials
  | ["measurements"] => collectMeasurements
  | ["summary"] => measurementSummary
  | ["encoder-audit"] => encoderAudit
  | ["encoder-audit",current,destination] => encoderAudit current destination
  | ["cleanup-measurements"] => cleanupMeasurements
  | ["canonical-setup",tag] => canonicalSetup tag
  | ["canonical-component",tag] => canonicalComponent tag
  | ["canonical-audit"] => canonicalAudit
  | ["canonical-collect-component",tag] => canonicalCollectComponent tag
  | ["canonical-prepare-auditor"] => canonicalPrepareAuditor
  | ["canonical-prepare-cells"] => canonicalPrepareCells
  | ["canonical-retire"] => canonicalRetire
  | ["canonical-seal-installed"] =>
    drained
    let target := base/"canonical-order-build/StudyMain"
    let path := base/"canonical-order-prefix/libexec/eggshell"
    let digest ← hash target
    check ((← hash path) == digest) "installed runtime differs from canonical-order product"
    let link := path.withExtension "shared"
    check (!(← link.pathExists)) "sharing temporary exists"
    discard <| command "/bin/ln" #[target.toString,link.toString]
    IO.FS.rename link path
    write (workspace/"docs/candidates/canonical-order/installed-runtime.json")
      (Json.mkObj [("sha256",toJson digest),("sharesImmutableProductInode",toJson true)])
  | ["seal-installed"] =>
    drained
    let path := base/"allocation-probe-prefix/libexec/eggshell"
    let digest ← hash (build/"StudyMain")
    check (digest == (← hash path)) "installed diagnostic differs"
    let link := path.withExtension "shared"
    check (!(← link.pathExists)) "sharing temporary exists"
    discard <| command "/bin/ln" #[(build/"StudyMain").toString,link.toString]
    IO.FS.rename link path
    write (folder/"installed-runtime.json") (Json.mkObj [("sha256",toJson digest),("sharesImmutableProductInode",toJson true)])
  | ["collect",tag] =>
    drained
    let g ← read (base/(tag++".guard.json"))
    check (g.getObjValD "state" == toJson "finished" && g.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "owner not drained"
    let destination := if tag.startsWith "canonical-order-" then workspace/"docs/candidates/canonical-order" else folder
    write (destination/(tag++".json")) (Json.mkObj [("guard",g),
      ("stdout",toJson (← IO.FS.readFile (base/(tag++".stdout")))),
      ("stderr",toJson (← IO.FS.readFile (base/(tag++".stderr"))))])
  | _ => throw (IO.userError "unknown allocation operation")
end AllocationStudy
def main := AllocationStudy.main
