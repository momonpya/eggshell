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
  if ← (validated/"StudyMain").pathExists then
    check (controls.getObjValD "runtimeSha256" == toJson (← hash (validated/"StudyMain")))
      "numerical controls belong to another binary"
  else
    let retired ← read (workspace/"docs/candidates/deferred-audit/retired-earlier-products.json")
    let rows ← IO.ofExcept (retired.getObjValAs? (Array Json) "executables")
    check (retired.getObjValD "completed" == toJson true && rows.any (fun row =>
      row.getObjValD "path" == toJson (validated/"StudyMain").toString &&
      row.getObjValD "sha256" == controls.getObjValD "runtimeSha256"))
      "missing validated executable has no matching completed retirement record"
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

def inspectDecodedReaders : IO Unit := do
  drained
  let family := "deferred-audit"
  let actual ← linkedWitnesses (base/(family++"-build"))
  let take := fun (text first last : String) => do
    let parts := text.splitOn first
    check (parts.length == 2) "ambiguous decoded-reader declaration"
    let tail := parts[1]!.splitOn last
    check (tail.length > 1) "missing decoded-reader declaration end"
    pure (first++tail[0]!)
  let mut modules := #[]
  let mut texts : Std.HashMap String String := {}
  for name in ["Eggshell.GraphStore","Eggshell.PreparedReaders","Eggshell.Handoff"] do
    let some witness := actual[name]? | throw (IO.userError "missing actual reader source witness")
    let row ← IO.ofExcept (Json.parse witness >>= Json.getArr?)
    let text ← IO.ofExcept row[0]!.getStr?
    let path := base/(family++"-source")/(name.replace "." "/"++".lean")
    check (text == (← IO.FS.readFile path)) "reader observation does not match its actual linked source"
    texts := texts.insert name text
    modules := modules.push (Json.mkObj [("module",toJson name),("sourceSha256",toJson (← hash path)),
      ("actualLinkedSourceEqual",toJson true)])
  let graph := texts["Eggshell.GraphStore"]!
  let readers ← take graph "@[no_expose] def NodeReaders.new" "\n@[no_expose] def NodeReaders.at"
  let memo ← take graph "private structure NodeMemo" "\n/-- A request-local DAG reader"
  let frame ← take texts["Eggshell.PreparedReaders"]! "structure Image where" "\ndef maxBytes"
  let federation ← take texts["Eggshell.Handoff"]! "def federatedDiscovery (" "\ndef "
  check (readers.contains "snapshots.mapM fun _ => NodeMemo.new" && memo.contains "IO.mkRef {}" &&
    federation.contains "let readers ← Persistence.Store.NodeReaders.new sources" && !frame.contains "NodeReader")
    "the proposed repeated decoded-value allocation is not present"
  write (workspace/"docs/candidates"/family/"decoded-reader-observation.json") (Json.mkObj [
    ("runtimeSha256",toJson (← hash (base/(family++"-build/StudyMain")))),("modules",toJson modules),
    ("requestLocalMemo",toJson memo),("readerCreation",toJson readers),("sharedImageFields",toJson frame),
    ("federatedReaderCreation",toJson "let readers ← Persistence.Store.NodeReaders.new sources"),
    ("newLoadRuns",toJson (0 : Nat)),("measuredHeapCauseEstablished",toJson false),
    ("next",toJson "Share checked decoded immutable nodes by full project/scope/head; retain private overlays and replay original read observations. Preserve Outcome membership and Exact checks.")])

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

def canonicalComponent (tag : String) (family : String := "canonical-order") : IO Unit := do
  drained
  check (["canonical-order","single-canonical"].contains family) "unknown source component"
  let fixture := base/"real-source-search-read-trial-result/data/reply-witnesses/affacad8c38e209788a0eafb78d716bda6237f42a0b995594a4af87c9089a6f2.json"
  guard tag #["/usr/bin/env","LEAN_NUM_THREADS=1",(base/(family++"-build/StudyMain")).toString,
    family++"-check",fixture.toString,(← hash fixture),(base/(tag++"-result.json")).toString]

