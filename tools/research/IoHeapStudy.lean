import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
import Std.Data.HashSet
open Lean
namespace Eggshell.Research.IoHeapStudy
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def compiler : System.FilePath := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
def parent := base/"shared-view-build"
def source := base/"io-heap-source"
def target := base/"io-heap-build"
def study := workspace/"docs/candidates/io-heap"
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= (IO.ofExcept ∘ Json.parse)
def write (path : System.FilePath) (value : Json) : IO Unit := IO.FS.writeFile path value.compress
def command (cmd : String) (args : Array String) : IO String := do
  let result ← IO.Process.output {cmd,args,cwd := some workspace}
  check (result.exitCode == 0) (result.stdout++result.stderr)
  return result.stdout
def hash (path : System.FilePath) : IO String :=
  return ((← command "/usr/bin/shasum" #["-a","256",path.toString]).splitOn " ").headD ""

structure Arena where
  id : Nat
  blocks : Nat
  granuleMiB : Nat
  inuse : Option Nat := none
  committed : Option Nat := none
  deriving ToJson

def arenaSummary (raw : String) : Except String Json := do
  let mut arenas : Array Arena := #[]
  let mut current : Option Arena := none
  let mut phase := ""
  let mut bitmapCount := 0
  let mut total := none
  let finish := fun (arena : Arena) => do
    unless arena.inuse.isSome do throw "arena has no inuse summary"
    return arena
  for rawLine in raw.splitOn "\n" do
    let rawLine := rawLine.trimAscii.toString
    let skip := if rawLine.startsWith "mimalloc: thread " then 2 else if rawLine.startsWith "mimalloc: " then 1 else 0
    let line := (String.intercalate ": " ((rawLine.splitOn ": ").drop skip)).trimAscii.toString
    let words := ((line.splitOn " ").filter (!·.isEmpty)).toArray
    if line.startsWith "arena " then
      if let some arena := current then arenas := arenas.push (← finish arena)
      let some id := (words[1]?.getD "").dropEnd 1 |>.toString.toNat? | throw "invalid arena identity"
      let some blocks := (words[2]?.getD "").toNat? | throw "invalid arena block count"
      let unit := words[6]?.getD ""
      unless unit.endsWith "MiB" do throw "unknown arena granule unit"
      let some granuleMiB := (unit.dropEnd 3 |>.toString).toNat? | throw "invalid arena granule"
      current := some {id,blocks,granuleMiB}
      phase := ""
    else if line == "inuse blocks:" || line == "committed blocks:" then
      phase := line
      bitmapCount := 0
    else if line.startsWith "total ('x'):" then
      let some count := (words.back?.getD "").toNat? | throw "invalid arena bitmap count"
      let some arena := current | throw "bitmap outside an arena"
      unless count == bitmapCount && count ≤ arena.blocks do throw "arena bitmap and printed count disagree"
      current := some (if phase == "inuse blocks:" then {arena with inuse := some count}
        else {arena with committed := some count})
      phase := ""
    else if line.startsWith "total inuse blocks" then
      total := (words.back?.getD "").toNat?
    else if !phase.isEmpty && !line.isEmpty then
      unless line.toList.all (fun c => c == 'x' || c == '.' || c == ' ') do throw "invalid arena bitmap"
      bitmapCount := bitmapCount+(line.toList.filter (· == 'x')).length
  if let some arena := current then arenas := arenas.push (← finish arena)
  let inuse := arenas.foldl (fun n arena => n+arena.inuse.getD 0) 0
  unless total == some inuse do throw "arena inventory has no matching final count"
  return Json.mkObj [("arenas",toJson arenas),("inuseBlocks",toJson inuse),
    ("inuseGranuleBytes",toJson (arenas.foldl (fun n arena => n+arena.inuse.getD 0*arena.granuleMiB*1024*1024) 0)),
    ("countsAreAllocatorGranulesNotRssOrReachableBytes",toJson true)]
def drained : IO Unit := do
  let processes ← command "/bin/ps" #["-axo","command="]
  check (!(processes.splitOn "\n").any (fun row => row.contains "controller/StudyMain guard ")) "native guard remains live"
  for entry in ← base.readDir do
    if entry.fileName.startsWith "io-heap-" && entry.fileName.endsWith ".guard.json" then
      let guard ← read entry.path
      check (guard.getObjValD "state" == toJson "finished" && guard.getObjValD "ownedPids" == toJson (#[] : Array Nat))
        "I/O heap guard not drained"

/-- Retain actual producer interfaces of every still-retained native entry.
Only obsolete compiled library files inside this study's build directories
are removed. Original DBs, source/dependency witnesses and objects are untouched. -/
private partial def obsoleteInterfaces (needed : Std.HashSet String)
    (directory : System.FilePath) : IO (Array (String × Nat)) := do
  let mut result := #[]
  for file in ← directory.readDir do
    let metadata ← file.path.symlinkMetadata
    if metadata.type == .dir then
      result := result ++ (← obsoleteInterfaces needed file.path)
    else
      let actual ← try pure (some (← IO.FS.realPath file.path)) catch _ => pure none
      let keep := actual.any fun path =>
        !path.toString.startsWith (base.toString++"/") || needed.contains path.toString
      if !keep then result := result.push (file.path.toString,metadata.byteSize.toNat)
  return result

def retireInterfaces : IO Unit := do
  drained
  let record := study/"interface-retirement.json"
  check (!(← record.pathExists)) "preserve the interface retirement inventory"
  let mut needed : Std.HashSet String := {}
  let mut executables := #[]
  for entry in ← base.readDir do
    let executable := entry.path/"StudyMain"
    if !(← entry.path.isDir) || !(← executable.pathExists) || entry.fileName == "controller" then continue
    let build ← read (entry.path/"build.json")
    let mainModule ← IO.ofExcept ((build.getObjValD "settings").getObjValAs? String "mainModule")
    let inputs ← IO.ofExcept (fromJson? (← read (entry.path/(mainModule.replace "." "_"++".dependencies"))) :
      Except String (Array (String × String)))
    let modules := inputs.push (mainModule,"")
    for (name,_) in modules do
      if name.startsWith "@" then continue
      let path := entry.path/"lib"/(name.replace "." "/")
      let interface := path.withExtension "olean"
      if !(← interface.pathExists) then
        check (!(name.startsWith "Eggshell." || name.startsWith "tools." || name.startsWith "tests." || name == "Main"))
          "selected native module lost its compiler interface"
        continue
      let some directory := path.parent | throw (IO.userError "interface has no directory")
      let some stem := path.fileName | throw (IO.userError "interface has no stem")
      for file in ← directory.readDir do
        if file.fileName.startsWith (stem++".") && !(← file.path.isDir) && (← file.path.pathExists) then
          needed := needed.insert (← IO.FS.realPath file.path).toString
    executables := executables.push (executable.toString,← hash executable)
  check (executables.size ≥ 5 && needed.size > 1000) "native interface inventory is unexpectedly small"
  let mut remove : Array (String × Nat) := #[]
  for entry in ← base.readDir do
    let library := entry.path/"lib"
    if entry.fileName.endsWith "-build" && (← library.pathExists) && (← library.isDir) then
      remove := remove ++ (← obsoleteInterfaces needed library)
  let inventory := Json.mkObj [("retainedExecutables",toJson executables),("requiredPhysicalInterfaces",toJson needed.size),
    ("removed",toJson remove),("plannedBytes",toJson (remove.foldl (fun bytes entry => bytes+entry.2) 0)),
    ("objectsAndSourceDependencyWitnessesUntouched",toJson true),("archived",toJson false)]
  write record (inventory.setObjVal! "complete" (toJson false))
  drained
  for (path,_) in remove do IO.FS.removeFile (.mk path)
  for path in needed do check (← (System.FilePath.mk path).pathExists) "selected producer interface removed"
  for (path,before) in executables do check ((← hash (.mk path)) == before) "retained executable changed"
  write record (inventory.setObjVal! "complete" (toJson true))
  IO.println (Json.mkObj [("retainedExecutables",toJson executables.size),("requiredInterfaces",toJson needed.size),
    ("removedFiles",toJson remove.size),("bytes",inventory.getObjValD "plannedBytes")]).compress
def prepare : IO Unit := do
  drained
  check ((← hash (parent/"StudyMain")) == "a9827fcedad5a2d390f64f0e191aee00d0bec5a3f395f6baf5596af0b7d3e7fb") "selected parent changed"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",
    (workspace/"tools/research/DiscoveryStagesStudy.lean").toString,"materialize-native",parent.toString,
    source.toString,target.toString,"tools.research.IoHeapChecks",(base/"io-heap-settings.json").toString]
  IO.FS.writeFile (source/"tools/research/HeapObservation.lean") (← IO.FS.readFile (workspace/"tools/research/HeapObservation.lean"))
  IO.FS.createDirAll target
  IO.FS.writeFile (target/"adapter.c") (← IO.FS.readFile (workspace/"tools/research/native/heap_observation.c"))
  let response := (← IO.FS.readFile (parent/"runtime.rsp"))++(toJson (target/"adapter.o").toString).compress++"\n"
  IO.FS.writeFile (base/"io-heap-parent.rsp") response
  let settings ← read (base/"io-heap-settings.json")
  write (base/"io-heap-settings.json") (settings.setObjVal! "baselineResponse" (toJson (base/"io-heap-parent.rsp").toString))
  IO.FS.createDirAll study
  write (study/"plan.json") (Json.mkObj [("previousGoalTurn",toJson "progress:tracing-off and calibrated abandoned-heap census rule out two main explanations"),
    ("purpose",toJson "measure current native I/O owner heap and allocator arena bitmaps;no foreign live-heap traversal"),
    ("parentRuntimeSha256",toJson (← hash (parent/"StudyMain"))),
    ("positiveControlBeforeSearch",toJson "same timer/TCP resolving thread,16MiB retained and released on that live owner"),
    ("noAllocatorPolicyOrConcurrencyChange",toJson true),("noMiCollect",toJson true),
    ("censusMayConsolidateRemoteFreeLists",toJson true),("answeringModelCalls",toJson (0 : Nat)),("adopted",toJson false)])
def build : IO Unit := do
  let sdk := (← command "/usr/bin/xcrun" #["--show-sdk-path"]).trimAscii.toString
  discard <| command (compiler/"bin/leanc").toString #["-c","-O2","-Wall","-Wextra","-Werror",
    "-isysroot",sdk,"-isystem",sdk++"/usr/include","-o",(target/"adapter.o").toString,(target/"adapter.c").toString]
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",
    (workspace/"tools/research/StudyBuildMain.lean").toString,(base/"io-heap-settings.json").toString]
  write (study/"adapter.json") (Json.mkObj [("sdk",toJson sdk),("sourceSha256",toJson (← hash (target/"adapter.c"))),
    ("objectSha256",toJson (← hash (target/"adapter.o"))),("runtimeSha256",toJson (← hash (target/"StudyMain")))])
def refreshEntry : IO Unit := do
  drained
  for name in ["IoHeapChecks","HeapObservation"] do
    IO.FS.writeFile (source/("tools/research/"++name++".lean"))
      (← IO.FS.readFile (workspace/("tools/research/"++name++".lean")))
  IO.FS.writeFile (target/"adapter.c") (← IO.FS.readFile (workspace/"tools/research/native/heap_observation.c"))
def prepareShapes : IO Unit := do
  drained
  write (study/"cohort-adapter.json") (← read (study/"adapter.json"))
  let relative := "tools/research/IoHeapChecks.lean"
  let witness ← IO.ofExcept (fromJson? (← read (target/"tools_research_IoHeapChecks.source")) :
    Except String (String × Array (String × String)))
  check (!witness.1.contains "def shapes") "preserve the cohort entry before shape compilation"
  let original := study/"cohort-entry.tmp"
  IO.FS.writeFile original witness.1
  let patch ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","--label","cohort/IoHeapChecks.lean",
    "--label","shapes/IoHeapChecks.lean",original.toString,(workspace/relative).toString]}
  check (patch.exitCode == 1) "missing native buffer shape control"
  IO.FS.writeFile (study/"shape-entry.patch") patch.stdout
  IO.FS.removeFile original
  refreshEntry
