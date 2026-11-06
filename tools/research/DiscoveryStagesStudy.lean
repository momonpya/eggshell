import Lean.Data.Json.FromToJson
import Lean.Data.Json.Parser
import Std.Data.HashMap
open Lean
def workspace : System.FilePath := "/Users/ovm/.codex/worktrees/hook-deadline-baseline/eggshell"
def base : System.FilePath := "/Users/ovm/.codex/experiments/eggshell/scope-token-study-20261028/fixed-frame-study"
def compiler : System.FilePath := "/Users/ovm/.elan/toolchains/leanprover--lean4---v4.33.0"
def study := workspace/"docs/candidates/discovery-stages"
def sourceRoot := base/"discovery-stages-source"
def target := base/"discovery-stages-build"
def clientSource := base/"discovery-stages-client-source"
def clientTarget := base/"discovery-stages-client-build"
def parent := base/"pure-file-reads-build"
def clientParent := base/"numerical-stages-client-build"
def focusSource := base/"prepared-focus-source"
def focusTarget := base/"prepared-focus-build"
def focusStudy := workspace/"docs/candidates/prepared-focus"
def focusHookSource := base/"prepared-focus-hook-source"
def focusHookTarget := base/"prepared-focus-hook-build"
def focusHookStudy := workspace/"docs/candidates/prepared-focus-hook"
def check (ok : Bool) (message : String) : IO Unit := unless ok do throw (IO.userError message)
def read (path : System.FilePath) : IO Json := IO.FS.readFile path >>= (IO.ofExcept ∘ Json.parse)
def write (path : System.FilePath) (value : Json) : IO Unit := IO.FS.writeFile path value.compress
def arr (value : Json) (key : String) : Array Json := (value.getObjValAs? (Array Json) key).toOption.getD #[]
def command (cmd : String) (args : Array String) (cwd : System.FilePath := workspace) : IO String := do
  let result ← IO.Process.output {cmd,args,cwd := some cwd}
  check (result.exitCode == 0) (result.stdout++result.stderr)
  return result.stdout