def canonicalAudit (family : String := "canonical-order") : IO Unit := do
  drained
  check (["canonical-order","rendering-lifetime","single-canonical","deferred-audit"].contains family) "unknown native refinement"
  let rendering := family == "rendering-lifetime"
  let single := family == "single-canonical"
  let deferred := family == "deferred-audit"
  let parent := if deferred then "single-canonical" else if rendering || single then "canonical-order" else "resident-source"
  let target := base/(family++"-build")
  let destination := workspace/"docs/candidates"/family
  let auditTool := (workspace/"tools/research/StudyBuildClosureAudit.lean").toString
  discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",auditTool,
    "inspect",target.toString,(destination/"native-closure.json").toString]
  let changes := if deferred then #["Eggshell.Handoff","Eggshell.SelectionAudit","Eggshell.ContractAudit",
      "+tools.research.DeferredAuditChecks"]
    else if single then #["Eggshell.CanonicalSourceDelivery","Eggshell.PublicationClient","Eggshell.Handoff",
      "tools.research.RuntimeReadControls","+tools.research.SingleCanonicalChecks"]
    else if rendering then #["Eggshell.Handoff","Eggshell.SelectionAudit","Eggshell.ContractAudit",
      "+tools.research.RenderingLifetimeChecks"]
    else #["Eggshell.CanonicalSourceDelivery","+tools.research.CanonicalOrderChecks"]
  discard <| command (compiler/"bin/lean").toString (#["-j1","-M768","--run",auditTool,
    "compare-sources",(base/(parent++"-build")).toString,target.toString,
    (destination/"native-sources.json").toString]++changes)
  check ((← read (destination/"native-sources.json")).getObjValD "exactExpectedChangeSet" == toJson true)
    "canonical ordering changed unrelated native sources"
  let entryName := "tools_research_ReplayReadinessChecks.source"
  let nativeEntry ← IO.ofExcept ((← read (target/entryName)).getArr?)
  let parentEntry ← IO.ofExcept ((← read (base/(parent++"-build")/entryName)).getArr?)
  let before ← IO.ofExcept parentEntry[0]!.getStr?
  let expected := if deferred then before.replace "import tools.research.SingleCanonicalChecks"
      "import tools.research.SingleCanonicalChecks\nimport tools.research.DeferredAuditChecks"
    else if single then before.replace "import tools.research.CanonicalOrderChecks"
      "import tools.research.CanonicalOrderChecks\nimport tools.research.SingleCanonicalChecks" |>.replace
      "  | [\"canonical-order-check\",fixture,sha,output] =>"
      ("  | [\"single-canonical-check\",fixture,sha,output] =>\n"++
       "    Eggshell.Research.SingleCanonicalChecks.run (.mk fixture) sha (.mk output); return 0\n"++
       "  | [\"canonical-order-check\",fixture,sha,output] =>")
    else if rendering then before.replace "import tools.research.CanonicalOrderChecks"
      "import tools.research.CanonicalOrderChecks\nimport tools.research.RenderingLifetimeChecks"
    else before.replace "import tools.research.ResidentSourceChecks"
      "import tools.research.ResidentSourceChecks\nimport tools.research.CanonicalOrderChecks" |>.replace
    "  | [\"resident-source-check\",fixture,sha,output] =>"
    ("  | [\"canonical-order-check\",fixture,sha,output] =>\n"++
     "    Eggshell.Research.CanonicalOrderChecks.run (.mk fixture) sha (.mk output); return 0\n"++
     "  | [\"resident-source-check\",fixture,sha,output] =>")
  check (nativeEntry[0]! == toJson expected) "entry changed beyond the comparison dispatch"
  let checkName := if deferred then "DeferredAuditChecks" else if single then "SingleCanonicalChecks" else if rendering then "RenderingLifetimeChecks" else "CanonicalOrderChecks"
  let checks ← IO.ofExcept ((← read (target/("tools_research_"++checkName++".source"))).getArr?)
  check (checks[0]! == toJson (← IO.FS.readFile (workspace/("tools/research/"++checkName++".lean"))))
    "native checks differ from recorded independent parent"
  for moduleName in changes.toList.filter (!·.startsWith "+") do
    let relative := moduleName.replace "." "/"++".lean"
    let name := if moduleName.startsWith "Eggshell." then (moduleName.drop "Eggshell.".length).toString
      else moduleName.replace "." "_"
    let difference ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","--label","a/"++relative,"--label","b/"++relative,
      (base/(parent++"-source")/relative).toString,(base/(family++"-source")/relative).toString]}
    check (difference.exitCode == 1) "expected native refinement is absent"
    IO.FS.writeFile (destination/(name++".patch")) difference.stdout
  write (destination/"entry-source.json") (Json.mkObj [
    (if rendering || deferred then "onlyCheckedImportAdded" else "onlyComparisonDispatchAdded",toJson true),
    ("independentParentAndNativeChecksExact",toJson true)])