def setup (action tag : String) : IO Unit := do
  drained
  let settings := base/(tag++".guard-settings.json")
  check (!(← settings.pathExists)) "fresh guard tag required"
  let args ← match action with
    | "build" => pure #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (workspace/"tools/research/IoHeapStudy.lean").toString,"build"]
    | "checks" => pure #["/usr/bin/env","LEAN_NUM_THREADS=1",(target/"StudyMain").toString,
      "io-heap-check",(base/(tag++"-result")).toString]
    | "shapes" => pure #["/usr/bin/env","LEAN_NUM_THREADS=1",(target/"StudyMain").toString,
      "io-heap-shapes",(base/(tag++"-result")).toString]
    | "policy" => pure #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",
      (workspace/"tools/research/IoHeapStudy.lean").toString,"build-policy"]
    | "cohort" => do
      let client := base/"frontend-traffic-stop-build/StudyMain"
      check ((← read (study/"native-closure.json")).getObjValD "consistent" == toJson true &&
        (← read (study/"augmented-controls.json")).getObjValD "sameNativeTimerAndTcpOwner" == toJson true &&
        (← hash client) == "b7bf4901734522beb9bb2d20a8f5cea76afeee6d978a7932e4b4e65e1a2de873")
        "native scope,controls and sealed client required before cohort"
      IO.FS.removeFile (base/"worker-cpu-target/bin/eggshelld")
      discard <| command "/bin/ln" #["-s",(target/"StudyMain").toString,(base/"worker-cpu-target/bin/eggshelld").toString]
      pure #["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_TRACE_SERVICE_PROFILE=0","EGGSHELL_TRACE_QUERY_STAGES=0",
        "EGGSHELL_TRACE_NUMERICAL_STAGES=0","EGGSHELL_TRACE_ALLOCATOR=0","EGGSHELL_TRACE_ACTOR_HEAP=0","EGGSHELL_RESEARCH_IO_HEAP=1",
        "EGGSHELL_DATA_ROOT="++(base/(tag++"-result/private")).toString,
        "EGGSHELL_CONFIG="++(base/(tag++"-result/eggshell.toml")).toString,"PLUGIN_ROOT="++(base/"worker-cpu-target").toString,
        client.toString,(base/(tag++"-result")).toString,(target/"StudyMain").toString,← hash (target/"StudyMain")]
    | _ => throw (IO.userError "unknown I/O heap action")
  write settings (Json.mkObj [("command",toJson args),("cwd",toJson workspace.toString),
    ("record",toJson (base/(tag++".guard.json")).toString),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])