def hash (path : System.FilePath) : IO String := do
  return ((← command "/usr/bin/shasum" #["-a","256",path.toString]).splitOn " ").headD ""
def drained : IO Unit := do
  for entry in ← base.readDir do
    unless ["pure-file-reads-","discovery-stages-","prepared-focus-"].any (fun stem => entry.fileName.startsWith stem) &&
        entry.fileName.endsWith ".guard.json" do continue
    let value ← read entry.path
    check (value.getObjValD "state" == toJson "finished" && value.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "previous guard not drained"
    let pid ← IO.ofExcept (value.getObjValAs? Nat "guardPid")
    let probe ← IO.Process.output {cmd := "/bin/ps",args := #["-p",toString pid,"-o","command="]}
    let settingsName := (entry.fileName.dropEnd ".guard.json".length).toString++".guard-settings.json"
    let sameGuard := probe.exitCode == 0 && probe.stdout.contains "controller/StudyMain" &&
      probe.stdout.contains "guard " && probe.stdout.contains settingsName
    check (!sameGuard) ("previous guard still live: "++entry.fileName)

def materialize (selected destination output : System.FilePath) (entry : String) : IO Unit := do
  check (!(← destination.pathExists)) "fresh native source destination required"
  let build ← read (selected/"build.json")
  let config := build.getObjValD "settings"
  let oldEntry ← IO.ofExcept (config.getObjValAs? String "mainModule")
  let mut mapping ← read (selected/"object-mapping.json")
  for row in arr build "modules" do
    mapping := mapping.setObjVal! (← IO.ofExcept (row.getObjValAs? String "object")) (row.getObjValD "module")
  let objects ← ((← IO.FS.readFile (selected/"runtime.rsp")).splitOn "\n").filterMapM fun row => do
    if row.trimAscii.isEmpty then return none
    return some (← IO.ofExcept (Json.parse row >>= Json.getStr?))
  let mut files : Std.HashMap String String := {}
  let mut embedded := #[]
  for object in objects do
    let witness := (System.FilePath.mk object).withExtension "source"
    unless ← witness.pathExists do continue
    let name ← IO.ofExcept (mapping.getObjValAs? String object)
    if name == oldEntry && oldEntry != entry then continue
    let path := destination/(name.replace "." "/"++".lean")
    let value ← IO.ofExcept (fromJson? (← read witness) : Except String (String × Array (String × String)))
    files := files.insert path.normalize.toString value.1
    for (relative,bytes) in value.2 do embedded := embedded.push ((path.parent.get!/relative).normalize.toString,bytes)
  for (path,bytes) in embedded do
    check (path.startsWith destination.toString) "embedded source escaped root"
    if let some current := files[path]? then check (current == bytes) "selected source witnesses disagree"
    else files := files.insert path bytes
  for (path,bytes) in files do
    let path := System.FilePath.mk path
    IO.FS.createDirAll path.parent.get!
    IO.FS.writeFile path bytes
  if oldEntry != entry then
    IO.FS.writeFile (destination/(entry.replace "." "/"++".lean"))
      (← IO.FS.readFile (workspace/(entry.replace "." "/"++".lean")))
  IO.FS.createDirAll (destination/".lake/build/lib")
  discard <| command "/bin/ln" #["-s",(selected/"lib").toString,(destination/".lake/build/lib/lean").toString]
  write (destination/"object-mapping.json") mapping
  let mut settings := config.setObjVal! "parents" (toJson (#[selected.toString]++(← IO.ofExcept (config.getObjValAs? (Array String) "parents"))))
  for (key,value) in [("project",destination.toString),("core",destination.toString),("output",output.toString),
      ("baselineResponse",(selected/"runtime.rsp").toString),
      ("baselineMain",(selected/(oldEntry.replace "." "_"++".o")).toString),
      ("objectModules",(destination/"object-mapping.json").toString),("mainModule",entry)] do
    settings := settings.setObjVal! key (toJson value)
  write (base/(if destination == sourceRoot then "discovery-stages-settings.json" else if destination == focusSource then
    "prepared-focus-settings.json" else if destination == focusHookSource then "prepared-focus-hook-settings.json"
    else "discovery-stages-client-settings.json")) settings

def prepare : IO Unit := do
  drained
  IO.FS.createDirAll study
  check ((← hash (parent/"StudyMain")) == "b2dc39ff335bf7aafa105d7da1ca2575ddefdc8e34c49e78430927579371012a") "runtime parent changed"
  check ((← hash (clientParent/"StudyMain")) == "a80cad2a80fb084842d22e3ead44358762fbdea3e175601b1d407d82c67b308e") "sealed client changed"
  materialize parent sourceRoot target "tools.research.DiscoveryStagesChecks"
  materialize clientParent clientSource clientTarget "tools.research.WorkerCpuProfile"
  write (study/"plan.json") (Json.mkObj [("classificationPreviousTurn",toJson "progress:removed redundant synchronized file cache with kernel/native evidence"),
    ("status",toJson "diagnostic candidate,not adopted"),("cohort",toJson "same16sources/32cases/2waves;no80fullsearch retry"),
    ("questionIndependentPreparationNotMovedIntoRetrieval",toJson true),
    ("purpose",toJson "split post-provider discovery/focus/transport and retain exact shutdown errors/process identities"),
    ("unchanged",toJson "rank,scope,full certification,deadlines,worker count,resource bounds"),
    ("runtimeParent",toJson (← hash (parent/"StudyMain"))),("sealedClientParent",toJson (← hash (clientParent/"StudyMain")))])

def prepareFocus : IO Unit := do
  drained
  check ((← hash (target/"StudyMain")) == "284ba3a063a703234c53d61cbea991cf35b3b692a5a9200f30df664cdcee52ae") "focus parent changed"
  materialize target focusSource focusTarget "tools.research.PreparedFocusChecks"
  IO.FS.writeFile (focusSource/"tools/research/PreparedFocusFacts.lean")
    (← IO.FS.readFile (workspace/"tools/research/PreparedFocusFacts.lean"))
  IO.FS.createDirAll focusStudy
  write (focusStudy/"plan.json") (Json.mkObj [("previousTurn",toJson "progress:separated actual post-provider costs and found repeated window tokenization"),
    ("status",toJson "isolated,not adopted"),("scope",toJson "compile interned original-window lexical facts in publication deltas and decode in existing shared metadata"),
    ("unchanged",toJson "original source heads,rank/Float order,MiniLM,synapses,e-class certification,deadlines,resource bounds"),
    ("hookIntegrationRequiredBeforePerformanceClaim",toJson true),("paidComparisons",toJson "0/18")])

def setup (action tag : String) : IO Unit := do
  drained
  let path := base/(tag++".guard-settings.json")
  check (!(← path.pathExists)) "fresh diagnostic tag required"
  let arguments ← if action == "build" || action == "client-build" || action == "focus-build" || action == "focus-hook-build" then
    pure #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",(workspace/"tools/research/StudyBuildMain.lean").toString,
      (base/(if action == "build" then "discovery-stages-settings.json" else if action == "focus-build" then
        "prepared-focus-settings.json" else if action == "focus-hook-build" then "prepared-focus-hook-settings.json"
        else "discovery-stages-client-settings.json")).toString]
    else if action == "focus-hook-preflight" then pure #["/usr/bin/env",
      "LEAN_PATH="++(focusHookTarget/"lib").toString++":"++(focusHookSource/".lake/build/lib/lean").toString++":"++(compiler/"lib/lean").toString,
      (compiler/"bin/lean").toString,"--root="++focusHookSource.toString,"-j1","-M3072","-DwarningAsError=true",
      (focusHookSource/"Eggshell/Handoff.lean").toString]
    else if action == "focus-hook-checks" then pure #["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_TRACE_SERVICE_PROFILE=0",
      "EGGSHELL_DATA_ROOT="++(base/(tag++"-result/private")).toString,
      "EGGSHELL_CONFIG="++(base/(tag++"-result/eggshell.toml")).toString,
      (focusHookTarget/"StudyMain").toString,"file-read-check",(base/(tag++"-result")).toString]
    else if action == "focus-checks" then pure #["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_TRACE_SERVICE_PROFILE=0",
      "EGGSHELL_DATA_ROOT="++(base/(tag++"-result/private")).toString,
      "EGGSHELL_CONFIG="++(base/(tag++"-result/eggshell.toml")).toString,
      (focusTarget/"StudyMain").toString,"prepared-focus-check",(base/(tag++"-result")).toString]
    else if action == "hooks" || action == "focus-hook-cohort" then pure #["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_TRACE_SERVICE_PROFILE=1",
      "EGGSHELL_TRACE_QUERY_STAGES=1","EGGSHELL_TRACE_NUMERICAL_STAGES=1","EGGSHELL_TRACE_ALLOCATOR=1","EGGSHELL_TRACE_ACTOR_HEAP=1",
      "EGGSHELL_DATA_ROOT="++(base/(tag++"-result/private")).toString,"EGGSHELL_CONFIG="++(base/(tag++"-result/eggshell.toml")).toString,
      "PLUGIN_ROOT="++(base/"worker-cpu-target").toString,(clientTarget/"StudyMain").toString,
      (base/(tag++"-result")).toString,((if action == "hooks" then target else focusHookTarget)/"StudyMain").toString,
      ← hash ((if action == "hooks" then target else focusHookTarget)/"StudyMain")]
    else throw (IO.userError "unknown diagnostic action")
  write path (Json.mkObj [("command",toJson arguments),("cwd",toJson workspace.toString),
    ("record",toJson (base/(tag++".guard.json")).toString),("ownedPrefixes",toJson #[base.toString]),
    ("limitRssKiB",toJson (3670016 : Nat)),("minFreeKiB",toJson (2097152 : Nat))])

def sealRuntime : IO Unit := do
  drained
  for (selected,built,changes,name) in [(parent,target,#["Eggshell.Handoff"],"runtime"),
      (clientParent,clientTarget,(#[] : Array String),"client")] do
    discard <| command (compiler/"bin/lean").toString (#["-j1","-M1536","--run",
      (workspace/"tools/research/StudyBuildClosureAudit.lean").toString,"compare-sources",selected.toString,
      built.toString,(study/(name++"-sources.json")).toString]++changes)
    check ((← read (study/(name++"-sources.json"))).getObjValD "exactExpectedChangeSet" == toJson true) "unexpected native change"
  for (oldRoot,newRoot,name) in [(base/"pure-file-reads-source",sourceRoot,"Eggshell.Handoff"),
      (base/"discovery-stages-client-original",clientSource,"tools.research.WorkerCpuProfile")] do
    let relative := name.replace "." "/"++".lean"
    let patch ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","--label","a/"++relative,"--label","b/"++relative,
      (oldRoot/relative).toString,(newRoot/relative).toString]}
    check (patch.exitCode == 1) "missing observation patch"
    IO.FS.writeFile (study/(name.replace "." "_"++".patch")) patch.stdout
  write (study/"build.json") (Json.mkObj [("runtime",toJson (← hash (target/"StudyMain"))),
    ("client",toJson (← hash (clientTarget/"StudyMain"))),
    ("ordinaryContractAuditAndStageBindings",toJson (← IO.FS.readFile (target/"tools_research_DiscoveryStagesChecks-lean.stdout")))])
  IO.FS.removeFile (base/"worker-cpu-target/bin/eggshelld")
  discard <| command "/bin/ln" #["-s",(target/"StudyMain").toString,(base/"worker-cpu-target/bin/eggshelld").toString]

def distribution (values : Array Nat) : Json := Id.run do
  let values := values.qsort (· < ·)
  return Json.mkObj [("count",toJson values.size),("min",toJson values[0]?),
    ("median",toJson values[values.size/2]?),("max",toJson values.back?)]
def processSummary (rows : Json) : IO Json := do
  let values ← IO.ofExcept rows.getArr?
  let values ← values.mapM fun row => do
    let program := (row.getObjValAs? String "program").toOption.getD ""
    if program.length ≤ 2048 then return row
    -- Use a real stdin digest; never interpolate a command argument.
    let digest ← IO.Process.output {cmd := "/usr/bin/shasum",args := #["-a","256"]} (some program)
    check (digest.exitCode == 0) "cannot digest long numerical command"
    return row.setObjVal! "program" (toJson ((program.splitOn " -c ").headD ""++" [inline code omitted]"))
      |>.setObjVal! "programSha256" (toJson ((digest.stdout.splitOn " ").headD ""))
      |>.setObjVal! "programUtf8Bytes" (toJson program.utf8ByteSize)
  return toJson values
def record (tag : String) (destination : System.FilePath := study) (mode : String := "--discovery-stages")
    (previousPath : System.FilePath := workspace/"docs/candidates/typed-original-reads/evidence.json")
    (expectFocusSample : Bool := true) (guardStem : String := "discovery-stages-") : IO Unit := do
  drained
  let study := destination
  let recordScript := workspace/"docs/candidates/shared-leases/records.lean"
  if !(← (study/"evidence.json").pathExists) then
    discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",recordScript.toString,mode,tag]
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",recordScript.toString,mode,"verify","35"]
  let evidence ← read (study/"evidence.json")
  let previous ← read previousPath
  let runs := arr evidence "runs"
  check (runs.size == 1) "one predeclared diagnostic cohort required"
  let run := runs[0]!
  let control := (arr previous "runs")[0]!
  let measured := fun run => (arr run "rowsIncludingPrime").filter fun row =>
    ((row.getObjValAs? String "session").toOption.getD "").startsWith "cpu-wave-"
  let matching := (measured run).filter fun row => (measured control).any fun old =>
    old.getObjValD "session" == row.getObjValD "session" && old.getObjValD "stdoutSha256" == row.getObjValD "stdoutSha256"
  write (study/"parity.json") (Json.mkObj [("matchingCompleteStdout",toJson matching.size),
    ("fixedQueries",toJson (measured run).size),("control",control.getObjValD "tag"),
    ("notTokenAdoptionComparison",toJson true)])
  let mut intervals : Std.HashMap String (Array Nat) := {}
  let mut heaps : Std.HashMap String (Array Int) := {}
  let mut common := 0
  let mut reference := 0
  for wave in arr run "waves" do
    for receipt in arr wave "receipts" do
      let pages := receipt.getObjValD "request-pages"
      let rows ← IO.ofExcept (fromJson? (pages.getObjValD "queryStages") : Except String (Array (String × Nat)))
      if rows.any (·.1 == "configured:owner-view:common") then common := common+1
      if rows.any (·.1 == "configured:owner-view:reference") then reference := reference+1
      let normalized := fun (label : String) => if label.contains "render complete chars=" then
        ((label.splitOn "render complete chars=").headD "")++"render complete" else label
      for i in [:rows.size-1] do
        let first := rows[i]!
        let last := rows[i+1]!
        check (first.2 ≤ last.2) "non-monotone actor stages"
        let key := normalized first.1++" -> "++normalized last.1
        intervals := intervals.insert key ((intervals[key]?.getD #[]).push (last.2-first.2))
      let observations ← IO.ofExcept (fromJson? (pages.getObjValD "ownerHeapStages") : Except String (Array (String × Json)))
      for i in [:observations.size-1] do
        let first := observations[i]!
        let last := observations[i+1]!
        let before ← IO.ofExcept (first.2.getObjValAs? Nat "ownerUsedBytes")
        let after ← IO.ofExcept (last.2.getObjValAs? Nat "ownerUsedBytes")
        let key := normalized first.1++" -> "++normalized last.1
        heaps := heaps.insert key ((heaps[key]?.getD #[]).push (Int.ofNat after-Int.ofNat before))
  let gapRows := intervals.toArray.map fun (key,values) => (key,distribution values)
  let gapRows := gapRows.qsort fun a b =>
    (a.2.getObjValAs? Nat "median").toOption.getD 0 > (b.2.getObjValAs? Nat "median").toOption.getD 0
  let heapRows := heaps.toArray.map fun (key,values) => Id.run do
    let values := values.qsort (· < ·)
    return (key,Json.mkObj [("count",toJson values.size),("min",toJson values[0]?),
      ("median",toJson values[values.size/2]?),("max",toJson values.back?)])
  let root := base/(tag++"-result")
  let report ← read (root/"report.json")
  let hosts := ["prime","first","second"].filterMap fun name =>
    ((arr (report.getObjValD name) "after").find? fun row => row.getObjValD "role" == toJson "publication-service").map fun row => (name,row)
  let mut shutdown ← read (root/"shutdown.json")
  for key in ["before","afterFrontend","afterPublisher"] do
    shutdown := shutdown.setObjVal! key (← processSummary (shutdown.getObjValD key))
  let frontend ← read (root/"shutdown-frontend.json")
  let frontend := frontend.setObjVal! "processesAfter" (← processSummary (frontend.getObjValD "processesAfter"))
  write (study/"measurements.json") (Json.mkObj [("consecutiveStageGapsMs",toJson gapRows),
    ("ownerHeapDeltasNotWholeProcessLiveBytes",toJson heapRows),("commonPathQueries",toJson common),
    ("referencePathQueries",toJson reference),("hostAfterWaves",toJson hosts),
    ("shutdown",shutdown),("frontendShutdown",frontend),
    ("sample",← read (root/"sample-result.json")),("wallIntervalsNotCpuOrAdditiveMedians",toJson true)])
  let mut guards := #[]
  for entry in ← base.readDir do
    if entry.fileName.startsWith guardStem && entry.fileName.endsWith ".guard.json" then
      let value ← read entry.path
      let value ← if value.getObjValD "peakProcesses" == Json.null then pure value else
        pure (value.setObjVal! "peakProcesses" (← processSummary (value.getObjValD "peakProcesses")))
      guards := guards.push (entry.fileName,value)
  write (study/"controls.json") (toJson guards)
  let sample := root/"worker.sample.txt"
  let lines := (← IO.FS.readFile sample).splitOn "\n"
  let observed := lines.findIdx? (·.contains "l_Eggshell_Plugin_refocusObservedNeighborhood")
  if expectFocusSample && observed.isNone then throw (IO.userError "tail sample does not show the claimed focus branch")
  let first := observed.getD 22
  write (study/"sample-context.json") (Json.mkObj [("sha256",toJson (← hash sample)),
    ("header",toJson (lines.take 22)),("firstLine",toJson (first+1)),
    ("excerpt",toJson ((lines.drop first).take 85)),
    ("sampleObservationsNotCpuPercentages",toJson true),("focusFrameObserved",toJson observed.isSome)])
  if mode == "--discovery-stages" then
    write (study/"development.json") (Json.mkObj [("controllerPreflightErrors",toJson #[
      "reserved matches identifier","mutable intervals shadowed;both corrected before client build"]),
      ("nativeAndHookFailuresThisCohort",toJson (0 : Nat))])
  IO.println (Json.mkObj [("largestGaps",toJson (gapRows.extract 0 12)),("hosts",toJson hosts),
    ("common",toJson common),("reference",toJson reference),
    ("frontendExit",shutdown.getObjValD "frontendExit"),("publisherExit",shutdown.getObjValD "publisherExit")]).pretty

def cleanup (tag : String) : IO Unit := do
  drained
  let verify ← read (study/"verification.json")
  check (verify.getObjValD "actualOutputs" == toJson (35 : Nat) &&
    (← read (study/"parity.json")).getObjValD "matchingCompleteStdout" == toJson (32 : Nat)) "retain actual bodies and parity before cleanup"
  let baseline := base/"allocator-service-build/StudyMain"
  check ((← hash baseline) == "4e4c9b9c95cb2c72b4447a86f5abc81b6bb619854889eb5ffa8492ba592e593a") "active baseline changed"
  IO.FS.removeFile (base/"worker-cpu-target/bin/eggshelld")
  discard <| command "/bin/ln" #["-s",baseline.toString,(base/"worker-cpu-target/bin/eggshelld").toString]
  let root := base/(tag++"-result")
  check (root.toString.startsWith (base/"discovery-stages-").toString && (← (root/"report.json").pathExists)) "only ended diagnostic state may be removed"
  IO.FS.removeDirAll root
  IO.FS.removeDirAll (base/"discovery-stages-client-original")
  let mut count := 0
  for build in [target,clientTarget] do
    for entry in ← build.readDir do
      if entry.fileName.endsWith ".stdout" || entry.fileName.endsWith ".stderr" then
        IO.FS.removeFile entry.path
        count := count+1
  write (study/"cleanup.json") (Json.mkObj [("endedDbCacheSessionsAndRawLogsRemoved",toJson root.toString),
    ("temporaryClientReferenceRemoved",toJson true),("compilerLogsRemoved",toJson count),
    ("baselineAliasRestored",toJson true),("originalSourcesAndRequiredNativeInputsRetained",toJson true),("archived",toJson false)])

def retireParents : IO Unit := do
  drained
  check ((← read (study/"parity.json")).getObjValD "matchingCompleteStdout" == toJson (32 : Nat))
    "retain full current-parent body parity before retiring old executables"
  let mut removed := #[]
  for (name,expected) in [("typed-original-reads-build","85bdaaff131a61deb0ac3ef332acf477131d5f8f6f363aa4239534d918f86d6c"),
      ("pure-file-reads-build","b2dc39ff335bf7aafa105d7da1ca2575ddefdc8e34c49e78430927579371012a")] do
    let path := base/name/"StudyMain"
    check ((← hash path) == expected && (← (base/name/"runtime.rsp").pathExists)) "unexpected retired executable"
    IO.FS.removeFile path
    removed := removed.push (path.toString,expected)
  let previous ← read (study/"cleanup.json")
  write (study/"cleanup.json") (previous.setObjVal! "obsoleteExecutablesRemoved" (toJson removed))

def compactRecords (destination : System.FilePath := study) : IO Unit := do
  drained
  let study := destination
  for name in ["evidence.json","bodies.json","verification.json"] do
    let path := study/name
    let value ← read path
    write path value
    check ((← read path) == value) "record formatting changed parsed evidence"

def retireObsoleteExecutables : IO Unit := do
  drained
  IO.FS.createDirAll focusStudy
  let mut keep := #["allocator-service-build","prepared-focus-build","prepared-focus-hook-build","discovery-stages-build",
    "discovery-stages-client-build","numerical-stages-client-build","metadata-ingress-candidate-build"]
  for path in [base/"owned-ready-prefix/libexec/eggshell",base/"reply-admission-prefix/libexec/eggshell",
      base/"worker-cpu-target/bin/eggshelld"] do
    let actual ← IO.FS.realPath path
    if actual.fileName == some "StudyMain" then
      if let some name := actual.parent.bind System.FilePath.fileName then keep := keep.push name
  let mut planned := #[]
  for entry in ← base.readDir do
    unless entry.fileName.endsWith "-build" && !keep.contains entry.fileName do continue
    let executable := entry.path/"StudyMain"
    unless ← executable.pathExists do continue
    check ((← executable.symlinkMetadata).type == .file &&
      (← (entry.path/"build.json").pathExists) && (← (entry.path/"runtime.rsp").pathExists)) "unrecognized old native executable"
    planned := planned.push (executable.toString,← hash executable)
  write (focusStudy/"retirement-plan.json") (Json.mkObj [("obsoleteExecutables",toJson planned),
    ("keptActiveRuntimeClientsGuardAndRawAuditor",toJson keep),
    ("objectsInterfacesSourceWitnessesAndOriginalDbsRetained",toJson true)])
  for (path,digest) in planned do
    check ((← hash (.mk path)) == digest) "obsolete executable changed during cleanup"
    IO.FS.removeFile (.mk path)
  write (focusStudy/"retired-executables.json") (Json.mkObj [("removed",toJson planned),
    ("archived",toJson false),("onlyOwnedCompletedNativeExecutableFiles",toJson true)])
  IO.println (Json.mkObj [("removedExecutables",toJson planned.size)]).compress

def sealFocus (tag : String) : IO Unit := do
  drained
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",
    (workspace/"tools/research/StudyBuildClosureAudit.lean").toString,"inspect",focusTarget.toString,
    (focusStudy/"native-closure.json").toString]
  let changes := #["tools.research.PreparedSourceView","Eggshell.CanonicalSourceCache",
    "tools.research.OwnerMetadataImage","tools.research.SharedReadViews"]
  let nativeSources := focusStudy/"native-sources.json"
  discard <| command (compiler/"bin/lean").toString (#["-j1","-M1536","--run",
    (workspace/"tools/research/StudyBuildClosureAudit.lean").toString,"compare-sources",target.toString,
    focusTarget.toString,nativeSources.toString]++changes++#["+tools.research.PreparedFocusFacts"])
  check ((← read nativeSources).getObjValD "exactExpectedChangeSet" == toJson true) "unexpected focus native change"
  for name in changes do
    let relative := name.replace "." "/"++".lean"
    let patch ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","--label","a/"++relative,"--label","b/"++relative,
      (sourceRoot/relative).toString,(focusSource/relative).toString]}
    check (patch.exitCode == 1) "missing focus implementation patch"
    IO.FS.writeFile (focusStudy/(name.replace "." "_"++".patch")) patch.stdout
  check ((← IO.FS.readFile (sourceRoot/"Eggshell/CanonicalSourcePrepared.lean")) ==
    (← IO.FS.readFile (focusSource/"Eggshell/CanonicalSourcePrepared.lean"))) "per-read cache acquisition changed the source API"
  for name in ["PreparedFocusFacts","PreparedFocusChecks"] do
    check ((← IO.FS.readFile (workspace/s!"tools/research/{name}.lean")) ==
      (← IO.FS.readFile (focusSource/s!"tools/research/{name}.lean"))) "recorded focus source differs from executable input"
  write (focusStudy/"build.json") (Json.mkObj [("runtime",toJson (← hash (focusTarget/"StudyMain"))),
    ("parent",toJson (← hash (target/"StudyMain"))),
    ("kernelAndOrdinaryContractAudit",toJson (← IO.FS.readFile (focusTarget/"tools_research_PreparedFocusChecks-lean.stdout"))),
    ("capturedReadOnly",toJson true),("readType",toJson "Image -> immutable coordinates -> Except String (List Nat)")])
  let final ← read (base/(tag++"-result/report.json"))
  check (final.getObjValD "capturedReadIsPure" == toJson true &&
    final.getObjValD "perReadCacheAcquisitionRemoved" == toJson true &&
    final.getObjValD "publishedRankComparisons" == toJson (1630 : Nat)) "focus native control incomplete"
  write (focusStudy/"native-checks.json") final
  write (focusStudy/"previous-component-checks.json") (← read (base/"prepared-focus-checks2-result/report.json"))
  let beforeDelta := base/"prepared-focus-checks1-result/published-checks.json"
  if ← beforeDelta.pathExists then write (focusStudy/"failed-delta-checks.json") (← read beforeDelta)
  let mut guards := #[]
  for entry in ← base.readDir do
    if entry.fileName.startsWith "prepared-focus-" && entry.fileName.endsWith ".guard.json" then
      guards := guards.push (entry.fileName,← read entry.path)
  write (focusStudy/"controls.json") (toJson guards)
  write (focusStudy/"development.json") (Json.mkObj [("failures",toJson #[
    "build1:ambiguous tuple inferred as Totals;fixed explicit Recipe.Stored x Statistics",
    "build3:missing do in checker callback;fixed",
    "build4:unchecked Build.Entry indexing required nonexistent Inhabited;used checked optional entry",
    "checks1:private delta clone lacked original writer sentinel;fixed clone,product unchanged",
    "build7:disk free guard stopped at2015280KiB;all PIDs drained,obsolete binaries removed,limits unchanged",
    "before build9:rejected Loaded.focusWindows API because every read reacquired mutable shared cache;removed API and used existing captured immutable metadata",
    "build9:pure Except proof required final definitional reduction;added rfl,reader implementation unchanged",
    "build10:checker capture callback lacked do around clock read;fixed callback and exercised existing query reservation instead of retaining unreserved test data",
    "build11:checker used unavailable Except.isError;replaced with existing toOption.isNone",
    "seal controller preflight:reserved partial identifier;renamed before running seal",
    "one unapplied patch had invalid context;no partial source change"]),
    ("hookIntegrationTested",toJson false),("answeringModelCalls",toJson (0 : Nat)),
    ("paidMatchedComparisons",toJson "0/18"),("adopted",toJson false)])

def cleanupFocus : IO Unit := do
  drained
  check ((← read (focusStudy/"native-sources.json")).getObjValD "exactExpectedChangeSet" == toJson true)
    "preserve native closure before cleanup"
  check ((← read (focusStudy/"native-checks.json")).getObjValD "capturedReadIsPure" == toJson true)
    "preserve native controls before cleanup"
  let mut removed := #[]
  for entry in ← base.readDir do
    if entry.fileName.startsWith "prepared-focus-checks" && entry.fileName.endsWith "-result" &&
        (← entry.path.isDir) then
      IO.FS.removeDirAll entry.path
      removed := removed.push entry.fileName
  let mut logs := 0
  for entry in ← focusTarget.readDir do
    if entry.fileName.endsWith ".stdout" || entry.fileName.endsWith ".stderr" then
      IO.FS.removeFile entry.path
      logs := logs+1
  write (focusStudy/"cleanup.json") (Json.mkObj [("endedDbCachesAndSessionRootsRemoved",toJson removed),
    ("compilerLogsRemoved",toJson logs),("protectedOriginalsAndNativeInputsRetained",toJson true),
    ("runtimeAliasUnchanged",toJson true),("archived",toJson false)])

def verifyFocusOriginals : IO Unit := do
  drained
  let heads ← IO.ofExcept (fromJson? (← read (workspace/"docs/candidates/worker-cpu/heads.json")) :
    Except String (Array (String × (String × String))))
  for (path,(bytes,digest)) in heads do
    check ((← IO.FS.readFile (.mk path)) == bytes && (← hash (.mk path)) == digest)
      "protected complete original head changed"
  write (focusStudy/"protected-originals.json") (Json.mkObj [("completeHeadsAndSha256Unchanged",toJson heads.size),
    ("protectedAfterSha256Manifest",toJson "docs/candidates/project-cache/protected-after.sha256")])

def prepareFocusHook : IO Unit := do
  drained
  let parentBuild ← read (focusStudy/"build.json")
  check ((← hash (focusTarget/"StudyMain")) == (← IO.ofExcept (parentBuild.getObjValAs? String "runtime"))) "focus native parent changed"
  materialize focusTarget focusHookSource focusHookTarget "tools.research.PreparedFocusHookChecks"
  IO.FS.createDirAll focusHookStudy
  write (focusHookStudy/"plan.json") (Json.mkObj [("previousTurn",toJson "progress:proved pure captured window ranks and bounded delta publication"),
    ("status",toJson "isolated,not adopted"),("purpose",toJson "consume the existing captured metadata in the actual Handoff focus and reuse its one batch through synaptic selection"),
    ("fixed",toJson "same16originals/32queries/2waves;rank,MiniLM,scope,certification,deadlines and resource bounds unchanged"),
    ("no80FullSearchRetry",toJson true),("paidComparisons",toJson "0/18")])

def scopeFocusHook : IO Unit := do
  drained
  let file := focusHookSource/"Eggshell/Handoff.lean"
  let text ← IO.FS.readFile file
  let [before,rest] := text.splitOn "  let preparedWindows ←" | throw (IO.userError "unique focus batch lifetime start required")
  let [middle,after] := rest.splitOn "  try\n    if !synaptic.canonicalFailure.isEmpty" |
    throw (IO.userError "unique original batch lifetime required")
  let block := "  let preparedWindows ←"++middle
  let nested := "\n".intercalate ((block.splitOn "\n").dropLast.map ("  "++·))++"\n"
  IO.FS.writeFile file (before++"  try\n"++
    "    if recommendation && evidence.isNone && windowQuery.isSome && focusBatch.isNone && !focusDomain.isEmpty then return some pendingSearch\n"++
    nested++"    if !synaptic.canonicalFailure.isEmpty"++after)

def sealFocusHook (checksTag : String) : IO Unit := do
  drained
  let native ← read (base/(checksTag++"-result/report.json"))
  check (native.getObjValD "typedAndWireWindowRanksExact" == toJson true &&
    native.getObjValD "foreignFocusWorkAndWindowsRejectedAndReleased" == toJson true &&
    native.getObjValD "allReservationsReleased" == toJson true) "actual focus protocol controls incomplete"
  let audit := workspace/"tools/research/StudyBuildClosureAudit.lean"
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",audit.toString,
    "inspect",focusHookTarget.toString,(focusHookStudy/"native-closure.json").toString]
  let changes := #["tools.research.SourceViewBatch","Eggshell.PublicationClient",
    "Eggshell.PublicationService","Eggshell.SynapseTransport","Eggshell.Handoff","Eggshell.ContractAudit"]
  discard <| command (compiler/"bin/lean").toString (#["-j1","-M1536","--run",audit.toString,
    "compare-sources",focusTarget.toString,focusHookTarget.toString,(focusHookStudy/"native-sources.json").toString]++changes)
  for name in changes do
    let relative := name.replace "." "/"++".lean"
    let patch ← IO.Process.output {cmd := "/usr/bin/diff",args := #["-U0","--label","a/"++relative,"--label","b/"++relative,
      (focusSource/relative).toString,(focusHookSource/relative).toString]}
    check (patch.exitCode == 1) "missing actual focus implementation patch"
    IO.FS.writeFile (focusHookStudy/(name.replace "." "_"++".patch")) patch.stdout
  write (focusHookStudy/"native-checks.json") native
  write (focusHookStudy/"build.json") (Json.mkObj [("runtime",toJson (← hash (focusHookTarget/"StudyMain"))),
    ("parent",toJson (← hash (focusTarget/"StudyMain"))),
    ("kernelAndOrdinaryContractAudit",toJson (← IO.FS.readFile (focusHookTarget/"tools_research_PreparedFocusHookChecks-lean.stdout")))])
  IO.FS.removeFile (base/"worker-cpu-target/bin/eggshelld")
  discard <| command "/bin/ln" #["-s",(focusHookTarget/"StudyMain").toString,(base/"worker-cpu-target/bin/eggshelld").toString]