def canonicalCollectComponent (tag : String) (family : String := "canonical-order") : IO Unit := do
  drained
  let destination := workspace/"docs/candidates"/family
  let g ← read (base/(tag++".guard.json"))
  check (g.getObjValD "state" == toJson "finished" && g.getObjValD "exitCode" == toJson (0 : Nat) &&
    g.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "component did not finish and release its owners"
  let report ← read (base/(tag++"-result.json"))
  write (destination/"component.json") (Json.mkObj [("report",report),("guard",g),
    ("runtimeSha256",toJson (← hash (base/(family++"-build/StudyMain")))),
    ("adopted",toJson false),("answeringModelCalls",toJson (0 : Nat))])

def canonicalPrepareAuditor (family : String := "canonical-order") : IO Unit := do
  drained
  let destination := workspace/"docs/candidates"/family
  check ((← read (destination/"native-sources.json")).getObjValD "exactExpectedChangeSet" == toJson true)
    "verify the product before the actual delivery driver"
  let candidate := base/(family++"-source")
  let target := base/(family++"-build")
  ensureAt candidate "tools.research.RealDeliveryProbe" (← IO.mkRef {})
  let settings ← read (base/(family++"-settings.json"))
  let parents ← IO.ofExcept (settings.getObjValAs? (Array String) "parents")
  write (base/(family++"-auditor-settings.json")) (settings.setObjVal! "output"
      (toJson (base/(family++"-auditor-build")).toString)
    |>.setObjVal! "mainModule" (toJson "tools.research.RealDeliveryProbe")
    |>.setObjVal! "parents" (toJson (#[target.toString]++parents))
    |>.setObjVal! "baselineResponse" (toJson (target/"runtime.rsp").toString)
    |>.setObjVal! "baselineMain" (toJson (target/"tools_research_ReplayReadinessChecks.o").toString))
  guard (family++"-auditor-build1") #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
    (workspace/"tools/research/StudyBuildMain.lean").toString,(base/(family++"-auditor-settings.json")).toString]

def canonicalPrepareCells (family : String := "canonical-order") (attempt : Nat := 1) : IO Unit := do
  drained
  check (attempt > 0) "positive actual delivery attempt required"
  let target := base/(family++"-build")
  let auditor := base/(family++"-auditor-build")
  let destination := workspace/"docs/candidates"/family
  let auditTool := (workspace/"tools/research/StudyBuildClosureAudit.lean").toString
  if attempt == 1 then
    discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",auditTool,
      "inspect",auditor.toString,(destination/"auditor-closure.json").toString]
    discard <| command (compiler/"bin/lean").toString #["-j1","-M768","--run",auditTool,
      "common-sources",target.toString,auditor.toString,(destination/"auditor-sources.json").toString]
  let proof ← read (destination/"auditor-sources.json")
  check (proof.getObjValD "allProductCorePresent" == toJson true && proof.getObjValD "commonSourcesUnchanged" == toJson true &&
    proof.getObjValD "auditorSha256" == toJson (← hash (auditor/"StudyMain")))
    "actual delivery driver differs from product core"
  let installation := base/(family++"-prefix")
  let digest ← hash (target/"StudyMain")
  let manifest := base/(family++"-install.json")
  write manifest (Json.mkObj [("root",toJson installation.toString),
    ("runtime",Json.mkObj [("path",toJson (target/"StudyMain").toString),("sha256",toJson digest)]),
    ("models",toJson (base/"prefix/share/eggshell/minilm").toString)])
  if attempt == 1 then guard (family++"-install1") #[(auditor/"StudyMain").toString,"install-prefix",manifest.toString]
  let original ← read (base/"resident-source-cells2.json")
  let label := family++"-cells"++(if attempt == 1 then "" else toString attempt)
  let root := base/(label++"-result")
  let probes ← IO.ofExcept (original.getObjValAs? (Array Json) "probes")
  let probes ← probes.mapM fun probe => do
    let cell := (System.FilePath.mk (← IO.ofExcept (probe.getObjValAs? String "destination"))).fileName.get!
    return probe.setObjVal! "destination" (toJson (root/cell).toString)
      |>.setObjVal! "runtime" (Json.mkObj [("path",toJson (installation/"libexec/eggshell").toString),("sha256",toJson digest)])
      |>.setObjVal! "pluginRoot" (toJson (installation/"share/eggshell/codex-plugin").toString)
  write (base/(label++".json")) (Json.mkObj [("output",toJson root.toString),("probes",toJson probes)])
  guard (family++"-cells"++toString attempt) #["/usr/bin/env","LEAN_NUM_THREADS=1",(auditor/"StudyMain").toString,
    "cells",(base/(label++".json")).toString]

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