def recordChecks (tag : String) : IO Unit := do
  drained
  let guard ← read (base/(tag++".guard.json"))
  check (guard.getObjValD "exitCode" == toJson (0 : Nat) && guard.getObjValD "guardTriggered" == toJson false) "I/O controls did not pass"
  let report ← read (base/(tag++"-result/report.json"))
  check (report.getObjValD "sameNativeTimerAndTcpOwner" == toJson true &&
    report.getObjValD "applicationRootEmptyAfterRemoteRelease" == toJson true &&
    report.getObjValD "complete" == toJson true) "I/O control scope changed"
  let raw ← IO.ofExcept (report.getObjValAs? String "arenas")
  let parsed ← IO.ofExcept (arenaSummary raw)
  write (study/"native-controls.json") (Json.mkObj [("guard",guard),("report",report),("arenaSummary",parsed),
    ("runtimeSha256",toJson (← hash (target/"StudyMain")))])
  let audit := workspace/"tools/research/StudyBuildClosureAudit.lean"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",audit.toString,
    "inspect",target.toString,(study/"component-native-closure.json").toString]
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",audit.toString,
    "compare-sources",parent.toString,target.toString,(study/"component-native-sources.json").toString,"+tools.research.HeapObservation"]
def retainControls (tag : String) : IO Unit := do
  drained
  let guard ← read (base/(tag++".guard.json"))
  check (guard.getObjValD "exitCode" == toJson (0 : Nat) && guard.getObjValD "guardTriggered" == toJson false)
    "augmented observer controls failed"
  let report ← read (base/(tag++"-result/report.json"))
  check (report.getObjValD "sameNativeTimerAndTcpOwner" == toJson true &&
    report.getObjValD "complete" == toJson true) "augmented controls incomplete"
  let adapter ← read (study/"adapter.json")
  check (adapter.getObjValD "runtimeSha256" == toJson (← hash (target/"StudyMain"))) "control runtime changed before sealing"
  write (study/"augmented-controls.json") (report
    |>.setObjVal! "controlRuntimeSha256" (adapter.getObjValD "runtimeSha256")
    |>.setObjVal! "helperSha256" (toJson (← hash (source/"tools/research/HeapObservation.lean")))
    |>.setObjVal! "adapterSourceSha256" (toJson (← hash (target/"adapter.c"))))
  write (study/"augmented-controls.guard.json") guard