def recordFocusHook (tag : String) : IO Unit := do
  record tag focusHookStudy "--prepared-focus-hook" (study/"evidence.json") false "prepared-focus-hook-"
  let evidence ← read (focusHookStudy/"evidence.json")
  let observed := (arr evidence "runs").flatMap fun run => (arr run "waves").flatMap (arr · "receipts")
  let used := observed.filter fun row => (row.getObjValD "prepared-window-focus").getObjValD "used" == toJson true
  write (focusHookStudy/"focus-path.json") (Json.mkObj [("observedReceipts",toJson observed.size),
    ("preparedFocusUsed",toJson used.size),("no80FullSearchRetry",toJson true),
    ("answeringModelCalls",toJson (0 : Nat)),("paidMatchedComparisons",toJson "0/18"),("adopted",toJson false)])
  write (focusHookStudy/"development.json") (Json.mkObj [("failures",toJson #[
    "build1:array-map composition proof needed final definitional reduction;added rfl",
    "build2/build3:two multiline record literals violated Lean layout;used typed local and positional FocusRow constructor",
    "build4:ordinary ContractAudit required old refocus symbol;bind new interpreter and additionally audit prepared service read and absence of window reconstruction in that interpreter",
    "build5:old native fixture positional Request constructor lacked the new optional field;use named fields",
    "preflight1:diagnostic used1536MiB while ordinary native compiler uses3072MiB;align with ordinary compiler setting,unchanged3670016KiB RSS guard",
    "controller:historical terminal guard PID was reused;check actual guard command/tag instead of unrelated numeric PID",
    "two unapplied patches had invalid context;no partial source changes"]),
    ("resourceCeilingUnchanged",toJson true),("adopted",toJson false)])