def collectRecord (family tag : String) : IO Unit := do
  drained
  let destination := workspace/"docs/candidates"/family
  IO.FS.createDirAll destination
  let status ← read (base/(tag++".guard.json"))
  check (status.getObjValD "state" == toJson "finished" &&
    status.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "preserve a live guard"
  let mut logs := #[]
  for extension in ["stdout","stderr"] do
    let path := base/(tag++"."++extension)
    if !(← path.pathExists) then
      logs := logs.push (Json.mkObj [("name",toJson extension),("present",toJson false),
        ("reason",toJson "This invocation inherited its output; no separate log was captured.")])
      continue
    let bytes ← IO.FS.readFile path
    let lines := bytes.splitOn "\n"
    logs := logs.push (Json.mkObj [("name",toJson extension),("bytes",toJson bytes.utf8ByteSize),
      ("sha256",toJson (← hash path)),("completeText",toJson (decide (bytes.utf8ByteSize ≤ 16384))),
      ("errorLines",toJson ((lines.filter fun line => line.contains "error:" ||
        line.contains "does not reach" || line.contains "lost its").take 20)),
      ("text",toJson (if bytes.utf8ByteSize ≤ 16384 then bytes else
        "\n".intercalate (lines.take 3)++"\n[large diagnostic body omitted; SHA above]\n"++
        "\n".intercalate (lines.drop (lines.length-10))))])
  write (destination/(tag++".json")) (Json.mkObj [("guard",status),("logs",toJson logs),
    ("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])


def inspectRendering (family tag : String) : IO Unit := do
  drained
  check (["canonical-order","rendering-lifetime"].contains family) "unknown linked renderer"
  guard tag #["/usr/bin/env","LEAN_PATH="++(base/(family++"-build/lib")).toString,
    "EGGSHELL_RENDERER_IR="++(workspace/"docs/candidates/rendering-lifetime"/(family++"-renderer-ir.txt")).toString,
    (compiler/"bin/lean").toString,"-j1","-M768",(workspace/"tools/research/RenderingClosureInspect.lean").toString]

def sealInstalled (family : String) : IO Unit := do
  drained
  check (["canonical-order","rendering-lifetime","single-canonical","deferred-audit"].contains family) "unknown immutable product"
  let target := base/(family++"-build/StudyMain")
  let path := base/(family++"-prefix/libexec/eggshell")
  let digest ← hash target
  check ((← hash path) == digest) "installed runtime differs from the product"
  let link := path.withExtension "shared"
  check (!(← link.pathExists)) "sharing temporary exists"
  discard <| command "/bin/ln" #[target.toString,link.toString]
  IO.FS.rename link path
  write (workspace/"docs/candidates"/family/"installed-runtime.json")
    (Json.mkObj [("sha256",toJson digest),("sharesImmutableProductInode",toJson true)])

def packRecords (family : String) : IO Unit := do
  drained
  let destination := workspace/"docs/candidates"/family
  let mut records : Array Json := #[]
  let mut paths : Array System.FilePath := #[]
  for entry in ← destination.readDir do
    if entry.fileName.startsWith (family++"-") && entry.fileName.endsWith ".json" then
      let value ← read entry.path
      if value.getObjValD "guard" == Json.null then continue
      records := records.push (Json.mkObj [("name",toJson entry.fileName),("record",value)])
      paths := paths.push entry.path
  check (!paths.isEmpty) "no ended records to consolidate"
  write (destination/"attempts.json") (toJson (records.qsort (fun a b =>
    (a.getObjValD "name").compress < (b.getObjValD "name").compress)))
  for path in paths do IO.FS.removeFile path
  if family == "rendering-lifetime" then
    let mut observation ← read (destination/"ir-observation.json")
    for name in ["canonical-order","rendering-lifetime"] do
      let path := destination/(name++"-renderer-ir.txt")
      let lines := (← IO.FS.readFile path).splitOn "\n"
      let selected := lines.filter fun line => line.contains "[Eggshell.Plugin.PendingRendering.mk]" ||
        line.contains "let x_130 : obj := pap" || line.contains "let x_122 : obj := pap" ||
        line.contains "let x_295 : obj := pap" || line.contains "let x_312 : obj := pap" ||
        line.contains "let x_316 : obj := pap"
      observation := observation.setObjVal! (name++"Evidence") (Json.mkObj [
        ("fullIrSha256",toJson (← hash path)),("snippets",toJson selected),
        ("declarations",(← read (path.withExtension "json")).getObjValD "declarations")])
    write (destination/"ir-observation.json") observation
    for name in ["canonical-order","rendering-lifetime"] do
      let path := destination/(name++"-renderer-ir.txt")
      IO.FS.removeFile path
      IO.FS.removeFile (path.withExtension "json")

def retireReadDrivers : IO Unit := do
  drained
  let destination := workspace/"docs/candidates/single-canonical"
  IO.FS.createDirAll destination
  let mut rows := #[]
  for (name,file) in [("resident-source-auditor-build","auditor-sources.json"),
      ("resident-source-capacity-build","capacity-sources.json")] do
    let path := base/name/"StudyMain"
    check (← path.pathExists) "ended read driver already retired"
    let expected := (← read (workspace/"docs/candidates/resident-source"/file)).getObjValD "auditorSha256"
    check (expected == toJson (← hash path)) "ended driver differs from its audited binary"
    rows := rows.push (Json.mkObj [("path",toJson path.toString),("sha256",expected)])
  write (destination/"retired-read-drivers.json") (Json.mkObj [("completed",toJson false),
    ("executables",toJson rows),("nativeInputsOriginalDbProjectCacheAndModelsRetained",toJson true),("archiveCreated",toJson false)])
  for row in rows do IO.FS.removeFile (.mk (← IO.ofExcept (row.getObjValAs? String "path")))
  write (destination/"retired-read-drivers.json") (Json.mkObj [("completed",toJson true),
    ("executables",toJson rows),("nativeInputsOriginalDbProjectCacheAndModelsRetained",toJson true),("archiveCreated",toJson false)])

def retireOldReadProducts (families : List String := ["resident-source","delivery-key-sets"])
    (recordName : String := "retired-old-products") : IO Unit := do
  drained
  let destination := workspace/"docs/candidates/single-canonical"
  let mut rows := #[]
  check (families.all (["resident-source","delivery-key-sets","delivery-ledger"].contains ·)) "current products cannot be retired here"
  for family in families do
    let evidence ← read (workspace/"docs/candidates"/family/"delivery-cells.json")
    check (evidence.getObjValD "actualDeliveryAllSixPassed" == toJson true) "retain completed source audits"
    let cells ← IO.ofExcept (evidence.getObjValAs? (Array Json) "cells")
    let expected := ((cells[0]!.getObjValD "outcome").getObjValD "runtime").getObjValD "sha256"
    for path in [base/(family++"-build/StudyMain"),base/(family++"-prefix/libexec/eggshell")] do
      check (expected == toJson (← hash path)) "obsolete product differs from its audited binary"
      rows := rows.push (Json.mkObj [("path",toJson path.toString),("sha256",expected)])
  let record := Json.mkObj [("executables",toJson rows),
    ("currentCanonicalAndValidatedModelProductsOriginalDbCacheAndNativeInputsRetained",toJson true),("archiveCreated",toJson false)]
  write (destination/(recordName++".json")) (record.setObjVal! "completed" (toJson false))
  for row in rows do IO.FS.removeFile (.mk (← IO.ofExcept (row.getObjValAs? String "path")))
  write (destination/(recordName++".json")) (record.setObjVal! "completed" (toJson true))

def singlePreflight (tag : String) : IO Unit := do
  drained
  let root := base/"single-canonical-source"
  let take := fun (text first last : String) => do
    let parts := text.splitOn first
    check (parts.length == 2) "preflight start is ambiguous"
    let rest := parts[1]!.splitOn last
    check (rest.length == 2) "preflight end is ambiguous"
    pure (first++rest[0]!)
  let merged ← take (← IO.FS.readFile (root/"Eggshell/CanonicalSourceDelivery.lean"))
    "structure Merged where" "\nstructure Part where"
  let materialize ← take (← IO.FS.readFile (root/"Eggshell/Handoff.lean"))
    "def materializeFetched (" "\n/-- The serialized graph frame and all source-status rows are reserved once."
  let path := base/"SingleCanonicalPreflight.lean"
  IO.FS.writeFile path ("module\npublic import Eggshell.Handoff\nimport all Eggshell.Handoff\n"++
    "@[expose] public section\nnamespace Eggshell.Synapses.CanonicalSource.Delivery\n"++merged++
    "\nend Eggshell.Synapses.CanonicalSource.Delivery\nnamespace Eggshell.Plugin.SharedRangeAdapter\n"++materialize++
    "\nend Eggshell.Plugin.SharedRangeAdapter\n"++
    "#print axioms Eggshell.Synapses.CanonicalSource.Delivery.Merged.prepare_rows_exact\n"++
    "#print axioms Eggshell.Plugin.SharedRangeAdapter.materializeFetched_with_additional\n"++
    "#print axioms Eggshell.Plugin.SharedRangeAdapter.materializeFetched_empty\n")
  guard tag #["/usr/bin/env","LEAN_PATH="++(base/"canonical-order-build/lib").toString,
    (compiler/"bin/lean").toString,"-j1","-M1536",path.toString]

def singleSetup (tag : String) : IO Unit := do
  drained
  let root := base/"single-canonical-source"
  IO.FS.writeFile (root/"tools/research/SingleCanonicalChecks.lean")
    (← IO.FS.readFile (workspace/"tools/research/SingleCanonicalChecks.lean"))
  ensureAt root "tools.research.SingleCanonicalChecks" (← IO.mkRef {})
  let entry := root/"tools/research/ReplayReadinessChecks.lean"
  let text ← IO.FS.readFile entry
  unless text.contains "import tools.research.SingleCanonicalChecks" do
    IO.FS.writeFile entry (text.replace "import tools.research.CanonicalOrderChecks"
      "import tools.research.CanonicalOrderChecks\nimport tools.research.SingleCanonicalChecks" |>.replace
      "  | [\"canonical-order-check\",fixture,sha,output] =>"
      ("  | [\"single-canonical-check\",fixture,sha,output] =>\n"++
       "    Eggshell.Research.SingleCanonicalChecks.run (.mk fixture) sha (.mk output); return 0\n"++
       "  | [\"canonical-order-check\",fixture,sha,output] =>"))
  let actual ← linkedWitnesses (base/"canonical-order-build")
  let some witness := actual["Eggshell.Handoff"]? | throw (IO.userError "parent renderer witness missing")
  let encoded ← IO.ofExcept (Json.parse witness >>= Json.getArr?)
  let original ← IO.ofExcept encoded[0]!.getStr?
  let fragments := original.splitOn "def materialize ("
  check (fragments.length == 2) "parent materializer is ambiguous"
  let ending := fragments[1]!.splitOn "\n/-- The serialized graph frame and all source-status rows are reserved once."
  check (ending.length == 2) "parent materializer ending is ambiguous"
  let declaration := "def materialize ("++ending[0]!
  check (((← IO.FS.readFile (root/"Eggshell/Handoff.lean")).splitOn declaration).length == 2)
    "the original materializer was changed"
  write (workspace/"docs/candidates/single-canonical/plan.json") (Json.mkObj [
    ("parentRuntimeSha256",toJson (← hash (base/"canonical-order-build/StudyMain"))),
    ("originalMaterializerEqualsLinkedParent",toJson true),("firstNormalizerValidationUnchanged",toJson true),
    ("generalNormalizationIdempotenceProved",toJson false),("adopted",toJson false),
    ("answeringModelCalls",toJson (0 : Nat))])
  guard tag #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
    (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"single-canonical-settings.json").toString]

def singleControls (tag : String) : IO Unit := do
  drained
  guard tag #["/usr/bin/env","LEAN_NUM_THREADS=1",
    "EGGSHELL_DATA_ROOT="++(base/"single-canonical-controls-data").toString,
    (base/"single-canonical-build/StudyMain").toString,"local-batch-check",
    (base/"single-canonical-controls-result").toString]