def sealObserver (_tag : String) : IO Unit := do
  drained
  let controls ← read (study/"augmented-controls.json")
  check (controls.getObjValD "sameNativeTimerAndTcpOwner" == toJson true &&
    controls.getObjValD "helperSha256" == toJson (← hash (source/"tools/research/HeapObservation.lean")) &&
    controls.getObjValD "adapterSourceSha256" == toJson (← hash (target/"adapter.c")))
    "observer boundary changed after native positive/negative controls"
  let audit := workspace/"tools/research/StudyBuildClosureAudit.lean"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",audit.toString,
    "inspect",target.toString,(study/"native-closure.json").toString]
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",audit.toString,
    "compare-sources",parent.toString,target.toString,(study/"native-sources.json").toString,
    "Eggshell.PublicationService","Eggshell.PreparedReaders","+tools.research.HeapObservation"]
  let mut patches := ""
  for name in ["PublicationService","PreparedReaders"] do
    let path := "Eggshell/"++name++".lean"
    let patch ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","--label","a/"++path,"--label","b/"++path,
      (base/"shared-view-source"/path).toString,(source/path).toString]}
    check (patch.exitCode == 1) "owner observation patch missing"
    patches := patches++patch.stdout
  IO.FS.writeFile (study/"observer.patch") patches
