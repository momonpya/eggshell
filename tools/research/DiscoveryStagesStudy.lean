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
    unless ["pure-file-reads-","discovery-stages-"].any (fun stem => entry.fileName.startsWith stem) &&
        entry.fileName.endsWith ".guard.json" do continue
    let value ← read entry.path
    check (value.getObjValD "state" == toJson "finished" && value.getObjValD "ownedPids" == toJson (#[] : Array Nat)) "previous guard not drained"
    let pid ← IO.ofExcept (value.getObjValAs? Nat "guardPid")
    let probe ← IO.Process.output {cmd := "/bin/ps",args := #["-p",toString pid,"-o","pid="]}
    check (probe.exitCode != 0 && probe.stdout.trimAscii.isEmpty) "previous guard still live"

def materialize (selected destination : System.FilePath) (entry : String) : IO Unit := do
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
  let output := if destination == sourceRoot then target else clientTarget
  for (key,value) in [("project",destination.toString),("core",destination.toString),("output",output.toString),
      ("baselineResponse",(selected/"runtime.rsp").toString),
      ("baselineMain",(selected/(oldEntry.replace "." "_"++".o")).toString),
      ("objectModules",(destination/"object-mapping.json").toString),("mainModule",entry)] do
    settings := settings.setObjVal! key (toJson value)
  write (base/(if destination == sourceRoot then "discovery-stages-settings.json" else "discovery-stages-client-settings.json")) settings

def prepare : IO Unit := do
  drained
  IO.FS.createDirAll study
  check ((← hash (parent/"StudyMain")) == "b2dc39ff335bf7aafa105d7da1ca2575ddefdc8e34c49e78430927579371012a") "runtime parent changed"
  check ((← hash (clientParent/"StudyMain")) == "a80cad2a80fb084842d22e3ead44358762fbdea3e175601b1d407d82c67b308e") "sealed client changed"
  materialize parent sourceRoot "tools.research.DiscoveryStagesChecks"
  materialize clientParent clientSource "tools.research.WorkerCpuProfile"
  write (study/"plan.json") (Json.mkObj [("classificationPreviousTurn",toJson "progress:removed redundant synchronized file cache with kernel/native evidence"),
    ("status",toJson "diagnostic candidate,not adopted"),("cohort",toJson "same16sources/32cases/2waves;no80fullsearch retry"),
    ("questionIndependentPreparationNotMovedIntoRetrieval",toJson true),
    ("purpose",toJson "split post-provider discovery/focus/transport and retain exact shutdown errors/process identities"),
    ("unchanged",toJson "rank,scope,full certification,deadlines,worker count,resource bounds"),
    ("runtimeParent",toJson (← hash (parent/"StudyMain"))),("sealedClientParent",toJson (← hash (clientParent/"StudyMain")))])

def setup (action tag : String) : IO Unit := do
  drained
  let path := base/(tag++".guard-settings.json")
  check (!(← path.pathExists)) "fresh diagnostic tag required"
  let arguments ← if action == "build" || action == "client-build" then
    pure #[(compiler/"bin/lean").toString,"-j1","-M1536","--run",(workspace/"tools/research/StudyBuildMain.lean").toString,
      (base/(if action == "build" then "discovery-stages-settings.json" else "discovery-stages-client-settings.json")).toString]
    else if action == "hooks" then pure #["/usr/bin/env","LEAN_NUM_THREADS=1","EGGSHELL_TRACE_SERVICE_PROFILE=1",
      "EGGSHELL_TRACE_QUERY_STAGES=1","EGGSHELL_TRACE_NUMERICAL_STAGES=1","EGGSHELL_TRACE_ALLOCATOR=1","EGGSHELL_TRACE_ACTOR_HEAP=1",
      "EGGSHELL_DATA_ROOT="++(base/(tag++"-result/private")).toString,"EGGSHELL_CONFIG="++(base/(tag++"-result/eggshell.toml")).toString,
      "PLUGIN_ROOT="++(base/"worker-cpu-target").toString,(clientTarget/"StudyMain").toString,
      (base/(tag++"-result")).toString,(target/"StudyMain").toString,← hash (target/"StudyMain")]
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
def record (tag : String) : IO Unit := do
  drained
  let recordScript := workspace/"docs/candidates/shared-leases/records.lean"
  if !(← (study/"evidence.json").pathExists) then
    discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",recordScript.toString,"--discovery-stages",tag]
  discard <| command (compiler/"bin/lean").toString #["-j1","-M1536","--run",recordScript.toString,"--discovery-stages","verify","35"]
  let evidence ← read (study/"evidence.json")
  let previous ← read (workspace/"docs/candidates/typed-original-reads/evidence.json")
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
    if entry.fileName.startsWith "discovery-stages-" && entry.fileName.endsWith ".guard.json" then
      guards := guards.push (entry.fileName,← read entry.path)
  write (study/"controls.json") (toJson guards)
  let sample := root/"worker.sample.txt"
  let lines := (← IO.FS.readFile sample).splitOn "\n"
  let some first := lines.findIdx? (·.contains "l_Eggshell_Plugin_refocusObservedNeighborhood") |
    throw (IO.userError "tail sample does not show the claimed focus branch")
  write (study/"sample-context.json") (Json.mkObj [("sha256",toJson (← hash sample)),
    ("header",toJson (lines.take 22)),("firstLine",toJson (first+1)),
    ("excerpt",toJson ((lines.drop first).take 85)),
    ("sampleObservationsNotCpuPercentages",toJson true)])
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

def compactRecords : IO Unit := do
  drained
  for name in ["evidence.json","bodies.json","verification.json"] do
    let path := study/name
    let value ← read path
    write path value
    check ((← read path) == value) "record formatting changed parsed evidence"

def main (args : List String) : IO Unit := do
  match args with
  | ["prepare"] => prepare
  | ["setup",action,tag] => setup action tag
  | ["seal"] => sealRuntime
  | ["record",tag] => record tag
  | ["cleanup",tag] => cleanup tag
  | ["retire-parents"] => retireParents
  | ["compact-records"] => compactRecords
  | _ => throw (IO.userError "prepare | setup ACTION TAG | seal | record TAG | cleanup TAG | retire-parents | compact-records")