def singleCollectControls (tag : String) : IO Unit := do
  drained
  let status ← read (base/(tag++".guard.json"))
  check (status.getObjValD "exitCode" == toJson (0 : Nat) &&
    status.getObjValD "state" == toJson "finished" &&
    status.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "controls did not finish and drain"
  let root := base/"single-canonical-controls-result"
  let report ← read (root/"report.json")
  for name in ["fullScopeHeadRootCapabilityExpiryRejection","typedAndWireWindowRanksExact",
      "originalHeadsUnchanged","allReservationsReleased"] do
    check (report.getObjValD name == toJson true) ("control failed: "++name)
  check (report.getObjValD "focusComparisons" == toJson (12 : Nat) &&
    (report.getObjValD "final").getObjValD "active" == toJson (0 : Nat)) "focus or reservation controls incomplete"
  let mut records := #[]
  for name in ["report.json","held-lock-reads.json","read-boundary.json","shared-eighty.json"] do
    records := records.push (Json.mkObj [("file",toJson name),("sha256",toJson (← hash (root/name))),
      ("record",← read (root/name))])
  let destination := workspace/"docs/candidates/single-canonical"
  write (destination/"read-controls.json") (Json.mkObj [("runtimeSha256",toJson (← hash (base/"single-canonical-build/StudyMain"))),
    ("guard",status),("records",toJson records),("fullEightyHookLoad",toJson false),("adopted",toJson false)])
  let mut removed := #[]
  for path in [root/"file-fixture",root/"focus-fixture",base/"single-canonical-controls-data"] do
    if ← path.pathExists then
      IO.FS.removeDirAll path
      removed := removed.push path.toString
  write (destination/"read-controls-cleanup.json") (Json.mkObj [("removed",toJson removed),
    ("originalDbProjectCacheModelRetained",toJson true),("archived",toJson false)])

def retireReferenceDriver : IO Unit := do
  drained
  let destination := workspace/"docs/candidates/single-canonical"
  let current ← read (destination/"auditor-sources.json")
  check (current.getObjValD "allProductCorePresent" == toJson true &&
    current.getObjValD "commonSourcesUnchanged" == toJson true) "validate the current driver before retiring its predecessor"
  let root := base/"canonical-order-auditor-build"
  let expected := (← read (workspace/"docs/candidates/canonical-order/auditor-sources.json")).getObjValD "auditorSha256"
  check (expected == toJson (← hash (root/"StudyMain"))) "reference helper differs from its audited binary"
  for row in (← IO.FS.readFile (root/"runtime.rsp")).splitOn "\n" do
    if row.trimAscii.isEmpty then continue
    let path ← IO.ofExcept (Json.parse row >>= Json.getStr?)
    if path.endsWith ".o" then check (← (System.FilePath.mk path).pathExists) "reference helper cannot be relinked"
  let record := Json.mkObj [("path",toJson (root/"StudyMain").toString),("sha256",expected),
    ("completeRelinkResponseAndObjectsRetained",toJson true),
    ("currentCanonicalProductAndNewMatchingDriverRetained",toJson true),("archiveCreated",toJson false)]
  write (destination/"retired-reference-driver.json") (record.setObjVal! "completed" (toJson false))
  IO.FS.removeFile (root/"StudyMain")
  write (destination/"retired-reference-driver.json") (record.setObjVal! "completed" (toJson true))

def retireSingleAuditor (family : String := "single-canonical") : IO Unit := do
  drained
  check (["single-canonical","deferred-audit"].contains family) "unknown ended delivery helper"
  let destination := workspace/"docs/candidates"/family
  check ((← read (destination/"delivery-cells.json")).getObjValD "actualDeliveryAllSixPassed" == toJson true &&
    (← (base/(family++"-capacity-settings.json")).pathExists))
    "finish actual delivery and prepare the capacity driver before retiring the ended helper"
  let root := base/(family++"-auditor-build")
  let expected := (← read (destination/"auditor-sources.json")).getObjValD "auditorSha256"
  check (expected == toJson (← hash (root/"StudyMain"))) "ended helper differs from its audited binary"
  for row in (← IO.FS.readFile (root/"runtime.rsp")).splitOn "\n" do
    if row.trimAscii.isEmpty then continue
    let path ← IO.ofExcept (Json.parse row >>= Json.getStr?)
    if path.endsWith ".o" then check (← (System.FilePath.mk path).pathExists) "ended helper cannot be relinked"
  let record := Json.mkObj [("path",toJson (root/"StudyMain").toString),("sha256",expected),
    ("completeRelinkInputsRetained",toJson true),("productPrefixCapacitySourceOriginalDbCacheModelRetained",toJson true),
    ("archived",toJson false)]
  write (destination/"retired-delivery-helper.json") (record.setObjVal! "completed" (toJson false))
  IO.FS.removeFile (root/"StudyMain")
  write (destination/"retired-delivery-helper.json") (record.setObjVal! "completed" (toJson true))

def singleRecords : IO Unit := do
  drained
  for tag in ["single-canonical-proof1","single-canonical-build1","single-canonical-build2",
      "single-canonical-component1","single-canonical-auditor-build1","single-canonical-controls2",
      "single-canonical-install1","single-canonical-cells1","single-canonical-capacity-build1",
      "single-canonical-capacity-small1","single-canonical-capacity-801"] do
    if ← (base/(tag++".guard.json")).pathExists then collectRecord "single-canonical" tag
  let tag := "single-canonical-controls1"
  let stderr := base/(tag++".stderr")
  check (!(← (base/(tag++".guard.json")).pathExists) && (← stderr.pathExists))
    "preserve the actual rejected-before-start invocation"
  write (workspace/"docs/candidates/single-canonical/rejected-before-start.json") (Json.mkObj [
    ("guardTag",toJson tag),("settings",← read (base/(tag++".guard-settings.json"))),
    ("stderr",toJson (← IO.FS.readFile stderr)),("stderrSha256",toJson (← hash stderr)),
    ("guardRecordPresent",toJson false),("testStarted",toJson false),("adopted",toJson false)])

def retireSingleCapacity (family : String := "single-canonical") : IO Unit := do
  drained
  check (["single-canonical","deferred-audit","deferred-assembly","draft-units"].contains family) "unknown ended capacity helper"
  let destination := workspace/"docs/candidates"/family
  let cleanup ← read (destination/"capacity-small-cleanup.json")
  let small ← read (destination/"capacity-small.json")
  let successful := (small.getObjValD "report").getObjValD "allPhasesPassed" == toJson true
  check ((cleanup.getObjValD "completed" == toJson true || successful) &&
    (← (destination/(family++"-capacity-small1.json")).pathExists))
    "preserve terminal evidence and clean owned sessions first"
  if successful then
    let large ← read (destination/"capacity-80.json")
    check ((large.getObjValD "guard").getObjValD "state" == toJson "finished" &&
      (large.getObjValD "guard").getObjValD "ownedPids" == toJson (#[] : Array Nat) &&
      (← (destination/"capacity-80-cleanup.json").pathExists)) "finish the larger stage before retiring its client"
  let root := base/(family++"-capacity-build")
  let digest ← hash (root/"StudyMain")
  check ((← read (destination/"capacity-sources.json")).getObjValD "auditorSha256" == toJson digest)
    "capacity helper changed after audit"
  for entry in ← base.readDir do
    if !entry.fileName.endsWith "-build" || entry.path == root then continue
    let response := entry.path/"runtime.rsp"
    if ← response.pathExists then
      check (!(← IO.FS.readFile response).contains (root.toString++"/"))
        "another native product still depends on the ended capacity helper"
  let paths := #[root,base/(family++"-capacity-source"),base/(family++"-capacity-small-result"),
    base/(family++"-capacity-80-result")]
  let witness := root/"tools_research_MemoryCapacity.source"
  let entry := workspace/"tools/research/MemoryCapacity.lean"
  let native : String × Array (String × String) ← IO.ofExcept (fromJson? (← read witness))
  check (native.1 == (← IO.FS.readFile entry)) "keep the actual thin client source in the repository"
  let record := Json.mkObj [("runtimeSha256",toJson digest),("removed",toJson (paths.map (·.toString))),
    ("nativeEntryWitnessSha256",toJson (← hash witness)),("nativeEntryLeanSha256",toJson (← hash entry)),
    ("nativeEntrySourceInRepository",toJson "tools/research/MemoryCapacity.lean"),
    ("nativeEntrySourceMatchesRepository",toJson true),
    ("noOtherNativeResponseReferencesRemovedRoot",toJson true),
    ("productParentOriginalDbProjectCacheModelRetained",toJson true),("archived",toJson false)]
  write (destination/"retired-capacity-helper.json") (record.setObjVal! "completed" (toJson false))
  for path in paths do if ← path.pathExists then IO.FS.removeDirAll path
  write (destination/"retired-capacity-helper.json") (record.setObjVal! "completed" (toJson true))

def singleRetireLogs (family : String := "single-canonical") : IO Unit := do
  drained
  check (["single-canonical","deferred-audit"].contains family) "unknown ended log family"
  let destination := workspace/"docs/candidates"/family
  let attempts ← IO.ofExcept ((← read (destination/"attempts.json")).getArr?)
  let mut paths : Array System.FilePath := #[]
  for attempt in attempts do
    let name ← IO.ofExcept (attempt.getObjValAs? String "name")
    check (name.startsWith (family++"-") && name.endsWith ".json" &&
      name.toList.all (fun c => c.isAlphanum || c == '-' || c == '.')) "log tag escaped the ended trial"
    let tag := (name.dropEnd 5).toString
    if (attempt.getObjValD "record").getObjValD "logs" == Json.null then continue
    for log in ← IO.ofExcept ((attempt.getObjValD "record").getObjValAs? (Array Json) "logs") do
      if log.getObjValD "present" == toJson false then continue
      let extension ← IO.ofExcept (log.getObjValAs? String "name")
      check (["stdout","stderr"].contains extension) "unexpected captured stream"
      let path := base/(tag++"."++extension)
      check (toJson (← hash path) == log.getObjValD "sha256") "captured log changed before cleanup"
      paths := paths.push path
  let record := Json.mkObj [("removed",toJson (paths.map (·.toString))),
    ("boundedLogsErrorLinesAndDigestsRetained",toJson true),("archived",toJson false)]
  write (destination/"ended-log-cleanup.json") (record.setObjVal! "completed" (toJson false))
  for path in paths do IO.FS.removeFile path
  write (destination/"ended-log-cleanup.json") (record.setObjVal! "completed" (toJson true))

def singleCompactRetirements : IO Unit := do
  drained
  let destination := workspace/"docs/candidates/single-canonical"
  for name in ["retired-unreferenced-native-artifacts.json","retired-duplicate-native-artifacts.json",
      "retired-unreferenced-native-witnesses.json","retired-old-frontend-caches.json"] do
    let path := destination/name
    let value ← read path
    check (value.getObjValD "completed" == toJson true) "do not summarize an unfinished removal"
    let removed ← IO.ofExcept (value.getObjValAs? (Array Json) "removed")
    let fields ← IO.ofExcept value.getObj?
    let retained := fields.toArray.filter (fun field => field.1 != "removed")
    write path (Json.mkObj (retained.toList++[("removedFileCount",toJson removed.size),
      ("originalRemovalManifestSha256",toJson (← hash path)),
      ("obsoletePerFilePathsDiscarded",toJson true),("archiveCreated",toJson false)]))

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
  | ["inspect-decoded-readers"] => inspectDecodedReaders
  | ["cleanup-measurements"] => cleanupMeasurements
  | ["canonical-setup",tag] => canonicalSetup tag
  | ["canonical-component",tag] => canonicalComponent tag
  | ["component",family,tag] => canonicalComponent tag family
  | ["canonical-audit"] => canonicalAudit
  | ["audit-family",family] => canonicalAudit family
  | ["canonical-collect-component",tag] => canonicalCollectComponent tag
  | ["collect-component",family,tag] => canonicalCollectComponent tag family
  | ["canonical-prepare-auditor"] => canonicalPrepareAuditor
  | ["prepare-auditor",family] => canonicalPrepareAuditor family
  | ["canonical-prepare-cells"] => canonicalPrepareCells
  | ["prepare-cells",family] => canonicalPrepareCells family
  | ["prepare-cells",family,attempt] => do
    let some attempt := attempt.toNat? | throw (IO.userError "invalid actual delivery attempt")
    canonicalPrepareCells family attempt
  | ["canonical-retire"] => canonicalRetire
  | ["collect-record",family,tag] => collectRecord family tag
  | ["inspect-renderer",family,tag] => inspectRendering family tag
  | ["canonical-seal-installed"] => sealInstalled "canonical-order"
  | ["seal-installed-family",family] => sealInstalled family
  | ["pack-records",family] => packRecords family
  | ["retire-read-drivers"] => retireReadDrivers
  | ["retire-old-read-products"] => retireOldReadProducts
  | ["retire-superseded-product",family] => retireOldReadProducts [family] ("retired-"++family++"-product")
  | ["single-preflight",tag] => singlePreflight tag
  | ["single-setup",tag] => singleSetup tag
  | ["single-controls",tag] => singleControls tag
  | ["single-collect-controls",tag] => singleCollectControls tag
  | ["retire-reference-driver"] => retireReferenceDriver
  | ["retire-single-auditor"] => retireSingleAuditor
  | ["retire-auditor",family] => retireSingleAuditor family
  | ["single-records"] => singleRecords
  | ["retire-single-capacity"] => retireSingleCapacity
  | ["retire-capacity",family] => retireSingleCapacity family
  | ["single-retire-logs"] => singleRetireLogs
  | ["retire-logs",family] => singleRetireLogs family
  | ["single-compact-retirements"] => singleCompactRetirements
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