def analyze : IO Unit := do
  drained
  let evidence ← read (study/"evidence.json")
  let outputs ← IO.ofExcept (evidence.getObjValAs? (Array Json) "actualOutputs")
  check (outputs.size == 35 && outputs.all (fun row => row.getObjValD "bodyByteEqual" == toJson true &&
    row.getObjValD "completeStdoutEqual" == toJson true) &&
    evidence.getObjValD "requiredOriginalAndAck" == toJson (32 : Nat) &&
    evidence.getObjValD "semanticCompletedWithHandoff" == toJson (32 : Nat) &&
    evidence.getObjValD "guardIntervened" == toJson false &&
    evidence.getObjValD "guardOwnedPids" == toJson (#[] : Array Nat)) "observer changed actual output or completion"
  let mut rows := #[]
  for wave in ← IO.ofExcept (evidence.getObjValAs? (Array Json) "waves") do
    let stats := wave.getObjValD "serviceStats"
    let observations := stats.getObjValD "ownerHeaps"
    let arenas ← IO.ofExcept (arenaSummary (← IO.ofExcept (observations.getObjValAs? String "arenas")))
    let coordinator := ((stats.getObjValD "operations").getObjValD "preparedReaders").getObjValD "coordinatorHeap"
    let values := #[
      ("main",(observations.getObjValD "main").getObjValD "heap"),
      ("io",(observations.getObjValD "io").getObjValD "heap"),
      ("worker",(observations.getObjValD "worker").getObjValD "heap"),
      ("handler",observations.getObjValD "handler"),
      ("coordinatorAtLastFork",coordinator.getObjValD "heap")]
    for (_,heap) in values do check (heap.getObjValD "complete" == toJson (1 : Nat)) "incomplete heap owner census"
    let summary := values.map fun (name,heap) => (name,Json.mkObj [
      ("allocatedBytes",heap.getObjValD "allocatedBytes"),("committedBytes",heap.getObjValD "committedBytes"),
      ("reservedBytes",heap.getObjValD "reservedBytes"),("areas",heap.getObjValD "areas")])
    rows := rows.push (Json.mkObj [("wave",wave.getObjValD "name"),("hostRssKiB",wave.getObjValD "hostRssKiB"),
      ("owners",Json.mkObj summary.toList),("coordinatorAtLastFork",coordinator),
      ("coordinatorIsLastForkNotIdleSample",toJson true),("arenas",arenas),
      ("observerElapsedMs",observations.getObjValD "elapsedMs")])
  let result := Json.mkObj [("waves",toJson rows),("all35StdoutExact",toJson true),
    ("noAllocatorCollectionOrPolicyChange",toJson true),("notReachabilityProof",toJson true),
    ("latencyMs",evidence.getObjValD "latencyMs"),("adopted",toJson false)]
  write (study/"analysis.json") result
  IO.println result.compress
def priorVmSummary : IO Unit := do
  let previous ← read (workspace/"docs/candidates/working-set/memory-profile.json")
  let maps ← IO.ofExcept (previous.getObjValAs? (Array Json) "maps")
  for sample in maps do
    let raw ← IO.ofExcept (sample.getObjValAs? String "stdout")
    let rows := (raw.splitOn "\n").filter fun line =>
      ["IOAccelerator","Physical footprint","reusable","REUSABLE","TOTAL","Summary"].any (fun key => line.contains key)
    IO.println (Json.mkObj [("role",sample.getObjValD "role"),
      ("rssKiB",sample.getObjValD "observedRssKiB"),("summary",toJson rows)]).compress
def buildPolicy : IO Unit := do
  let destination := base/"io-heap-policy-control"
  check (!(← destination.pathExists)) "fresh policy control required"
  let sealedAdapter ← read (study/"adapter.json")
  check (sealedAdapter.getObjValD "runtimeSha256" == toJson (← hash (target/"StudyMain")))
    "sealed observer runtime changed before policy control"
  IO.FS.createDirAll destination
  IO.FS.writeFile (destination/"adapter.c") (← IO.FS.readFile (workspace/"tools/research/native/heap_observation.c"))
  let patch ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","--label","cohort/heap_observation.c",
    "--label","policy/heap_observation.c",(target/"adapter.c").toString,(destination/"adapter.c").toString]}
  check (patch.exitCode == 1) "missing read-only policy observation change"
  IO.FS.writeFile (study/"policy-adapter.patch") patch.stdout
  let sdk := (← command "/usr/bin/xcrun" #["--show-sdk-path"]).trimAscii.toString
  discard <| command (compiler/"bin/leanc").toString #["-c","-O2","-Wall","-Wextra","-Werror",
    "-isysroot",sdk,"-isystem",sdk++"/usr/include","-o",(destination/"adapter.o").toString,(destination/"adapter.c").toString]
  let old ← IO.FS.readFile (target/"runtime.rsp")
  let oldArgument := (toJson (target/"adapter.o").toString).compress
  let newArgument := (toJson (destination/"adapter.o").toString).compress
  check ((old.splitOn oldArgument).length == 2) "foreign object must occur exactly once"
  let response := old.replace oldArgument newArgument
  IO.FS.writeFile (destination/"runtime.rsp") response
  discard <| command (compiler/"bin/leanc").toString #["-Wl,-dead_strip","-o",(destination/"StudyMain").toString,
    "@"++(destination/"runtime.rsp").toString]
  write (study/"policy-build.json") (Json.mkObj [("cohortRuntimeSha256",sealedAdapter.getObjValD "runtimeSha256"),
    ("runtimeSha256",toJson (← hash (destination/"StudyMain"))),
    ("sourceSha256",toJson (← hash (destination/"adapter.c"))),("objectSha256",toJson (← hash (destination/"adapter.o"))),
    ("onlyForeignObserverObjectReplaced",toJson true),("noOptionSetOrCollection",toJson true)])
  discard <| command "/usr/bin/env" #["LEAN_NUM_THREADS=1",(destination/"StudyMain").toString,
    "io-heap-check",(destination/"result").toString]
  let report ← read (destination/"result/report.json")
  write (study/"policy-controls.json") report
  let policy := report.getObjValD "before" |>.getObjValD "heap"
  IO.println policy.compress