def cleanupFocusHook (tag : String) : IO Unit := do
  drained
  check ((arr (← read (focusHookStudy/"evidence.json")) "runs").any (fun run => run.getObjValD "tag" == toJson tag))
    "named completed cohort must be recorded before cleanup"
  check ((← read (focusHookStudy/"verification.json")).getObjValD "actualOutputs" == toJson (35 : Nat))
    "retain actual hook bodies before cleanup"
  let baseline := base/"allocator-service-build/StudyMain"
  check ((← hash baseline) == "4e4c9b9c95cb2c72b4447a86f5abc81b6bb619854889eb5ffa8492ba592e593a") "baseline changed"
  IO.FS.removeFile (base/"worker-cpu-target/bin/eggshelld")
  discard <| command "/bin/ln" #["-s",baseline.toString,(base/"worker-cpu-target/bin/eggshelld").toString]
  let mut removed := #[]
  for entry in ← base.readDir do
    if entry.fileName.startsWith "prepared-focus-hook-" && entry.fileName.endsWith "-result" && (← entry.path.isDir) then
      IO.FS.removeDirAll entry.path
      removed := removed.push entry.fileName
  let mut count := 0
  for entry in ← focusHookTarget.readDir do
    if entry.fileName.endsWith ".stdout" || entry.fileName.endsWith ".stderr" then
      IO.FS.removeFile entry.path
      count := count+1
  write (focusHookStudy/"cleanup.json") (Json.mkObj [("endedDbCacheSessionsRemoved",toJson removed),
    ("compilerLogsRemoved",toJson count),("baselineAliasRestored",toJson true),
    ("protectedOriginalsAndNativeInputsRetained",toJson true),("archived",toJson false)])

def main (args : List String) : IO Unit := do
  match args with
  | ["prepare"] => prepare
  | ["prepare-focus"] => prepareFocus
  | ["prepare-focus-hook"] => prepareFocusHook
  | ["scope-focus-hook"] => scopeFocusHook
  | ["seal-focus-hook",tag] => sealFocusHook tag
  | ["record-focus-hook",tag] => recordFocusHook tag
  | ["cleanup-focus-hook",tag] => cleanupFocusHook tag
  | ["setup",action,tag] => setup action tag
  | ["seal"] => sealRuntime
  | ["record",tag] => record tag
  | ["cleanup",tag] => cleanup tag
  | ["retire-parents"] => retireParents
  | ["compact-records"] => compactRecords
  | ["compact-focus-hook"] => compactRecords focusHookStudy
  | ["retire-obsolete-executables"] => retireObsoleteExecutables
  | ["seal-focus",tag] => sealFocus tag
  | ["cleanup-focus"] => cleanupFocus
  | ["verify-focus-originals"] => verifyFocusOriginals
  | _ => throw (IO.userError "prepare | prepare-focus | setup ACTION TAG | seal | seal-focus TAG | record TAG | cleanup TAG | cleanup-focus | retire-parents | compact-records | retire-obsolete-executables")