def finish : IO Unit := do
  drained
  let evidence ← read (study/"evidence.json")
  check (evidence.getObjValD "requiredOriginalAndAck" == toJson (32 : Nat) &&
    evidence.getObjValD "semanticCompletedWithHandoff" == toJson (32 : Nat)) "retain actual cohort first"
  let shapeGuard ← read (base/"io-heap-shapes1.guard.json")
  check (shapeGuard.getObjValD "exitCode" == toJson (0 : Nat) &&
    shapeGuard.getObjValD "guardTriggered" == toJson false) "native shape calibration failed"
  let shapes ← read (base/"io-heap-shapes1-result/report.json")
  check (shapes.getObjValD "allPayloadShapesCounted" == toJson true) "census misses large native buffers"
  write (study/"shape-controls.json") shapes
  write (study/"shape-build.json") (← read (study/"adapter.json"))
  let policy ← read (study/"policy-controls.json")
  let settings := (policy.getObjValD "before").getObjValD "heap"
  write (study/"policy-summary.json") (Json.mkObj [("purgeDisabled",settings.getObjValD "purgeDisabled"),
    ("purgeDelayMagnitudeMs",settings.getObjValD "purgeDelayMagnitudeMs"),
    ("arenaPurgeMultiplier",settings.getObjValD "arenaPurgeMultiplier"),
    ("purgeDecommits",settings.getObjValD "purgeDecommits"),
    ("arenaEagerCommitMode",settings.getObjValD "arenaEagerCommitMode"),
    ("sameServiceStartupNativeControl",toJson true),("actualCohortPolicyNotDirectlySampled",toJson true),
    ("noOptionSetOrCollection",toJson true)])
  let mut guards := #[]
  for entry in ← base.readDir do
    if entry.fileName.startsWith "io-heap-" && entry.fileName.endsWith ".guard.json" then
      guards := guards.push (entry.fileName,← read entry.path)
  write (study/"guards.json") (toJson guards)
  let originalCheck ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256","-c",
    (workspace/"docs/candidates/project-cache/protected-after.sha256").toString],cwd := some base}
  check (originalCheck.exitCode == 0) "protected source changed"
  let heads ← IO.ofExcept (fromJson? (← read (workspace/"docs/candidates/worker-cpu/heads.json")) :
    Except String (Array (String × (String × String))))
  for (path,(bytes,digest)) in heads do
    check ((← IO.FS.readFile (.mk path)) == bytes && (← hash (.mk path)) == digest) "original project head changed"
  let audit := workspace/"tools/research/StudyBuildClosureAudit.lean"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",audit.toString,
    "inspect",parent.toString,(study/"retained-parent-closure.json").toString]
  let retirement ← read (study/"interface-retirement.json")
  let removed ← IO.ofExcept (fromJson? (retirement.getObjValD "removed") : Except String (Array (String × Nat)))
  let mut groups : Std.HashMap String (Nat × Nat) := {}
  for (path,bytes) in removed do
    let relative := (path.drop (base.toString.length+1)).toString
    let name := (relative.splitOn "/").headD ""
    let old := groups[name]?.getD (0,0)
    groups := groups.insert name (old.1+1,old.2+bytes)
  let compact := Json.mkObj [("complete",retirement.getObjValD "complete"),
    ("removedFiles",toJson removed.size),("logicalBytes",retirement.getObjValD "plannedBytes"),
    ("byBuild",toJson groups.toArray),("retainedExecutables",retirement.getObjValD "retainedExecutables"),
    ("requiredPhysicalInterfaces",retirement.getObjValD "requiredPhysicalInterfaces"),
    ("objectsAndSourceDependencyWitnessesUntouched",toJson true),("archived",toJson false)]
  check (compact.getObjValD "complete" == toJson true) "interface cleanup did not finish"
  write (study/"interface-retirement.json") compact
  write (study/"development.json") (Json.mkObj [("guards",toJson guards.size),
    ("expectedCalibrationFailures",toJson #["checks1:remote release remains in allocator accounting",
      "checks2:ordinary unrelated allocation does not clear remote accounting"]),
    ("nativeBuildFailures",toJson #["build2:invalid IO sequencing syntax", "build7:explicit Bool conversion needed for diagnostic inequalities"]),
    ("prelaunchRefusals",toJson #["build6 before settings completion", "build6 before disk cleanup:free space below2GiB"]),
    ("largeBufferCalibrationAddedBeforeHeapAttribution",toJson true),
    ("noNew80SearchRetry",toJson true),("answeringModelCalls",toJson (0 : Nat)),("paidComparisons",toJson "0/18")])
  let baseline := base/"allocator-service-build/StudyMain"
  check ((← IO.FS.realPath (base/"worker-cpu-target/bin/eggshelld")) == baseline) "active baseline alias changed"
  let mut retired := #[]
  for directory in [target,source,base/"io-heap-policy-control",
      base/"io-heap-checks1-result",base/"io-heap-checks2-result",base/"io-heap-checks3-result",
      base/"io-heap-checks4-result",base/"io-heap-shapes1-result"] do
    if ← directory.pathExists then
      let size := (← command "/usr/bin/du" #["-sk",directory.toString]).trimAscii.toString
      IO.FS.removeDirAll directory
      retired := retired.push (directory.toString,size)
  for path in [base/"io-heap-parent.rsp",base/"io-heap-settings.json"] do
    if ← path.pathExists then IO.FS.removeFile path
  write (study/"retirement.json") (Json.mkObj [("removed",toJson retired),
    ("allGuardOwnedPidsEmpty",toJson true),("baselineAliasRestored",toJson true),
    ("protectedCompleteHeads",toJson heads.size),("otherProtectedOriginalFiles",toJson (5 : Nat)),
    ("allProtectedBytesUnchanged",toJson true),("retainedParentClosureConsistent",toJson true),
    ("rawDbCacheLogAndUnusedObserverExecutablesDeleted",toJson true),("archived",toJson false)])
  IO.println (Json.mkObj [("guards",toJson guards.size),("shapeControls",shapes.getObjValD "allPayloadShapesCounted"),
    ("policy",← read (study/"policy-summary.json")),("retiredDirectories",toJson retired.size)]).compress
def verifyArtifacts : IO Unit := do
  drained
  let temporary := base/"io-heap-witness-check"
  check (!(← temporary.pathExists)) "fresh witness verification directory required"
  IO.FS.createDirAll temporary
  try
    IO.FS.writeFile (temporary/"heap_observation.c") (← IO.FS.readFile (workspace/"tools/research/native/heap_observation.c"))
    IO.FS.writeFile (temporary/"IoHeapChecks.lean") (← IO.FS.readFile (workspace/"tools/research/IoHeapChecks.lean"))
    for patch in ["policy-adapter.patch","shape-entry.patch"] do
      discard <| command "/usr/bin/patch" #["-s","-R","-p1","-d",temporary.toString,"-i",(study/patch).toString]
    let cohort ← read (study/"cohort-adapter.json")
    let cHash ← hash (temporary/"heap_observation.c")
    check (cohort.getObjValD "sourceSha256" == toJson cHash) "reconstructed cohort C boundary differs"
    let body ← IO.FS.readFile (temporary/"IoHeapChecks.lean")
    check (!body.contains "def shapes" && body.contains "def controls") "reconstructed cohort entry differs"
    let shapes ← read (study/"shape-controls.json")
    let rows ← IO.ofExcept (shapes.getObjValAs? (Array Json) "rows")
    check (rows.map (·.getObjValD "payloadBytes") == #[toJson (65536 : Nat),toJson (2097152 : Nat),toJson (33554432 : Nat)] &&
      rows.all (fun row => row.getObjValD "sameOwner" == toJson true && row.getObjValD "complete" == toJson true &&
        row.getObjValD "heldPayloadCounted" == toJson true && row.getObjValD "ownerLocalReleaseCounted" == toJson true))
      "actual native shape controls do not cover the stated buffers"
    let guards ← IO.ofExcept (fromJson? (← read (study/"guards.json")) : Except String (Array (String × Json)))
    check (guards.size == 15 && guards.all (fun (_,guard) => guard.getObjValD "state" == toJson "finished" &&
      guard.getObjValD "ownedPids" == toJson (#[] : Array Nat))) "retained guards not drained"
    let failed := guards.filter fun (_,guard) => guard.getObjValD "exitCode" != toJson (0 : Nat)
    let analysis ← read (study/"analysis.json")
    write (study/"verification.json") (Json.mkObj [("reconstructedCohortCSourceSha256",toJson cHash),
      ("reconstructedCohortEntrySha256",toJson (← hash (temporary/"IoHeapChecks.lean"))),
      ("actualBufferShapesVerified",toJson true),("all15GuardsDrained",toJson true),
      ("failedGuardsRetained",toJson (failed.map Prod.fst)),("bodyVerification",analysis.getObjValD "all35StdoutExact"),
      ("adopted",toJson false)])
    let development ← read (study/"development.json")
    write (study/"development.json") (development.setObjVal! "controllerPreflightCorrections" (toJson #[
      "explicit lambda for overloaded String.contains in prior-vm projection",
      "bound analysis IO before JSON field projection in witness verification"]))
    let plan ← read (study/"plan.json")
    write (study/"plan.json") (plan.setObjVal! "continuationPreviousGoalTurn"
      (toJson "progress:24d851d6 proved immutable authorization;native80-reader control and actual32-hook parity passed"))
    IO.println (Json.mkObj [("all15GuardsDrained",toJson true),("failedGuardsRetained",toJson (failed.map Prod.fst)),
      ("shapeControls",toJson true),("cohortCSourceReconstructedExactly",toJson true)]).compress
  finally IO.FS.removeDirAll temporary
def main (args : List String) : IO Unit := do
  match args with
  | ["prepare"] => prepare
  | ["build"] => build
  | ["setup",action,tag] => setup action tag
  | ["refresh-entry"] => refreshEntry
  | ["prepare-shapes"] => prepareShapes
  | ["record-checks",tag] => recordChecks tag
  | ["seal-observer",tag] => sealObserver tag
  | ["retain-controls",tag] => retainControls tag
  | ["retire-interfaces"] => retireInterfaces
  | ["analyze"] => analyze
  | ["prior-vm"] => priorVmSummary
  | ["build-policy"] => buildPolicy
  | ["finish"] => finish
  | ["verify"] => verifyArtifacts
  | _ => throw (IO.userError "prepare | setup ACTION TAG")
end Eggshell.Research.IoHeapStudy
def main := Eggshell.Research.IoHeapStudy.main
